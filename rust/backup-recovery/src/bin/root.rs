use nyvorel_backup_recovery::{actions, collector, root_common::Paths};

fn main() {
    let mut args = std::env::args().skip(1);
    let command = args.next().unwrap_or_default();
    let paths = Paths::new();
    let result = match command.as_str() {
        "collect" => {
            let dry_run = args.next().as_deref() == Some("--dry-run");
            if !dry_run && unsafe { libc::geteuid() } != 0 {
                Err("State collector must run as root.".into())
            } else {
                collector::collect_state(&paths, dry_run).map(|state| {
                    if dry_run {
                        println!("{state}");
                    }
                })
            }
        }
        "" => Err("Action required.".into()),
        _ => {
            if unsafe { libc::geteuid() } != 0 {
                Err("This helper must run as root.".into())
            } else {
                actions::run_action(&paths, &command)
            }
        }
    };
    if let Err(error) = result {
        eprintln!("{error}");
        std::process::exit(1);
    }
}
