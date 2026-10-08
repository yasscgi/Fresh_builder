use std::{fs, path::Path};

use builder_render::{RenderMesh, RenderScene, RenderVertex};

pub fn decode_stl_scene(
    path: impl AsRef<Path>,
    meters_per_unit: f32,
) -> Result<RenderScene, String> {
    let path = path.as_ref();
    let bytes = fs::read(path)
        .map_err(|error| format!("Failed to read STL {}: {error}", path.display()))?;
    if bytes.is_empty() {
        return Err(format!("STL {} is empty", path.display()));
    }

    let scale = if meters_per_unit.is_finite() && meters_per_unit > 0.0 {
        meters_per_unit
    } else {
        0.001
    };

    let mesh = if looks_like_binary_stl(&bytes) {
        decode_binary_stl(&bytes, scale)?
    } else {
        decode_ascii_stl(&bytes, scale)?
    };

    if mesh.indices.is_empty() {
        return Err(format!(
            "STL {} contains no renderable triangles",
            path.display()
        ));
    }

    Ok(RenderScene {
        meshes: vec![mesh],
        ..RenderScene::default()
    })
}

fn looks_like_binary_stl(bytes: &[u8]) -> bool {
    if bytes.len() < 84 {
        return false;
    }

    let triangle_count = u32::from_le_bytes([
        bytes[80],
        bytes[81],
        bytes[82],
        bytes[83],
    ]) as usize;
    let expected = 84usize.saturating_add(triangle_count.saturating_mul(50));
    expected <= bytes.len() && triangle_count > 0
}

fn decode_binary_stl(bytes: &[u8], scale: f32) -> Result<RenderMesh, String> {
    if bytes.len() < 84 {
        return Err("Binary STL header is truncated".to_owned());
    }

    let triangle_count = u32::from_le_bytes([
        bytes[80],
        bytes[81],
        bytes[82],
        bytes[83],
    ]) as usize;
    let expected = 84usize
        .checked_add(
            triangle_count
                .checked_mul(50)
                .ok_or_else(|| "Binary STL triangle count overflow".to_owned())?,
        )
        .ok_or_else(|| "Binary STL size overflow".to_owned())?;

    if bytes.len() < expected {
        return Err(format!(
            "Binary STL is truncated: expected at least {expected} bytes, got {}",
            bytes.len()
        ));
    }

    let mut vertices = Vec::with_capacity(triangle_count * 3);
    let mut indices = Vec::with_capacity(triangle_count * 3);
    let mut offset = 84usize;

    for _ in 0..triangle_count {
        let encoded_normal = read_vec3(bytes, offset)?;
        offset += 12;

        let mut triangle = [[0.0_f32; 3]; 3];
        for point in &mut triangle {
            let value = read_vec3(bytes, offset)?;
            offset += 12;
            *point = [
                value[0] * scale,
                value[1] * scale,
                value[2] * scale,
            ];
        }
        offset += 2;

        let fallback = face_normal(triangle[0], triangle[1], triangle[2]);
        let normal = normalized_or(encoded_normal, fallback);

        for point in triangle {
            let index = vertices.len() as u32;
            vertices.push(RenderVertex {
                position: point,
                normal,
                uv: [0.0, 0.0],
                joints: [0; 4],
                weights: [0.0; 4],
            });
            indices.push(index);
        }
    }

    Ok(RenderMesh {
        name: "stl_mesh".to_owned(),
        vertices,
        indices,
        skinned: false,
    })
}

