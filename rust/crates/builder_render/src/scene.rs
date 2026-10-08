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


impl RenderScene {
    pub fn baked_model_transform(&self, matrix: [[f32; 4]; 4]) -> Self {
        let mut baked = self.clone();
        for mesh in &mut baked.meshes {
            for vertex in &mut mesh.vertices {
                vertex.position = transform_point3(matrix, vertex.position);
                vertex.normal = transform_normal3(matrix, vertex.normal);
            }
            mesh.skinned = false;
            for vertex in &mut mesh.vertices {
                vertex.joints = [0; 4];
                vertex.weights = [0.0; 4];
            }
        }
        baked.skeleton.joints.clear();
        baked
    }
}

fn transform_point3(matrix: [[f32; 4]; 4], point: [f32; 3]) -> [f32; 3] {
    [
        matrix[0][0] * point[0]
            + matrix[1][0] * point[1]
            + matrix[2][0] * point[2]
            + matrix[3][0],
        matrix[0][1] * point[0]
            + matrix[1][1] * point[1]
            + matrix[2][1] * point[2]
            + matrix[3][1],
        matrix[0][2] * point[0]
            + matrix[1][2] * point[1]
            + matrix[2][2] * point[2]
            + matrix[3][2],
    ]
}

fn transform_normal3(matrix: [[f32; 4]; 4], normal: [f32; 3]) -> [f32; 3] {
    let value = [
        matrix[0][0] * normal[0] + matrix[1][0] * normal[1] + matrix[2][0] * normal[2],
        matrix[0][1] * normal[0] + matrix[1][1] * normal[1] + matrix[2][1] * normal[2],
        matrix[0][2] * normal[0] + matrix[1][2] * normal[1] + matrix[2][2] * normal[2],
    ];
    let length = (value[0] * value[0] + value[1] * value[1] + value[2] * value[2]).sqrt();
    if length > 1.0e-8 {
        [value[0] / length, value[1] / length, value[2] / length]
    } else {
        normal
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
    fn baking_model_transform_updates_geometry_and_removes_skinning() {
        let scene = RenderScene {
            meshes: vec![RenderMesh {
                name: "part".into(),
                vertices: vec![RenderVertex {
                    position: [1.0, 0.0, 0.0],
                    normal: [1.0, 0.0, 0.0],
                    joints: [1, 2, 0, 0],
                    weights: [0.5, 0.5, 0.0, 0.0],
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

        let matrix = [
            [2.0, 0.0, 0.0, 0.0],
            [0.0, 2.0, 0.0, 0.0],
            [0.0, 0.0, 2.0, 0.0],
            [1.0, 2.0, 3.0, 1.0],
        ];
        let baked = scene.baked_model_transform(matrix);
        assert_eq!(baked.meshes[0].vertices[0].position, [3.0, 2.0, 3.0]);
        assert_eq!(baked.meshes[0].vertices[0].normal, [1.0, 0.0, 0.0]);
        assert!(!baked.meshes[0].skinned);
        assert!(baked.skeleton.joints.is_empty());
    }

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
