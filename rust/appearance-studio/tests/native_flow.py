#!/usr/bin/env python3
"""Compare complete native appearance flows in isolated XDG trees.

No command can reach the live config, shell runtime, monitor, or gsettings.
"""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT.parents[1]
RUST = ROOT / "target/release/nyvorel-appearance-studio"
PYTHON = PROJECT / "quickshell/scripts/appearance-studio/appearance_studio.py"
REAL_HOME = Path.home()


def fixture(root):
    home = root / "home"
    config = home / ".config"
    state = home / ".local/state"
    cache = home / ".cache"
    generated = state / "quickshell/user/generated"
    nyvorel = config / "nyvorel"
    scripts = config / "quickshell/nyvorel/scripts/colors"
    appearance_scripts = config / "quickshell/nyvorel/scripts/appearance-studio"
    fake_bin = root / "bin"
    for path in (generated, nyvorel, scripts, appearance_scripts, fake_bin, home / ".local/bin"):
        path.mkdir(parents=True, exist_ok=True)
    shutil.copytree(PROJECT / "matugen", config / "matugen")
    shutil.copy2(PROJECT / "quickshell/scripts/appearance-studio/wallpaper_profile.py", appearance_scripts / "wallpaper_profile.py")
    shutil.copy2(PROJECT / "quickshell/scripts/appearance-studio/palette_probe.py", appearance_scripts / "palette_probe.py")
    wallpaper = root.parent / "wallpaper.ppm"
    wallpaper.write_text("P3\n2 2\n255\n120 30 90\n120 30 90\n20 80 160\n20 80 160\n")
    (root.parent / "video.mp4").write_bytes(b"isolated video fixture")
    cfg = json.loads((REAL_HOME / ".config/nyvorel/config.json").read_text())
    cfg.setdefault("background", {})["wallpaperPath"] = str(wallpaper)
    (nyvorel / "config.json").write_text(json.dumps(cfg))
    appearance = json.loads((REAL_HOME / ".config/nyvorel/appearance-studio.json").read_text())
    appearance["preview"] = None
    appearance["active"]["wallpaper"] = str(wallpaper)
    (nyvorel / "appearance-studio.json").write_text(json.dumps(appearance))
    shutil.copy2(REAL_HOME / ".local/state/quickshell/user/generated/colors.json", generated / "colors.json")
    fake_switchwall = scripts / "switchwall.sh"
    fake_switchwall.write_text(
        "#!/usr/bin/python3\n"
        "import json, os, pathlib, subprocess, sys\n"
        "if os.environ.get('NYVOREL_APPEARANCE_TEST_FAIL_SWITCHWALL'): sys.exit(7)\n"
        "args = sys.argv[1:]\n"
        "def opt(name): return args[args.index(name)+1]\n"
        f"binary = {str(RUST)!r}\n"
        "result = subprocess.run([binary, '__palette', opt('--color'), opt('--type'), opt('--mode')], capture_output=True, text=True)\n"
        "if result.returncode: sys.exit(result.returncode)\n"
        "target = pathlib.Path(os.environ['XDG_STATE_HOME'])/'quickshell/user/generated/colors.json'\n"
        "target.parent.mkdir(parents=True, exist_ok=True)\n"
        "target.write_text(json.dumps(json.loads(result.stdout)))\n"
    )
    fake_switchwall.chmod(0o755)
    for helper in ("nyvorel-glass-runtime", "nyvorel-fluid-runtime"):
        path = home / ".local/bin" / helper
        path.write_text("#!/bin/sh\nexit 0\n")
        path.chmod(0o755)
    for helper, body in (
        ("gsettings", "#!/bin/sh\nif [ \"$1\" = get ]; then printf \"'prefer-dark'\\n\"; fi\nexit 0\n"),
        ("systemd-run", "#!/bin/sh\nexit 0\n"),
        ("hyprctl", "#!/bin/sh\nif [ \"$1\" = monitors ]; then printf '[{\"name\":\"eDP-1\"}]\\n'; exit 0; fi\nexit 1\n"),
        ("pkill", "#!/bin/sh\nexit 0\n"),
        ("ffmpeg", "#!/bin/sh\nfor last; do :; done\ncp \"$NYVOREL_TEST_FRAME\" \"$last\"\n"),
        ("mpvpaper", "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$NYVOREL_TEST_MPVLOG\"\n"),
    ):
        path = fake_bin / helper
        path.write_text(body)
        path.chmod(0o755)
    env = dict(os.environ,
               HOME=str(home), XDG_CONFIG_HOME=str(config), XDG_STATE_HOME=str(state),
               XDG_CACHE_HOME=str(cache), XDG_CURRENT_DESKTOP="test",
               NYVOREL_APPEARANCE_TEST_NO_WATCHDOG="1",
               NYVOREL_APPEARANCE_SMART_SEEDS="1",
               NYVOREL_VIRTUAL_ENV=str(REAL_HOME / ".local/state/quickshell/.venv"),
               NYVOREL_TEST_FRAME=str(wallpaper),
               NYVOREL_TEST_MPVLOG=str(root / "mpvpaper.log"),
               PATH=str(fake_bin) + os.pathsep + os.environ["PATH"])
    env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
    return env


