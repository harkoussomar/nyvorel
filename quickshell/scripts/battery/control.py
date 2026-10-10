#!/usr/bin/env python3
"""Bridge the shell to an installed, administrator-owned threshold helper.

Keep compatibility with pre-rename installations. Never infer a configured
threshold from a missing file, or silently discard a privileged action failure.
"""
import json
import os
from pathlib import Path
import subprocess
import sys

BACKENDS = (
    (Path('/usr/local/bin/nyvorel-battery-threshold'), Path('/etc/nyvorel-battery-threshold')),
    (Path('/usr/local/bin/ii-battery-threshold'), Path('/etc/ii-battery-threshold')),
)
THRESHOLD = Path('/sys/class/power_supply/BAT0/charge_control_end_threshold')
LIMITS = (60, 70, 80, 90, 100)


def read_limit(path):
    try:
        value = int(path.read_text().strip())
        return value if 1 <= value <= 100 else None
    except (OSError, ValueError):
        return None


def backend():
    return next(((helper, config) for helper, config in BACKENDS
                 if helper.is_file() and os.access(helper, os.X_OK)), None)


def status():
    selected = backend()
    current = read_limit(THRESHOLD)
    saved = read_limit(selected[1]) if selected else None
    # Both supported helpers explicitly default missing/invalid config to 100.
    persistent = saved if saved in LIMITS else 100
    return {'available': selected is not None and current is not None,
            'current': current if current is not None else -1,
            'persistent': persistent,
            'message': ('Charge control is unavailable on this battery' if current is None
                        else 'Battery threshold helper is not installed' if not selected else '')}


def action(args):
    if args != ['once'] and not (len(args) == 2 and args[0] == 'set'
                                and args[1] in tuple(map(str, LIMITS))):
        raise ValueError('Allowed actions: set 60|70|80|90|100, once')
    selected = backend()
    if not selected or read_limit(THRESHOLD) is None:
        raise ValueError(status()['message'])
    result = subprocess.run(['/usr/bin/sudo', '-n', str(selected[0]), *args],
                            capture_output=True, text=True, timeout=15)
    if result.returncode:
        raise ValueError(result.stderr.strip() or 'Battery threshold change failed')
    expected = 100 if args == ['once'] else int(args[1])
    state = status()
    if state['current'] != expected or (args[0] == 'set' and state['persistent'] != expected):
        raise ValueError('Battery threshold did not match the requested value')
    return state


def main():
    try:
        print(json.dumps(status() if sys.argv[1:] == ['status'] else action(sys.argv[1:])))
        return 0
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
