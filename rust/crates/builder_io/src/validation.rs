use std::collections::HashMap;

use builder_render::RenderScene;

#[derive(Clone, Debug, Default, PartialEq)]
pub struct PrintValidationReport {
    pub mesh_count: u32,
    pub triangle_count: u64,
    pub degenerate_triangles: u64,
    pub boundary_edges: u64,
    pub non_manifold_edges: u64,
    pub invalid_indices: u64,
    pub inconsistent_winding_edges: u64,
    pub connected_components: u32,
    pub size_meters: [f32; 3],
}

impl PrintValidationReport {
    pub fn watertight(&self) -> bool {
        self.invalid_indices == 0
            && self.degenerate_triangles == 0
            && self.boundary_edges == 0
            && self.non_manifold_edges == 0
            && self.inconsistent_winding_edges == 0
    }
}

pub fn validate_print_scene(scene: &RenderScene) -> PrintValidationReport {
    let mut report = PrintValidationReport {
        mesh_count: scene.meshes.len() as u32,
        ..PrintValidationReport::default()
    };
    let mut bounds_min = [f32::INFINITY; 3];
    let mut bounds_max = [f32::NEG_INFINITY; 3];
    let mut has_vertex = false;

    for mesh in &scene.meshes {
        let mut edges = HashMap::<(u32, u32), (u32, i32)>::new();
        let mut triangle_edges = Vec::<[(u32, u32); 3]>::new();

        for vertex in &mesh.vertices {
            let position = vertex.position;
            if position.iter().all(|value| value.is_finite()) {
                has_vertex = true;
                for axis in 0..3 {
                    bounds_min[axis] = bounds_min[axis].min(position[axis]);
                    bounds_max[axis] = bounds_max[axis].max(position[axis]);
                }
            }
        }

        for triangle in mesh.indices.chunks_exact(3) {
            report.triangle_count += 1;
            let a = triangle[0];
            let b = triangle[1];
            let c = triangle[2];

            if [a, b, c]
                .iter()
                .any(|index| *index as usize >= mesh.vertices.len())
            {
                report.invalid_indices += 1;
                continue;
            }

            let pa = mesh.vertices[a as usize].position;
            let pb = mesh.vertices[b as usize].position;
            let pc = mesh.vertices[c as usize].position;
            if triangle_area_twice(pa, pb, pc) <= 1.0e-10 {
                report.degenerate_triangles += 1;
            }

            let oriented = [(a, b), (b, c), (c, a)];
            let mut canonical = [(0_u32, 0_u32); 3];
            for (slot, (u, v)) in oriented.into_iter().enumerate() {
                let edge = if u < v { (u, v) } else { (v, u) };
                canonical[slot] = edge;
                let direction = if (u, v) == edge { 1 } else { -1 };
                let entry = edges.entry(edge).or_insert((0, 0));
                entry.0 += 1;
                entry.1 += direction;
            }
            triangle_edges.push(canonical);
        }

        if mesh.indices.len() % 3 != 0 {
            report.invalid_indices += 1;
        }

        for (count, direction_sum) in edges.values().copied() {
            match count {
                1 => report.boundary_edges += 1,
                2 => {
                    if direction_sum != 0 {
                        report.inconsistent_winding_edges += 1;
                    }
                }
                _ => report.non_manifold_edges += 1,
            }
        }

        if !triangle_edges.is_empty() {
            report.connected_components +=
                triangle_component_count(&triangle_edges) as u32;
        }
    }

    if has_vertex {
        report.size_meters = [
            (bounds_max[0] - bounds_min[0]).max(0.0),
            (bounds_max[1] - bounds_min[1]).max(0.0),
            (bounds_max[2] - bounds_min[2]).max(0.0),
        ];
    }

    report
}


