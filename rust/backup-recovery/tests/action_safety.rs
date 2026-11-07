use nyvorel_backup_recovery::{actions, root_common::Paths};
use serde_json::{json, Value};
use std::fs;
use std::path::PathBuf;

// Exercise the root action entry point with a deliberately absent disk. No
// backup, restore, mount or SMART command may be reached in this fixture.
#[test]
fn missing_disk_blocks_all_disk_mutating_actions() {
    let root = std::env::temp_dir().join(format!(
        "nyvorel-backup-action-safety-{}",
        std::process::id()
    ));
    let _ = fs::remove_dir_all(&root);
    let config_dir = root.join("etc/backup-recovery");
    fs::create_dir_all(&config_dir).unwrap();
    let mountpoint = root.join("unmounted-backup-disk");
    fs::create_dir_all(&mountpoint).unwrap();
    let config = json!({
        "user": "omar", "backup_uuid": "NEVER-PRESENT-TEST-UUID",
        "mountpoint": mountpoint.to_string_lossy(),
        "restic_repo": mountpoint.join("restic").to_string_lossy(),
        "restic_password_file": root.join("password").to_string_lossy(),
        "notifications": {"enabled": false}
    });
    fs::write(
        config_dir.join("config.json"),
        serde_json::to_vec(&config).unwrap(),
    )
    .unwrap();
    std::env::set_var("NYVOREL_BACKUP_TEST_ROOT", &root);
    let paths = Paths::new();
    for action in [
        "backup",
        "timeshift",
        "restic-check",
        "restore-test",
        "refresh-manifests",
        "smart-short",
        "smart-long",
        "mount",
    ] {
        let result = actions::run_action(&paths, action);
        assert!(result.is_err(), "{action} unexpectedly succeeded");
        let state: Value =
            serde_json::from_slice(&fs::read(paths.state("action-state.json")).unwrap()).unwrap();
        assert_eq!(state["state"], "failed", "{action}: {result:?}");
        assert_eq!(state["action"], action);
    }
    assert!(!PathBuf::from(&config["restic_repo"].as_str().unwrap()).exists());
    std::env::remove_var("NYVOREL_BACKUP_TEST_ROOT");
    fs::remove_dir_all(root).unwrap();
}