fn decode_ascii_stl(bytes: &[u8], scale: f32) -> Result<RenderMesh, String> {
    let text = std::str::from_utf8(bytes)
        .map_err(|_| "STL is neither valid binary STL nor UTF-8 ASCII STL".to_owned())?;

    let mut vertices = Vec::<RenderVertex>::new();
    let mut indices = Vec::<u32>::new();
    let mut pending_normal = [0.0_f32; 3];
    let mut triangle_positions = Vec::<[f32; 3]>::with_capacity(3);

    for raw_line in text.lines() {
        let line = raw_line.trim();
        let mut parts = line.split_whitespace();
        match parts.next() {
            Some("facet") if parts.next() == Some("normal") => {
                pending_normal = [
                    parse_f32(parts.next(), "ASCII STL normal x")?,
                    parse_f32(parts.next(), "ASCII STL normal y")?,
                    parse_f32(parts.next(), "ASCII STL normal z")?,
                ];
            }
            Some("vertex") => {
                triangle_positions.push([
                    parse_f32(parts.next(), "ASCII STL vertex x")? * scale,
                    parse_f32(parts.next(), "ASCII STL vertex y")? * scale,
                    parse_f32(parts.next(), "ASCII STL vertex z")? * scale,
                ]);

                if triangle_positions.len() == 3 {
                    let fallback = face_normal(
                        triangle_positions[0],
                        triangle_positions[1],
                        triangle_positions[2],
                    );
                    let normal = normalized_or(pending_normal, fallback);
                    for point in triangle_positions.drain(..) {
                        let index = vertices.len() as u32;
                        vertices.push(RenderVertex {
                            position: point,
                            normal,
                            uv: [0.0, 0.0],
                            joints: [0; 4],
                            weights: [0.0; 4],
                        });
                        indices.push(index);
                    }
                }
            }
            _ => {}
        }
    }

    if !triangle_positions.is_empty() {
        return Err("ASCII STL ended with an incomplete triangle".to_owned());
    }

    Ok(RenderMesh {
        name: "stl_mesh".to_owned(),
        vertices,
        indices,
        skinned: false,
    })
}

fn read_vec3(bytes: &[u8], offset: usize) -> Result<[f32; 3], String> {
    if offset + 12 > bytes.len() {
        return Err("STL vector is truncated".to_owned());
    }
    Ok([
        f32::from_le_bytes(bytes[offset..offset + 4].try_into().unwrap()),
        f32::from_le_bytes(bytes[offset + 4..offset + 8].try_into().unwrap()),
        f32::from_le_bytes(bytes[offset + 8..offset + 12].try_into().unwrap()),
    ])
}

fn parse_f32(value: Option<&str>, label: &str) -> Result<f32, String> {
    value
        .ok_or_else(|| format!("Missing {label}"))?
        .parse::<f32>()
        .map_err(|error| format!("Invalid {label}: {error}"))
}

fn normalized_or(value: [f32; 3], fallback: [f32; 3]) -> [f32; 3] {
    let length_sq = value[0] * value[0] + value[1] * value[1] + value[2] * value[2];
    if length_sq.is_finite() && length_sq > 1.0e-12 {
        let inv = length_sq.sqrt().recip();
        [value[0] * inv, value[1] * inv, value[2] * inv]
    } else {
        fallback
    }
}

fn face_normal(a: [f32; 3], b: [f32; 3], c: [f32; 3]) -> [f32; 3] {
    let ab = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
    let ac = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
    normalized_or(
        [
            ab[1] * ac[2] - ab[2] * ac[1],
            ab[2] * ac[0] - ab[0] * ac[2],
            ab[0] * ac[1] - ab[1] * ac[0],
        ],
        [0.0, 1.0, 0.0],
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn binary_stl_decode_applies_meters_per_unit() {
        let mut bytes = vec![0_u8; 84];
        bytes[80..84].copy_from_slice(&1_u32.to_le_bytes());

        let normal = [0.0_f32, 0.0, 1.0];
        let points = [
            [0.0_f32, 0.0, 0.0],
            [100.0_f32, 0.0, 0.0],
            [0.0_f32, 100.0, 0.0],
        ];

        for component in normal {
            bytes.extend_from_slice(&component.to_le_bytes());
        }
        for point in points {
            for component in point {
                bytes.extend_from_slice(&component.to_le_bytes());
            }
        }
        bytes.extend_from_slice(&0_u16.to_le_bytes());

        let mesh = decode_binary_stl(&bytes, 0.001).unwrap();
        assert_eq!(mesh.vertices.len(), 3);
        assert!((mesh.vertices[1].position[0] - 0.1).abs() < 1.0e-6);
    }

    #[test]
    fn ascii_stl_decode_parses_triangle() {
        let data = br#"solid test
facet normal 0 0 1
 outer loop
  vertex 0 0 0
  vertex 10 0 0
  vertex 0 10 0
 endloop
endfacet
endsolid test
"#;
        let mesh = decode_ascii_stl(data, 0.001).unwrap();
        assert_eq!(mesh.indices, vec![0, 1, 2]);
        assert!((mesh.vertices[1].position[0] - 0.01).abs() < 1.0e-6);
    }
}