def invoke(backend, args, env):
    command = (["/usr/bin/python3", str(PYTHON)] if backend == "python" else [str(RUST)]) + args
    result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=80)
    if not result.stdout:
        raise AssertionError(f"No JSON from {command}: {result.stderr}")
    value = json.loads(result.stdout)
    if result.returncode or value.get("ok") is not True:
        raise AssertionError(f"{backend} {args}: {value}\n{result.stderr}")
    return value


def normalized(value):
    if isinstance(value, dict):
        return {key: ("<generated>" if key in ("id", "timestamp", "token", "started", "updated", "expiresAt") else normalized(item))
                for key, item in value.items()}
    if isinstance(value, list):
        return [normalized(item) for item in value]
    if isinstance(value, str):
        return value.replace("/python/home/", "/ENV/home/").replace("/rust/home/", "/ENV/home/")
    return value


def check_same(left, right, label):
    left = normalized(left)
    right = normalized(right)
    def equivalent(a, b):
        if isinstance(a, (int, float)) and not isinstance(a, bool) and isinstance(b, (int, float)) and not isinstance(b, bool):
            return abs(a-b) < 1e-8
        if isinstance(a, dict) and isinstance(b, dict):
            return a.keys() == b.keys() and all(equivalent(a[key], b[key]) for key in a)
        if isinstance(a, list) and isinstance(b, list):
            return len(a) == len(b) and all(equivalent(x, y) for x, y in zip(a, b))
        return a == b
    if not equivalent(left, right):
        def differences(a, b, path=""):
            if isinstance(a, dict) and isinstance(b, dict):
                for key in sorted(a.keys() | b.keys()):
                    yield from differences(a.get(key), b.get(key), f"{path}.{key}")
            elif isinstance(a, list) and isinstance(b, list):
                for index, (x, y) in enumerate(zip(a, b)):
                    yield from differences(x, y, f"{path}[{index}]")
                if len(a) != len(b):
                    yield f"{path}.length", len(a), len(b)
            elif not equivalent(a, b):
                yield path, a, b
        raise AssertionError(f"{label} differs: {list(differences(left, right))[:8]}")