fn triangle_component_count(triangle_edges: &[[(u32, u32); 3]]) -> usize {
    let mut edge_to_triangles =
        HashMap::<(u32, u32), Vec<usize>>::new();
    for (triangle_index, edges) in triangle_edges.iter().enumerate() {
        for edge in edges {
            edge_to_triangles
                .entry(*edge)
                .or_default()
                .push(triangle_index);
        }
    }

    let mut visited = vec![false; triangle_edges.len()];
    let mut stack = Vec::<usize>::new();
    let mut components = 0usize;

    for start in 0..triangle_edges.len() {
        if visited[start] {
            continue;
        }
        components += 1;
        visited[start] = true;
        stack.push(start);

        while let Some(current) = stack.pop() {
            for edge in triangle_edges[current] {
                if let Some(neighbors) = edge_to_triangles.get(&edge) {
                    for &neighbor in neighbors {
                        if !visited[neighbor] {
                            visited[neighbor] = true;
                            stack.push(neighbor);
                        }
                    }
                }
            }
        }
    }

    components
}

fn triangle_area_twice(a: [f32; 3], b: [f32; 3], c: [f32; 3]) -> f32 {
    let ab = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
    let ac = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
    let cross = [
        ab[1] * ac[2] - ab[2] * ac[1],
        ab[2] * ac[0] - ab[0] * ac[2],
        ab[0] * ac[1] - ab[1] * ac[0],
    ];
    (cross[0] * cross[0] + cross[1] * cross[1] + cross[2] * cross[2]).sqrt()
}

#[cfg(test)]
mod tests {
    use super::*;
    use builder_render::{RenderMesh, RenderScene, RenderVertex};

    #[test]
    fn reports_physical_bounds_in_engine_meters() {
        let scene = RenderScene {
            meshes: vec![RenderMesh {
                name: "bounds".into(),
                vertices: vec![
                    RenderVertex { position: [0.0, 0.0, 0.0], ..RenderVertex::default() },
                    RenderVertex { position: [0.1, 0.2, 0.3], ..RenderVertex::default() },
                    RenderVertex { position: [0.0, 0.2, 0.0], ..RenderVertex::default() },
                ],
                indices: vec![0, 1, 2],
                skinned: false,
            }],
            ..RenderScene::default()
        };
        let report = validate_print_scene(&scene);
        assert_eq!(report.size_meters, [0.1, 0.2, 0.3]);
    }

    #[test]
    fn detects_inconsistent_shared_edge_winding() {
        let scene = RenderScene {
            meshes: vec![RenderMesh {
                name: "winding".into(),
                vertices: vec![
                    RenderVertex { position: [0.0, 0.0, 0.0], ..RenderVertex::default() },
                    RenderVertex { position: [1.0, 0.0, 0.0], ..RenderVertex::default() },
                    RenderVertex { position: [0.0, 1.0, 0.0], ..RenderVertex::default() },
                    RenderVertex { position: [1.0, 1.0, 0.0], ..RenderVertex::default() },
                ],
                indices: vec![
                    0, 1, 2,
                    1, 2, 3,
                ],
                skinned: false,
            }],
            ..RenderScene::default()
        };
        let report = validate_print_scene(&scene);
        assert_eq!(report.inconsistent_winding_edges, 1);
        assert_eq!(report.connected_components, 1);
    }

    #[test]
    fn counts_disconnected_triangle_shells() {
        let scene = RenderScene {
            meshes: vec![RenderMesh {
                name: "shells".into(),
                vertices: vec![
                    RenderVertex { position: [0.0, 0.0, 0.0], ..RenderVertex::default() },
                    RenderVertex { position: [1.0, 0.0, 0.0], ..RenderVertex::default() },
                    RenderVertex { position: [0.0, 1.0, 0.0], ..RenderVertex::default() },
                    RenderVertex { position: [10.0, 0.0, 0.0], ..RenderVertex::default() },
                    RenderVertex { position: [11.0, 0.0, 0.0], ..RenderVertex::default() },
                    RenderVertex { position: [10.0, 1.0, 0.0], ..RenderVertex::default() },
                ],
                indices: vec![0, 1, 2, 3, 4, 5],
                skinned: false,
            }],
            ..RenderScene::default()
        };
        let report = validate_print_scene(&scene);
        assert_eq!(report.connected_components, 2);
    }

    #[test]
    fn open_triangle_reports_three_boundary_edges() {
        let scene = RenderScene {
            meshes: vec![RenderMesh {
                name: "open".into(),
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
        let report = validate_print_scene(&scene);
        assert_eq!(report.triangle_count, 1);
        assert_eq!(report.boundary_edges, 3);
        assert!(!report.watertight());
    }
}
