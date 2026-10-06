use bytemuck::{Pod, Zeroable};
use wgpu::util::DeviceExt;

use crate::{GpuContext, RenderScene};

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
}

impl GpuContext {
    pub fn upload_scene(&self, scene: &RenderScene) -> Result<GpuScene, String> {
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

        Ok(GpuScene {
            meshes,
            joint_count: scene.joint_count(),
        })
    }
}
