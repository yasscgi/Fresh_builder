use crate::{identity_matrix, RenderSkeleton};

pub type Mat4 = [[f32; 4]; 4];

const WEIGHT_EPSILON: f32 = 1.0e-8;

#[derive(Clone, Debug)]
pub struct SkeletonPose {
    names: Vec<String>,
    parents: Vec<Option<u32>>,
    inverse_bind: Vec<Mat4>,
    rest_local: Vec<Mat4>,
    current_local: Vec<Mat4>,
}

impl SkeletonPose {
    pub fn from_skeleton(skeleton: &RenderSkeleton) -> Result<Self, String> {
        let joint_count = skeleton.joints.len();

        for (index, joint) in skeleton.joints.iter().enumerate() {
            if let Some(parent) = joint.parent {
                if parent as usize >= joint_count {
                    return Err(format!(
                        "Joint {} has out-of-range parent index {}",
                        joint.name, parent
                    ));
                }
                if parent as usize == index {
                    return Err(format!("Joint {} cannot parent itself", joint.name));
                }
            }
        }

        let pose = Self {
            names: skeleton.joints.iter().map(|joint| joint.name.clone()).collect(),
            parents: skeleton.joints.iter().map(|joint| joint.parent).collect(),
            inverse_bind: skeleton
                .joints
                .iter()
                .map(|joint| joint.inverse_bind_matrix)
                .collect(),
            rest_local: skeleton
                .joints
                .iter()
                .map(|joint| joint.local_matrix)
                .collect(),
            current_local: skeleton
                .joints
                .iter()
                .map(|joint| joint.local_matrix)
                .collect(),
        };

        pose.global_matrices()?;
        Ok(pose)
    }

    pub fn joint_count(&self) -> usize {
        self.current_local.len()
    }

    pub fn joint_index(&self, name: &str) -> Option<usize> {
        self.names.iter().position(|candidate| candidate == name)
    }

    pub fn local_matrix(&self, joint_index: usize) -> Option<Mat4> {
        self.current_local.get(joint_index).copied()
    }

    pub fn set_local_matrix(&mut self, joint_index: usize, matrix: Mat4) -> Result<(), String> {
        let slot = self
            .current_local
            .get_mut(joint_index)
            .ok_or_else(|| format!("Joint index {joint_index} is out of range"))?;
        *slot = matrix;
        Ok(())
    }

    pub fn reset_to_rest(&mut self) {
        self.current_local.clone_from(&self.rest_local);
    }

    pub fn global_matrices(&self) -> Result<Vec<Mat4>, String> {
        global_matrices(&self.parents, &self.current_local)
    }

    pub fn rest_global_matrices(&self) -> Result<Vec<Mat4>, String> {
        global_matrices(&self.parents, &self.rest_local)
    }

    pub fn palette(&self) -> Result<Vec<Mat4>, String> {
        let globals = self.global_matrices()?;
        Ok(globals
            .iter()
            .zip(&self.inverse_bind)
            .map(|(global, inverse_bind)| mat4_mul(*global, *inverse_bind))
            .collect())
    }

    pub fn rest_palette(&self) -> Result<Vec<Mat4>, String> {
        let globals = self.rest_global_matrices()?;
        Ok(globals
            .iter()
            .zip(&self.inverse_bind)
            .map(|(global, inverse_bind)| mat4_mul(*global, *inverse_bind))
            .collect())
    }
}

pub fn mat4_mul(a: Mat4, b: Mat4) -> Mat4 {
    let mut out = [[0.0; 4]; 4];
    for column in 0..4 {
        for row in 0..4 {
            out[column][row] = (0..4).map(|k| a[k][row] * b[column][k]).sum();
        }
    }
    out
}

