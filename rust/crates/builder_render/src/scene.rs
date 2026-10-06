#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct RenderVertex {
    pub position: [f32; 3],
    pub normal: [f32; 3],
    pub uv: [f32; 2],
    pub joints: [u16; 4],
    pub weights: [f32; 4],
}

#[derive(Clone, Debug, PartialEq)]
pub struct RenderJoint {
    pub name: String,
    pub parent: Option<u32>,
    pub inverse_bind_matrix: [[f32; 4]; 4],
    pub local_matrix: [[f32; 4]; 4],
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct RenderSkeleton {
    pub joints: Vec<RenderJoint>,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct RenderMesh {
    pub name: String,
    pub vertices: Vec<RenderVertex>,
    pub indices: Vec<u32>,
    pub skinned: bool,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct RenderScene {
    pub meshes: Vec<RenderMesh>,
    pub skeleton: RenderSkeleton,
}

impl RenderScene {
    pub fn vertex_count(&self) -> usize {
        self.meshes.iter().map(|mesh| mesh.vertices.len()).sum()
    }

    pub fn index_count(&self) -> usize {
        self.meshes.iter().map(|mesh| mesh.indices.len()).sum()
    }

    pub fn joint_count(&self) -> u32 {
        self.skeleton.joints.len() as u32
    }

    pub fn is_empty(&self) -> bool {
        self.meshes.is_empty() || self.vertex_count() == 0
    }
}

pub fn identity_matrix() -> [[f32; 4]; 4] {
    [
        [1.0, 0.0, 0.0, 0.0],
        [0.0, 1.0, 0.0, 0.0],
        [0.0, 0.0, 1.0, 0.0],
        [0.0, 0.0, 0.0, 1.0],
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn counts_scene_geometry_and_joints() {
        let scene = RenderScene {
            meshes: vec![RenderMesh {
                name: "body".into(),
                vertices: vec![RenderVertex::default(); 3],
                indices: vec![0, 1, 2],
                skinned: true,
            }],
            skeleton: RenderSkeleton {
                joints: vec![RenderJoint {
                    name: "hips".into(),
                    parent: None,
                    inverse_bind_matrix: identity_matrix(),
                    local_matrix: identity_matrix(),
                }],
            },
        };
        assert_eq!(scene.vertex_count(), 3);
        assert_eq!(scene.index_count(), 3);
        assert_eq!(scene.joint_count(), 1);
        assert!(!scene.is_empty());
    }
}
