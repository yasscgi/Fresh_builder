use builder_core::{solve_two_bone_ik, TwoBoneIkInput, Vec3};
use builder_io::{decode_gltf_scene, detect_asset_format, inspect_scene_file, AssetFormat, ImportReadiness};
use std::sync::Mutex;

use builder_render::{ViewPreset, ViewportCamera, ViewportRenderer};
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

#[derive(Clone, Debug)]
pub struct ViewportSmokeStatus {
    pub success: bool,
    pub width: u32,
    pub height: u32,
    pub gpu_name: String,
    pub backend: String,
    pub error: String,
}

#[derive(Clone, Copy, Debug)]
pub struct BridgeColor {
    pub r: f64,
    pub g: f64,
    pub b: f64,
    pub a: f64,
}

#[derive(Clone, Copy, Debug)]
pub struct BridgeCameraState {
    pub yaw: f32,
    pub pitch: f32,
    pub distance: f32,
    pub target_x: f32,
    pub target_y: f32,
    pub target_z: f32,
}

#[derive(Clone, Copy, Debug)]
pub struct BridgeViewportSize {
    pub width: u32,
    pub height: u32,
}

#[derive(Clone, Debug)]
pub struct LocalAssetInfo {
    pub path: String,
    pub format: String,
    pub supported_for_import: bool,
}

#[derive(Clone, Debug)]
pub struct LocalSceneInfo {
    pub path: String,
    pub format: String,
    pub byte_len: u64,
    pub meters_per_unit: f32,
    pub skinned: bool,
    pub readiness: String,
}

#[derive(Clone, Debug)]
pub struct DecodedSceneInfo {
    pub mesh_count: u32,
    pub vertex_count: u64,
    pub index_count: u64,
    pub joint_count: u32,
    pub skinned_mesh_count: u32,
}

#[derive(Clone, Copy, Debug)]
pub enum BridgeViewPreset {
    Front,
    Back,
    Left,
    Right,
    Top,
    Bottom,
}

#[frb(opaque)]
pub struct NativeViewportSession {
    inner: Mutex<NativeViewportSessionInner>,
}

struct NativeViewportSessionInner {
    renderer: ViewportRenderer,
    camera: ViewportCamera,
}

pub fn core_status() -> CoreStatus {
    CoreStatus {
        name: "Fresh Builder Native Core".to_owned(),
        bridge_version: env!("CARGO_PKG_VERSION").to_owned(),
        design_version: 4,
        rig_profile: "freshstl_mixamo_rig_v3".to_owned(),
    }
}

pub fn inspect_local_asset(path: String) -> LocalAssetInfo {
    let format = detect_asset_format(&path);
    let supported_for_import = matches!(
        format,
        AssetFormat::Fbx
            | AssetFormat::Glb
            | AssetFormat::Gltf
            | AssetFormat::Stl
            | AssetFormat::ThreeMf
    );

    LocalAssetInfo {
        path,
        format: format!("{format:?}").to_ascii_lowercase(),
        supported_for_import,
    }
}

pub fn inspect_local_scene(
    path: String,
    meters_per_unit: f32,
    skinned: bool,
) -> Result<LocalSceneInfo, String> {
    let scene = inspect_scene_file(&path, meters_per_unit, skinned)?;
    let readiness = match scene.readiness() {
        ImportReadiness::Ready => "ready",
        ImportReadiness::NeedsFbxDecoder => "needs_fbx_decoder",
        ImportReadiness::Unsupported => "unsupported",
    };

    Ok(LocalSceneInfo {
        path: scene.source_path,
        format: format!("{:?}", scene.format).to_ascii_lowercase(),
        byte_len: scene.byte_len,
        meters_per_unit: scene.meters_per_unit,
        skinned: scene.skinned,
        readiness: readiness.to_owned(),
    })
}

