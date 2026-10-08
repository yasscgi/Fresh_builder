use bytemuck::{Pod, Zeroable};
use wgpu::util::DeviceExt;

use crate::{euler_xyz_matrix, identity_matrix, mat4_mul, GpuContext, Mat4, RenderScene, SkeletonPose};

#[repr(C)]
#[derive(Clone, Copy, Debug, Pod, Zeroable)]
pub struct GpuVertex {
    pub position: [f32; 3],
    pub normal: [f32; 3],
    pub uv: [f32; 2],
    pub joints: [u32; 4],
    pub weights: [f32; 4],
}

pub struct GpuMesh {
    pub name: String,
    pub vertex_buffer: wgpu::Buffer,
    pub index_buffer: wgpu::Buffer,
    pub index_count: u32,
    pub skinned: bool,
}

pub struct GpuScene {
    pub meshes: Vec<GpuMesh>,
    pub joint_count: u32,
    pub skeleton_pose: SkeletonPose,
    joint_palette_buffer: wgpu::Buffer,
    pub joint_palette_bind_group: wgpu::BindGroup,
    model_buffer: wgpu::Buffer,
    pub model_bind_group: wgpu::BindGroup,
    model_matrix: Mat4,
}

impl GpuScene {
    pub fn model_matrix(&self) -> Mat4 {
        self.model_matrix
    }

    pub fn set_model_transform(
        &mut self,
        queue: &wgpu::Queue,
        translation: [f32; 3],
        rotation_xyz: [f32; 3],
        scale: f32,
    ) -> Result<(), String> {
        if translation.iter().any(|value| !value.is_finite())
            || rotation_xyz.iter().any(|value| !value.is_finite())
            || !scale.is_finite()
            || scale <= 0.0
        {
            return Err("Scene transform requires finite values and a positive scale".to_owned());
        }

        self.model_matrix =
            model_transform_matrix(translation, rotation_xyz, scale);
        queue.write_buffer(
            &self.model_buffer,
            0,
            bytemuck::cast_slice(std::slice::from_ref(&self.model_matrix)),
        );
        Ok(())
    }

    pub fn joint_index(&self, name: &str) -> Option<usize> {
        self.skeleton_pose.joint_index(name)
    }

    pub fn joint_names(&self) -> &[String] {
        self.skeleton_pose.joint_names()
    }

    pub fn joint_world_position(&self, joint_index: usize) -> Result<[f32; 3], String> {
        self.skeleton_pose.joint_world_position(joint_index)
    }

    pub fn apply_two_bone_solution(
        &mut self,
        queue: &wgpu::Queue,
        upper: usize,
        lower: usize,
        end: usize,
        solved_mid: [f32; 3],
        solved_end: [f32; 3],
    ) -> Result<(), String> {
        self.skeleton_pose
            .apply_two_bone_solution(upper, lower, end, solved_mid, solved_end)?;
        self.upload_current_palette(queue)
    }

    pub fn set_joint_local_matrix(
        &mut self,
        queue: &wgpu::Queue,
        joint_index: usize,
        matrix: Mat4,
    ) -> Result<(), String> {
        self.skeleton_pose.set_local_matrix(joint_index, matrix)?;
        self.upload_current_palette(queue)
    }

    pub fn set_joint_local_euler_xyz(
        &mut self,
        queue: &wgpu::Queue,
        joint_index: usize,
        x: f32,
        y: f32,
        z: f32,
    ) -> Result<(), String> {
        if !x.is_finite() || !y.is_finite() || !z.is_finite() {
            return Err("FK Euler values must be finite".to_owned());
        }
        self.skeleton_pose
            .set_local_delta_matrix(joint_index, euler_xyz_matrix(x, y, z))?;
        self.upload_current_palette(queue)
    }

    pub fn set_hand_open(
        &mut self,
        queue: &wgpu::Queue,
        open_amount: f32,
    ) -> Result<usize, String> {
        let affected = self.skeleton_pose.apply_mixamo_hand_open(open_amount)?;
        self.upload_current_palette(queue)?;
        Ok(affected)
    }

    pub fn reset_pose(&mut self, queue: &wgpu::Queue) -> Result<(), String> {
        self.skeleton_pose.reset_to_rest();
        self.upload_current_palette(queue)
    }

    pub fn upload_current_palette(&self, queue: &wgpu::Queue) -> Result<(), String> {
        let palette = self.skeleton_pose.palette()?;
        self.write_palette(queue, &palette)
    }

