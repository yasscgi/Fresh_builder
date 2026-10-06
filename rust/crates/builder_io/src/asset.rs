use std::path::Path;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AssetFormat {
    Fbx,
    Glb,
    Gltf,
    Stl,
    ThreeMf,
    Unknown,
}

impl AssetFormat {
    pub fn extension(self) -> &'static str {
        match self {
            Self::Fbx => "fbx",
            Self::Glb => "glb",
            Self::Gltf => "gltf",
            Self::Stl => "stl",
            Self::ThreeMf => "3mf",
            Self::Unknown => "bin",
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct AssetSource {
    pub cache_key: String,
    pub remote_url: String,
    pub declared_format: Option<String>,
    pub meters_per_unit: f32,
}

impl AssetSource {
    pub fn format(&self) -> AssetFormat {
        self.declared_format
            .as_deref()
            .map(parse_format)
            .filter(|format| *format != AssetFormat::Unknown)
            .unwrap_or_else(|| detect_asset_format(&self.remote_url))
    }
}

pub fn detect_asset_format(path_or_url: &str) -> AssetFormat {
    let path = path_or_url.split('?').next().unwrap_or(path_or_url);
    let extension = Path::new(path)
        .extension()
        .and_then(|value| value.to_str())
        .unwrap_or_default();
    parse_format(extension)
}

fn parse_format(value: &str) -> AssetFormat {
    match value.trim().trim_start_matches('.').to_ascii_lowercase().as_str() {
        "fbx" => AssetFormat::Fbx,
        "glb" => AssetFormat::Glb,
        "gltf" => AssetFormat::Gltf,
        "stl" => AssetFormat::Stl,
        "3mf" => AssetFormat::ThreeMf,
        _ => AssetFormat::Unknown,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_format_behind_signed_url_query() {
        assert_eq!(
            detect_asset_format("https://example.test/model/Base.fbx?token=abc"),
            AssetFormat::Fbx
        );
    }

    #[test]
    fn declared_format_wins_over_url() {
        let source = AssetSource {
            cache_key: "hat:1".to_owned(),
            remote_url: "https://example.test/download".to_owned(),
            declared_format: Some("GLB".to_owned()),
            meters_per_unit: 1.0,
        };

        assert_eq!(source.format(), AssetFormat::Glb);
    }
}