def main():
    with tempfile.TemporaryDirectory(prefix="nyvorel-native-flow-") as directory:
        roots = {name: Path(directory) / name for name in ("python", "rust")}
        envs = {name: fixture(root) for name, root in roots.items()}
        for args in (
            ["apply", "--source", "preset", "--preset", "ocean", "--mode", "light"],
            ["apply", "--source", "preset", "--preset", "ocean", "--mode", "light",
             "--ui-json", json.dumps({"bar.verbose": False, "appearance.geometry.radius.global": 12})],
            ["apply", "--source", "preset", "--preset", "midnight", "--mode", "dark", "--preview"],
            ["apply", "--source", "custom", "--seed", "#ad4279", "--mode", "dim", "--preview"],
            ["keep-preview"],
            ["apply", "--source", "custom", "--seed", "ii4:#AD4279|#22BBCC|#7744AA|#777777", "--mode", "oled"],
            ["ui-profile", "default"],
            ["target", "qt", "false"],
            ["target", "qt", "true"],
            ["apply", "--source", "hybrid", "--preset", "forest", "--mode", "dark"],
            ["apply", "--source", "preset", "--preset", "ocean", "--wallpaper", str(Path(directory) / "video.mp4")],
            ["apply", "--source", "preset", "--preset", "ocean", "--wallpaper", str(Path(directory) / "wallpaper.ppm")],
            ["target", "shell", "false"],
            ["apply", "--source", "preset", "--preset", "arctic", "--mode", "dark"],
            ["target", "shell", "true"],
        ):
            values = {name: invoke(name, args, envs[name]) for name in roots}
            check_same(values["python"], values["rust"], str(args))
            statuses = {name: invoke(name, ["status"], envs[name]) for name in roots}
            check_same(statuses["python"], statuses["rust"], f"status after {args}")
        favorites = {name: invoke(name, ["favorite-add", "--label", "Saved test"], envs[name]) for name in roots}
        check_same(favorites["python"], favorites["rust"], "favorite-add")
        for kind in ("favorite-apply", "history-apply"):
            ids = ({name: favorites[name]["favorite"]["id"] for name in roots}
                   if kind == "favorite-apply" else
                   {name: invoke(name, ["status"], envs[name])["history"][0]["id"] for name in roots})
            values = {name: invoke(name, [kind, ids[name]], envs[name]) for name in roots}
            check_same(values["python"], values["rust"], kind)
            check_same(invoke("python", ["status"], envs["python"]), invoke("rust", ["status"], envs["rust"]), kind + " status")
        for name in roots:
            invoke(name, ["apply", "--source", "preset", "--preset", "arctic", "--preview"], envs[name])
        check_same(invoke("python", ["revert-preview"], envs["python"]), invoke("rust", ["revert-preview"], envs["rust"]), "revert-preview")
        check_same(invoke("python", ["status"], envs["python"]), invoke("rust", ["status"], envs["rust"]), "revert status")
        variants = {name: invoke(name, ["variants", "--wallpaper", str(Path(directory) / "wallpaper.ppm"), "--mode", "dark"], envs[name]) for name in roots}
        check_same(variants["python"], variants["rust"], "variants")
        # A failed renderer must restore exact config, state, and color bytes.
        for name, root in roots.items():
            files = [root / "home/.config/nyvorel/config.json",
                     root / "home/.config/nyvorel/appearance-studio.json",
                     root / "home/.local/state/quickshell/user/generated/colors.json"]
            before = [path.read_bytes() for path in files]
            env = dict(envs[name], NYVOREL_APPEARANCE_TEST_FAIL_SWITCHWALL="1")
            command = (["/usr/bin/python3", str(PYTHON)] if name == "python" else [str(RUST)]) + [
                "apply", "--source", "preset", "--preset", "ocean", "--mode", "light"]
            failed = subprocess.run(command, env=env, capture_output=True, text=True, timeout=30)
            if failed.returncode == 0 or json.loads(failed.stdout).get("ok") is not False:
                raise AssertionError(f"Expected renderer failure for {name}")
            if [path.read_bytes() for path in files] != before:
                raise AssertionError(f"Failed renderer did not roll back {name}")
            bad_bin = root / "bad-bin"
            bad_bin.mkdir()
            matugen = bad_bin / "matugen"
            matugen.write_text("#!/bin/sh\nexit 9\n")
            matugen.chmod(0o755)
            bad_env = dict(envs[name], PATH=str(bad_bin) + os.pathsep + envs[name]["PATH"])
            preview_failure = subprocess.run(
                (["/usr/bin/python3", str(PYTHON)] if name == "python" else [str(RUST)]) +
                ["apply", "--source", "preset", "--preset", "ocean", "--preview"],
                env=bad_env, capture_output=True, text=True, timeout=30)
            if preview_failure.returncode == 0 or json.loads(preview_failure.stdout).get("ok") is not False:
                raise AssertionError(f"Expected preview renderer failure for {name}")
            if [path.read_bytes() for path in files] != before:
                raise AssertionError(f"Failed preview did not roll back {name}")
            if (root / "home/.cache/nyvorel-appearance-studio/preview").exists():
                raise AssertionError(f"Failed preview retained a snapshot for {name}")
    print("Native Appearance Studio preview, Keep, apply, profile, target, rollback parity: passed")


if __name__ == "__main__":
    main()
