use builder_core::{solve_two_bone_ik, TwoBoneIkInput, Vec3};
use flutter_rust_bridge::frb;

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

#[derive(Clone, Debug)]
pub struct CoreStatus {
    pub name: String,
    pub bridge_version: String,
    pub design_version: u32,
    pub rig_profile: String,
}

#[derive(Clone, Copy, Debug)]
pub struct BridgeVec3 {
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

#[derive(Clone, Copy, Debug)]
pub struct BridgeIkInput {
    pub root: BridgeVec3,
    pub mid: BridgeVec3,
    pub end: BridgeVec3,
    pub target: BridgeVec3,
    pub pole: BridgeVec3,
}

#[derive(Clone, Copy, Debug)]
pub struct BridgeIkResult {
    pub mid: BridgeVec3,
    pub end: BridgeVec3,
    pub upper_length: f32,
    pub lower_length: f32,
    pub clamped_distance: f32,
    pub reached_target: bool,
}

#[derive(Clone, Debug)]
pub struct GpuStatus {
    pub available: bool,
    pub name: String,
    pub backend: String,
    pub device_type: String,
    pub driver: String,
    pub driver_info: String,
    pub error: String,
}

pub fn core_status() -> CoreStatus {
    CoreStatus {
        name: "Fresh Builder Native Core".to_owned(),
        bridge_version: env!("CARGO_PKG_VERSION").to_owned(),
        design_version: 4,
        rig_profile: "freshstl_mixamo_rig_v3".to_owned(),
    }
}

pub fn solve_ik_preview(input: BridgeIkInput) -> Option<BridgeIkResult> {
    let solved = solve_two_bone_ik(TwoBoneIkInput {
        root: input.root.into(),
        mid: input.mid.into(),
        end: input.end.into(),
        target: input.target.into(),
        pole: input.pole.into(),
    })?;

    Some(BridgeIkResult {
        mid: solved.mid.into(),
        end: solved.end.into(),
        upper_length: solved.upper_length,
        lower_length: solved.lower_length,
        clamped_distance: solved.clamped_distance,
        reached_target: solved.reached_target,
    })
}

pub async fn gpu_status() -> GpuStatus {
    match builder_render::probe_high_performance_adapter().await {
        Ok(info) => GpuStatus {
            available: true,
            name: info.name,
            backend: info.backend,
            device_type: info.device_type,
            driver: info.driver,
            driver_info: info.driver_info,
            error: String::new(),
        },
        Err(error) => GpuStatus {
            available: false,
            name: String::new(),
            backend: String::new(),
            device_type: String::new(),
            driver: String::new(),
            driver_info: String::new(),
            error,
        },
    }
}

impl From<BridgeVec3> for Vec3 {
    fn from(value: BridgeVec3) -> Self {
        Vec3::new(value.x, value.y, value.z)
    }
}

impl From<Vec3> for BridgeVec3 {
    fn from(value: Vec3) -> Self {
        Self {
            x: value.x,
            y: value.y,
            z: value.z,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bridge_ik_uses_builder_core_solver() {
        let solved = solve_ik_preview(BridgeIkInput {
            root: BridgeVec3 {
                x: 0.0,
                y: 0.0,
                z: 0.0,
            },
            mid: BridgeVec3 {
                x: 0.0,
                y: 1.0,
                z: 0.0,
            },
            end: BridgeVec3 {
                x: 0.0,
                y: 2.0,
                z: 0.0,
            },
            target: BridgeVec3 {
                x: 1.0,
                y: 1.0,
                z: 0.0,
            },
            pole: BridgeVec3 {
                x: 0.0,
                y: 0.0,
                z: 1.0,
            },
        })
        .expect("valid chain");

        assert!(solved.reached_target);
        assert!((solved.end.x - 1.0).abs() < 1.0e-4);
        assert!((solved.end.y - 1.0).abs() < 1.0e-4);
    }

    #[test]
    fn bridge_reports_contract_versions() {
        let status = core_status();
        assert_eq!(status.design_version, 4);
        assert_eq!(status.rig_profile, "freshstl_mixamo_rig_v3");
    }
}
