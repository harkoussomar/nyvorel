"""Nyvorel Option-D style Kitty status bar.

The bar consumes metadata published by ~/.config/fish/functions/fish_title.fish
using the existing NYVOREL_DEVBAR protocol. All colors come from the generated
Nyvorel Kitty theme; no theme colors are hard-coded here.
"""

from __future__ import annotations

from datetime import datetime
from pathlib import Path
from typing import Dict

from kitty.boss import get_boss
from kitty.fast_data_types import Screen, add_timer
from kitty.tab_bar import DrawData, ExtraData, TabBarData, as_rgb
from kitty.utils import color_as_int

THEME_FILE = Path.home() / ".config/kitty/nyvorel-dynamic-theme.conf"
_REFRESH_SECONDS = 20.0
_timer_started = False
_active_context: Dict[str, str] = {}


def _read_theme() -> Dict[str, str]:
    out: Dict[str, str] = {}
    try:
        for raw in THEME_FILE.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line:
                continue
            if line.startswith("# nyvorel-interface-style:"):
                out["ii_interface_style"] = line.split(":", 1)[1].strip().lower()
                continue
            if line.startswith("#"):
                continue
            parts = line.split(None, 1)
            if len(parts) == 2:
                out[parts[0]] = parts[1].strip()
    except OSError:
        pass
    return out


def _rgb(value, fallback) -> int:
    if isinstance(value, str) and value.startswith("#") and len(value) >= 7:
        try:
            return as_rgb(int(value[1:7], 16))
        except ValueError:
            pass
    try:
        return as_rgb(color_as_int(fallback))
    except Exception:
        try:
            return as_rgb(int(fallback))
        except Exception:
            return 0


def _palette(draw_data: DrawData):
    theme = _read_theme()
    bg = _rgb(theme.get("tab_bar_background"), draw_data.default_bg)
    surface = _rgb(theme.get("active_tab_background"), draw_data.active_bg)
    fg = _rgb(theme.get("foreground"), draw_data.active_fg)
    muted = _rgb(theme.get("inactive_tab_foreground"), draw_data.inactive_fg)
    primary = _rgb(theme.get("cursor"), draw_data.active_fg)
    accent = _rgb(theme.get("selection_foreground"), draw_data.active_fg)
    outline = _rgb(theme.get("inactive_border_color"), draw_data.inactive_fg)
    changed_bg = _rgb(theme.get("selection_background"), draw_data.active_bg)
    style = theme.get("ii_interface_style", "default")
    if style not in {"fluid", "prism", "inlay", "default"}:
        style = "default"
    return {
        "style": style,
        "bg": bg,
        "surface": surface,
        "fg": fg,
        "muted": muted,
        "primary": primary,
        "accent": accent,
        "outline": outline,
        "changed_bg": changed_bg,
    }


def _parse(title: str) -> Dict[str, str]:
    if not title.startswith("NYVOREL_DEVBAR::"):
        return {
            "branch": "",
            "changes": "0",
            "ahead": "0",
            "behind": "0",
            "runtime": "",
            "package_manager": "",
            "location": title or "~",
            "project_root": "",
            "title": title or "shell",
        }

    fields = title.split("::")
    fields += [""] * (9 - len(fields))
    return {
        "branch": fields[1],
        "changes": fields[2] or "0",
        "ahead": fields[3] or "0",
        "behind": fields[4] or "0",
        "runtime": fields[5],
        "package_manager": fields[6],
        "location": fields[7],
        "project_root": fields[8],
        "title": fields[7] or "shell",
    }


def _num(value: str) -> int:
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return 0


def _clip(text: str, width: int) -> str:
    text = text or ""
    if width <= 1:
        return "…" if text else ""
    if len(text) <= width:
        return text
    return text[: width - 1] + "…"


def _project_label(ctx: Dict[str, str]) -> str:
    root = ctx.get("project_root", "")
    if root:
        home = str(Path.home())
        if root == home:
            return "~"
        try:
            return Path(root).name or "/"
        except Exception:
            pass
    loc = ctx.get("location", "")
    if loc in ("omar", str(Path.home())):
        return "~"
    return loc or "~"