pub fn transform_point(matrix: Mat4, point: [f32; 3]) -> [f32; 3] {
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

pub fn blend_skin_matrices(
    palette: &[Mat4],
    joints: [u32; 4],
    weights: [f32; 4],
) -> Mat4 {
    let mut blended = [[0.0; 4]; 4];
    let mut total_weight = 0.0;

    for influence in 0..4 {
        let weight = weights[influence];
        let joint_index = joints[influence] as usize;
        if !weight.is_finite() || weight <= 0.0 || joint_index >= palette.len() {
            continue;
        }

        total_weight += weight;
        for column in 0..4 {
            for row in 0..4 {
                blended[column][row] += palette[joint_index][column][row] * weight;
            }
        }
    }

    if total_weight <= WEIGHT_EPSILON || !total_weight.is_finite() {
        return identity_matrix();
    }

    let inv_weight = total_weight.recip();
    for column in 0..4 {
        for row in 0..4 {
            blended[column][row] *= inv_weight;
        }
    }
    blended
}

fn global_matrices(parents: &[Option<u32>], local: &[Mat4]) -> Result<Vec<Mat4>, String> {
    if parents.len() != local.len() {
        return Err("Skeleton parent/local matrix counts do not match".to_owned());
    }

    let mut globals = vec![identity_matrix(); local.len()];
    let mut visit_state = vec![0_u8; local.len()];

    for index in 0..local.len() {
        compute_global(index, parents, local, &mut globals, &mut visit_state)?;
    }

    Ok(globals)
}

fn compute_global(
    index: usize,
    parents: &[Option<u32>],
    local: &[Mat4],
    globals: &mut [Mat4],
    visit_state: &mut [u8],
) -> Result<Mat4, String> {
    match visit_state[index] {
        2 => return Ok(globals[index]),
        1 => return Err(format!("Skeleton hierarchy contains a cycle at joint {index}")),
        _ => {}
    }

    visit_state[index] = 1;
    let global = match parents[index] {
        Some(parent) => {
            let parent = parent as usize;
            if parent >= local.len() {
                return Err(format!("Joint {index} has out-of-range parent {parent}"));
            }
            let parent_global = compute_global(parent, parents, local, globals, visit_state)?;
            mat4_mul(parent_global, local[index])
        }
        None => local[index],
    };

    globals[index] = global;
    visit_state[index] = 2;
    Ok(global)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{RenderJoint, RenderSkeleton};

    fn translation(x: f32, y: f32, z: f32) -> Mat4 {
        let mut matrix = identity_matrix();
        matrix[3] = [x, y, z, 1.0];
        matrix
    }

    fn rotation_z(radians: f32) -> Mat4 {
        let (sin, cos) = radians.sin_cos();
        [
            [cos, sin, 0.0, 0.0],
            [-sin, cos, 0.0, 0.0],
            [0.0, 0.0, 1.0, 0.0],
            [0.0, 0.0, 0.0, 1.0],
        ]
    }

    fn approx_matrix(a: Mat4, b: Mat4) {
        for column in 0..4 {
            for row in 0..4 {
                assert!(
                    (a[column][row] - b[column][row]).abs() < 1.0e-5,
                    "matrix mismatch at [{column}][{row}]: {} vs {}",
                    a[column][row],
                    b[column][row]
                );
            }
        }
    }

    #[test]
    fn rest_palette_produces_identity_deformation() {
        let skeleton = RenderSkeleton {
            joints: vec![
                RenderJoint {
                    name: "root".into(),
                    parent: None,
                    inverse_bind_matrix: translation(-1.0, 0.0, 0.0),
                    local_matrix: translation(1.0, 0.0, 0.0),
                },
                RenderJoint {
                    name: "child".into(),
                    parent: Some(0),
                    inverse_bind_matrix: translation(-1.0, -2.0, 0.0),
                    local_matrix: translation(0.0, 2.0, 0.0),
                },
            ],
        };

        let pose = SkeletonPose::from_skeleton(&skeleton).unwrap();
        let palette = pose.rest_palette().unwrap();
        approx_matrix(palette[0], identity_matrix());
        approx_matrix(palette[1], identity_matrix());
    }

    #[test]
    fn parent_rotation_moves_child_global_transform() {
        let skeleton = RenderSkeleton {
            joints: vec![
                RenderJoint {
                    name: "root".into(),
                    parent: None,
                    inverse_bind_matrix: identity_matrix(),
                    local_matrix: identity_matrix(),
                },
                RenderJoint {
                    name: "child".into(),
                    parent: Some(0),
                    inverse_bind_matrix: identity_matrix(),
                    local_matrix: translation(1.0, 0.0, 0.0),
                },
            ],
        };

        let mut pose = SkeletonPose::from_skeleton(&skeleton).unwrap();
        pose.set_local_matrix(0, rotation_z(core::f32::consts::FRAC_PI_2))
            .unwrap();

        let globals = pose.global_matrices().unwrap();
        let child = transform_point(globals[1], [0.0, 0.0, 0.0]);
        assert!(child[0].abs() < 1.0e-5);
        assert!((child[1] - 1.0).abs() < 1.0e-5);
    }

    #[test]
    fn four_weight_blend_is_normalized() {
        let palette = vec![
            translation(1.0, 0.0, 0.0),
            translation(0.0, 2.0, 0.0),
            translation(0.0, 0.0, 3.0),
            identity_matrix(),
        ];
        let blended = blend_skin_matrices(
            &palette,
            [0, 1, 2, 3],
            [2.0, 2.0, 2.0, 2.0],
        );
        let point = transform_point(blended, [0.0, 0.0, 0.0]);
        assert!((point[0] - 0.25).abs() < 1.0e-5);
        assert!((point[1] - 0.5).abs() < 1.0e-5);
        assert!((point[2] - 0.75).abs() < 1.0e-5);
    }

    #[test]
    fn zero_total_weight_falls_back_to_identity() {
        let palette = vec![translation(5.0, 0.0, 0.0)];
        approx_matrix(
            blend_skin_matrices(&palette, [0, 0, 0, 0], [0.0; 4]),
            identity_matrix(),
        );
    }

    #[test]
    fn hierarchy_cycles_are_rejected() {
        let skeleton = RenderSkeleton {
            joints: vec![
                RenderJoint {
                    name: "a".into(),
                    parent: Some(1),
                    inverse_bind_matrix: identity_matrix(),
                    local_matrix: identity_matrix(),
                },
                RenderJoint {
                    name: "b".into(),
                    parent: Some(0),
                    inverse_bind_matrix: identity_matrix(),
                    local_matrix: identity_matrix(),
                },
            ],
        };
        assert!(SkeletonPose::from_skeleton(&skeleton).is_err());
    }
}
