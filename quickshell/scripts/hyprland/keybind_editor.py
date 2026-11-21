#!/usr/bin/env python3
"""Read active shortcuts and transactionally save Nyvorel shortcut overrides."""

import ctypes as C
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time


MODIFIERS = ((64, "SUPER"), (4, "CTRL"), (8, "ALT"), (1, "SHIFT"),
             (2, "CAPS"), (16, "MOD2"), (32, "MOD3"), (128, "MOD5"))
MODIFIER_MASK = dict((name, bit) for bit, name in MODIFIERS)
CAPTURE_MAP = "nyvorel-record-shortcut"


class EditError(Exception):
    pass


def hyprctl(*args):
    result = subprocess.run(["hyprctl", *args], text=True, capture_output=True, timeout=4)
    if result.returncode:
        raise EditError("Could not communicate with the running Hyprland session.")
    return result.stdout.strip()


def bind_slot(bind):
    key = f'code:{bind["keycode"]}' if bind.get("keycode") else bind.get("key", "").lower()
    return bind.get("submap") or "global", int(bind["modmask"]), key


def chord_slot(scope, chord):
    parts = [part.strip() for part in chord.split("+")]
    mask = 0
    for modifier in parts[:-1]:
        mask |= MODIFIER_MASK[modifier.upper()]
    return scope, mask, parts[-1].lower()


def wrap_chord(mask, key):
    return " + ".join([name for bit, name in MODIFIERS if mask & bit] + [key])


def unhex(value):
    return bytes.fromhex(value).decode("utf-8")


def hex_text(value):
    return value.encode("utf-8").hex()


def catalog(path):
    records = {}
    if not path.exists():
        return records
    for line in path.read_text(encoding="ascii").splitlines():
        try:
            *columns, count, movable, overridden, suspended = line.split("\t")
            key, scope, default, chord, default_label, label = map(unhex, columns)
            slot = chord_slot(scope, chord)
            default_slot = chord_slot(scope, default)
            records[key] = dict(id=key, scope=scope, defaultChord=default, chord=chord,
                                defaultLabel=default_label, label=label, slot=slot,
                                defaultSlot=default_slot, count=int(count), movable=movable == "1",
                                overridden=overridden == "1", suspended=suspended == "1")
        except (ValueError, KeyError):
            continue
    return records


def active_state(registry):
    binds = json.loads(hyprctl("-j", "binds"))
    records = catalog(registry)
    by_slot = {}
    for bind in binds:
        by_slot.setdefault(bind_slot(bind), []).append(bind)
    grouped_records = {}
    for record in records.values():
        grouped_records.setdefault(record["slot"], []).append(record)
    editable = {}
    for slot, entries in grouped_records.items():
        if len(entries) != 1:
            continue
        record = entries[0]
        active = by_slot.get(slot, [])
        if len(active) == record["count"] and any(bind.get("description") == record["label"] for bind in active):
            editable[record["id"]] = record
            for bind in active:
                if bind.get("description") and not bind["description"].startswith("[hidden]"):
                    bind["editor"] = {key: record[key] for key in (
                        "id", "movable", "defaultChord", "defaultLabel", "chord", "label", "count",
                        "overridden", "suspended"
                    )}
    return binds, editable