def _draw(
    screen: Screen,
    text: str,
    fg: int,
    bg: int,
    *,
    bold: bool = False,
) -> None:
    screen.cursor.fg = fg
    screen.cursor.bg = bg
    screen.cursor.bold = bold
    screen.cursor.italic = False
    screen.cursor.dim = False
    screen.draw(text)


def _separator_text(style: str) -> str:
    if style == "fluid":
        return " │ "
    if style == "prism":
        return "  "
    if style == "inlay":
        return "│"
    return " · "


def _separator(screen: Screen, colors) -> None:
    style = colors["style"]
    bg = colors["surface"] if style == "inlay" else colors["bg"]
    _draw(screen, _separator_text(style), colors["outline"], bg)


def _draw_active_fluid(screen: Screen, ctx: Dict[str, str], colors, columns: int) -> None:
    # Frozen Fluid path: this is the original terminal bottom-bar renderer.
    narrow = columns < 92
    project = _clip(_project_label(ctx), 20 if narrow else 26)

    _draw(screen, f" 󰉋 {project} ", colors["primary"], colors["bg"], bold=True)

    branch = ctx.get("branch", "")
    if branch:
        _separator(screen, colors)
        branch_width = 22 if narrow else 36
        _draw(screen, f"󰘬 {_clip(branch, branch_width)} ", colors["primary"], colors["bg"], bold=False)

        changes = _num(ctx.get("changes", "0"))
        if changes > 0:
            if not narrow:
                _draw(screen, " ", colors["fg"], colors["bg"])
            _draw(
                screen,
                f" ● {changes} changed ",
                colors["accent"],
                colors["changed_bg"],
                bold=False,
            )
        elif not narrow:
            _draw(screen, " ✓ clean ", colors["muted"], colors["bg"])

        ahead = _num(ctx.get("ahead", "0"))
        behind = _num(ctx.get("behind", "0"))
        if columns >= 118 and (ahead or behind):
            sync_bits = []
            if ahead:
                sync_bits.append(f"⇡{ahead}")
            if behind:
                sync_bits.append(f"⇣{behind}")
            _draw(screen, " " + " ".join(sync_bits) + " ", colors["muted"], colors["bg"])


def _draw_active_default(screen: Screen, ctx: Dict[str, str], colors, columns: int) -> None:
    narrow = columns < 92
    project = _clip(_project_label(ctx), 20 if narrow else 28)
    _draw(screen, f" 󰉋 {project} ", colors["primary"], colors["bg"], bold=True)
    branch = ctx.get("branch", "")
    if branch:
        _separator(screen, colors)
        _draw(screen, f"git:{_clip(branch, 22 if narrow else 34)}", colors["muted"], colors["bg"])
        changes = _num(ctx.get("changes", "0"))
        if changes:
            _draw(screen, f" +{changes}", colors["accent"], colors["bg"], bold=True)


def _draw_active_prism(screen: Screen, ctx: Dict[str, str], colors, columns: int) -> None:
    narrow = columns < 92
    project = _clip(_project_label(ctx), 18 if narrow else 25)
    _draw(screen, f" 󰉋 {project} ", colors["primary"], colors["surface"], bold=True)
    branch = ctx.get("branch", "")
    if branch:
        _separator(screen, colors)
        _draw(screen, f" 󰘬 {_clip(branch, 21 if narrow else 32)} ", colors["primary"], colors["surface"])
        changes = _num(ctx.get("changes", "0"))
        if changes:
            _draw(screen, "  ", colors["muted"], colors["bg"])
            _draw(screen, f" ● {changes} ", colors["accent"], colors["changed_bg"])
        elif not narrow:
            _draw(screen, "  ", colors["muted"], colors["bg"])
            _draw(screen, " ✓ ", colors["muted"], colors["surface"])


