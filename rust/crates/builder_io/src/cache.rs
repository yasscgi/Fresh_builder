use std::{
    fs,
    io,
    path::{Path, PathBuf},
};

use sha2::{Digest, Sha256};

use crate::{AssetFormat, AssetSource};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CachedAsset {
    pub path: PathBuf,
    pub format: AssetFormat,
    pub byte_len: u64,
    pub cache_hit: bool,
}

#[derive(Clone, Debug)]
pub struct AssetCache {
    root: PathBuf,
}

impl AssetCache {
    pub fn new(root: impl Into<PathBuf>) -> io::Result<Self> {
        let root = root.into();
        fs::create_dir_all(&root)?;
        Ok(Self { root })
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn cached(&self, source: &AssetSource) -> io::Result<Option<CachedAsset>> {
        let format = source.format();
        let path = self.cache_path(&source.cache_key, format);

        match fs::metadata(&path) {
            Ok(metadata) if metadata.is_file() && metadata.len() > 0 => {
                Ok(Some(CachedAsset {
                    path,
                    format,
                    byte_len: metadata.len(),
                    cache_hit: true,
                }))
            }
            Ok(_) => Ok(None),
            Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(None),
            Err(error) => Err(error),
        }
    }

    pub fn store_bytes(
        &self,
        source: &AssetSource,
        bytes: &[u8],
    ) -> io::Result<CachedAsset> {
        if bytes.is_empty() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "Refusing to cache an empty Builder asset",
            ));
        }

        let format = source.format();
        let final_path = self.cache_path(&source.cache_key, format);
        let temp_path = final_path.with_extension(format!("{}.part", format.extension()));

        fs::write(&temp_path, bytes)?;
        fs::rename(&temp_path, &final_path)?;

        Ok(CachedAsset {
            path: final_path,
            format,
            byte_len: bytes.len() as u64,
            cache_hit: false,
        })
    }

    pub fn remove(&self, source: &AssetSource) -> io::Result<bool> {
        let path = self.cache_path(&source.cache_key, source.format());
        match fs::remove_file(path) {
            Ok(()) => Ok(true),
            Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(false),
            Err(error) => Err(error),
        }
    }

    fn cache_path(&self, cache_key: &str, format: AssetFormat) -> PathBuf {
        let digest = Sha256::digest(cache_key.as_bytes());
        let name = format!("{digest:x}.{}", format.extension());
        self.root.join(name)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn test_root() -> PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock")
            .as_nanos();
        std::env::temp_dir().join(format!("fresh-builder-cache-{nonce}"))
    }

    #[test]
    fn stores_and_reuses_cached_asset() {
        let root = test_root();
        let cache = AssetCache::new(&root).expect("cache");
        let source = AssetSource {
            cache_key: "asset:variation".to_owned(),
            remote_url: "https://example.test/Hat.fbx?token=1".to_owned(),
            declared_format: Some("fbx".to_owned()),
            meters_per_unit: 0.001,
        };

        let first = cache.store_bytes(&source, b"FBX test bytes").expect("store");
        assert!(!first.cache_hit);

        let second = cache.cached(&source).expect("lookup").expect("hit");
        assert!(second.cache_hit);
        assert_eq!(first.path, second.path);
        assert_eq!(second.byte_len, 14);

        fs::remove_dir_all(root).expect("cleanup");
    }
}
