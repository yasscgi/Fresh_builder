use builder_render::RenderScene;

pub fn encode_binary_stl(scene: &RenderScene) -> Result<Vec<u8>, String> {
    let triangle_count = scene
        .meshes
        .iter()
        .map(|mesh| {
            if mesh.indices.len() % 3 != 0 {
                Err(format!(
                    "Mesh {} index count {} is not divisible by 3",
                    mesh.name,
                    mesh.indices.len()
                ))
            } else {
                Ok(mesh.indices.len() / 3)
            }
        })
        .collect::<Result<Vec<_>, _>>()?
        .into_iter()
        .sum::<usize>();

    if triangle_count > u32::MAX as usize {
        return Err("STL triangle count exceeds u32 capacity".to_owned());
    }

    let mut bytes = Vec::with_capacity(84 + triangle_count * 50);
    let mut header = [0_u8; 80];
    let label = b"Fresh Builder binary STL";
    header[..label.len()].copy_from_slice(label);
    bytes.extend_from_slice(&header);
    bytes.extend_from_slice(&(triangle_count as u32).to_le_bytes());

    for mesh in &scene.meshes {
        for triangle in mesh.indices.chunks_exact(3) {
            let a = vertex_position(mesh, triangle[0])?;
            let b = vertex_position(mesh, triangle[1])?;
            let c = vertex_position(mesh, triangle[2])?;
            let normal = face_normal(a, b, c);

            push_vec3(&mut bytes, normal);
            push_vec3(&mut bytes, a);
            push_vec3(&mut bytes, b);
            push_vec3(&mut bytes, c);
            bytes.extend_from_slice(&0_u16.to_le_bytes());
        }
    }

    Ok(bytes)
}

pub fn write_binary_stl(
    scene: &RenderScene,
    path: impl AsRef<std::path::Path>,
) -> Result<(), String> {
    let bytes = encode_binary_stl(scene)?;
    std::fs::write(path.as_ref(), bytes)
        .map_err(|error| format!("Failed to write STL {}: {error}", path.as_ref().display()))
}

fn vertex_position(
    mesh: &builder_render::RenderMesh,
    index: u32,
) -> Result<[f32; 3], String> {
    mesh.vertices
        .get(index as usize)
        .map(|vertex| vertex.position)
        .ok_or_else(|| {
            format!(
                "Mesh {} references out-of-range vertex {}",
                mesh.name, index
            )
        })
}

fn push_vec3(bytes: &mut Vec<u8>, value: [f32; 3]) {
    for component in value {
        bytes.extend_from_slice(&component.to_le_bytes());
    }
}

fn face_normal(a: [f32; 3], b: [f32; 3], c: [f32; 3]) -> [f32; 3] {
    let ab = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
    let ac = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
    let cross = [
        ab[1] * ac[2] - ab[2] * ac[1],
        ab[2] * ac[0] - ab[0] * ac[2],
        ab[0] * ac[1] - ab[1] * ac[0],
    ];
    let length =
        (cross[0] * cross[0] + cross[1] * cross[1] + cross[2] * cross[2]).sqrt();
    if length > 1.0e-12 {
        [cross[0] / length, cross[1] / length, cross[2] / length]
    } else {
        [0.0, 0.0, 0.0]
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use builder_render::{RenderMesh, RenderScene, RenderVertex};

    #[test]
    fn encodes_one_binary_stl_triangle() {
        let scene = RenderScene {
            meshes: vec![RenderMesh {
                name: "triangle".into(),
                vertices: vec![
                    RenderVertex { position: [0.0, 0.0, 0.0], ..RenderVertex::default() },
                    RenderVertex { position: [1.0, 0.0, 0.0], ..RenderVertex::default() },
                    RenderVertex { position: [0.0, 1.0, 0.0], ..RenderVertex::default() },
                ],
                indices: vec![0, 1, 2],
                skinned: false,
            }],
            ..RenderScene::default()
        };

        let bytes = encode_binary_stl(&scene).unwrap();
        assert_eq!(bytes.len(), 134);
        assert_eq!(u32::from_le_bytes(bytes[80..84].try_into().unwrap()), 1);
    }

    #[test]
    fn rejects_non_triangle_index_buffers() {
        let scene = RenderScene {
            meshes: vec![RenderMesh {
                name: "bad".into(),
                vertices: vec![RenderVertex::default(); 4],
                indices: vec![0, 1, 2, 3],
                skinned: false,
            }],
            ..RenderScene::default()
        };
        assert!(encode_binary_stl(&scene).is_err());
    }
}