def _draw_active_inlay(screen: Screen, ctx: Dict[str, str], colors, columns: int) -> None:
    narrow = columns < 92
    project = _clip(_project_label(ctx), 18 if narrow else 24)
    _draw(screen, f" 󰉋 {project} ", colors["primary"], colors["surface"], bold=True)
    branch = ctx.get("branch", "")
    if branch:
        _separator(screen, colors)
        _draw(screen, f" 󰘬 {_clip(branch, 20 if narrow else 30)} ", colors["fg"], colors["surface"])
        changes = _num(ctx.get("changes", "0"))
        if changes:
            _separator(screen, colors)
            _draw(screen, f" ! {changes} ", colors["accent"], colors["changed_bg"], bold=True)
        elif not narrow:
            _separator(screen, colors)
            _draw(screen, " ✓ ", colors["muted"], colors["surface"])


def _draw_active(screen: Screen, ctx: Dict[str, str], colors, columns: int) -> None:
    style = colors["style"]
    if style == "fluid":
        _draw_active_fluid(screen, ctx, colors, columns)
    elif style == "prism":
        _draw_active_prism(screen, ctx, colors, columns)
    elif style == "inlay":
        _draw_active_inlay(screen, ctx, colors, columns)
    else:
        _draw_active_default(screen, ctx, colors, columns)


def _right_cells(ctx: Dict[str, str], columns: int):
    cells = []
    runtime = ctx.get("runtime", "")
    if runtime and columns >= 92:
        cells.append(("runtime", f" {runtime} "))
    cells.append(("time", datetime.now().strftime(" 󰥔 %H:%M ")))
    return cells


def _right_width(cells, style: str) -> int:
    sep = len(_separator_text(style))
    return sum(len(text) + (sep if i > 0 else 0) for i, (_, text) in enumerate(cells))


def _draw_right(screen: Screen, cells, colors) -> None:
    style = colors["style"]
    for i, (kind, text) in enumerate(cells):
        if i:
            _separator(screen, colors)
        bg = colors["surface"] if style in {"prism", "inlay"} else colors["bg"]
        if kind == "runtime":
            _draw(screen, text, colors["primary"], bg, bold=True)
        else:
            _draw(screen, text, colors["fg"], bg, bold=True)


def _redraw_tab_bar(_timer_id) -> None:
    try:
        tm = get_boss().active_tab_manager
        if tm is not None:
            tm.mark_tab_bar_dirty()
    except Exception:
        pass


def _ensure_timer() -> None:
    global _timer_started
    if _timer_started:
        return
    try:
        add_timer(_redraw_tab_bar, _REFRESH_SECONDS, True)
        _timer_started = True
    except Exception:
        pass


def draw_tab(
    draw_data: DrawData,
    screen: Screen,
    tab: TabBarData,
    before: int,
    max_title_length: int,
    index: int,
    is_last: bool,
    extra_data: ExtraData,
) -> int:
    global _active_context

    _ensure_timer()
    colors = _palette(draw_data)
    screen.cursor.bg = colors["bg"]

    ctx = _parse(tab.title)

    if tab.is_active:
        _active_context = ctx
        _draw_active(screen, ctx, colors, screen.columns)
    else:
        label = _clip(_project_label(ctx), 18)
        style = colors["style"]
        if style == "fluid":
            _draw(screen, f" {index}:{label} ", colors["muted"], colors["bg"])
        elif style == "prism":
            _draw(screen, f" {index}·{label} ", colors["muted"], colors["surface"])
        elif style == "inlay":
            _draw(screen, f" {index} {label} ", colors["muted"], colors["surface"])
        else:
            _draw(screen, f" {index}:{label} ", colors["muted"], colors["bg"])

    left_end = screen.cursor.x

    if is_last:
        active = _active_context or ctx
        cells = _right_cells(active, screen.columns)
        width = _right_width(cells, colors["style"])
        padding = screen.columns - screen.cursor.x - width
        if padding > 0:
            _draw(screen, " " * padding, colors["muted"], colors["bg"])
        _draw_right(screen, cells, colors)

    return left_end