class KeyboardAliases:
    """Resolve keysyms and raw XKB keycodes against configured keyboard layouts."""

    class Names(C.Structure):
        _fields_ = [(name, C.c_char_p) for name in ("rules", "model", "layout", "variant", "options")]

    def __init__(self):
        self.lib = C.CDLL("libxkbcommon.so.0")
        for name, args, result in (
            ("xkb_context_new", [C.c_int], C.c_void_p),
            ("xkb_keymap_new_from_names", [C.c_void_p, C.POINTER(self.Names), C.c_int], C.c_void_p),
            ("xkb_keymap_unref", [C.c_void_p], None),
            ("xkb_context_unref", [C.c_void_p], None),
            ("xkb_keymap_min_keycode", [C.c_void_p], C.c_uint),
            ("xkb_keymap_max_keycode", [C.c_void_p], C.c_uint),
            ("xkb_keymap_num_layouts_for_key", [C.c_void_p, C.c_uint], C.c_uint),
            ("xkb_keymap_num_levels_for_key", [C.c_void_p, C.c_uint, C.c_uint], C.c_uint),
            ("xkb_keymap_key_get_syms_by_level", [C.c_void_p, C.c_uint, C.c_uint, C.c_uint, C.POINTER(C.POINTER(C.c_uint))], C.c_int),
            ("xkb_keysym_from_name", [C.c_char_p, C.c_int], C.c_uint),
            ("xkb_keysym_to_utf32", [C.c_uint], C.c_uint),
        ):
            function = getattr(self.lib, name)
            function.argtypes, function.restype = args, result
        self.codes = {}
        self.base_symbols = {}
        context = self.lib.xkb_context_new(0)
        if not context:
            raise EditError("Could not check the active keyboard layout.")
        try:
            names = []
            for option in ("rules", "model", "layout", "variant", "options"):
                value = json.loads(hyprctl("-j", "getoption", f"input:kb_{option}")).get("str", "")
                names.append(value.encode() if value and value != "[[EMPTY]]" else None)
            keymap = self.lib.xkb_keymap_new_from_names(context, C.byref(self.Names(*names)), 0)
            if not keymap:
                raise EditError("Could not check the active keyboard layout.")
            try:
                for code in range(self.lib.xkb_keymap_min_keycode(keymap), self.lib.xkb_keymap_max_keycode(keymap) + 1):
                    for layout in range(self.lib.xkb_keymap_num_layouts_for_key(keymap, code)):
                        for level in range(self.lib.xkb_keymap_num_levels_for_key(keymap, code, layout)):
                            symbols = C.POINTER(C.c_uint)()
                            count = self.lib.xkb_keymap_key_get_syms_by_level(keymap, code, layout, level, C.byref(symbols))
                            if count == 1 and layout == 0 and level == 0:
                                self.base_symbols[code] = symbols[0]
                            for symbol in symbols[:count]:
                                self.codes.setdefault(symbol, set()).add(code)
            finally:
                self.lib.xkb_keymap_unref(keymap)
        finally:
            self.lib.xkb_context_unref(context)

    def symbol(self, key):
        return self.lib.xkb_keysym_from_name(key.encode(), 1)

    def key_label(self, code):
        character = chr(self.lib.xkb_keysym_to_utf32(self.base_symbols.get(code, 0)))
        return character.upper() if character.isprintable() and not character.isspace() else ""

    def physical(self, key):
        if key.startswith("code:"):
            return {int(key.removeprefix("code:"))}
        return self.codes.get(self.symbol(key), set())

    def overlaps(self, first, second):
        if first[:2] != second[:2]:
            return False
        a, b = first[2], second[2]
        if a == b:
            return True
        sym_a, sym_b = self.symbol(a), self.symbol(b)
        if sym_a and sym_a == sym_b:
            return True
        # Physical bindings match independently of the configured layout.
        if a.startswith("code:") or b.startswith("code:"):
            return bool(self.physical(a) & self.physical(b))
        return False


def overrides_at(path):
    if not path.exists():
        return {}
    result = {}
    for line in path.read_text(encoding="ascii").splitlines():
        key, chord, label = map(unhex, line.split("\t"))
        result[key] = (chord, label)
    return result


def publish(path, data):
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix=".keybind-overrides-", delete=False) as file:
        pending = Path(file.name)
        try:
            file.write(data)
            file.flush()
            os.replace(pending, path)
        finally:
            pending.unlink(missing_ok=True)


def conflict_check(binds, records, targets, reset=False):
    if not targets:
        return
    aliases = KeyboardAliases()
    edited_slots = {records[key]["slot"] for key in targets}
    record_slots = {record["slot"]: record for record in records.values()}
    candidates = [(bind_slot(bind), bind, record_slots.get(bind_slot(bind))) for bind in binds
                  if not bind.get("catch_all") and bind_slot(bind) not in edited_slots]
    for key, slot in targets.items():
        record = records[key]
        if not slot[2].startswith("code:") and not aliases.symbol(slot[2]):
            raise EditError("Hyprland does not recognize this key.")
        for other_slot, bind, other in candidates:
            if not aliases.overlaps(slot, other_slot):
                continue
            intentional_alias = (reset and other and other_slot != slot
                                 and other_slot == other["defaultSlot"]
                                 and record["defaultLabel"] == other["defaultLabel"])
            if intentional_alias:
                continue
            description = bind.get("description") or "another active binding"
            raise EditError(f"{wrap_chord(slot[1], slot[2])} is already used by {description}.")
        for other_key, other_slot in targets.items():
            if key < other_key and aliases.overlaps(slot, other_slot):
                if reset and slot != other_slot and record["defaultLabel"] == records[other_key]["defaultLabel"]:
                    continue
                raise EditError("The selected default shortcuts overlap. Review the current bindings before resetting.")