    fn write_palette(&self, queue: &wgpu::Queue, palette: &[Mat4]) -> Result<(), String> {
        if palette.len() != self.joint_count as usize {
            return Err(format!(
                "Joint palette size {} does not match scene joint count {}",
                palette.len(),
                self.joint_count
            ));
        }

        if palette.is_empty() {
            queue.write_buffer(
                &self.joint_palette_buffer,
                0,
                bytemuck::cast_slice(&[identity_matrix()]),
            );
        } else {
            queue.write_buffer(
                &self.joint_palette_buffer,
                0,
                bytemuck::cast_slice(palette),
            );
        }
        Ok(())
    }
}


fn model_transform_matrix(
    translation: [f32; 3],
    rotation_xyz: [f32; 3],
    scale: f32,
) -> Mat4 {
    let translation_matrix = [
        [1.0, 0.0, 0.0, 0.0],
        [0.0, 1.0, 0.0, 0.0],
        [0.0, 0.0, 1.0, 0.0],
        [translation[0], translation[1], translation[2], 1.0],
    ];
    let scale_matrix = [
        [scale, 0.0, 0.0, 0.0],
        [0.0, scale, 0.0, 0.0],
        [0.0, 0.0, scale, 0.0],
        [0.0, 0.0, 0.0, 1.0],
    ];
    let rotation_matrix =
        euler_xyz_matrix(rotation_xyz[0], rotation_xyz[1], rotation_xyz[2]);

    mat4_mul(
        translation_matrix,
        mat4_mul(rotation_matrix, scale_matrix),
    )
}

impl GpuContext {
    pub fn upload_scene(
        &self,
        scene: &RenderScene,
        joint_palette_layout: &wgpu::BindGroupLayout,
        model_layout: &wgpu::BindGroupLayout,
    ) -> Result<GpuScene, String> {
        self.validate_scene_for_upload(scene)?;
        let mut meshes = Vec::with_capacity(scene.meshes.len());

        for mesh in &scene.meshes {
            let vertices: Vec<GpuVertex> = mesh
                .vertices
                .iter()
                .map(|vertex| GpuVertex {
                    position: vertex.position,
                    normal: vertex.normal,
                    uv: vertex.uv,
                    joints: vertex.joints.map(u32::from),
                    weights: vertex.weights,
                })
                .collect();

            let vertex_buffer = self.device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some(&format!("fresh-builder:{}:vertices", mesh.name)),
                contents: bytemuck::cast_slice(&vertices),
                usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
            });
            let index_buffer = self.device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some(&format!("fresh-builder:{}:indices", mesh.name)),
                contents: bytemuck::cast_slice(&mesh.indices),
                usage: wgpu::BufferUsages::INDEX | wgpu::BufferUsages::COPY_DST,
            });

            meshes.push(GpuMesh {
                name: mesh.name.clone(),
                vertex_buffer,
                index_buffer,
                index_count: mesh.indices.len() as u32,
                skinned: mesh.skinned,
            });
        }

        let skeleton_pose = SkeletonPose::from_skeleton(&scene.skeleton)?;
        let palette = skeleton_pose.rest_palette()?;
        let palette_storage = if palette.is_empty() {
            vec![identity_matrix()]
        } else {
            palette
        };

        let joint_palette_buffer =
            self.device
                .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                    label: Some("fresh-builder:joint-palette"),
                    contents: bytemuck::cast_slice(&palette_storage),
                    usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
                });

        let joint_palette_bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Fresh Builder Joint Palette Bind Group"),
            layout: joint_palette_layout,
            entries: &[wgpu::BindGroupEntry {
                binding: 0,
                resource: joint_palette_buffer.as_entire_binding(),
            }],
        });


        let model_matrix = identity_matrix();
        let model_buffer =
            self.device
                .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                    label: Some("fresh-builder:model-transform"),
                    contents: bytemuck::cast_slice(std::slice::from_ref(&model_matrix)),
                    usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
                });
        let model_bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Fresh Builder Model Transform Bind Group"),
            layout: model_layout,
            entries: &[wgpu::BindGroupEntry {
                binding: 0,
                resource: model_buffer.as_entire_binding(),
            }],
        });

        Ok(GpuScene {
            meshes,
            joint_count: scene.joint_count(),
            skeleton_pose,
            joint_palette_buffer,
            joint_palette_bind_group,
            model_buffer,
            model_bind_group,
            model_matrix,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::model_transform_matrix;
    use crate::transform_point;

    #[test]
    fn scene_model_transform_scales_rotates_then_translates() {
        let matrix = model_transform_matrix(
            [1.0, 2.0, 3.0],
            [0.0, 0.0, core::f32::consts::FRAC_PI_2],
            2.0,
        );
        let point = transform_point(matrix, [1.0, 0.0, 0.0]);
        assert!((point[0] - 1.0).abs() < 1.0e-5);
        assert!((point[1] - 4.0).abs() < 1.0e-5);
        assert!((point[2] - 3.0).abs() < 1.0e-5);
    }
}
