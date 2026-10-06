#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct RenderVertex {
    pub position: [f32; 3],
    pub normal: [f32; 3],
    pub uv: [f32; 2],
    pub joints: [u16; 4],
    pub weights: [f32; 4],
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
    pub joint_count: u32,
}

impl RenderScene {
    pub fn vertex_count(&self) -> usize {
        self.meshes.iter().map(|mesh| mesh.vertices.len()).sum()
    }

    pub fn index_count(&self) -> usize {
        self.meshes.iter().map(|mesh| mesh.indices.len()).sum()
    }

    pub fn is_empty(&self) -> bool {
        self.meshes.is_empty() || self.vertex_count() == 0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn counts_scene_geometry() {
        let scene = RenderScene {
            meshes: vec![RenderMesh {
                name: "body".into(),
                vertices: vec![RenderVertex::default(); 3],
                indices: vec![0, 1, 2],
                skinned: true,
            }],
            joint_count: 22,
        };
        assert_eq!(scene.vertex_count(), 3);
        assert_eq!(scene.index_count(), 3);
        assert!(!scene.is_empty());
    }
}