pub fn decode_local_scene(
    path: String,
    meters_per_unit: f32,
) -> Result<DecodedSceneInfo, String> {
    let format = detect_asset_format(&path);
    let scene = match format {
        AssetFormat::Glb | AssetFormat::Gltf => decode_gltf_scene(&path, meters_per_unit)?,
        AssetFormat::Fbx => {
            return Err("FBX decoder is intentionally separate; no FBX-to-GLB conversion is performed".to_owned())
        }
        other => return Err(format!("Native scene decoding is not implemented for {other:?} yet")),
    };

    Ok(DecodedSceneInfo {
        mesh_count: scene.meshes.len() as u32,
        vertex_count: scene.vertex_count() as u64,
        index_count: scene.index_count() as u64,
        joint_count: scene.joint_count(),
        skinned_mesh_count: scene.meshes.iter().filter(|mesh| mesh.skinned).count() as u32,
    })
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

pub async fn viewport_smoke_test(width: u32, height: u32) -> ViewportSmokeStatus {
    match ViewportRenderer::new(width, height).await {
        Ok(renderer) => {
            renderer.render_clear([0.035, 0.018, 0.075, 1.0]);
            let info = renderer.adapter_info();

            ViewportSmokeStatus {
                success: true,
                width,
                height,
                gpu_name: info.name.clone(),
                backend: info.backend.clone(),
                error: String::new(),
            }
        }
        Err(error) => ViewportSmokeStatus {
            success: false,
            width,
            height,
            gpu_name: String::new(),
            backend: String::new(),
            error,
        },
    }
}

impl NativeViewportSession {
    pub async fn create(width: u32, height: u32) -> Result<Self, String> {
        let renderer = ViewportRenderer::new(width, height).await?;
        let camera = ViewportCamera::default();

        Ok(Self {
            inner: Mutex::new(NativeViewportSessionInner { renderer, camera }),
        })
    }

    pub fn resize(&self, width: u32, height: u32) -> Result<(), String> {
        let mut inner = self.lock_inner()?;
        inner.renderer.resize(width, height)
    }

    pub fn render_clear(&self, color: BridgeColor) -> Result<(), String> {
        let inner = self.lock_inner()?;
        inner
            .renderer
            .render_clear([color.r, color.g, color.b, color.a]);
        Ok(())
    }

    pub fn orbit(
        &self,
        delta_x: f32,
        delta_y: f32,
        sensitivity: f32,
    ) -> Result<BridgeCameraState, String> {
        let mut inner = self.lock_inner()?;
        inner.camera.orbit(delta_x, delta_y, sensitivity);
        Ok(inner.camera.into())
    }

    pub fn zoom(&self, delta: f32, sensitivity: f32) -> Result<BridgeCameraState, String> {
        let mut inner = self.lock_inner()?;
        inner.camera.zoom(delta, sensitivity);
        Ok(inner.camera.into())
    }

    pub fn set_view_preset(
        &self,
        preset: BridgeViewPreset,
    ) -> Result<BridgeCameraState, String> {
        let mut inner = self.lock_inner()?;
        inner.camera.set_preset(preset.into());
        Ok(inner.camera.into())
    }

    pub fn camera_state(&self) -> Result<BridgeCameraState, String> {
        let inner = self.lock_inner()?;
        Ok(inner.camera.into())
    }

    pub fn viewport_size(&self) -> Result<BridgeViewportSize, String> {
        let inner = self.lock_inner()?;
        let (width, height) = inner.renderer.size();
        Ok(BridgeViewportSize { width, height })
    }

    pub fn gpu_status(&self) -> Result<GpuStatus, String> {
        let inner = self.lock_inner()?;
        let info = inner.renderer.adapter_info();

        Ok(GpuStatus {
            available: true,
            name: info.name.clone(),
            backend: info.backend.clone(),
            device_type: info.device_type.clone(),
            driver: info.driver.clone(),
            driver_info: info.driver_info.clone(),
            error: String::new(),
        })
    }

    fn lock_inner(&self) -> Result<std::sync::MutexGuard<'_, NativeViewportSessionInner>, String> {
        self.inner
            .lock()
            .map_err(|_| "Native viewport session lock was poisoned".to_owned())
    }
}

impl From<ViewportCamera> for BridgeCameraState {
    fn from(value: ViewportCamera) -> Self {
        Self {
            yaw: value.yaw,
            pitch: value.pitch,
            distance: value.distance,
            target_x: value.target[0],
            target_y: value.target[1],
            target_z: value.target[2],
        }
    }
}

impl From<BridgeViewPreset> for ViewPreset {
    fn from(value: BridgeViewPreset) -> Self {
        match value {
            BridgeViewPreset::Front => ViewPreset::Front,
            BridgeViewPreset::Back => ViewPreset::Back,
            BridgeViewPreset::Left => ViewPreset::Left,
            BridgeViewPreset::Right => ViewPreset::Right,
            BridgeViewPreset::Top => ViewPreset::Top,
            BridgeViewPreset::Bottom => ViewPreset::Bottom,
        }
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
            root: BridgeVec3 { x: 0.0, y: 0.0, z: 0.0 },
            mid: BridgeVec3 { x: 0.0, y: 1.0, z: 0.0 },
            end: BridgeVec3 { x: 0.0, y: 2.0, z: 0.0 },
            target: BridgeVec3 { x: 1.0, y: 1.0, z: 0.0 },
            pole: BridgeVec3 { x: 0.0, y: 0.0, z: 1.0 },
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
