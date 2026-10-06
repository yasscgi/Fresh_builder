use std::path::Path;

use builder_render::{RenderMesh, RenderScene, RenderVertex};

pub fn decode_gltf_scene(path: impl AsRef<Path>, meters_per_unit: f32) -> Result<RenderScene, String> {
    let path = path.as_ref();
    let (document, buffers, _) =
        gltf::import(path).map_err(|error| format!("Failed to decode {}: {error}", path.display()))?;

    let scale = if meters_per_unit.is_finite() && meters_per_unit > 0.0 {
        meters_per_unit
    } else {
        1.0
    };

    let joint_count = document
        .skins()
        .map(|skin| skin.joints().count() as u32)
        .max()
        .unwrap_or(0);

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
                skinned: primitive.get(&gltf::Semantic::Joints(0)).is_some()
                    && primitive.get(&gltf::Semantic::Weights(0)).is_some(),
            });
        }
    }

    let scene = RenderScene { meshes, joint_count };
    if scene.is_empty() {
        return Err(format!("{} contains no renderable mesh geometry", path.display()));
    }
    Ok(scene)
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
    use super::normalize_weights;

    #[test]
    fn skin_weights_are_normalized() {
        assert_eq!(normalize_weights([2.0, 2.0, 0.0, 0.0]), [0.5, 0.5, 0.0, 0.0]);
        assert_eq!(normalize_weights([0.0; 4]), [0.0; 4]);
    }
}
