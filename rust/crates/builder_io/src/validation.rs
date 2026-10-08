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
}

impl PrintValidationReport {
    pub fn watertight(&self) -> bool {
        self.invalid_indices == 0
            && self.degenerate_triangles == 0
            && self.boundary_edges == 0
            && self.non_manifold_edges == 0
    }
}

pub fn validate_print_scene(scene: &RenderScene) -> PrintValidationReport {
    let mut report = PrintValidationReport {
        mesh_count: scene.meshes.len() as u32,
        ..PrintValidationReport::default()
    };

    for mesh in &scene.meshes {
        let mut edges = HashMap::<(u32, u32), u32>::new();

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

            for (u, v) in [(a, b), (b, c), (c, a)] {
                let edge = if u < v { (u, v) } else { (v, u) };
                *edges.entry(edge).or_default() += 1;
            }
        }

        if mesh.indices.len() % 3 != 0 {
            report.invalid_indices += 1;
        }

        for count in edges.values().copied() {
            match count {
                1 => report.boundary_edges += 1,
                2 => {}
                _ => report.non_manifold_edges += 1,
            }
        }
    }

    report
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
