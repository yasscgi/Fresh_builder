#![forbid(unsafe_code)]

use core::ops::{Add, Div, Mul, Neg, Sub};

const EPSILON: f32 = 1.0e-6;

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Vec3 {
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

impl Vec3 {
    pub const ZERO: Self = Self::new(0.0, 0.0, 0.0);
    pub const X: Self = Self::new(1.0, 0.0, 0.0);
    pub const Y: Self = Self::new(0.0, 1.0, 0.0);
    pub const Z: Self = Self::new(0.0, 0.0, 1.0);

    pub const fn new(x: f32, y: f32, z: f32) -> Self {
        Self { x, y, z }
    }

    pub fn dot(self, other: Self) -> f32 {
        self.x * other.x + self.y * other.y + self.z * other.z
    }

    pub fn cross(self, other: Self) -> Self {
        Self::new(
            self.y * other.z - self.z * other.y,
            self.z * other.x - self.x * other.z,
            self.x * other.y - self.y * other.x,
        )
    }

    pub fn length_squared(self) -> f32 {
        self.dot(self)
    }

    pub fn length(self) -> f32 {
        self.length_squared().sqrt()
    }

    pub fn distance(self, other: Self) -> f32 {
        (self - other).length()
    }

    pub fn normalized(self) -> Option<Self> {
        let length = self.length();
        (length > EPSILON).then_some(self / length)
    }

    pub fn approx_eq(self, other: Self, epsilon: f32) -> bool {
        self.distance(other) <= epsilon
    }
}

impl Add for Vec3 {
    type Output = Self;

    fn add(self, rhs: Self) -> Self::Output {
        Self::new(self.x + rhs.x, self.y + rhs.y, self.z + rhs.z)
    }
}

impl Sub for Vec3 {
    type Output = Self;

    fn sub(self, rhs: Self) -> Self::Output {
        Self::new(self.x - rhs.x, self.y - rhs.y, self.z - rhs.z)
    }
}

impl Mul<f32> for Vec3 {
    type Output = Self;

    fn mul(self, rhs: f32) -> Self::Output {
        Self::new(self.x * rhs, self.y * rhs, self.z * rhs)
    }
}

impl Div<f32> for Vec3 {
    type Output = Self;

    fn div(self, rhs: f32) -> Self::Output {
        Self::new(self.x / rhs, self.y / rhs, self.z / rhs)
    }
}

impl Neg for Vec3 {
    type Output = Self;

    fn neg(self) -> Self::Output {
        Self::new(-self.x, -self.y, -self.z)
    }
}


#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RigProfileGeneration {
    V2Legacy,
    V3,
    Unsupported,
}

