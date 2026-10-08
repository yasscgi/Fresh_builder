use builder_render::{RenderScene, RenderVertex};

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct SafeRepairReport {
    pub removed_invalid_triangles: u64,
    pub removed_degenerate_triangles: u64,
    pub kept_triangles: u64,
}

pub fn safe_repair_scene(scene: &RenderScene) -> (RenderScene, SafeRepairReport) {
    let mut repaired = scene.clone();
    let mut report = SafeRepairReport::default();

    for mesh in &mut repaired.meshes {
        let mut next_indices = Vec::<u32>::with_capacity(mesh.indices.len());

        for triangle in mesh.indices.chunks_exact(3) {
            if triangle
                .iter()
                .any(|index| *index as usize >= mesh.vertices.len())
            {
                report.removed_invalid_triangles += 1;
                continue;
            }

            let a = mesh.vertices[triangle[0] as usize].position;
            let b = mesh.vertices[triangle[1] as usize].position;
            let c = mesh.vertices[triangle[2] as usize].position;
            let normal = face_normal(a, b, c);

            if normal.is_none() {
                report.removed_degenerate_triangles += 1;
                continue;
            }

            next_indices.extend_from_slice(triangle);
            report.kept_triangles += 1;
        }

        if mesh.indices.len() % 3 != 0 {
            report.removed_invalid_triangles += 1;
        }

        mesh.indices = next_indices;
        recompute_vertex_normals(mesh.vertices.as_mut_slice(), &mesh.indices);
    }

    repaired.meshes.retain(|mesh| !mesh.indices.is_empty());
    (repaired, report)
}

fn recompute_vertex_normals(vertices: &mut [RenderVertex], indices: &[u32]) {
    let mut sums = vec![[0.0_f32; 3]; vertices.len()];

    for triangle in indices.chunks_exact(3) {
        let ia = triangle[0] as usize;
        let ib = triangle[1] as usize;
        let ic = triangle[2] as usize;

        let Some(normal) = face_normal(
            vertices[ia].position,
            vertices[ib].position,
            vertices[ic].position,
        ) else {
            continue;
        };

        for index in [ia, ib, ic] {
            sums[index][0] += normal[0];
            sums[index][1] += normal[1];
            sums[index][2] += normal[2];
        }
    }

    for (vertex, sum) in vertices.iter_mut().zip(sums) {
        vertex.normal = normalize_or(sum, vertex.normal);
    }
}

fn face_normal(
    a: [f32; 3],
    b: [f32; 3],
    c: [f32; 3],
) -> Option<[f32; 3]> {
    let ab = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
    let ac = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
    let cross = [
        ab[1] * ac[2] - ab[2] * ac[1],
        ab[2] * ac[0] - ab[0] * ac[2],
        ab[0] * ac[1] - ab[1] * ac[0],
    ];
    let length_sq =
        cross[0] * cross[0] + cross[1] * cross[1] + cross[2] * cross[2];
    if !length_sq.is_finite() || length_sq <= 1.0e-12 {
        return None;
    }
    let inv = length_sq.sqrt().recip();
    Some([cross[0] * inv, cross[1] * inv, cross[2] * inv])
}

fn normalize_or(value: [f32; 3], fallback: [f32; 3]) -> [f32; 3] {
    let length_sq =
        value[0] * value[0] + value[1] * value[1] + value[2] * value[2];
    if !length_sq.is_finite() || length_sq <= 1.0e-12 {
        return fallback;
    }
    let inv = length_sq.sqrt().recip();
    [value[0] * inv, value[1] * inv, value[2] * inv]
}

#[cfg(test)]
mod tests {
    use super::*;
    use builder_render::{RenderMesh, RenderScene, RenderVertex};

    #[test]
    fn removes_invalid_and_degenerate_triangles() {
        let scene = RenderScene {
            meshes: vec![RenderMesh {
                name: "repair".into(),
                vertices: vec![
                    RenderVertex { position: [0.0, 0.0, 0.0], ..RenderVertex::default() },
                    RenderVertex { position: [1.0, 0.0, 0.0], ..RenderVertex::default() },
                    RenderVertex { position: [0.0, 1.0, 0.0], ..RenderVertex::default() },
                    RenderVertex { position: [2.0, 0.0, 0.0], ..RenderVertex::default() },
                ],
                indices: vec![
                    0, 1, 2,
                    0, 0, 0,
                    0, 1, 99,
                ],
                skinned: false,
            }],
            ..RenderScene::default()
        };

        let (repaired, report) = safe_repair_scene(&scene);
        assert_eq!(report.kept_triangles, 1);
        assert_eq!(report.removed_degenerate_triangles, 1);
        assert_eq!(report.removed_invalid_triangles, 1);
        assert_eq!(repaired.meshes[0].indices, vec![0, 1, 2]);
        assert!(repaired.meshes[0].vertices[0].normal[2] > 0.99);
    }

    #[test]
    fn drops_meshes_with_no_valid_triangles() {
        let scene = RenderScene {
            meshes: vec![RenderMesh {
                name: "empty".into(),
                vertices: vec![RenderVertex::default(); 3],
                indices: vec![0, 0, 0],
                skinned: false,
            }],
            ..RenderScene::default()
        };

        let (repaired, report) = safe_repair_scene(&scene);
        assert_eq!(report.removed_degenerate_triangles, 1);
        assert!(repaired.meshes.is_empty());
    }
}
