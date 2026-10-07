use bytemuck::{Pod, Zeroable};
use wgpu::util::DeviceExt;

use crate::{euler_xyz_matrix, identity_matrix, GpuContext, Mat4, RenderScene, SkeletonPose};

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
}

impl GpuScene {
    pub fn joint_index(&self, name: &str) -> Option<usize> {
        self.skeleton_pose.joint_index(name)
    }

    pub fn joint_names(&self) -> &[String] {
        self.skeleton_pose.joint_names()
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

impl GpuContext {
    pub fn upload_scene(
        &self,
        scene: &RenderScene,
        joint_palette_layout: &wgpu::BindGroupLayout,
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

        Ok(GpuScene {
            meshes,
            joint_count: scene.joint_count(),
            skeleton_pose,
            joint_palette_buffer,
            joint_palette_bind_group,
        })
    }
}
