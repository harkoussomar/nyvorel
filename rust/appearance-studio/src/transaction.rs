//! Exact file-byte snapshots for appearance mutations and rollback.

use serde_json::{Map, Value};
use std::collections::HashSet;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

enum SavedFile {
    Absent,
    Regular { bytes: Vec<u8>, mode: u32 },
}

pub struct Snapshot(Vec<(PathBuf, SavedFile)>);

fn file_kind(path: &Path) -> Result<Option<fs::Metadata>, String> {
    match fs::symlink_metadata(path) {
        Ok(metadata) if metadata.file_type().is_symlink() => Err(format!(
            "Appearance transaction path is a symlink: {}",
            path.display()
        )),
        Ok(metadata) if metadata.is_file() => Ok(Some(metadata)),
        Ok(_) => Err(format!(
            "Appearance transaction path is not a file: {}",
            path.display()
        )),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(format!("Cannot inspect {}: {error}", path.display())),
    }
}

impl Snapshot {
    pub fn capture(paths: &[&Path]) -> Result<Self, String> {
        let mut files = Vec::with_capacity(paths.len());
        for path in paths {
            let saved = match file_kind(path)? {
                Some(metadata) => SavedFile::Regular {
                    bytes: fs::read(path).map_err(|error| error.to_string())?,
                    mode: metadata.permissions().mode() & 0o7777,
                },
                None => SavedFile::Absent,
            };
            files.push(((*path).to_owned(), saved));
        }
        Ok(Self(files))
    }

    pub fn restore(&self) -> Result<(), String> {
        let mut failures = Vec::new();
        for (path, saved) in &self.0 {
            if let Err(error) = restore_one(path, saved) {
                failures.push(error);
            }
        }
        if failures.is_empty() {
            Ok(())
        } else {
            Err(failures.join("; "))
        }
    }

    /// Write a new immutable preview baseline in the legacy-compatible layout.
    /// The directory is published only after every backup and metadata file is
    /// flushed; a failed capture cannot be mistaken for a usable preview.
    #[allow(dead_code)] // Staged for the native preview transaction.
    pub fn create_preview(
        dir: &Path,
        paths: &[PathBuf],
        baseline: &Value,
        gsettings: &Value,
    ) -> Result<(), String> {
        if !baseline.is_object() || !baseline["active"].is_object() || !gsettings.is_object() {
            return Err("Invalid preview baseline metadata".into());
        }
        if paths.is_empty() || paths.len() > 1000 {
            return Err("Invalid preview backup path count".into());
        }
        if fs::symlink_metadata(dir).is_ok() {
            return Err(format!(
                "Preview snapshot already exists: {}",
                dir.display()
            ));
        }
        let parent = dir.parent().ok_or("Preview directory has no parent")?;
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(|error| error.to_string())?
            .as_nanos();
        let temporary = parent.join(format!(".preview-{}-{nonce}", std::process::id()));
        fs::create_dir(&temporary).map_err(|error| error.to_string())?;
        let result = (|| -> Result<(), String> {
            let store = temporary.join("files");
            fs::create_dir(&store).map_err(|error| error.to_string())?;
            let mut manifest = Map::new();
            let mut seen = HashSet::new();
            for (index, path) in paths.iter().enumerate() {
                if !path.is_absolute() || !seen.insert(path) {
                    return Err(format!(
                        "Invalid or duplicate preview path: {}",
                        path.display()
                    ));
                }
                let key = format!("{index:03}");
                let value = match file_kind(path)? {
                    Some(_) => {
                        let bytes = fs::read(path).map_err(|error| error.to_string())?;
                        write_new(&store.join(&key), &bytes)?;
                        Value::String(key)
                    }
                    None => Value::Null,
                };
                manifest.insert(path.display().to_string(), value);
            }
            write_new(
                &temporary.join("manifest.json"),
                &serde_json::to_vec(&manifest).map_err(|error| error.to_string())?,
            )?;
            write_new(
                &temporary.join("gsettings.json"),
                &serde_json::to_vec(gsettings).map_err(|error| error.to_string())?,
            )?;
            write_new(
                &temporary.join("state-before.json"),
                &serde_json::to_vec(baseline).map_err(|error| error.to_string())?,
            )?;
            File::open(&store)
                .and_then(|directory| directory.sync_all())
                .map_err(|error| error.to_string())?;
            File::open(&temporary)
                .and_then(|directory| directory.sync_all())
                .map_err(|error| error.to_string())?;
            if fs::symlink_metadata(dir).is_ok() {
                return Err(format!(
                    "Preview snapshot already exists: {}",
                    dir.display()
                ));
            }
            fs::rename(&temporary, dir).map_err(|error| error.to_string())?;
            File::open(parent)
                .and_then(|directory| directory.sync_all())
                .map_err(|error| error.to_string())?;
            Ok(())
        })();
        if result.is_err() {
            let _ = fs::remove_dir_all(&temporary);
        }
        result
    }

