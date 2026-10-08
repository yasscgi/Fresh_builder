use std::{
    collections::{HashMap, HashSet},
    path::Path,
};

use builder_render::{
    identity_matrix, RenderJoint, RenderMesh, RenderScene, RenderSkeleton,
    RenderVertex,
};

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
        clean_skin_weights: true,
        skip_skin_vertices: false,
        load_external_files: false,
        ignore_missing_external_files: true,
        ..Default::default()
    };

    let scene = ufbx::load_file(path_str, opts).map_err(|error| {
        format!(
            "Failed to decode FBX {}: {}",
            path.display(),
            error.description
        )
    })?;

    let mut skinned_node_id = None::<u32>;
    for node in &scene.nodes {
        let Some(mesh) = &node.mesh else {
            continue;
        };
        if mesh.skin_deformers.is_empty() {
            continue;
        }
        if mesh.skin_deformers.len() > 1 {
            return Err(format!(
                "FBX node '{}' has {} skin deformers; Native Builder currently supports one.",
                node.element.name,
                mesh.skin_deformers.len()
            ));
        }
        if let Some(existing) = skinned_node_id {
            if existing != node.element.typed_id {
                return Err(
                    "Native FBX skinning currently supports one skinned mesh node per scene. Export a single skinned base character or use GLB/glTF for multi-skinned scenes."
                        .to_owned(),
                );
            }
        } else {
            skinned_node_id = Some(node.element.typed_id);
        }
    }

    let (skeleton, bone_joint_indices) = if let Some(node_id) = skinned_node_id {
        let node = scene
            .nodes
            .iter()
            .find(|candidate| candidate.element.typed_id == node_id)
            .ok_or_else(|| "FBX skinned node disappeared during decode".to_owned())?;
        let mesh = node
            .mesh
            .as_ref()
            .ok_or_else(|| "FBX skinned node has no mesh".to_owned())?;
        let skin = &mesh.skin_deformers[0];
        build_skeleton(&scene, skin)?
    } else {
        (RenderSkeleton::default(), HashMap::new())
    };

    let mut rendered = RenderScene {
        meshes: Vec::new(),
        skeleton,
    };

    for node in &scene.nodes {
        if node.is_root || !node.visible {
            continue;
        }

        let Some(mesh_ref) = &node.mesh else {
            continue;
        };
        let mesh = &**mesh_ref;
        if mesh.num_triangles == 0 || mesh.faces.is_empty() {
            continue;
        }

        let skin = if mesh.skin_deformers.is_empty() {
            None
        } else {
            Some(&mesh.skin_deformers[0])
        };

        let mut vertices =
            Vec::<RenderVertex>::with_capacity(mesh.num_triangles * 3);
        let mut indices = Vec::<u32>::with_capacity(mesh.num_triangles * 3);
        let mut tri_indices =
            vec![0_u32; (mesh.max_face_triangles * 3).max(3)];
        let normal_matrix = ufbx::matrix_for_normals(&node.geometry_to_world);

        for &face in &mesh.faces {
            let triangle_count = mesh.triangulate_face(&mut tri_indices, face);
            let corner_count = triangle_count as usize * 3;

            for &source_index in &tri_indices[..corner_count] {
                let source_index = source_index as usize;
                let local_position = mesh.vertex_position[source_index];
                let local_normal = mesh.vertex_normal[source_index];

                let (position, normal, joints, weights) =
                    if let Some(skin) = skin {
                        let control_vertex =
                            mesh.vertex_indices[source_index] as usize;
                        let (joints, weights) = skin_weights(
                            skin,
                            control_vertex,
                            &bone_joint_indices,
                        )?;

                        (
                            vec3_to_f32(local_position),
                            normalize_vec3(local_normal),
                            joints,
                            weights,
                        )
                    } else {
                        let world_position = ufbx::transform_position(
                            &node.geometry_to_world,
                            local_position,
                        );
                        let world_normal = ufbx::vec3_normalize(
                            ufbx::transform_direction(
                                &normal_matrix,
                                local_normal,
                            ),
                        );
                        (
                            vec3_to_f32(world_position),
                            vec3_to_f32(world_normal),
                            [0; 4],
                            [0.0; 4],
                        )
                    };

                let uv = if mesh.vertex_uv.exists {
                    let value = mesh.vertex_uv[source_index];
                    [value.x as f32, value.y as f32]
                } else {
                    [0.0, 0.0]
                };

                let vertex_index = vertices.len() as u32;
                vertices.push(RenderVertex {
                    position,
                    normal,
                    uv,
                    joints,
                    weights,
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
            skinned: skin.is_some(),
        });
    }

    if rendered.is_empty() {
        return Err(format!(
            "FBX {} contains no renderable mesh geometry",
            path.display()
        ));
    }

    Ok(rendered)
}

fn build_skeleton(
    scene: &ufbx::Scene,
    skin: &ufbx::SkinDeformer,
) -> Result<(RenderSkeleton, HashMap<u32, u16>), String> {
    let mut included = HashSet::<u32>::new();
    let mut inverse_by_node = HashMap::<u32, ufbx::Matrix>::new();

    for cluster in &skin.clusters {
        let bone = cluster
            .bone_node
            .as_deref()
            .ok_or_else(|| "FBX skin cluster is missing its bone node".to_owned())?;
        inverse_by_node
            .entry(bone.element.typed_id)
            .or_insert(cluster.geometry_to_bone);

        let mut current = Some(bone);
        while let Some(node) = current {
            included.insert(node.element.typed_id);
            current = node.parent.as_deref();
        }
    }

    let mut nodes: Vec<&ufbx::Node> = scene
        .nodes
        .iter()
        .map(|node| &**node)
        .filter(|node| included.contains(&node.element.typed_id))
        .collect();
    nodes.sort_by_key(|node| node.node_depth);

    if nodes.len() > u16::MAX as usize {
        return Err("FBX skeleton exceeds 65535 joints".to_owned());
    }

    let index_by_node: HashMap<u32, u16> = nodes
        .iter()
        .enumerate()
        .map(|(index, node)| (node.element.typed_id, index as u16))
        .collect();

    let joints = nodes
        .iter()
        .map(|node| {
            let parent = node
                .parent
                .as_deref()
                .and_then(|parent| index_by_node.get(&parent.element.typed_id))
                .copied()
                .map(u32::from);

            let local_matrix = if node.parent.is_none() {
                matrix_to_render(node.node_to_world)
            } else {
                matrix_to_render(node.node_to_parent)
            };

            let inverse_bind_matrix = inverse_by_node
                .get(&node.element.typed_id)
                .copied()
                .map(matrix_to_render)
                .unwrap_or_else(identity_matrix);

            RenderJoint {
                name: node.element.name.to_string(),
                parent,
                inverse_bind_matrix,
                local_matrix,
            }
        })
        .collect();

    Ok((RenderSkeleton { joints }, index_by_node))
}

fn skin_weights(
    skin: &ufbx::SkinDeformer,
    control_vertex: usize,
    bone_joint_indices: &HashMap<u32, u16>,
) -> Result<([u16; 4], [f32; 4]), String> {
    let skin_vertex = skin
        .vertices
        .get(control_vertex)
        .ok_or_else(|| format!("FBX skin vertex {control_vertex} is missing"))?;

    let mut joints = [0_u16; 4];
    let mut weights = [0.0_f32; 4];
    let mut used = 0usize;
    let mut total = 0.0_f32;

    let begin = skin_vertex.weight_begin as usize;
    let count = skin_vertex.num_weights as usize;

    for weight in skin.weights.iter().skip(begin).take(count) {
        if used >= 4 {
            break;
        }

        let cluster = skin
            .clusters
            .get(weight.cluster_index as usize)
            .ok_or_else(|| {
                format!(
                    "FBX skin weight references missing cluster {}",
                    weight.cluster_index
                )
            })?;
        let bone = cluster
            .bone_node
            .as_deref()
            .ok_or_else(|| "FBX skin cluster is missing its bone node".to_owned())?;
        let Some(&joint_index) =
            bone_joint_indices.get(&bone.element.typed_id)
        else {
            continue;
        };

        let value = weight.weight as f32;
        if !value.is_finite() || value <= 0.0 {
            continue;
        }

        joints[used] = joint_index;
        weights[used] = value;
        total += value;
        used += 1;
    }

    if total > f32::EPSILON {
        for weight in &mut weights[..used] {
            *weight /= total;
        }
    }

    Ok((joints, weights))
}

fn matrix_to_render(matrix: ufbx::Matrix) -> [[f32; 4]; 4] {
    [
        [
            matrix.m00 as f32,
            matrix.m10 as f32,
            matrix.m20 as f32,
            0.0,
        ],
        [
            matrix.m01 as f32,
            matrix.m11 as f32,
            matrix.m21 as f32,
            0.0,
        ],
        [
            matrix.m02 as f32,
            matrix.m12 as f32,
            matrix.m22 as f32,
            0.0,
        ],
        [
            matrix.m03 as f32,
            matrix.m13 as f32,
            matrix.m23 as f32,
            1.0,
        ],
    ]
}

fn vec3_to_f32(value: ufbx::Vec3) -> [f32; 3] {
    [value.x as f32, value.y as f32, value.z as f32]
}

fn normalize_vec3(value: ufbx::Vec3) -> [f32; 3] {
    vec3_to_f32(ufbx::vec3_normalize(value))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matrix_conversion_matches_translation_layout() {
        let mut matrix = ufbx::Matrix::identity();
        matrix.m03 = 1.0;
        matrix.m13 = 2.0;
        matrix.m23 = 3.0;

        let converted = matrix_to_render(matrix);
        assert_eq!(converted[3], [1.0, 2.0, 3.0, 1.0]);
    }

    #[test]
    fn missing_fbx_returns_a_readable_error() {
        let error = decode_fbx_scene("definitely-missing-fresh-builder.fbx")
            .unwrap_err();
        assert!(error.contains("Failed to decode FBX"));
    }
}
