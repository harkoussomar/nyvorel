mod health;
mod linux;
mod state;

use serde_json::{Value, json};
use std::{env, process::ExitCode};

fn run(args: &[String]) -> (Value, u8) {
    if args.is_empty() {
        return (json!({"error": "missing command"}), 2);
    }

    let paths = state::Paths::from_env();
    // The lock covers each read-modify-write transaction, including snapshots.
    // The status command also takes it so it cannot observe a half-written state.
    let result = (|| -> Result<(Value, Value), String> {
        let _lock = state::Lock::acquire(&paths.lock)?;
        let mut stored = state::load_state(&paths)?;
        let payload = match args[0].as_str() {
            "snapshot" => state::snapshot(&paths, &mut stored)?,
            "status" => Value::Null,
            "favorites" => {
                let mut output = json!({});
                output["favorites"] = stored["favorites"].clone();
                output
            }
            "toggle-favorite" => {
                let id = args.get(1).ok_or("missing favorite id")?;
                state::toggle_favorite(&paths, &mut stored, id)?
            }
            "history" => {
                let mut output = json!({});
                output["history"] = stored["history"].clone();
                output
            }
            "undo" => state::undo(&paths, &mut stored)?,
            "backup" => state::backup(&paths, &mut stored)?,
            "restore-latest" => state::restore_latest(&paths, &mut stored)?,
            other => return Err(format!("unknown command: {other}")),
        };
        Ok((payload, stored))
    })();

    match result {
        Ok((mut payload, stored)) => {
            // External health probes can be slow. Release the state lock first so
            // snapshots and clicks are not blocked by hyprctl timeouts.
            let summary = health::summary(&paths, &stored);
            for (key, value) in summary.as_object().expect("health summary is an object") {
                payload[key] = value.clone();
            }
            (payload, 0)
        }
        Err(message) => {
            let stored = state::load_state(&paths).unwrap_or_else(|_| state::default_state());
            let mut payload = health::summary(&paths, &stored);
            payload["message"] = json!(message);
            payload["error"] = json!(true);
            (payload, 0) // Match the existing Python QML transport contract.
        }
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();
    let (payload, status) = run(&args);
    println!("{}", payload);
    ExitCode::from(status)
}
