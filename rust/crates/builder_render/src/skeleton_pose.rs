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

    pub fn joint_names(&self) -> &[String] {
        &self.names
    }

    pub fn parent_index(&self, joint_index: usize) -> Option<usize> {
        self.parents
            .get(joint_index)
            .and_then(|parent| parent.map(|value| value as usize))
    }

    pub fn joint_world_position(&self, joint_index: usize) -> Result<[f32; 3], String> {
        let globals = self.global_matrices()?;
        let global = globals
            .get(joint_index)
            .copied()
            .ok_or_else(|| format!("Joint index {joint_index} is out of range"))?;
        Ok(transform_point(global, [0.0, 0.0, 0.0]))
    }

    pub fn apply_two_bone_solution(
        &mut self,
        upper: usize,
        lower: usize,
        end: usize,
        solved_mid: [f32; 3],
        solved_end: [f32; 3],
    ) -> Result<(), String> {
        if !finite_vec3(solved_mid) || !finite_vec3(solved_end) {
            return Err("IK solution points must be finite".to_owned());
        }
        if self.parent_index(lower) != Some(upper) {
            return Err("IK lower joint must be a direct child of upper joint".to_owned());
        }
        if self.parent_index(end) != Some(lower) {
            return Err("IK end joint must be a direct child of lower joint".to_owned());
        }

        self.aim_joint_child(upper, lower, solved_mid)?;
        self.aim_joint_child(lower, end, solved_end)?;
        Ok(())
    }

    fn aim_joint_child(
        &mut self,
        joint: usize,
        child: usize,
        desired_child_world: [f32; 3],
    ) -> Result<(), String> {
        let globals = self.global_matrices()?;
        let joint_global = *globals
            .get(joint)
            .ok_or_else(|| format!("Joint index {joint} is out of range"))?;
        let child_global = *globals
            .get(child)
            .ok_or_else(|| format!("Joint index {child} is out of range"))?;

        let joint_position = transform_point(joint_global, [0.0, 0.0, 0.0]);
        let child_position = transform_point(child_global, [0.0, 0.0, 0.0]);
        let current_direction = sub3(child_position, joint_position);
        let desired_direction = sub3(desired_child_world, joint_position);
        let world_delta = rotation_between(current_direction, desired_direction)?;
        let desired_global = rotate_global_basis(joint_global, world_delta);

        let local = match self.parent_index(joint) {
            Some(parent) => {
                let parent_global = *globals
                    .get(parent)
                    .ok_or_else(|| format!("Parent joint index {parent} is out of range"))?;
                let inverse_parent = affine_inverse(parent_global)?;
                mat4_mul(inverse_parent, desired_global)
            }
            None => desired_global,
        };

        self.set_local_matrix(joint, local)
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

    pub fn set_local_delta_matrix(
        &mut self,
        joint_index: usize,
        delta: Mat4,
    ) -> Result<(), String> {
        let rest = self
            .rest_local
            .get(joint_index)
            .copied()
            .ok_or_else(|| format!("Joint index {joint_index} is out of range"))?;
        let slot = self
            .current_local
            .get_mut(joint_index)
            .ok_or_else(|| format!("Joint index {joint_index} is out of range"))?;
        *slot = mat4_mul(rest, delta);
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

fn finite_vec3(value: [f32; 3]) -> bool {
    value.iter().all(|component| component.is_finite())
}

fn sub3(a: [f32; 3], b: [f32; 3]) -> [f32; 3] {
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
}

fn dot3(a: [f32; 3], b: [f32; 3]) -> f32 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}

fn cross3(a: [f32; 3], b: [f32; 3]) -> [f32; 3] {
    [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    ]
}

fn length3(value: [f32; 3]) -> f32 {
    dot3(value, value).sqrt()
}

fn normalize3(value: [f32; 3]) -> Result<[f32; 3], String> {
    let length = length3(value);
    if !length.is_finite() || length <= 1.0e-7 {
        return Err("Cannot normalize a collapsed IK direction".to_owned());
    }
    Ok([value[0] / length, value[1] / length, value[2] / length])
}

fn transform_vector(matrix: Mat4, vector: [f32; 3]) -> [f32; 3] {
    [
        matrix[0][0] * vector[0] + matrix[1][0] * vector[1] + matrix[2][0] * vector[2],
        matrix[0][1] * vector[0] + matrix[1][1] * vector[1] + matrix[2][1] * vector[2],
        matrix[0][2] * vector[0] + matrix[1][2] * vector[1] + matrix[2][2] * vector[2],
    ]
}

fn rotation_between(from: [f32; 3], to: [f32; 3]) -> Result<Mat4, String> {
    let from = normalize3(from)?;
    let to = normalize3(to)?;
    let cosine = dot3(from, to).clamp(-1.0, 1.0);

    if cosine > 1.0 - 1.0e-6 {
        return Ok(identity_matrix());
    }

    let (axis, sine) = if cosine < -1.0 + 1.0e-6 {
        let reference = if from[0].abs() < 0.9 {
            [1.0, 0.0, 0.0]
        } else {
            [0.0, 1.0, 0.0]
        };
        (normalize3(cross3(from, reference))?, 0.0)
    } else {
        let cross = cross3(from, to);
        let sine = length3(cross);
        (normalize3(cross)?, sine)
    };

    let [x, y, z] = axis;
    let one_minus_cosine = 1.0 - cosine;

    Ok([
        [
            cosine + x * x * one_minus_cosine,
            y * x * one_minus_cosine + z * sine,
            z * x * one_minus_cosine - y * sine,
            0.0,
        ],
        [
            x * y * one_minus_cosine - z * sine,
            cosine + y * y * one_minus_cosine,
            z * y * one_minus_cosine + x * sine,
            0.0,
        ],
        [
            x * z * one_minus_cosine + y * sine,
            y * z * one_minus_cosine - x * sine,
            cosine + z * z * one_minus_cosine,
            0.0,
        ],
        [0.0, 0.0, 0.0, 1.0],
    ])
}

fn rotate_global_basis(global: Mat4, rotation: Mat4) -> Mat4 {
    let mut out = global;
    for column in 0..3 {
        let rotated = transform_vector(
            rotation,
            [global[column][0], global[column][1], global[column][2]],
        );
        out[column][0] = rotated[0];
        out[column][1] = rotated[1];
        out[column][2] = rotated[2];
    }
    out
}

fn affine_inverse(matrix: Mat4) -> Result<Mat4, String> {
    let m00 = matrix[0][0];
    let m01 = matrix[1][0];
    let m02 = matrix[2][0];
    let m10 = matrix[0][1];
    let m11 = matrix[1][1];
    let m12 = matrix[2][1];
    let m20 = matrix[0][2];
    let m21 = matrix[1][2];
    let m22 = matrix[2][2];

    let determinant =
        m00 * (m11 * m22 - m12 * m21)
        - m01 * (m10 * m22 - m12 * m20)
        + m02 * (m10 * m21 - m11 * m20);

    if !determinant.is_finite() || determinant.abs() <= 1.0e-8 {
        return Err("IK parent transform is not invertible".to_owned());
    }
    let inv_det = determinant.recip();

    let r00 = (m11 * m22 - m12 * m21) * inv_det;
    let r01 = (m02 * m21 - m01 * m22) * inv_det;
    let r02 = (m01 * m12 - m02 * m11) * inv_det;
    let r10 = (m12 * m20 - m10 * m22) * inv_det;
    let r11 = (m00 * m22 - m02 * m20) * inv_det;
    let r12 = (m02 * m10 - m00 * m12) * inv_det;
    let r20 = (m10 * m21 - m11 * m20) * inv_det;
    let r21 = (m01 * m20 - m00 * m21) * inv_det;
    let r22 = (m00 * m11 - m01 * m10) * inv_det;

    let translation = [matrix[3][0], matrix[3][1], matrix[3][2]];
    let inverse_translation = [
        -(r00 * translation[0] + r01 * translation[1] + r02 * translation[2]),
        -(r10 * translation[0] + r11 * translation[1] + r12 * translation[2]),
        -(r20 * translation[0] + r21 * translation[1] + r22 * translation[2]),
    ];

    Ok([
        [r00, r10, r20, 0.0],
        [r01, r11, r21, 0.0],
        [r02, r12, r22, 0.0],
        [
            inverse_translation[0],
            inverse_translation[1],
            inverse_translation[2],
            1.0,
        ],
    ])
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

pub fn euler_xyz_matrix(x: f32, y: f32, z: f32) -> Mat4 {
    let (sx, cx) = x.sin_cos();
    let (sy, cy) = y.sin_cos();
    let (sz, cz) = z.sin_cos();

    let rx = [
        [1.0, 0.0, 0.0, 0.0],
        [0.0, cx, sx, 0.0],
        [0.0, -sx, cx, 0.0],
        [0.0, 0.0, 0.0, 1.0],
    ];
    let ry = [
        [cy, 0.0, -sy, 0.0],
        [0.0, 1.0, 0.0, 0.0],
        [sy, 0.0, cy, 0.0],
        [0.0, 0.0, 0.0, 1.0],
    ];
    let rz = [
        [cz, sz, 0.0, 0.0],
        [-sz, cz, 0.0, 0.0],
        [0.0, 0.0, 1.0, 0.0],
        [0.0, 0.0, 0.0, 1.0],
    ];

    mat4_mul(rz, mat4_mul(ry, rx))
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
    fn fk_delta_preserves_rest_translation() {
        let skeleton = RenderSkeleton {
            joints: vec![RenderJoint {
                name: "arm".into(),
                parent: None,
                inverse_bind_matrix: identity_matrix(),
                local_matrix: translation(2.0, 0.0, 0.0),
            }],
        };

        let mut pose = SkeletonPose::from_skeleton(&skeleton).unwrap();
        pose.set_local_delta_matrix(
            0,
            euler_xyz_matrix(0.0, 0.0, core::f32::consts::FRAC_PI_2),
        )
        .unwrap();

        let global = pose.global_matrices().unwrap()[0];
        let origin = transform_point(global, [0.0, 0.0, 0.0]);
        let x_axis = transform_point(global, [1.0, 0.0, 0.0]);

        assert!((origin[0] - 2.0).abs() < 1.0e-5);
        assert!(origin[1].abs() < 1.0e-5);
        assert!((x_axis[0] - 2.0).abs() < 1.0e-5);
        assert!((x_axis[1] - 1.0).abs() < 1.0e-5);
    }

    #[test]
    fn rotation_between_aligns_bone_direction() {
        let rotation = rotation_between([1.0, 0.0, 0.0], [0.0, 1.0, 0.0]).unwrap();
        let aligned = transform_vector(rotation, [1.0, 0.0, 0.0]);
        assert!(aligned[0].abs() < 1.0e-5);
        assert!((aligned[1] - 1.0).abs() < 1.0e-5);
        assert!(aligned[2].abs() < 1.0e-5);
    }

    #[test]
    fn two_bone_solution_aims_upper_and_lower_at_solved_points() {
        let skeleton = RenderSkeleton {
            joints: vec![
                RenderJoint {
                    name: "upper".into(),
                    parent: None,
                    inverse_bind_matrix: identity_matrix(),
                    local_matrix: identity_matrix(),
                },
                RenderJoint {
                    name: "lower".into(),
                    parent: Some(0),
                    inverse_bind_matrix: identity_matrix(),
                    local_matrix: translation(1.0, 0.0, 0.0),
                },
                RenderJoint {
                    name: "end".into(),
                    parent: Some(1),
                    inverse_bind_matrix: identity_matrix(),
                    local_matrix: translation(1.0, 0.0, 0.0),
                },
            ],
        };

        let mut pose = SkeletonPose::from_skeleton(&skeleton).unwrap();
        let solved_mid = [0.0, 1.0, 0.0];
        let solved_end = [1.0, 1.0, 0.0];
        pose.apply_two_bone_solution(0, 1, 2, solved_mid, solved_end)
            .unwrap();

        let mid = pose.joint_world_position(1).unwrap();
        let end = pose.joint_world_position(2).unwrap();
        for axis in 0..3 {
            assert!((mid[axis] - solved_mid[axis]).abs() < 1.0e-4);
            assert!((end[axis] - solved_end[axis]).abs() < 1.0e-4);
        }
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
