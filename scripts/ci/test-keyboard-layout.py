#!/usr/bin/env python3
"""Exercise keyboard discovery and transactions without touching live Hyprland."""

import json
import os
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "quickshell/scripts/system/nyvorel-keyboard-layout"

RULES = """<xkbConfigRegistry><layoutList>
<layout><configItem><name>it</name><description>Italian</description></configItem></layout>
<layout><configItem><name>us</name><description>English (US)</description></configItem>
<variantList><variant><configItem><name>dvorak</name>
<description>English (Dvorak)</description></configItem></variant></variantList></layout>
</layoutList></xkbConfigRegistry>"""

MOCK_HYPRCTL = r"""#!/usr/bin/env python3
import json, os, re, sys
from pathlib import Path
path = Path(os.environ['MOCK_HYPR_STATE'])
state = json.loads(path.read_text())
args = sys.argv[1:]
if args[:1] == ['getoption']:
    key = 'layout' if args[1].endswith('kb_layout') else 'variant'
    print(json.dumps({'str': state[key] or '[[EMPTY]]'}))
elif args == ['devices', '-j']:
    print(json.dumps({'keyboards': [{
        'main': True, 'layout': state.get('device_layout', state['layout']),
        'variant': state['variant'], 'active_layout_index': state.get('index', 0),
    }]}))
elif args[:1] == ['eval'] and state.get('lua'):
    match = re.fullmatch(r'hl.config\(\{input=\{kb_layout=(.*),kb_variant=(.*)\}\}\)', args[1])
    if not match:
        sys.exit('Invalid Lua command')
    layout, variant = map(json.loads, match.groups())
    state.update(layout=layout, variant=variant, index=0)
    path.write_text(json.dumps(state))
    print('ok')
elif args[:1] == ['keyword'] and state.get('lua'):
    sys.exit('Legacy keyword is unavailable')
elif args[:2] == ['keyword', 'input:kb_layout']:
    state['layout'] = args[2]
    path.write_text(json.dumps(state))
    print('ok')
elif args[:2] == ['keyword', 'input:kb_variant']:
    if state.get('fail_variant') and args[2] == 'dvorak':
        sys.exit(1)
    state['variant'] = args[2]
    path.write_text(json.dumps(state))
    print('ok')
elif args == ['reload']:
    state.update(layout='it', variant='')
    path.write_text(json.dumps(state))
    print('ok')
else:
    sys.exit(2)
"""


def main():
    with tempfile.TemporaryDirectory(prefix="nyvorel-keyboard-ci-") as directory:
        base = Path(directory)
        (base / "evdev.xml").write_text(RULES)
        (base / "hyprctl").write_text(MOCK_HYPRCTL)
        (base / "hyprctl").chmod(0o755)
        state_path = base / "state.json"
        state_path.write_text(json.dumps({"layout": "it", "variant": ""}))
        env = dict(os.environ, PATH=f"{base}:{os.environ['PATH']}",
                   NYVOREL_XKB_RULES_FILE=str(base / "evdev.xml"),
                   MOCK_HYPR_STATE=str(state_path))

        def call(*args):
            result = subprocess.run([str(HELPER), *args], env=env,
                                    capture_output=True, text=True)
            return result.returncode, json.loads(result.stdout)

        code, response = call("catalog")
        assert code == 0
        assert {item["value"] for item in response["choices"]} == {"it", "us", "us:dvorak"}

        code, response = call("status")
        assert code == 0 and response["layout"] == "it" and response["variant"] == ""

        code, response = call("set", "us:dvorak")
        assert code == 0 and response["layout"] == "us" and response["variant"] == "dvorak"

        code, response = call("set", "missing")
        assert code != 0 and not response["ok"]
        assert json.loads(state_path.read_text())["layout"] == "us"

        state_path.write_text(json.dumps({"layout": "it", "variant": "", "fail_variant": True}))
        code, response = call("set", "us:dvorak")
        assert code != 0 and not response["ok"]
        state = json.loads(state_path.read_text())
        assert state["layout"] == "it" and state["variant"] == ""

        code, response = call("set", "us")
        assert code == 0 and response["layout"] == "us" and response["variant"] == ""
        code, response = call("restore")
        assert code == 0 and response["layout"] == "it" and response["variant"] == ""

        state_path.write_text(json.dumps({
            "lua": True, "layout": "it,us", "variant": ",dvorak", "index": 1,
        }))
        code, response = call("status")
        assert code == 0 and (response["layout"], response["variant"]) == ("us", "dvorak")
        code, response = call("set", "us")
        assert code == 0 and (response["layout"], response["variant"]) == ("us", "")

        state_path.write_text(json.dumps({
            "lua": True, "layout": "it", "variant": "", "device_layout": "it",
        }))
        code, response = call("set", "us")
        assert code != 0 and not response["ok"]
        assert json.loads(state_path.read_text())["layout"] == "it"

    print("Keyboard catalogue, active groups, Lua and legacy switching, rollback and restore passed")


if __name__ == "__main__":
    main()
