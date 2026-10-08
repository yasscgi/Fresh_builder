use std::path::Path;

use builder_render::{identity_matrix, RenderJoint, RenderMesh, RenderScene, RenderSkeleton, RenderVertex};

pub fn decode_gltf_scene(path: impl AsRef<Path>, meters_per_unit: f32) -> Result<RenderScene, String> {
    let path = path.as_ref();
    let (document, buffers, _) =
        gltf::import(path).map_err(|error| format!("Failed to decode {}: {error}", path.display()))?;

    let scale = if meters_per_unit.is_finite() && meters_per_unit > 0.0 {
        meters_per_unit
    } else {
        1.0
    };

    let mut skeleton = RenderSkeleton::default();
    if let Some(skin) = document.skins().next() {
        let reader = skin.reader(|buffer| Some(&buffers[buffer.index()]));
        let inverse_bind_matrices: Vec<[[f32; 4]; 4]> = reader
            .read_inverse_bind_matrices()
            .map(|values| values.map(|matrix| scale_matrix_translation(matrix, scale)).collect())
            .unwrap_or_else(|| vec![identity_matrix(); skin.joints().count()]);

        let joint_nodes: Vec<_> = skin.joints().collect();
        if inverse_bind_matrices.len() != joint_nodes.len() {
            return Err("glTF skin inverse-bind matrix count does not match joint count".to_owned());
        }

        skeleton.joints = joint_nodes
            .iter()
            .enumerate()
            .map(|(index, node)| {
                let parent = joint_nodes.iter().position(|candidate| {
                    candidate.children().any(|child| child.index() == node.index())
                }).map(|value| value as u32);

                RenderJoint {
                    name: node.name().map(str::to_owned).unwrap_or_else(|| format!("joint_{}", node.index())),
                    parent,
                    inverse_bind_matrix: inverse_bind_matrices[index],
                    local_matrix: scale_matrix_translation(node.transform().matrix(), scale),
                }
            })
            .collect();
    }

    let mut meshes = Vec::new();

    for mesh in document.meshes() {
        for (primitive_index, primitive) in mesh.primitives().enumerate() {
            let reader = primitive.reader(|buffer| Some(&buffers[buffer.index()]));

            let positions: Vec<[f32; 3]> = reader
                .read_positions()
                .ok_or_else(|| format!("Mesh {} primitive {primitive_index} has no positions", mesh.index()))?
                .map(|p| [p[0] * scale, p[1] * scale, p[2] * scale])
                .collect();

            let normals: Vec<[f32; 3]> = reader
                .read_normals()
                .map(|values| values.collect())
                .unwrap_or_else(|| vec![[0.0, 1.0, 0.0]; positions.len()]);

            let uvs: Vec<[f32; 2]> = reader
                .read_tex_coords(0)
                .map(|values| values.into_f32().collect())
                .unwrap_or_else(|| vec![[0.0, 0.0]; positions.len()]);

            let joints: Vec<[u16; 4]> = reader
                .read_joints(0)
                .map(|values| values.into_u16().collect())
                .unwrap_or_else(|| vec![[0, 0, 0, 0]; positions.len()]);

            let weights: Vec<[f32; 4]> = reader
                .read_weights(0)
                .map(|values| values.into_f32().map(normalize_weights).collect())
                .unwrap_or_else(|| vec![[0.0, 0.0, 0.0, 0.0]; positions.len()]);

            if normals.len() != positions.len()
                || uvs.len() != positions.len()
                || joints.len() != positions.len()
                || weights.len() != positions.len()
            {
                return Err(format!("Mesh {} primitive {primitive_index} has mismatched vertex attributes", mesh.index()));
            }

            let vertices = (0..positions.len())
                .map(|index| RenderVertex {
                    position: positions[index],
                    normal: normals[index],
                    uv: uvs[index],
                    joints: joints[index],
                    weights: weights[index],
                })
                .collect();

            let indices = reader
                .read_indices()
                .map(|values| values.into_u32().collect())
                .unwrap_or_else(|| (0..positions.len() as u32).collect());

            meshes.push(RenderMesh {
                name: mesh
                    .name()
                    .map(str::to_owned)
                    .unwrap_or_else(|| format!("mesh_{}_{}", mesh.index(), primitive_index)),
                vertices,
                indices,
                skinned: primitive
                    .get(&gltf::Semantic::Joints(0))
                    .is_some()
                    && primitive
                        .get(&gltf::Semantic::Weights(0))
                        .is_some(),
            });
        }
    }

    let scene = RenderScene { meshes, skeleton };
    if scene.is_empty() {
        return Err(format!("{} contains no renderable mesh geometry", path.display()));
    }
    Ok(scene)
}

fn scale_matrix_translation(mut matrix: [[f32; 4]; 4], scale: f32) -> [[f32; 4]; 4] {
    matrix[3][0] *= scale;
    matrix[3][1] *= scale;
    matrix[3][2] *= scale;
    matrix
}

fn normalize_weights(weights: [f32; 4]) -> [f32; 4] {
    let sum = weights.iter().copied().sum::<f32>();
    if sum <= f32::EPSILON || !sum.is_finite() {
        return [0.0; 4];
    }
    [
        weights[0] / sum,
        weights[1] / sum,
        weights[2] / sum,
        weights[3] / sum,
    ]
}

#[cfg(test)]
mod tests {
    use super::{normalize_weights, scale_matrix_translation};
    use builder_render::identity_matrix;

    #[test]
    fn skeleton_matrix_translation_uses_scene_unit_scale() {
        let mut matrix = identity_matrix();
        matrix[3] = [100.0, -50.0, 25.0, 1.0];
        let scaled = scale_matrix_translation(matrix, 0.001);
        assert!((scaled[3][0] - 0.1).abs() < 1.0e-6);
        assert!((scaled[3][1] + 0.05).abs() < 1.0e-6);
        assert!((scaled[3][2] - 0.025).abs() < 1.0e-6);
        assert_eq!(scaled[0], matrix[0]);
        assert_eq!(scaled[1], matrix[1]);
        assert_eq!(scaled[2], matrix[2]);
    }

    #[test]
    fn skin_weights_are_normalized() {
        assert_eq!(normalize_weights([2.0, 2.0, 0.0, 0.0]), [0.5, 0.5, 0.0, 0.0]);
        assert_eq!(normalize_weights([0.0; 4]), [0.0; 4]);
    }
}
