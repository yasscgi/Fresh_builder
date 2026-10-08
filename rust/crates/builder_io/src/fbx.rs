use std::path::Path;

use builder_render::{RenderMesh, RenderScene, RenderVertex};

pub fn decode_fbx_scene(path: impl AsRef<Path>) -> Result<RenderScene, String> {
    let path = path.as_ref();
    let path_str = path
        .to_str()
        .ok_or_else(|| format!("FBX path is not valid UTF-8: {}", path.display()))?;

    let opts = ufbx::LoadOpts {
        target_axes: ufbx::CoordinateAxes::right_handed_y_up(),
        target_unit_meters: 1.0,
        target_camera_axes: ufbx::CoordinateAxes::right_handed_y_up(),
        target_light_axes: ufbx::CoordinateAxes::right_handed_y_up(),
        space_conversion: ufbx::SpaceConversion::ModifyGeometry,
        generate_missing_normals: true,
        normalize_normals: true,
        ignore_animation: true,
        load_external_files: false,
        ignore_missing_external_files: true,
        ..Default::default()
    };

    let scene = ufbx::load_file(path_str, opts)
        .map_err(|error| format!("Failed to decode FBX {}: {}", path.display(), error.description))?;

    let mut rendered = RenderScene::default();

    for node in &scene.nodes {
        if node.is_root || !node.visible {
            continue;
        }

        let Some(mesh_ref) = &node.mesh else {
            continue;
        };
        let mesh = &**mesh_ref;

        if !mesh.skin_deformers.is_empty() {
            return Err(format!(
                "Rigged FBX is not enabled yet: node '{}' contains skin deformers. Use GLB/glTF for rigged characters until the FBX skin-cluster bridge is enabled.",
                node.element.name
            ));
        }

        if mesh.num_triangles == 0 || mesh.faces.is_empty() {
            continue;
        }

        let mut vertices = Vec::<RenderVertex>::with_capacity(mesh.num_triangles * 3);
        let mut indices = Vec::<u32>::with_capacity(mesh.num_triangles * 3);
        let mut tri_indices = vec![0_u32; (mesh.max_face_triangles * 3).max(3)];
        let normal_matrix = ufbx::matrix_for_normals(&node.geometry_to_world);

        for &face in &mesh.faces {
            let triangle_count = mesh.triangulate_face(&mut tri_indices, face);
            let corner_count = triangle_count as usize * 3;

            for &source_index in &tri_indices[..corner_count] {
                let source_index = source_index as usize;

                let local_position = mesh.vertex_position[source_index];
                let local_normal = mesh.vertex_normal[source_index];
                let world_position =
                    ufbx::transform_position(&node.geometry_to_world, local_position);
                let world_normal = ufbx::vec3_normalize(
                    ufbx::transform_direction(&normal_matrix, local_normal),
                );

                let uv = if mesh.vertex_uv.exists {
                    let value = mesh.vertex_uv[source_index];
                    [value.x as f32, value.y as f32]
                } else {
                    [0.0, 0.0]
                };

                let vertex_index = vertices.len() as u32;
                vertices.push(RenderVertex {
                    position: [
                        world_position.x as f32,
                        world_position.y as f32,
                        world_position.z as f32,
                    ],
                    normal: [
                        world_normal.x as f32,
                        world_normal.y as f32,
                        world_normal.z as f32,
                    ],
                    uv,
                    joints: [0; 4],
                    weights: [0.0; 4],
                });
                indices.push(vertex_index);
            }
        }

        if vertices.is_empty() {
            continue;
        }

        rendered.meshes.push(RenderMesh {
            name: node.element.name.to_string(),
            vertices,
            indices,
            skinned: false,
        });
    }

    if rendered.is_empty() {
        return Err(format!(
            "FBX {} contains no renderable static mesh geometry",
            path.display()
        ));
    }

    Ok(rendered)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_fbx_returns_a_readable_error() {
        let error = decode_fbx_scene("definitely-missing-fresh-builder.fbx")
            .unwrap_err();
        assert!(error.contains("Failed to decode FBX"));
    }
}