pub fn detect_rig_profile_generation(format: &str) -> RigProfileGeneration {
    match format.trim().to_ascii_lowercase().as_str() {
        "freshstl_mixamo_rig_v3" => RigProfileGeneration::V3,
        "freshstl_mixamo_rig_v2" => RigProfileGeneration::V2Legacy,
        _ => RigProfileGeneration::Unsupported,
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum SemanticBone {
    Hips,
    Spine,
    Spine1,
    Spine2,
    Neck,
    Head,
    LeftShoulder,
    LeftUpperArm,
    LeftLowerArm,
    LeftHand,
    RightShoulder,
    RightUpperArm,
    RightLowerArm,
    RightHand,
    LeftUpperLeg,
    LeftLowerLeg,
    LeftFoot,
    LeftToeBase,
    RightUpperLeg,
    RightLowerLeg,
    RightFoot,
    RightToeBase,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum IkEffector {
    LeftHand,
    RightHand,
    LeftFoot,
    RightFoot,
}

#[derive(Clone, Debug, PartialEq)]
pub struct RigBone {
    pub semantic: SemanticBone,
    pub source_name: String,
    pub parent: Option<SemanticBone>,
    pub rest_position: Vec3,
    pub primary_axis: Option<Vec3>,
    pub hinge_axis: Option<Vec3>,
    pub length: f32,
    pub confidence: f32,
}

#[derive(Clone, Debug, PartialEq)]
pub struct RigChainV3 {
    pub effector: IkEffector,
    pub upper: SemanticBone,
    pub lower: SemanticBone,
    pub end: SemanticBone,
    pub pole_direction: Vec3,
    pub upper_length: f32,
    pub lower_length: f32,
    pub confidence: f32,
}

#[derive(Clone, Debug, PartialEq)]
pub struct RigProfileV3 {
    pub format: String,
    pub autorig_version: Option<String>,
    pub detector_version: Option<String>,
    pub skeleton_signature: Option<String>,
    pub bones: Vec<RigBone>,
    pub chains: Vec<RigChainV3>,
}

impl Default for RigProfileV3 {
    fn default() -> Self {
        Self {
            format: "freshstl_mixamo_rig_v3".to_owned(),
            autorig_version: None,
            detector_version: None,
            skeleton_signature: None,
            bones: Vec::new(),
            chains: Vec::new(),
        }
    }
}

impl RigProfileV3 {
    pub fn chain(&self, effector: IkEffector) -> Option<&RigChainV3> {
        self.chains.iter().find(|chain| chain.effector == effector)
    }

    pub fn is_ik_ready(&self) -> bool {
        use IkEffector::*;
        [LeftHand, RightHand, LeftFoot, RightFoot]
            .iter()
            .all(|effector| self.chain(*effector).is_some())
    }
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct PoseState {
    pub rig_signature: Option<String>,
    pub hand_open: f32,
}

#[derive(Clone, Debug, PartialEq)]
pub struct AssetSelection {
    pub category_id: String,
    pub asset_id: String,
    pub variation_id: Option<String>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct BuilderDesign {
    pub format: String,
    pub version: u32,
    pub product_id: String,
    pub assets: Vec<AssetSelection>,
    pub pose: PoseState,
}

impl BuilderDesign {
    pub fn new(product_id: impl Into<String>) -> Self {
        Self {
            format: "fresh_builder_design".to_owned(),
            version: 4,
            product_id: product_id.into(),
            assets: Vec::new(),
            pose: PoseState::default(),
        }
    }
}

#[derive(Clone, Debug)]
pub struct BuilderHistory<T>
where
    T: Clone + PartialEq,
{
    current: T,
    undo: Vec<T>,
    redo: Vec<T>,
    transient_origin: Option<T>,
}

impl<T> BuilderHistory<T>
where
    T: Clone + PartialEq,
{
    pub fn new(initial: T) -> Self {
        Self {
            current: initial,
            undo: Vec::new(),
            redo: Vec::new(),
            transient_origin: None,
        }
    }

    pub fn current(&self) -> &T {
        &self.current
    }

    pub fn replace(&mut self, next: T) {
        if next == self.current {
            return;
        }
        self.cancel_transient();
        self.undo.push(self.current.clone());
        self.current = next;
        self.redo.clear();
    }

    pub fn begin_transient(&mut self) {
        if self.transient_origin.is_none() {
            self.transient_origin = Some(self.current.clone());
        }
    }

    pub fn replace_transient(&mut self, next: T) {
        debug_assert!(self.transient_origin.is_some());
        self.current = next;
    }

    pub fn commit_transient(&mut self) {
        let Some(origin) = self.transient_origin.take() else {
            return;
        };
        if origin != self.current {
            self.undo.push(origin);
            self.redo.clear();
        }
    }

    pub fn cancel_transient(&mut self) {
        if let Some(origin) = self.transient_origin.take() {
            self.current = origin;
        }
    }

    pub fn undo(&mut self) -> bool {
        self.cancel_transient();
        let Some(previous) = self.undo.pop() else {
            return false;
        };
        self.redo.push(self.current.clone());
        self.current = previous;
        true
    }

    pub fn redo(&mut self) -> bool {
        self.cancel_transient();
        let Some(next) = self.redo.pop() else {
            return false;
        };
        self.undo.push(self.current.clone());
        self.current = next;
        true
    }

    pub fn can_undo(&self) -> bool {
        !self.undo.is_empty()
    }

    pub fn can_redo(&self) -> bool {
        !self.redo.is_empty()
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct TwoBoneIkInput {
    pub root: Vec3,
    pub mid: Vec3,
    pub end: Vec3,
    pub target: Vec3,
    pub pole: Vec3,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct TwoBoneIkResult {
    pub mid: Vec3,
    pub end: Vec3,
    pub upper_length: f32,
    pub lower_length: f32,
    pub clamped_distance: f32,
    pub reached_target: bool,
}

pub fn solve_two_bone_ik(input: TwoBoneIkInput) -> Option<TwoBoneIkResult> {
    let upper = input.root.distance(input.mid);
    let lower = input.mid.distance(input.end);

    if upper <= EPSILON || lower <= EPSILON {
        return None;
    }

    let target_delta = input.target - input.root;
    let raw_distance = target_delta.length();

    let forward = target_delta
        .normalized()
        .or_else(|| (input.end - input.root).normalized())
        .unwrap_or(Vec3::Z);

    let min_distance = (upper - lower).abs() + EPSILON;
    let max_distance = (upper + lower - EPSILON).max(min_distance);
    let distance = raw_distance.clamp(min_distance, max_distance);

    let pole_direction = (input.pole - input.root)
        .normalized()
        .unwrap_or(Vec3::Y);

    let mut plane_normal = forward.cross(pole_direction).normalized();

    if plane_normal.is_none() {
        plane_normal = (input.mid - input.root)
            .cross(input.end - input.mid)
            .normalized();
    }

    if plane_normal.is_none() {
        let fallback = if forward.dot(Vec3::Y).abs() < 0.95 {
            Vec3::Y
        } else {
            Vec3::X
        };
        plane_normal = forward.cross(fallback).normalized();
    }

    let plane_normal = plane_normal?;
    let bend_direction = plane_normal.cross(forward).normalized()?;

    let cos_root = ((upper * upper + distance * distance - lower * lower)
        / (2.0 * upper * distance))
        .clamp(-1.0, 1.0);
    let sin_root = (1.0 - cos_root * cos_root).max(0.0).sqrt();

    let mid = input.root
        + forward * (cos_root * upper)
        + bend_direction * (sin_root * upper);
    let end = input.root + forward * distance;

    Some(TwoBoneIkResult {
        mid,
        end,
        upper_length: upper,
        lower_length: lower,
        clamped_distance: distance,
        reached_target: (distance - raw_distance).abs() <= 1.0e-4,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recognizes_v2_as_legacy_without_promoting_it_to_v3() {
        assert_eq!(
            detect_rig_profile_generation("freshstl_mixamo_rig_v2"),
            RigProfileGeneration::V2Legacy
        );
        assert_eq!(
            detect_rig_profile_generation("freshstl_mixamo_rig_v3"),
            RigProfileGeneration::V3
        );
        assert_eq!(
            detect_rig_profile_generation("unknown"),
            RigProfileGeneration::Unsupported
        );
    }

    #[test]
    fn continuous_drag_creates_one_undo_entry() {
        let mut history = BuilderHistory::new(0_i32);
        history.begin_transient();
        history.replace_transient(1);
        history.replace_transient(2);
        history.replace_transient(3);
        history.commit_transient();

        assert_eq!(*history.current(), 3);
        assert!(history.undo());
        assert_eq!(*history.current(), 0);
        assert!(!history.undo());
    }

    #[test]
    fn new_edit_invalidates_redo() {
        let mut history = BuilderHistory::new(0_i32);
        history.replace(1);
        history.undo();
        assert!(history.can_redo());

        history.replace(2);
        assert!(!history.can_redo());
    }

    #[test]
    fn solves_reachable_target_and_preserves_lengths() {
        let input = TwoBoneIkInput {
            root: Vec3::ZERO,
            mid: Vec3::Y,
            end: Vec3::new(0.0, 2.0, 0.0),
            target: Vec3::new(1.0, 1.0, 0.0),
            pole: Vec3::Z,
        };

        let solved = solve_two_bone_ik(input).expect("valid chain");

        assert!(solved.reached_target);
        assert!(solved.end.approx_eq(input.target, 1.0e-4));
        assert!((input.root.distance(solved.mid) - 1.0).abs() < 1.0e-4);
        assert!((solved.mid.distance(solved.end) - 1.0).abs() < 1.0e-4);
    }

    #[test]
    fn clamps_unreachable_target() {
        let input = TwoBoneIkInput {
            root: Vec3::ZERO,
            mid: Vec3::Y,
            end: Vec3::new(0.0, 2.0, 0.0),
            target: Vec3::new(0.0, 8.0, 0.0),
            pole: Vec3::Z,
        };

        let solved = solve_two_bone_ik(input).expect("valid chain");
        assert!(!solved.reached_target);
        assert!(solved.clamped_distance < 2.0);
    }

    #[test]
    fn rejects_collapsed_chain() {
        let input = TwoBoneIkInput {
            root: Vec3::ZERO,
            mid: Vec3::ZERO,
            end: Vec3::Y,
            target: Vec3::Y,
            pole: Vec3::Z,
        };

        assert!(solve_two_bone_ik(input).is_none());
    }
}
