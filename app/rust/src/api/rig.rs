use builder_core::{BuilderHistory, PoseState};
use flutter_rust_bridge::frb;
use std::{collections::BTreeMap, sync::Mutex};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BridgeRigMode {
    None,
    Ik,
    Fk,
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct BridgeEuler {
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct BridgePoint3 {
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

#[derive(Clone, Debug, PartialEq)]
struct RigPose {
    mode: BridgeRigMode,
    selected_bone: Option<String>,
    fk: BTreeMap<String, BridgeEuler>,
    ik: BTreeMap<String, BridgePoint3>,
    hand_open: f32,
}

impl Default for RigPose {
    fn default() -> Self {
        Self {
            mode: BridgeRigMode::None,
            selected_bone: None,
            fk: BTreeMap::new(),
            ik: BTreeMap::new(),
            hand_open: 1.0,
        }
    }
}

#[derive(Clone, Debug)]
pub struct BridgeRigState {
    pub mode: BridgeRigMode,
    pub selected_bone: Option<String>,
    pub hand_open: f32,
    pub can_undo: bool,
    pub can_redo: bool,
    pub gesture_active: bool,
}

#[derive(Clone, Debug)]
pub struct BridgeFkRotation {
    pub bone: String,
    pub rotation: BridgeEuler,
}

#[derive(Clone, Debug)]
pub struct BridgeIkTarget {
    pub effector: String,
    pub target: BridgePoint3,
}

#[derive(Clone, Debug)]
pub struct BridgeRigPoseSnapshot {
    pub mode: BridgeRigMode,
    pub selected_bone: Option<String>,
    pub fk: Vec<BridgeFkRotation>,
    pub ik: Vec<BridgeIkTarget>,
    pub hand_open: f32,
}

#[frb(opaque)]
pub struct NativeRigSession {
    history: Mutex<BuilderHistory<RigPose>>,
    gesture_active: Mutex<bool>,
}

impl NativeRigSession {
    pub fn create() -> Self {
        Self {
            history: Mutex::new(BuilderHistory::new(RigPose::default())),
            gesture_active: Mutex::new(false),
        }
    }

    pub fn state(&self) -> Result<BridgeRigState, String> {
        let history = self.history.lock().map_err(|_| "Rig history lock was poisoned")?;
        let gesture_active = *self.gesture_active.lock().map_err(|_| "Rig gesture lock was poisoned")?;
        Ok(state_from_history(&history, gesture_active))
    }

    pub fn pose_snapshot(&self) -> Result<BridgeRigPoseSnapshot, String> {
        let history = self
            .history
            .lock()
            .map_err(|_| "Rig history lock was poisoned")?;
        let pose = history.current();

        Ok(BridgeRigPoseSnapshot {
            mode: pose.mode,
            selected_bone: pose.selected_bone.clone(),
            fk: pose
                .fk
                .iter()
                .map(|(bone, rotation)| BridgeFkRotation {
                    bone: bone.clone(),
                    rotation: *rotation,
                })
                .collect(),
            ik: pose
                .ik
                .iter()
                .map(|(effector, target)| BridgeIkTarget {
                    effector: effector.clone(),
                    target: *target,
                })
                .collect(),
            hand_open: pose.hand_open,
        })
    }

    pub fn set_mode(&self, mode: BridgeRigMode) -> Result<BridgeRigState, String> {
        self.replace_committed(|pose| pose.mode = mode)
    }

    pub fn select_bone(&self, bone: Option<String>) -> Result<BridgeRigState, String> {
        self.replace_committed(|pose| pose.selected_bone = bone.filter(|name| !name.trim().is_empty()))
    }

    pub fn set_hand_open(&self, open: bool) -> Result<BridgeRigState, String> {
        self.replace_committed(|pose| pose.hand_open = if open { 1.0 } else { 0.0 })
    }

    pub fn begin_gesture(&self) -> Result<BridgeRigState, String> {
        let mut history = self.history.lock().map_err(|_| "Rig history lock was poisoned")?;
        history.begin_transient();
        *self.gesture_active.lock().map_err(|_| "Rig gesture lock was poisoned")? = true;
        Ok(state_from_history(&history, true))
    }

    pub fn update_fk_rotation(
        &self,
        bone: String,
        x: f32,
        y: f32,
        z: f32,
    ) -> Result<BridgeRigState, String> {
        if bone.trim().is_empty() || !x.is_finite() || !y.is_finite() || !z.is_finite() {
            return Err("FK rotation requires a bone name and finite Euler values".to_owned());
        }
        self.replace_transient(|pose| {
            pose.mode = BridgeRigMode::Fk;
            pose.selected_bone = Some(bone.clone());
            pose.fk.insert(bone, BridgeEuler { x, y, z });
        })
    }

    pub fn update_ik_target(
        &self,
        effector: String,
        x: f32,
        y: f32,
        z: f32,
    ) -> Result<BridgeRigState, String> {
        if effector.trim().is_empty() || !x.is_finite() || !y.is_finite() || !z.is_finite() {
            return Err("IK target requires an effector name and finite coordinates".to_owned());
        }
        self.replace_transient(|pose| {
            pose.mode = BridgeRigMode::Ik;
            pose.ik.insert(effector, BridgePoint3 { x, y, z });
        })
    }

    pub fn commit_gesture(&self) -> Result<BridgeRigState, String> {
        let mut history = self.history.lock().map_err(|_| "Rig history lock was poisoned")?;
        history.commit_transient();
        *self.gesture_active.lock().map_err(|_| "Rig gesture lock was poisoned")? = false;
        Ok(state_from_history(&history, false))
    }

    pub fn cancel_gesture(&self) -> Result<BridgeRigState, String> {
        let mut history = self.history.lock().map_err(|_| "Rig history lock was poisoned")?;
        history.cancel_transient();
        *self.gesture_active.lock().map_err(|_| "Rig gesture lock was poisoned")? = false;
        Ok(state_from_history(&history, false))
    }

    pub fn undo(&self) -> Result<BridgeRigState, String> {
        let mut history = self.history.lock().map_err(|_| "Rig history lock was poisoned")?;
        history.undo();
        *self.gesture_active.lock().map_err(|_| "Rig gesture lock was poisoned")? = false;
        Ok(state_from_history(&history, false))
    }

    pub fn redo(&self) -> Result<BridgeRigState, String> {
        let mut history = self.history.lock().map_err(|_| "Rig history lock was poisoned")?;
        history.redo();
        *self.gesture_active.lock().map_err(|_| "Rig gesture lock was poisoned")? = false;
        Ok(state_from_history(&history, false))
    }

    pub fn pose_state(&self, rig_signature: Option<String>) -> Result<PoseState, String> {
        let history = self.history.lock().map_err(|_| "Rig history lock was poisoned")?;
        Ok(PoseState {
            rig_signature,
            hand_open: history.current().hand_open,
        })
    }

    fn replace_committed(&self, edit: impl FnOnce(&mut RigPose)) -> Result<BridgeRigState, String> {
        let mut history = self.history.lock().map_err(|_| "Rig history lock was poisoned")?;
        let mut next = history.current().clone();
        edit(&mut next);
        history.replace(next);
        *self.gesture_active.lock().map_err(|_| "Rig gesture lock was poisoned")? = false;
        Ok(state_from_history(&history, false))
    }

    fn replace_transient(&self, edit: impl FnOnce(&mut RigPose)) -> Result<BridgeRigState, String> {
        let mut history = self.history.lock().map_err(|_| "Rig history lock was poisoned")?;
        let mut active = self.gesture_active.lock().map_err(|_| "Rig gesture lock was poisoned")?;
        if !*active {
            history.begin_transient();
            *active = true;
        }
        let mut next = history.current().clone();
        edit(&mut next);
        history.replace_transient(next);
        Ok(state_from_history(&history, true))
    }
}

fn state_from_history(history: &BuilderHistory<RigPose>, gesture_active: bool) -> BridgeRigState {
    let pose = history.current();
    BridgeRigState {
        mode: pose.mode,
        selected_bone: pose.selected_bone.clone(),
        hand_open: pose.hand_open,
        can_undo: history.can_undo(),
        can_redo: history.can_redo(),
        gesture_active,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fk_drag_commits_as_one_undo_step() {
        let rig = NativeRigSession::create();
        rig.begin_gesture().unwrap();
        rig.update_fk_rotation("LeftArm".into(), 0.1, 0.0, 0.0).unwrap();
        rig.update_fk_rotation("LeftArm".into(), 0.2, 0.0, 0.0).unwrap();
        let committed = rig.commit_gesture().unwrap();
        assert!(committed.can_undo);
        assert!(!committed.gesture_active);

        let undone = rig.undo().unwrap();
        assert!(!undone.can_undo);
    }

    #[test]
    fn ik_and_fk_are_mutually_explicit_modes() {
        let rig = NativeRigSession::create();
        let fk = rig.update_fk_rotation("Spine".into(), 0.0, 0.1, 0.0).unwrap();
        assert_eq!(fk.mode, BridgeRigMode::Fk);
        rig.commit_gesture().unwrap();

        let ik = rig.update_ik_target("LeftFoot".into(), 0.0, 0.0, 1.0).unwrap();
        assert_eq!(ik.mode, BridgeRigMode::Ik);
    }

    #[test]
    fn pose_snapshot_tracks_fk_undo_and_redo() {
        let rig = NativeRigSession::create();
        rig.update_fk_rotation("LeftArm".into(), 0.25, 0.0, 0.0)
            .unwrap();
        rig.commit_gesture().unwrap();

        let snapshot = rig.pose_snapshot().unwrap();
        assert_eq!(snapshot.fk.len(), 1);
        assert_eq!(snapshot.fk[0].bone, "LeftArm");
        assert!((snapshot.fk[0].rotation.x - 0.25).abs() < 1.0e-6);

        rig.undo().unwrap();
        assert!(rig.pose_snapshot().unwrap().fk.is_empty());

        rig.redo().unwrap();
        assert_eq!(rig.pose_snapshot().unwrap().fk.len(), 1);
    }

    #[test]
    fn hand_state_is_exportable_to_design_pose() {
        let rig = NativeRigSession::create();
        rig.set_hand_open(false).unwrap();
        let pose = rig.pose_state(Some("rig-v3".into())).unwrap();
        assert_eq!(pose.hand_open, 0.0);
        assert_eq!(pose.rig_signature.as_deref(), Some("rig-v3"));
    }
}
