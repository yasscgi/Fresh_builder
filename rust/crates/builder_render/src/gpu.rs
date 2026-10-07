#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GpuAdapterInfo {
    pub name: String,
    pub backend: String,
    pub device_type: String,
    pub driver: String,
    pub driver_info: String,
}

pub async fn probe_high_performance_adapter() -> Result<GpuAdapterInfo, String> {
    let instance = wgpu::Instance::default();

    let adapter = instance
        .request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::HighPerformance,
            force_fallback_adapter: false,
            compatible_surface: None,
            apply_limit_buckets: false,
        })
        .await
        .map_err(|error| format!("No compatible GPU adapter: {error:?}"))?;

    Ok(adapter_info(&adapter))
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SceneUploadStats {
    pub mesh_count: usize,
    pub vertex_count: usize,
    pub index_count: usize,
    pub joint_count: u32,
}

pub struct GpuContext {
    pub instance: wgpu::Instance,
    pub adapter: wgpu::Adapter,
    pub device: wgpu::Device,
    pub queue: wgpu::Queue,
    pub info: GpuAdapterInfo,
}

impl GpuContext {
    pub async fn new() -> Result<Self, String> {
        let instance = wgpu::Instance::default();

        let adapter = instance
            .request_adapter(&wgpu::RequestAdapterOptions {
                power_preference: wgpu::PowerPreference::HighPerformance,
                force_fallback_adapter: false,
                compatible_surface: None,
                apply_limit_buckets: false,
            })
            .await
            .map_err(|error| format!("No compatible GPU adapter: {error:?}"))?;

        let info = adapter_info(&adapter);

        let (device, queue) = adapter
            .request_device(&wgpu::DeviceDescriptor::default())
            .await
            .map_err(|error| format!("Failed to create WGPU device: {error:?}"))?;

        Ok(Self {
            instance,
            adapter,
            device,
            queue,
            info,
        })
    }

    pub fn validate_scene_for_upload(
        &self,
        scene: &crate::RenderScene,
    ) -> Result<SceneUploadStats, String> {
        validate_scene_for_upload(scene)
    }
}

fn validate_scene_for_upload(scene: &crate::RenderScene) -> Result<SceneUploadStats, String> {
    if scene.is_empty() {
        return Err("Cannot upload an empty Builder scene".to_owned());
    }

    crate::SkeletonPose::from_skeleton(&scene.skeleton)?;

    let joint_count = scene.joint_count();
    for mesh in &scene.meshes {
        if mesh.indices.iter().any(|index| *index as usize >= mesh.vertices.len()) {
            return Err(format!("Mesh {} contains an out-of-range index", mesh.name));
        }

        if mesh.skinned && joint_count == 0 {
            return Err(format!("Skinned mesh {} has no scene joints", mesh.name));
        }

        for vertex in &mesh.vertices {
            for influence in 0..4 {
                let weight = vertex.weights[influence];
                if !weight.is_finite() || weight < 0.0 {
                    return Err(format!("Mesh {} contains an invalid skin weight", mesh.name));
                }

                if mesh.skinned && weight > 0.0 && vertex.joints[influence] as u32 >= joint_count {
                    return Err(format!(
                        "Mesh {} references joint {} but the scene only has {} joints",
                        mesh.name, vertex.joints[influence], joint_count
                    ));
                }
            }
        }
    }

    Ok(SceneUploadStats {
        mesh_count: scene.meshes.len(),
        vertex_count: scene.vertex_count(),
        index_count: scene.index_count(),
        joint_count,
    })
}

fn adapter_info(adapter: &wgpu::Adapter) -> GpuAdapterInfo {
    let info = adapter.get_info();

    GpuAdapterInfo {
        name: info.name,
        backend: format!("{:?}", info.backend),
        device_type: format!("{:?}", info.device_type),
        driver: info.driver,
        driver_info: info.driver_info,
    }
}

#[cfg(test)]
mod tests {
    use super::{validate_scene_for_upload, GpuAdapterInfo};
    use crate::{identity_matrix, RenderJoint, RenderMesh, RenderScene, RenderSkeleton, RenderVertex};

    #[test]
    fn adapter_info_is_platform_neutral_data() {
        let info = GpuAdapterInfo {
            name: "Example GPU".to_owned(),
            backend: "Vulkan".to_owned(),
            device_type: "DiscreteGpu".to_owned(),
            driver: "driver".to_owned(),
            driver_info: "info".to_owned(),
        };

        assert_eq!(info.backend, "Vulkan");
        assert_eq!(info.device_type, "DiscreteGpu");
    }

    #[test]
    fn rejects_out_of_range_weighted_joint_index() {
        let scene = RenderScene {
            meshes: vec![RenderMesh {
                name: "body".into(),
                vertices: vec![RenderVertex {
                    joints: [2, 0, 0, 0],
                    weights: [1.0, 0.0, 0.0, 0.0],
                    ..RenderVertex::default()
                }],
                indices: vec![0],
                skinned: true,
            }],
            skeleton: RenderSkeleton {
                joints: vec![RenderJoint {
                    name: "root".into(),
                    parent: None,
                    inverse_bind_matrix: identity_matrix(),
                    local_matrix: identity_matrix(),
                }],
            },
        };

        assert!(validate_scene_for_upload(&scene).is_err());
    }

    #[test]
    fn zero_weight_joint_indices_are_safe_for_unskinned_vertices() {
        let scene = RenderScene {
            meshes: vec![RenderMesh {
                name: "static".into(),
                vertices: vec![RenderVertex {
                    joints: [u16::MAX; 4],
                    weights: [0.0; 4],
                    ..RenderVertex::default()
                }],
                indices: vec![0],
                skinned: false,
            }],
            skeleton: RenderSkeleton::default(),
        };

        assert!(validate_scene_for_upload(&scene).is_ok());
    }
}