    /// Load the immutable backup format written by the existing preview engine.
    /// Only known appearance paths and numeric backup keys are accepted.
    pub fn from_preview(dir: &Path, allowed: &[PathBuf]) -> Result<Self, String> {
        let manifest: Value = serde_json::from_slice(
            &fs::read(dir.join("manifest.json")).map_err(|error| error.to_string())?,
        )
        .map_err(|error| format!("Invalid preview manifest: {error}"))?;
        let entries = manifest
            .as_object()
            .ok_or("Invalid preview manifest object")?;
        if entries.is_empty() {
            return Err("Preview manifest is empty".into());
        }
        let mut files = Vec::with_capacity(entries.len());
        for (raw, key) in entries {
            let path = PathBuf::from(raw);
            if !allowed.contains(&path) {
                return Err(format!("Preview manifest contains an unknown path: {raw}"));
            }
            let saved = if key.is_null() {
                SavedFile::Absent
            } else {
                let key = key.as_str().ok_or("Invalid preview backup key")?;
                if key.len() != 3 || !key.bytes().all(|byte| byte.is_ascii_digit()) {
                    return Err(format!("Invalid preview backup key: {key}"));
                }
                let backup = dir.join("files").join(key);
                let backup_kind = file_kind(&backup)?;
                if backup_kind.is_none() {
                    return Err(format!("Missing preview backup for {raw}"));
                }
                let bytes = fs::read(&backup).map_err(|error| error.to_string())?;
                let mode = file_kind(&path)?
                    .map(|metadata| metadata.permissions().mode() & 0o7777)
                    .unwrap_or(0o644);
                SavedFile::Regular { bytes, mode }
            };
            files.push((path, saved));
        }
        Ok(Self(files))
    }
}

#[allow(dead_code)] // Used by the staged native preview capture.
fn write_new(path: &Path, bytes: &[u8]) -> Result<(), String> {
    let mut output = OpenOptions::new()
        .create_new(true)
        .write(true)
        .open(path)
        .map_err(|error| error.to_string())?;
    output.write_all(bytes).map_err(|error| error.to_string())?;
    output.sync_all().map_err(|error| error.to_string())
}

fn restore_one(path: &Path, saved: &SavedFile) -> Result<(), String> {
    let current = file_kind(path)?;
    match saved {
        SavedFile::Absent => {
            if current.is_some() {
                fs::remove_file(path).map_err(|error| error.to_string())?;
                sync_parent(path)?;
            }
            Ok(())
        }
        SavedFile::Regular { bytes, mode } => {
            if current.is_some()
                && fs::read(path).is_ok_and(|existing| existing == *bytes)
                && current
                    .as_ref()
                    .is_some_and(|meta| meta.permissions().mode() & 0o7777 == *mode)
            {
                return Ok(());
            }
            let parent = path
                .parent()
                .ok_or("Appearance rollback path has no parent")?;
            fs::create_dir_all(parent).map_err(|error| error.to_string())?;
            let nonce = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map_err(|error| error.to_string())?
                .as_nanos();
            let temporary = parent.join(format!(
                ".{}.restore-{}-{nonce}",
                path.file_name().unwrap_or_default().to_string_lossy(),
                std::process::id()
            ));
            let write_result = (|| -> Result<(), String> {
                let mut output = OpenOptions::new()
                    .create_new(true)
                    .write(true)
                    .open(&temporary)
                    .map_err(|error| error.to_string())?;
                output.write_all(bytes).map_err(|error| error.to_string())?;
                output.sync_all().map_err(|error| error.to_string())?;
                fs::set_permissions(&temporary, fs::Permissions::from_mode(*mode))
                    .map_err(|error| error.to_string())?;
                // Refuse a path swapped to a symlink while the temporary was written.
                file_kind(path)?;
                fs::rename(&temporary, path).map_err(|error| error.to_string())?;
                sync_parent(path)?;
                if fs::read(path).map_err(|error| error.to_string())? != *bytes {
                    return Err(format!(
                        "Appearance rollback verification failed: {}",
                        path.display()
                    ));
                }
                Ok(())
            })();
            let _ = fs::remove_file(temporary);
            write_result
        }
    }
}

fn sync_parent(path: &Path) -> Result<(), String> {
    File::open(path.parent().ok_or("Missing parent directory")?)
        .and_then(|directory| directory.sync_all())
        .map_err(|error| error.to_string())
}

