use std::{fs, path::Path};

use crate::{detect_asset_format, AssetFormat};

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct SceneBounds {
    pub min: [f32; 3],
    pub max: [f32; 3],
}

#[derive(Clone, Debug, PartialEq)]
pub struct SceneAsset {
    pub source_path: String,
    pub format: AssetFormat,
    pub byte_len: u64,
    pub meters_per_unit: f32,
    pub skinned: bool,
    pub mesh_count: u32,
    pub node_count: u32,
    pub joint_count: u32,
    pub bounds: Option<SceneBounds>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ImportReadiness {
    Ready,
    Unsupported,
}

impl SceneAsset {
    pub fn readiness(&self) -> ImportReadiness {
        match self.format {
            AssetFormat::Glb | AssetFormat::Gltf | AssetFormat::Stl | AssetFormat::Fbx => {
                ImportReadiness::Ready
            }
            AssetFormat::ThreeMf | AssetFormat::Unknown => ImportReadiness::Unsupported,
        }
    }
}

pub fn inspect_scene_file(
    path: impl AsRef<Path>,
    meters_per_unit: f32,
    skinned: bool,
) -> Result<SceneAsset, String> {
    let path = path.as_ref();
    let metadata = fs::metadata(path)
        .map_err(|error| format!("Unable to read Builder asset {}: {error}", path.display()))?;

    if !metadata.is_file() || metadata.len() == 0 {
        return Err(format!("Builder asset is empty or not a file: {}", path.display()));
    }

    let path_string = path.to_string_lossy().to_string();
    Ok(SceneAsset {
        format: detect_asset_format(&path_string),
        source_path: path_string,
        byte_len: metadata.len(),
        meters_per_unit: if meters_per_unit.is_finite() && meters_per_unit > 0.0 {
            meters_per_unit
        } else {
            1.0
        },
        skinned,
        mesh_count: 0,
        node_count: 0,
        joint_count: 0,
        bounds: None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn fbx_is_ready_for_native_decode() {
        let nonce = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos();
        let path = std::env::temp_dir().join(format!("fresh-builder-{nonce}.fbx"));
        fs::write(&path, b"Kaydara FBX Binary").unwrap();

        let rigged = inspect_scene_file(&path, 0.001, true).unwrap();
        assert_eq!(rigged.format, AssetFormat::Fbx);
        assert_eq!(rigged.readiness(), ImportReadiness::Ready);
        assert!(rigged.skinned);
        assert_eq!(rigged.meters_per_unit, 0.001);

        let static_scene = inspect_scene_file(&path, 0.001, false).unwrap();
        assert_eq!(static_scene.readiness(), ImportReadiness::Ready);

        fs::remove_file(path).unwrap();
    }
}