def save(registry, path, args):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.with_suffix(".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if hyprctl("configerrors"):
            raise EditError("Hyprland has configuration errors. Fix them before editing shortcuts.")
        binds, records = active_state(registry)
        if not registry.is_file():
            raise EditError("The Nyvorel shortcut editor is unavailable in this Hyprland session.")
        old = path.read_bytes() if path.exists() else None
        stored = overrides_at(path)
        targets = {}
        reset = args[0] in ("reset", "reset-all")
        if args[0] == "reset-all":
            keys = set(stored) & catalog(registry).keys()
            if not keys <= records.keys():
                raise EditError("Some edited shortcuts have changed outside Nyvorel. Resolve the overlapping bindings before resetting.")
            for key in keys:
                if records[key]["slot"] != records[key]["defaultSlot"]:
                    targets[key] = records[key]["defaultSlot"]
            stored = {}
        else:
            key = args[1]
            if key not in records:
                raise EditError("This binding changed outside Nyvorel. Reopen the editor and try again.")
            record = records[key]
            keys = {key}
            if reset:
                if record["slot"] != record["defaultSlot"]: targets[key] = record["defaultSlot"]
                stored.pop(key, None)
            else:
                expected_chord, expected_label, mask, new_key, label = args[2:]
                if expected_chord != record["chord"] or expected_label != record["label"]:
                    raise EditError("This shortcut changed while it was open. Reopen it before saving.")
                mask = int(mask)
                label = label.strip()
                if not label or len(label) > 100 or label.startswith("[hidden]") or any(ord(char) < 32 for char in label):
                    raise EditError("Enter a description between 1 and 100 characters.")
                chord = stored.get(key, ("", ""))[0]
                if new_key:
                    if not record["movable"] or not 0 <= mask <= 255:
                        raise EditError("This shortcut supports description edits only.")
                    code_match = re.fullmatch(r"code:([1-9][0-9]{0,2})", new_key)
                    known_keycode = code_match and 8 <= int(code_match[1]) <= 775
                    if not known_keycode and not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_]{0,63}", new_key):
                        raise EditError("Record a supported keyboard shortcut.")
                    if (mask & 76) == 0 and not re.fullmatch(r"F(?:[1-9]|[12][0-9]|3[0-5])|Print|XF86\w+", new_key, re.I):
                        raise EditError("Add Super, Ctrl or Alt to avoid intercepting regular typing.")
                    slot = (record["scope"], mask, new_key.lower())
                    if slot != record["slot"]:
                        targets[key] = slot
                        chord = "" if slot == record["defaultSlot"] else wrap_chord(mask, new_key)
                description = "" if label == record["defaultLabel"] else label
                if chord or description:
                    stored[key] = (chord, description)
                else:
                    stored.pop(key, None)

        conflict_check(binds, records, targets, reset)
        data = "".join("\t".join(map(hex_text, (key, chord, label))) + "\n"
                       for key, (chord, label) in sorted(stored.items())).encode("ascii")
        if data == (old or b""):
            return
        publish(path, data)
        try:
            if hyprctl("reload") != "ok":
                raise EditError("Hyprland rejected the shortcut change.")
            for _ in range(18):
                time.sleep(0.12)
                _, fresh = active_state(registry)
                if not hyprctl("configerrors") and all(
                    key in fresh
                    and fresh[key]["slot"] == targets.get(key, records[key]["slot"])
                    and fresh[key]["label"] == (stored.get(key, ("", ""))[1] or records[key]["defaultLabel"])
                    for key in keys
                ):
                    return
            raise EditError("Could not verify the change in Hyprland. The previous shortcuts were restored.")
        except (EditError, OSError, ValueError, subprocess.SubprocessError):
            if old is None:
                path.unlink(missing_ok=True)
            else:
                publish(path, old)
            hyprctl("reload")
            raise


def main(args):
    instance = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    runtime = os.environ.get("XDG_RUNTIME_DIR", "")
    if not runtime or not re.fullmatch(r"[A-Za-z0-9_-]+", instance):
        raise EditError("Could not find the running Hyprland session.")
    registry = Path(runtime) / f"nyvorel-keybinds-{instance}.tsv"
    config_home = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
    path = config_home / "nyvorel/keybind-overrides.tsv"
    if args == ["list"]:
        binds, _ = active_state(registry)
        physical_binds = [bind for bind in binds if bind.get("keycode") and bind.get("editor", {}).get("overridden")
                          and bind["editor"]["chord"] != bind["editor"]["defaultChord"]]
        if physical_binds:
            try:
                aliases = KeyboardAliases()
                for bind in physical_binds:
                    bind["displayKey"] = aliases.key_label(bind["keycode"])
            except (EditError, OSError, ValueError, subprocess.SubprocessError):
                pass
        return dict(bindings=binds, customized=bool(overrides_at(path)))
    if args == ["capture-start"]:
        if hyprctl("submap") not in ("", "global"):
            raise EditError("Another Hyprland shortcut mode is active. Exit it before recording.")
        hyprctl("eval", "nyvorel_begin_keybind_capture()")
        if hyprctl("submap") != CAPTURE_MAP:
            raise EditError("Could not pause Hyprland shortcuts for recording.")
        return {}
    if args == ["capture-stop"]:
        if hyprctl("submap") == CAPTURE_MAP:
            hyprctl("eval", "nyvorel_end_keybind_capture()")
            if hyprctl("submap") == CAPTURE_MAP:
                raise EditError("Could not end shortcut recording. It will time out shortly.")
        return {}
    valid = {"save": 7, "reset": 2, "reset-all": 1}
    if not args or valid.get(args[0]) != len(args):
        raise EditError("Invalid shortcut editor request.")
    save(registry, path, args)
    return {}


if __name__ == "__main__":
    try:
        print(json.dumps(dict(ok=True, **main(sys.argv[1:]))))
    except EditError as error:
        print(json.dumps(dict(ok=False, message=str(error))))
    except (OSError, ValueError, KeyError, subprocess.SubprocessError):
        print(json.dumps(dict(ok=False, message="Could not read or update the shortcut configuration.")))