#[cfg(test)]
mod tests {
    use super::Snapshot;
    use serde_json::json;
    use std::fs;
    use std::os::unix::fs::{symlink, PermissionsExt};

    #[test]
    fn restores_original_bytes_mode_and_absence() {
        let root = std::env::temp_dir().join(format!("appearance-snapshot-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&root).unwrap();
        let original = root.join("original");
        let missing = root.join("missing");
        fs::write(&original, b"original bytes").unwrap();
        fs::set_permissions(&original, fs::Permissions::from_mode(0o600)).unwrap();
        let snapshot = Snapshot::capture(&[&original, &missing]).unwrap();
        fs::write(&original, b"changed").unwrap();
        fs::set_permissions(&original, fs::Permissions::from_mode(0o644)).unwrap();
        fs::write(&missing, b"created").unwrap();
        snapshot.restore().unwrap();
        assert_eq!(fs::read(&original).unwrap(), b"original bytes");
        assert_eq!(
            fs::metadata(&original).unwrap().permissions().mode() & 0o777,
            0o600
        );
        assert!(!missing.exists());
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn rejects_symlink_on_capture_and_restore() {
        let root = std::env::temp_dir().join(format!("appearance-symlink-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&root).unwrap();
        let path = root.join("target");
        let other = root.join("other");
        fs::write(&path, b"original").unwrap();
        fs::write(&other, b"untouched").unwrap();
        let snapshot = Snapshot::capture(&[&path]).unwrap();
        fs::remove_file(&path).unwrap();
        symlink(&other, &path).unwrap();
        assert!(snapshot.restore().is_err());
        assert_eq!(fs::read(&other).unwrap(), b"untouched");
        assert!(Snapshot::capture(&[&path]).is_err());
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn preview_manifest_restores_only_known_paths() {
        let root = std::env::temp_dir().join(format!("appearance-preview-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(root.join("files")).unwrap();
        let target = root.join("target");
        let unknown = root.join("unknown");
        fs::write(&target, b"preview").unwrap();
        fs::write(root.join("files/000"), b"committed").unwrap();
        fs::write(
            root.join("manifest.json"),
            format!("{{\"{}\":\"000\"}}", target.display()),
        )
        .unwrap();
        let snapshot = Snapshot::from_preview(&root, std::slice::from_ref(&target)).unwrap();
        snapshot.restore().unwrap();
        assert_eq!(fs::read(&target).unwrap(), b"committed");
        fs::write(
            root.join("manifest.json"),
            format!("{{\"{}\":\"000\"}}", unknown.display()),
        )
        .unwrap();
        assert!(Snapshot::from_preview(&root, &[target]).is_err());
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn preview_capture_publishes_complete_legacy_snapshot() {
        let root =
            std::env::temp_dir().join(format!("appearance-preview-capture-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&root).unwrap();
        let existing = root.join("existing");
        let absent = root.join("absent");
        let preview = root.join("preview");
        fs::write(&existing, b"committed").unwrap();
        let baseline = json!({"active": {"source": "preset"}, "preview": null});
        let gsettings = json!({"gtk-theme": "'Adwaita'"});
        Snapshot::create_preview(
            &preview,
            &[existing.clone(), absent.clone()],
            &baseline,
            &gsettings,
        )
        .unwrap();
        assert_eq!(
            serde_json::from_slice::<serde_json::Value>(
                &fs::read(preview.join("state-before.json")).unwrap()
            )
            .unwrap(),
            baseline
        );
        assert_eq!(
            serde_json::from_slice::<serde_json::Value>(
                &fs::read(preview.join("gsettings.json")).unwrap()
            )
            .unwrap(),
            gsettings
        );
        fs::write(&existing, b"preview").unwrap();
        fs::write(&absent, b"new file").unwrap();
        Snapshot::from_preview(&preview, &[existing.clone(), absent.clone()])
            .unwrap()
            .restore()
            .unwrap();
        assert_eq!(fs::read(&existing).unwrap(), b"committed");
        assert!(!absent.exists());
        assert!(Snapshot::create_preview(&preview, &[existing], &baseline, &gsettings).is_err());
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn preview_capture_rejects_symlink_without_publishing() {
        let root = std::env::temp_dir().join(format!(
            "appearance-preview-capture-link-{}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&root).unwrap();
        let real = root.join("real");
        let link = root.join("link");
        let preview = root.join("preview");
        fs::write(&real, b"private").unwrap();
        symlink(&real, &link).unwrap();
        assert!(
            Snapshot::create_preview(&preview, &[link], &json!({"active": {}}), &json!({}),)
                .is_err()
        );
        assert!(!preview.exists());
        assert_eq!(fs::read(real).unwrap(), b"private");
        fs::remove_dir_all(root).unwrap();
    }
}
