-- Nyvorel native Hyprland Lua configuration.
-- Ported from the reviewed main-machine candidate for Hyprland 0.56.2.
-- Project-owned settings, keybinds, and rules are retained. Generated runtime
-- modules are loaded when present so Appearance Studio, Matugen, HyprMod, and
-- nwg-displays can continue to manage their own files.
-- This source has been parser-checked on 0.56.2; no 0.57 compatibility claim.
local config_home = os.getenv("XDG_CONFIG_HOME") or ((os.getenv("HOME") or "") .. "/.config")
local nyvorel_config_root = NYVOREL_CONFIG_ROOT or (config_home .. "/hypr")
local super_scroll = "~/.local/bin/nyvorel-super-scroll"
local function load_optional(path)
  local chunk = loadfile(path)
  if chunk then chunk() end
end
-- hyprland.conf:4
-- hyprland.conf:5
-- hyprland.conf:6
hl.define_submap("global", function()
-- hyprland.conf:9
-- hyprland/env.conf:2
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
-- hyprland/env.conf:5
hl.env("XDG_DATA_DIRS", (os.getenv("HOME") or "") .. "/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share")
-- hyprland/env.conf:8
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
-- hyprland/env.conf:9
hl.env("QT_QPA_PLATFORMTHEME", "kde")
-- hyprland/env.conf:10
hl.env("XDG_MENU_PREFIX", "plasma-")
-- hyprland/env.conf:13
hl.env("NYVOREL_VIRTUAL_ENV", "~/.local/state/quickshell/.venv")
-- hyprland/env.conf:16
hl.env("TERMINAL", "kitty -1")
-- hyprland.conf:10
-- hyprland.conf:13
-- hyprland/execs.conf:2
-- hyprland/execs.conf:3
-- hyprland/execs.conf:4
-- hyprland/execs.conf:7
-- hyprland/execs.conf:9
-- hyprland/execs.conf:10
-- hyprland/execs.conf:13
-- hyprland/execs.conf:17
-- hyprland/execs.conf:18
-- hyprland/execs.conf:21
-- hyprland.conf:14
-- hyprland/general.conf:2
hl.monitor({["output"] = "", ["mode"] = "preferred", ["position"] = "auto", ["scale"] = 1})
-- hyprland/general.conf:4
hl.gesture({["fingers"] = 3, ["direction"] = "swipe", ["action"] = "move"})
-- hyprland/general.conf:5
hl.gesture({["fingers"] = 3, ["direction"] = "pinch", ["action"] = "float"})
-- hyprland/general.conf:6
hl.gesture({["fingers"] = 4, ["direction"] = "horizontal", ["action"] = "workspace"})
-- hyprland/general.conf:7
hl.gesture({["fingers"] = 4, ["direction"] = "up", ["action"] = function() hl.dispatch(hl.dsp.global("quickshell:overviewWorkspacesToggle")) end})
-- hyprland/general.conf:8
hl.gesture({["fingers"] = 4, ["direction"] = "down", ["action"] = function() hl.dispatch(hl.dsp.global("quickshell:overviewWorkspacesClose")) end})
-- hyprland/general.conf:10
hl.config({["gestures"] = {["workspace_swipe_distance"] = 700}})
-- hyprland/general.conf:11
hl.config({["gestures"] = {["workspace_swipe_cancel_ratio"] = 0.2}})
-- hyprland/general.conf:12
hl.config({["gestures"] = {["workspace_swipe_min_speed_to_force"] = 5}})
-- hyprland/general.conf:13
hl.config({["gestures"] = {["workspace_swipe_direction_lock"] = true}})
-- hyprland/general.conf:14
hl.config({["gestures"] = {["workspace_swipe_direction_lock_threshold"] = 10}})
-- hyprland/general.conf:15
hl.config({["gestures"] = {["workspace_swipe_create_new"] = true}})
-- hyprland/general.conf:20
hl.config({["general"] = {["gaps_in"] = 2}})
-- hyprland/general.conf:21
hl.config({["general"] = {["gaps_out"] = 4}})
-- hyprland/general.conf:22
hl.config({["general"] = {["gaps_workspaces"] = 50}})
-- hyprland/general.conf:24
hl.config({["general"] = {["border_size"] = 1}})
-- hyprland/general.conf:25
hl.config({["general"] = {["col"] = {["active_border"] = "rgba(0DB7D455)"}}})
-- hyprland/general.conf:26
hl.config({["general"] = {["col"] = {["inactive_border"] = "rgba(31313600)"}}})
-- hyprland/general.conf:27
hl.config({["general"] = {["resize_on_border"] = true}})
-- hyprland/general.conf:29
hl.config({["general"] = {["no_focus_fallback"] = true}})
-- hyprland/general.conf:31
hl.config({["general"] = {["allow_tearing"] = true}})
-- hyprland/general.conf:34
hl.config({["general"] = {["snap"] = {["enabled"] = true}}})
-- hyprland/general.conf:35
hl.config({["general"] = {["snap"] = {["window_gap"] = 4}}})
-- hyprland/general.conf:36
hl.config({["general"] = {["snap"] = {["monitor_gap"] = 5}}})
-- hyprland/general.conf:37
hl.config({["general"] = {["snap"] = {["respect_gaps"] = true}}})
-- hyprland/general.conf:42
hl.config({["dwindle"] = {["preserve_split"] = true}})
-- hyprland/general.conf:43
hl.config({["dwindle"] = {["smart_split"] = false}})
-- hyprland/general.conf:44
hl.config({["dwindle"] = {["smart_resizing"] = false}})
-- hyprland/general.conf:45
hl.config({["dwindle"] = {["precise_mouse_move"] = true}})
-- hyprland/general.conf:51
hl.config({["decoration"] = {["rounding_power"] = 2}})
-- hyprland/general.conf:52
hl.config({["decoration"] = {["rounding"] = 8}})
-- hyprland/general.conf:55
hl.config({["decoration"] = {["blur"] = {["enabled"] = true}}})
-- hyprland/general.conf:56
hl.config({["decoration"] = {["blur"] = {["xray"] = true}}})
-- hyprland/general.conf:57
hl.config({["decoration"] = {["blur"] = {["special"] = false}}})
-- hyprland/general.conf:58
hl.config({["decoration"] = {["blur"] = {["new_optimizations"] = true}}})
-- hyprland/general.conf:59
hl.config({["decoration"] = {["blur"] = {["size"] = 10}}})
-- hyprland/general.conf:60
hl.config({["decoration"] = {["blur"] = {["passes"] = 3}}})
-- hyprland/general.conf:61
hl.config({["decoration"] = {["blur"] = {["brightness"] = 1}}})
-- hyprland/general.conf:62
hl.config({["decoration"] = {["blur"] = {["noise"] = 0.05}}})
-- hyprland/general.conf:63
hl.config({["decoration"] = {["blur"] = {["contrast"] = 0.89}}})
-- hyprland/general.conf:64
hl.config({["decoration"] = {["blur"] = {["vibrancy"] = 0.5}}})
-- hyprland/general.conf:65
hl.config({["decoration"] = {["blur"] = {["vibrancy_darkness"] = 0.5}}})
-- hyprland/general.conf:66
hl.config({["decoration"] = {["blur"] = {["popups"] = false}}})
-- hyprland/general.conf:67
hl.config({["decoration"] = {["blur"] = {["popups_ignorealpha"] = 0.6}}})
-- hyprland/general.conf:68
hl.config({["decoration"] = {["blur"] = {["input_methods"] = true}}})
-- hyprland/general.conf:69
hl.config({["decoration"] = {["blur"] = {["input_methods_ignorealpha"] = 0.8}}})
-- hyprland/general.conf:73
hl.config({["decoration"] = {["shadow"] = {["enabled"] = true}}})
-- hyprland/general.conf:74
hl.config({["decoration"] = {["shadow"] = {["range"] = 50}}})
-- hyprland/general.conf:75
hl.config({["decoration"] = {["shadow"] = {["offset"] = {0, 4}}}})
-- hyprland/general.conf:76
hl.config({["decoration"] = {["shadow"] = {["render_power"] = 10}}})
-- hyprland/general.conf:77
hl.config({["decoration"] = {["shadow"] = {["color"] = "rgba(00000027)"}}})
-- hyprland/general.conf:81
hl.config({["decoration"] = {["dim_inactive"] = true}})
-- hyprland/general.conf:82
hl.config({["decoration"] = {["dim_strength"] = 0.05}})
-- hyprland/general.conf:83
hl.config({["decoration"] = {["dim_special"] = 0.2}})
-- hyprland/general.conf:87
hl.config({["animations"] = {["enabled"] = true}})
-- hyprland/general.conf:91
hl.curve("specialWorkSwitch", {type="bezier", points={{0.05, 0.7}, {0.1, 1}}})
-- hyprland/general.conf:92
hl.curve("emphasizedAccel", {type="bezier", points={{0.3, 0}, {0.8, 0.15}}})
-- hyprland/general.conf:93
hl.curve("emphasizedDecel", {type="bezier", points={{0.05, 0.7}, {0.1, 1}}})
-- hyprland/general.conf:94
hl.curve("standard", {type="bezier", points={{0.2, 0}, {0, 1}}})
-- hyprland/general.conf:95
hl.curve("standardDecel", {type="bezier", points={{0, 0}, {0, 1}}})
-- hyprland/general.conf:98
hl.curve("expressiveFastSpatial", {type="bezier", points={{0.42, 1.67}, {0.21, 0.90}}})
-- hyprland/general.conf:99
hl.curve("expressiveDefaultSpatial", {type="bezier", points={{0.38, 1.21}, {0.22, 1.00}}})
-- hyprland/general.conf:100
hl.curve("expressiveSlowSpatial", {type="bezier", points={{0.39, 1.29}, {0.35, 0.98}}})
-- hyprland/general.conf:103
hl.animation({["leaf"] = "windowsIn", ["enabled"] = true, ["speed"] = 5, ["bezier"] = "emphasizedDecel"})
-- hyprland/general.conf:104
hl.animation({["leaf"] = "windowsOut", ["enabled"] = true, ["speed"] = 3, ["bezier"] = "emphasizedAccel"})
-- hyprland/general.conf:105
hl.animation({["leaf"] = "windowsMove", ["enabled"] = true, ["speed"] = 6, ["bezier"] = "standard"})
-- hyprland/general.conf:108
hl.animation({["leaf"] = "layersIn", ["enabled"] = true, ["speed"] = 5, ["bezier"] = "emphasizedDecel", ["style"] = "slide"})
-- hyprland/general.conf:109
hl.animation({["leaf"] = "layersOut", ["enabled"] = true, ["speed"] = 4, ["bezier"] = "emphasizedAccel", ["style"] = "slide"})
-- hyprland/general.conf:110
hl.animation({["leaf"] = "fadeLayers", ["enabled"] = true, ["speed"] = 5, ["bezier"] = "standard"})
-- hyprland/general.conf:113
hl.animation({["leaf"] = "workspaces", ["enabled"] = true, ["speed"] = 5, ["bezier"] = "standard"})
-- hyprland/general.conf:114
hl.animation({["leaf"] = "specialWorkspace", ["enabled"] = true, ["speed"] = 4, ["bezier"] = "specialWorkSwitch", ["style"] = "slidefadevert 15%"})
-- hyprland/general.conf:116
hl.animation({["leaf"] = "fade", ["enabled"] = true, ["speed"] = 6, ["bezier"] = "standard"})
-- hyprland/general.conf:117
hl.animation({["leaf"] = "fadeDim", ["enabled"] = true, ["speed"] = 6, ["bezier"] = "standard"})
-- hyprland/general.conf:118
hl.animation({["leaf"] = "border", ["enabled"] = true, ["speed"] = 6, ["bezier"] = "standard"})
-- hyprland/general.conf:119
hl.animation({["leaf"] = "zoomFactor", ["enabled"] = true, ["speed"] = 3, ["bezier"] = "standardDecel"})
-- hyprland/general.conf:123
hl.config({["input"] = {["kb_layout"] = "it"}})
-- hyprland/general.conf:124
hl.config({["input"] = {["numlock_by_default"] = true}})
-- hyprland/general.conf:125
hl.config({["input"] = {["repeat_delay"] = 250}})
-- hyprland/general.conf:126
hl.config({["input"] = {["repeat_rate"] = 35}})
-- hyprland/general.conf:128
hl.config({["input"] = {["follow_mouse"] = 1}})
-- hyprland/general.conf:129
hl.config({["input"] = {["sensitivity"] = 0.5}})
-- hyprland/general.conf:130
hl.config({["input"] = {["off_window_axis_events"] = 2}})
-- hyprland/general.conf:133
hl.config({["input"] = {["touchpad"] = {["natural_scroll"] = true}}})
-- hyprland/general.conf:134
hl.config({["input"] = {["touchpad"] = {["disable_while_typing"] = true}}})
-- hyprland/general.conf:135
hl.config({["input"] = {["touchpad"] = {["clickfinger_behavior"] = true}}})
-- hyprland/general.conf:136
hl.config({["input"] = {["touchpad"] = {["scroll_factor"] = 1.2}}})
-- hyprland/general.conf:141
hl.config({["misc"] = {["disable_hyprland_logo"] = true}})
-- hyprland/general.conf:142
hl.config({["misc"] = {["disable_splash_rendering"] = true}})
-- hyprland/general.conf:143
hl.config({["misc"] = {["vrr"] = 1}})
-- hyprland/general.conf:144
hl.config({["misc"] = {["mouse_move_enables_dpms"] = true}})
-- hyprland/general.conf:145
hl.config({["misc"] = {["key_press_enables_dpms"] = true}})
-- hyprland/general.conf:146
hl.config({["misc"] = {["animate_manual_resizes"] = false}})
-- hyprland/general.conf:147
hl.config({["misc"] = {["animate_mouse_windowdragging"] = false}})
-- hyprland/general.conf:148
hl.config({["misc"] = {["enable_swallow"] = false}})
-- hyprland/general.conf:149
hl.config({["misc"] = {["swallow_regex"] = "(foot|kitty|allacritty|Alacritty)"}})
-- hyprland/general.conf:150
hl.config({["misc"] = {["on_focus_under_fullscreen"] = 2}})
-- hyprland/general.conf:151
hl.config({["misc"] = {["allow_session_lock_restore"] = true}})
-- hyprland/general.conf:152
hl.config({["misc"] = {["session_lock_xray"] = true}})
-- hyprland/general.conf:153
hl.config({["misc"] = {["initial_workspace_tracking"] = false}})
-- hyprland/general.conf:154
hl.config({["misc"] = {["focus_on_activate"] = true}})
-- hyprland/general.conf:158
hl.config({["debug"] = {["vfr"] = 1}})
-- hyprland/general.conf:162
hl.config({["binds"] = {["scroll_event_delay"] = 0}})
-- hyprland/general.conf:163
hl.config({["binds"] = {["hide_special_on_workspace_change"] = true}})
-- hyprland/general.conf:167
hl.config({["cursor"] = {["zoom_factor"] = 1}})
-- hyprland/general.conf:168
hl.config({["cursor"] = {["zoom_rigid"] = false}})
-- hyprland/general.conf:169
hl.config({["cursor"] = {["zoom_disable_aa"] = true}})
-- hyprland/general.conf:170
hl.config({["cursor"] = {["hotspot_padding"] = 1}})
dofile(nyvorel_config_root .. "/custom/scroll-settings.lua")
-- hyprland.conf:15
-- hyprland/rules.conf:4
hl.window_rule({["no_blur"] = true, ["match"] = {["class"] = "^()$", ["title"] = "^()$"}, ["name"] = "nyvorel-1"})
-- hyprland/rules.conf:7
hl.window_rule({["no_blur"] = true, ["match"] = {["class"] = ".*"}, ["name"] = "nyvorel-2"})
-- hyprland/rules.conf:10
hl.window_rule({["center"] = true, ["match"] = {["title"] = "^(Open File)(.*)$"}, ["name"] = "nyvorel-3"})
-- hyprland/rules.conf:11
hl.window_rule({["float"] = true, ["match"] = {["title"] = "^(Open File)(.*)$"}, ["name"] = "nyvorel-4"})
-- hyprland/rules.conf:12
hl.window_rule({["center"] = true, ["match"] = {["title"] = "^(Select a File)(.*)$"}, ["name"] = "nyvorel-5"})
-- hyprland/rules.conf:13
hl.window_rule({["float"] = true, ["match"] = {["title"] = "^(Select a File)(.*)$"}, ["name"] = "nyvorel-6"})
-- hyprland/rules.conf:14
hl.window_rule({["center"] = true, ["match"] = {["title"] = "^(Choose wallpaper)(.*)$"}, ["name"] = "nyvorel-7"})
-- hyprland/rules.conf:15
hl.window_rule({["float"] = true, ["match"] = {["title"] = "^(Choose wallpaper)(.*)$"}, ["name"] = "nyvorel-8"})
-- hyprland/rules.conf:16
hl.window_rule({["size"] = "(monitor_w*.60) (monitor_h*.65)", ["match"] = {["title"] = "^(Choose wallpaper)(.*)$"}, ["name"] = "nyvorel-9"})
-- hyprland/rules.conf:17
hl.window_rule({["center"] = true, ["match"] = {["title"] = "^(Open Folder)(.*)$"}, ["name"] = "nyvorel-10"})
-- hyprland/rules.conf:18
hl.window_rule({["float"] = true, ["match"] = {["title"] = "^(Open Folder)(.*)$"}, ["name"] = "nyvorel-11"})
-- hyprland/rules.conf:19
hl.window_rule({["center"] = true, ["match"] = {["title"] = "^(Save As)(.*)$"}, ["name"] = "nyvorel-12"})
-- hyprland/rules.conf:20
hl.window_rule({["float"] = true, ["match"] = {["title"] = "^(Save As)(.*)$"}, ["name"] = "nyvorel-13"})
-- hyprland/rules.conf:21
hl.window_rule({["center"] = true, ["match"] = {["title"] = "^(Library)(.*)$"}, ["name"] = "nyvorel-14"})
-- hyprland/rules.conf:22
hl.window_rule({["float"] = true, ["match"] = {["title"] = "^(Library)(.*)$"}, ["name"] = "nyvorel-15"})
-- hyprland/rules.conf:23
hl.window_rule({["center"] = true, ["match"] = {["title"] = "^(File Upload)(.*)$"}, ["name"] = "nyvorel-16"})
-- hyprland/rules.conf:24
hl.window_rule({["float"] = true, ["match"] = {["title"] = "^(File Upload)(.*)$"}, ["name"] = "nyvorel-17"})
-- hyprland/rules.conf:25
hl.window_rule({["center"] = true, ["match"] = {["title"] = "^(.*)(wants to save)$"}, ["name"] = "nyvorel-18"})
-- hyprland/rules.conf:26
hl.window_rule({["float"] = true, ["match"] = {["title"] = "^(.*)(wants to save)$"}, ["name"] = "nyvorel-19"})
-- hyprland/rules.conf:27
hl.window_rule({["center"] = true, ["match"] = {["title"] = "^(.*)(wants to open)$"}, ["name"] = "nyvorel-20"})
-- hyprland/rules.conf:28
hl.window_rule({["float"] = true, ["match"] = {["title"] = "^(.*)(wants to open)$"}, ["name"] = "nyvorel-21"})
-- hyprland/rules.conf:29
hl.window_rule({["float"] = true, ["match"] = {["class"] = "^(blueberry\\.py)$"}, ["name"] = "nyvorel-22"})
-- hyprland/rules.conf:30
hl.window_rule({["float"] = true, ["match"] = {["class"] = "^(guifetch)$"}, ["name"] = "nyvorel-23"})
-- hyprland/rules.conf:31
hl.window_rule({["float"] = true, ["match"] = {["class"] = "^(pavucontrol)$"}, ["name"] = "nyvorel-24"})
-- hyprland/rules.conf:32
hl.window_rule({["size"] = "(monitor_w*.45) (monitor_h*.45)", ["match"] = {["class"] = "^(pavucontrol)$"}, ["name"] = "nyvorel-25"})
-- hyprland/rules.conf:33
hl.window_rule({["center"] = true, ["match"] = {["class"] = "^(pavucontrol)$"}, ["name"] = "nyvorel-26"})
-- hyprland/rules.conf:34
hl.window_rule({["float"] = true, ["match"] = {["class"] = "^(org.pulseaudio.pavucontrol)$"}, ["name"] = "nyvorel-27"})
-- hyprland/rules.conf:35
hl.window_rule({["size"] = "(monitor_w*.45) (monitor_h*.45)", ["match"] = {["class"] = "^(org.pulseaudio.pavucontrol)$"}, ["name"] = "nyvorel-28"})
-- hyprland/rules.conf:36
hl.window_rule({["center"] = true, ["match"] = {["class"] = "^(org.pulseaudio.pavucontrol)$"}, ["name"] = "nyvorel-29"})
-- hyprland/rules.conf:37
hl.window_rule({["float"] = true, ["match"] = {["class"] = "^(nm-connection-editor)$"}, ["name"] = "nyvorel-30"})
-- hyprland/rules.conf:38
hl.window_rule({["size"] = "(monitor_w*.45) (monitor_h*.45)", ["match"] = {["class"] = "^(nm-connection-editor)$"}, ["name"] = "nyvorel-31"})
-- hyprland/rules.conf:39
hl.window_rule({["center"] = true, ["match"] = {["class"] = "^(nm-connection-editor)$"}, ["name"] = "nyvorel-32"})
-- hyprland/rules.conf:40
hl.window_rule({["float"] = true, ["match"] = {["class"] = ".*plasmawindowed.*"}, ["name"] = "nyvorel-33"})
-- hyprland/rules.conf:41
hl.window_rule({["float"] = true, ["match"] = {["class"] = "kcm_.*"}, ["name"] = "nyvorel-34"})
-- hyprland/rules.conf:42
hl.window_rule({["float"] = true, ["match"] = {["class"] = ".*bluedevilwizard"}, ["name"] = "nyvorel-35"})
-- hyprland/rules.conf:43
hl.window_rule({["float"] = true, ["match"] = {["title"] = ".*Welcome"}, ["name"] = "nyvorel-36"})
-- hyprland/rules.conf:44
hl.window_rule({["float"] = true, ["match"] = {["title"] = "^(Nyvorel Settings)$"}, ["name"] = "nyvorel-37"})
-- hyprland/rules.conf:48
hl.window_rule({["border_size"] = 0, ["match"] = {["title"] = "^(Nyvorel Settings)$"}, ["name"] = "nyvorel-38"})
-- hyprland/rules.conf:49
hl.window_rule({["rounding"] = 0, ["match"] = {["title"] = "^(Nyvorel Settings)$"}, ["name"] = "nyvorel-39"})
-- hyprland/rules.conf:50
hl.window_rule({["no_shadow"] = true, ["match"] = {["title"] = "^(Nyvorel Settings)$"}, ["name"] = "nyvorel-40"})
-- hyprland/rules.conf:53
hl.window_rule({["float"] = true, ["match"] = {["title"] = ".*Shell conflicts.*"}, ["name"] = "nyvorel-41"})
-- hyprland/rules.conf:54
hl.window_rule({["float"] = true, ["match"] = {["class"] = "org.freedesktop.impl.portal.desktop.kde"}, ["name"] = "nyvorel-42"})
-- hyprland/rules.conf:55
hl.window_rule({["size"] = "(monitor_w*.60) (monitor_h*.65)", ["match"] = {["class"] = "org.freedesktop.impl.portal.desktop.kde"}, ["name"] = "nyvorel-43"})
-- hyprland/rules.conf:56
hl.window_rule({["float"] = true, ["match"] = {["class"] = "^(Zotero)$"}, ["name"] = "nyvorel-44"})
-- hyprland/rules.conf:57
hl.window_rule({["size"] = "(monitor_w*.45) (monitor_h*.45)", ["match"] = {["class"] = "^(Zotero)$"}, ["name"] = "nyvorel-45"})
-- hyprland/rules.conf:61
hl.window_rule({["float"] = true, ["match"] = {["class"] = "^(plasma-changeicons)$"}, ["name"] = "nyvorel-46"})
-- hyprland/rules.conf:62
hl.window_rule({["no_initial_focus"] = true, ["match"] = {["class"] = "^(plasma-changeicons)$"}, ["name"] = "nyvorel-47"})
-- hyprland/rules.conf:63
hl.window_rule({["move"] = "999999 999999", ["match"] = {["class"] = "^(plasma-changeicons)$"}, ["name"] = "nyvorel-48"})
-- hyprland/rules.conf:65
hl.window_rule({["move"] = "40 80", ["match"] = {["title"] = "^(Copying — Dolphin)$"}, ["name"] = "nyvorel-49"})
-- hyprland/rules.conf:68
hl.window_rule({["tile"] = true, ["match"] = {["class"] = "^dev\\.warp\\.Warp$"}, ["name"] = "nyvorel-50"})
-- hyprland/rules.conf:71
hl.window_rule({["float"] = true, ["match"] = {["title"] = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$"}, ["name"] = "nyvorel-51"})
-- hyprland/rules.conf:72
hl.window_rule({["keep_aspect_ratio"] = true, ["match"] = {["title"] = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$"}, ["name"] = "nyvorel-52"})
-- hyprland/rules.conf:73
hl.window_rule({["move"] = "(monitor_w*.73) (monitor_h*.72)", ["match"] = {["title"] = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$"}, ["name"] = "nyvorel-53"})
-- hyprland/rules.conf:74
hl.window_rule({["size"] = "(monitor_w*.25) (monitor_h*.25)", ["match"] = {["title"] = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$"}, ["name"] = "nyvorel-54"})
-- hyprland/rules.conf:75
hl.window_rule({["float"] = true, ["match"] = {["title"] = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$"}, ["name"] = "nyvorel-55"})
-- hyprland/rules.conf:76
hl.window_rule({["pin"] = true, ["match"] = {["title"] = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$"}, ["name"] = "nyvorel-56"})
-- hyprland/rules.conf:79
hl.window_rule({["immediate"] = true, ["match"] = {["title"] = ".*\\.exe"}, ["name"] = "nyvorel-57"})
-- hyprland/rules.conf:80
hl.window_rule({["immediate"] = true, ["match"] = {["title"] = ".*minecraft.*"}, ["name"] = "nyvorel-58"})
-- hyprland/rules.conf:81
hl.window_rule({["immediate"] = true, ["match"] = {["class"] = "^(steam_app).*"}, ["name"] = "nyvorel-59"})
-- hyprland/rules.conf:84
hl.window_rule({["no_initial_focus"] = true, ["match"] = {["class"] = "^jetbrains-.*$", ["float"] = 1, ["title"] = "^$|^\\s$|^win\\d+$"}, ["name"] = "nyvorel-60"})
-- hyprland/rules.conf:87
hl.window_rule({["no_shadow"] = true, ["match"] = {["float"] = 0}, ["name"] = "nyvorel-61"})
-- hyprland/rules.conf:90
hl.workspace_rule({["workspace"] = "special:special", ["gaps_out"] = 30})
-- hyprland/rules.conf:93
hl.layer_rule({["xray"] = true, ["match"] = {["namespace"] = ".*"}, ["name"] = "nyvorel-1"})
-- hyprland/rules.conf:95
hl.layer_rule({["no_anim"] = true, ["match"] = {["namespace"] = "walker"}, ["name"] = "nyvorel-2"})
-- hyprland/rules.conf:96
hl.layer_rule({["no_anim"] = true, ["match"] = {["namespace"] = "selection"}, ["name"] = "nyvorel-3"})
-- hyprland/rules.conf:97
hl.layer_rule({["no_anim"] = true, ["match"] = {["namespace"] = "overview"}, ["name"] = "nyvorel-4"})
-- hyprland/rules.conf:98
hl.layer_rule({["no_anim"] = true, ["match"] = {["namespace"] = "anyrun"}, ["name"] = "nyvorel-5"})
-- hyprland/rules.conf:99
hl.layer_rule({["no_anim"] = true, ["match"] = {["namespace"] = "indicator.*"}, ["name"] = "nyvorel-6"})
-- hyprland/rules.conf:100
hl.layer_rule({["no_anim"] = true, ["match"] = {["namespace"] = "osk"}, ["name"] = "nyvorel-7"})
-- hyprland/rules.conf:101
hl.layer_rule({["no_anim"] = true, ["match"] = {["namespace"] = "hyprpicker"}, ["name"] = "nyvorel-8"})
-- hyprland/rules.conf:103
hl.layer_rule({["no_anim"] = true, ["match"] = {["namespace"] = "noanim"}, ["name"] = "nyvorel-9"})
-- hyprland/rules.conf:104
hl.layer_rule({["blur"] = true, ["match"] = {["namespace"] = "gtk-layer-shell"}, ["name"] = "nyvorel-10"})
-- hyprland/rules.conf:105
hl.layer_rule({["ignore_alpha"] = 0, ["match"] = {["namespace"] = "gtk-layer-shell"}, ["name"] = "nyvorel-11"})
-- hyprland/rules.conf:106
hl.layer_rule({["blur"] = true, ["match"] = {["namespace"] = "launcher"}, ["name"] = "nyvorel-12"})
-- hyprland/rules.conf:107
hl.layer_rule({["ignore_alpha"] = 0.5, ["match"] = {["namespace"] = "launcher"}, ["name"] = "nyvorel-13"})
-- hyprland/rules.conf:108
hl.layer_rule({["blur"] = true, ["match"] = {["namespace"] = "notifications"}, ["name"] = "nyvorel-14"})
-- hyprland/rules.conf:109
hl.layer_rule({["ignore_alpha"] = 0.69, ["match"] = {["namespace"] = "notifications"}, ["name"] = "nyvorel-15"})
-- hyprland/rules.conf:110
hl.layer_rule({["match"] = {["namespace"] = "logout_dialog"}, ["name"] = "nyvorel-16"})
-- hyprland/rules.conf:113
hl.layer_rule({["animation"] = "slide left", ["match"] = {["namespace"] = "sideleft.*"}, ["name"] = "nyvorel-17"})
-- hyprland/rules.conf:114
hl.layer_rule({["animation"] = "slide right", ["match"] = {["namespace"] = "sideright.*"}, ["name"] = "nyvorel-18"})
-- hyprland/rules.conf:115
hl.layer_rule({["blur"] = true, ["match"] = {["namespace"] = "session[0-9]*"}, ["name"] = "nyvorel-19"})
-- hyprland/rules.conf:116
hl.layer_rule({["blur"] = true, ["match"] = {["namespace"] = "bar[0-9]*"}, ["name"] = "nyvorel-20"})
-- hyprland/rules.conf:117
hl.layer_rule({["ignore_alpha"] = 0.6, ["match"] = {["namespace"] = "bar[0-9]*"}, ["name"] = "nyvorel-21"})
-- hyprland/rules.conf:118
hl.layer_rule({["blur"] = true, ["match"] = {["namespace"] = "barcorner.*"}, ["name"] = "nyvorel-22"})
-- hyprland/rules.conf:119
hl.layer_rule({["ignore_alpha"] = 0.6, ["match"] = {["namespace"] = "barcorner.*"}, ["name"] = "nyvorel-23"})
-- hyprland/rules.conf:120
hl.layer_rule({["blur"] = true, ["match"] = {["namespace"] = "dock[0-9]*"}, ["name"] = "nyvorel-24"})
-- hyprland/rules.conf:121
hl.layer_rule({["ignore_alpha"] = 0.6, ["match"] = {["namespace"] = "dock[0-9]*"}, ["name"] = "nyvorel-25"})
-- hyprland/rules.conf:122
hl.layer_rule({["blur"] = true, ["match"] = {["namespace"] = "indicator.*"}, ["name"] = "nyvorel-26"})
-- hyprland/rules.conf:123
hl.layer_rule({["ignore_alpha"] = 0.6, ["match"] = {["namespace"] = "indicator.*"}, ["name"] = "nyvorel-27"})
-- hyprland/rules.conf:124
hl.layer_rule({["blur"] = true, ["match"] = {["namespace"] = "overview[0-9]*"}, ["name"] = "nyvorel-28"})
-- hyprland/rules.conf:125
hl.layer_rule({["ignore_alpha"] = 0.6, ["match"] = {["namespace"] = "overview[0-9]*"}, ["name"] = "nyvorel-29"})
-- hyprland/rules.conf:126
hl.layer_rule({["blur"] = true, ["match"] = {["namespace"] = "cheatsheet[0-9]*"}, ["name"] = "nyvorel-30"})
-- hyprland/rules.conf:127
hl.layer_rule({["ignore_alpha"] = 0.6, ["match"] = {["namespace"] = "cheatsheet[0-9]*"}, ["name"] = "nyvorel-31"})
-- hyprland/rules.conf:128
hl.layer_rule({["blur"] = true, ["match"] = {["namespace"] = "sideright[0-9]*"}, ["name"] = "nyvorel-32"})
-- hyprland/rules.conf:129
hl.layer_rule({["ignore_alpha"] = 0.6, ["match"] = {["namespace"] = "sideright[0-9]*"}, ["name"] = "nyvorel-33"})
-- hyprland/rules.conf:130
hl.layer_rule({["blur"] = true, ["match"] = {["namespace"] = "sideleft[0-9]*"}, ["name"] = "nyvorel-34"})
-- hyprland/rules.conf:131
hl.layer_rule({["ignore_alpha"] = 0.6, ["match"] = {["namespace"] = "sideleft[0-9]*"}, ["name"] = "nyvorel-35"})
-- hyprland/rules.conf:132
hl.layer_rule({["blur"] = true, ["match"] = {["namespace"] = "indicator.*"}, ["name"] = "nyvorel-36"})
-- hyprland/rules.conf:133
hl.layer_rule({["ignore_alpha"] = 0.6, ["match"] = {["namespace"] = "indicator.*"}, ["name"] = "nyvorel-37"})
-- hyprland/rules.conf:134
hl.layer_rule({["blur"] = true, ["match"] = {["namespace"] = "osk[0-9]*"}, ["name"] = "nyvorel-38"})
-- hyprland/rules.conf:135
hl.layer_rule({["ignore_alpha"] = 0.6, ["match"] = {["namespace"] = "osk[0-9]*"}, ["name"] = "nyvorel-39"})
-- hyprland/rules.conf:139
hl.layer_rule({["blur_popups"] = true, ["match"] = {["namespace"] = "quickshell:.*"}, ["name"] = "nyvorel-40"})
-- hyprland/rules.conf:140
hl.layer_rule({["blur"] = true, ["match"] = {["namespace"] = "quickshell:.*"}, ["name"] = "nyvorel-41"})
-- hyprland/rules.conf:141
hl.layer_rule({["ignore_alpha"] = 0.79, ["match"] = {["namespace"] = "quickshell:.*"}, ["name"] = "nyvorel-42"})
-- hyprland/rules.conf:142
hl.layer_rule({["animation"] = "slide", ["match"] = {["namespace"] = "quickshell:bar"}, ["name"] = "nyvorel-43"})
-- hyprland/rules.conf:143
hl.layer_rule({["no_anim"] = true, ["match"] = {["namespace"] = "quickshell:actionCenter"}, ["name"] = "nyvorel-44"})
-- hyprland/rules.conf:144
hl.layer_rule({["animation"] = "slide bottom", ["match"] = {["namespace"] = "quickshell:cheatsheet"}, ["name"] = "nyvorel-45"})
-- hyprland/rules.conf:145
hl.layer_rule({["animation"] = "slide bottom", ["match"] = {["namespace"] = "quickshell:dock"}, ["name"] = "nyvorel-46"})
-- hyprland/rules.conf:146
hl.layer_rule({["animation"] = "popin 120%", ["match"] = {["namespace"] = "quickshell:screenCorners"}, ["name"] = "nyvorel-47"})
-- hyprland/rules.conf:147
hl.layer_rule({["no_anim"] = true, ["match"] = {["namespace"] = "quickshell:lockWindowPusher"}, ["name"] = "nyvorel-48"})
-- hyprland/rules.conf:148
hl.layer_rule({["animation"] = "fade", ["match"] = {["namespace"] = "quickshell:notificationPopup"}, ["name"] = "nyvorel-49"})
-- hyprland/rules.conf:149
hl.layer_rule({["no_anim"] = true, ["match"] = {["namespace"] = "quickshell:overlay"}, ["name"] = "nyvorel-50"})
-- hyprland/rules.conf:150
hl.layer_rule({["ignore_alpha"] = 1, ["match"] = {["namespace"] = "quickshell:overlay"}, ["name"] = "nyvorel-51"})
-- hyprland/rules.conf:151
hl.layer_rule({["no_anim"] = true, ["match"] = {["namespace"] = "quickshell:overview"}, ["name"] = "nyvorel-52"})
-- hyprland/rules.conf:152
hl.layer_rule({["animation"] = "slide bottom", ["match"] = {["namespace"] = "quickshell:osk"}, ["name"] = "nyvorel-53"})
-- hyprland/rules.conf:153
hl.layer_rule({["no_anim"] = true, ["match"] = {["namespace"] = "quickshell:polkit"}, ["name"] = "nyvorel-54"})
-- hyprland/rules.conf:154
hl.layer_rule({["xray"] = false, ["match"] = {["namespace"] = "quickshell:popup"}, ["name"] = "nyvorel-55"})
-- hyprland/rules.conf:155
hl.layer_rule({["ignore_alpha"] = 1, ["match"] = {["namespace"] = "quickshell:popup"}, ["name"] = "nyvorel-56"})
-- hyprland/rules.conf:156
hl.layer_rule({["ignore_alpha"] = 1, ["match"] = {["namespace"] = "quickshell:mediaControls"}, ["name"] = "nyvorel-57"})
-- hyprland/rules.conf:157
hl.layer_rule({["animation"] = "slide", ["match"] = {["namespace"] = "quickshell:reloadPopup"}, ["name"] = "nyvorel-58"})
-- hyprland/rules.conf:158
hl.layer_rule({["no_anim"] = true, ["match"] = {["namespace"] = "quickshell:regionSelector"}, ["name"] = "nyvorel-59"})
-- hyprland/rules.conf:159
hl.layer_rule({["no_anim"] = true, ["match"] = {["namespace"] = "quickshell:screenshot"}, ["name"] = "nyvorel-60"})
-- hyprland/rules.conf:160
hl.layer_rule({["blur"] = true, ["match"] = {["namespace"] = "quickshell:session"}, ["name"] = "nyvorel-61"})
-- hyprland/rules.conf:161
hl.layer_rule({["no_anim"] = true, ["match"] = {["namespace"] = "quickshell:session"}, ["name"] = "nyvorel-62"})
-- hyprland/rules.conf:162
hl.layer_rule({["ignore_alpha"] = 0, ["match"] = {["namespace"] = "quickshell:session"}, ["name"] = "nyvorel-63"})
-- hyprland/rules.conf:163
hl.layer_rule({["animation"] = "slide right", ["match"] = {["namespace"] = "quickshell:sidebarRight"}, ["name"] = "nyvorel-64"})
-- hyprland/rules.conf:164
hl.layer_rule({["animation"] = "slide left", ["match"] = {["namespace"] = "quickshell:sidebarLeft"}, ["name"] = "nyvorel-65"})
-- hyprland/rules.conf:165
hl.layer_rule({["animation"] = "slide", ["match"] = {["namespace"] = "quickshell:verticalBar"}, ["name"] = "nyvorel-66"})
-- hyprland/rules.conf:166
hl.layer_rule({["order"] = -1, ["match"] = {["namespace"] = "quickshell:osk"}, ["name"] = "nyvorel-67"})
-- hyprland/rules.conf:168
hl.layer_rule({["no_anim"] = true, ["match"] = {["namespace"] = "quickshell:wNotificationCenter"}, ["name"] = "nyvorel-68"})
-- hyprland/rules.conf:169
hl.layer_rule({["no_anim"] = true, ["match"] = {["namespace"] = "quickshell:wOnScreenDisplay"}, ["name"] = "nyvorel-69"})
-- hyprland/rules.conf:170
hl.layer_rule({["no_anim"] = true, ["match"] = {["namespace"] = "quickshell:wStartMenu"}, ["name"] = "nyvorel-70"})
-- hyprland/rules.conf:171
hl.layer_rule({["ignore_alpha"] = 0, ["match"] = {["namespace"] = "quickshell:wTaskView"}, ["name"] = "nyvorel-71"})
-- hyprland/rules.conf:172
hl.layer_rule({["no_anim"] = true, ["match"] = {["namespace"] = "quickshell:wTaskView"}, ["name"] = "nyvorel-72"})
-- hyprland/rules.conf:175
hl.layer_rule({["no_anim"] = true, ["match"] = {["namespace"] = "gtk4-layer-shell"}, ["name"] = "nyvorel-73"})
-- hyprland/rules.conf:180
hl.window_rule({["no_blur"] = false, ["match"] = {["class"] = "^(kitty)$"}, ["name"] = "nyvorel-62"})
-- hyprland.conf:16
load_optional(nyvorel_config_root .. "/hyprland/colors.lua")
-- hyprland.conf:17
-- hyprland/keybinds.conf:10
hl.bind("SUPER + Tab", hl.dsp.global("quickshell:overviewWorkspacesToggle"), {})
-- hyprland/keybinds.conf:11
hl.bind("SUPER + V", hl.dsp.global("quickshell:overviewClipboardToggle"), {["description"] = "Clipboard history >> clipboard"})
-- hyprland/keybinds.conf:12
hl.bind("SUPER + Period", hl.dsp.global("quickshell:overviewEmojiToggle"), {["description"] = "Emoji >> clipboard"})
-- hyprland/keybinds.conf:13
hl.bind("SUPER + A", hl.dsp.global("quickshell:sidebarLeftToggle"), {})
-- hyprland/keybinds.conf:14
hl.bind("SUPER+ALT + A", hl.dsp.global("quickshell:sidebarLeftToggleDetach"), {})
-- hyprland/keybinds.conf:15
hl.bind("SUPER + B", hl.dsp.global("quickshell:sidebarLeftToggle"), {})
-- hyprland/keybinds.conf:16
hl.bind("SUPER + O", hl.dsp.global("quickshell:sidebarLeftToggle"), {})
-- hyprland/keybinds.conf:17
hl.bind("SUPER + N", hl.dsp.global("quickshell:sidebarRightToggle"), {["description"] = "Toggle right sidebar"})
-- hyprland/keybinds.conf:18
hl.bind("SUPER + Slash", hl.dsp.global("quickshell:cheatsheetToggle"), {["description"] = "Toggle cheatsheet"})
-- hyprland/keybinds.conf:19
hl.bind("SUPER + K", hl.dsp.global("quickshell:oskToggle"), {["description"] = "Toggle on-screen keyboard"})
-- hyprland/keybinds.conf:20
hl.bind("SUPER + M", hl.dsp.global("quickshell:mediaControlsToggle"), {["description"] = "Toggle media controls"})
-- hyprland/keybinds.conf:21
hl.bind("SUPER + G", hl.dsp.global("quickshell:overlayToggle"), {})
-- hyprland/keybinds.conf:22
hl.bind("CTRL+ALT + Delete", hl.dsp.global("quickshell:sessionToggle"), {["description"] = "Toggle session menu"})
-- hyprland/keybinds.conf:23
hl.bind("SUPER + J", hl.dsp.global("quickshell:barToggle"), {["description"] = "Toggle bar"})
-- hyprland/keybinds.conf:24
hl.bind("CTRL+ALT + Delete", hl.dsp.exec_cmd("qs -c nyvorel ipc call TEST_ALIVE || pkill wlogout || wlogout -p layer-shell"), {})
-- hyprland/keybinds.conf:25
hl.bind("SHIFT+SUPER+ALT + Slash", hl.dsp.exec_cmd("qs -p ~/.config/quickshell/nyvorel/welcome.qml"), {})
-- hyprland/keybinds.conf:27
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("qs -c nyvorel ipc call brightness increment || brightnessctl s 5%+"), {["repeating"] = true, ["locked"] = true})
-- hyprland/keybinds.conf:28
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("qs -c nyvorel ipc call brightness decrement || brightnessctl s 5%-"), {["repeating"] = true, ["locked"] = true})
-- hyprland/keybinds.conf:29
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%+ -l 1.5"), {["repeating"] = true, ["locked"] = true})
-- hyprland/keybinds.conf:30
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-"), {["repeating"] = true, ["locked"] = true})
-- hyprland/keybinds.conf:32
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_SINK@ toggle"), {["locked"] = true})
-- hyprland/keybinds.conf:33
hl.bind("SUPER+SHIFT + M", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_SINK@ toggle"), {["locked"] = true, ["description"] = "Toggle mute"})
-- hyprland/keybinds.conf:34
hl.bind("ALT + XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_SOURCE@ toggle"), {["locked"] = true})
-- hyprland/keybinds.conf:35
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_SOURCE@ toggle"), {["locked"] = true})
-- hyprland/keybinds.conf:36
hl.bind("SUPER+ALT + M", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_SOURCE@ toggle"), {["locked"] = true, ["description"] = "Toggle mic"})
-- hyprland/keybinds.conf:37
hl.bind("CTRL+SUPER + T", hl.dsp.global("quickshell:wallpaperSelectorToggle"), {["description"] = "Toggle wallpaper selector"})
-- hyprland/keybinds.conf:38
hl.bind("CTRL+SUPER+ALT + T", hl.dsp.global("quickshell:wallpaperSelectorRandom"), {["description"] = "Select random wallpaper"})
-- hyprland/keybinds.conf:39
hl.bind("CTRL+SUPER + T", hl.dsp.exec_cmd("qs -c nyvorel ipc call TEST_ALIVE || ~/.config/quickshell/nyvorel/scripts/colors/switchwall.sh"), {["description"] = "Change wallpaper"})
-- hyprland/keybinds.conf:40
hl.bind("CTRL+SUPER + R", hl.dsp.exec_cmd("sh -lc 'systemctl --user import-environment DISPLAY WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP XDG_SESSION_TYPE >/dev/null 2>&1 || true; hyprctl reload; systemctl --user restart nyvorel-quickshell.service'"), {})
-- hyprland/keybinds.conf:41
hl.bind("CTRL+SUPER + P", hl.dsp.global("quickshell:panelFamilyCycle"), {})
-- hyprland/keybinds.conf:45
hl.bind("SUPER + V", hl.dsp.exec_cmd("qs -c nyvorel ipc call TEST_ALIVE || pkill fuzzel || cliphist list | fuzzel --match-mode fzf --dmenu | cliphist decode | wl-copy"), {["description"] = "Copy clipboard history entry"})
-- hyprland/keybinds.conf:46
hl.bind("SUPER + Period", hl.dsp.exec_cmd("qs -c nyvorel ipc call TEST_ALIVE || pkill fuzzel || ~/.config/hypr/hyprland/scripts/fuzzel-emoji.sh copy"), {["description"] = "Copy an emoji"})
-- hyprland/keybinds.conf:47
hl.bind("SUPER+SHIFT + S", hl.dsp.global("quickshell:regionScreenshot"), {})
-- hyprland/keybinds.conf:48
hl.bind("SUPER+SHIFT + S", hl.dsp.exec_cmd("qs -c nyvorel ipc call TEST_ALIVE || pidof slurp || hyprshot --freeze --mode region --silent --output-folder ~/Pictures/Screenshots"), {})
-- hyprland/keybinds.conf:49
hl.bind("SUPER+SHIFT + A", hl.dsp.global("quickshell:regionSearch"), {})
-- hyprland/keybinds.conf:50
hl.bind("SUPER+SHIFT + A", hl.dsp.exec_cmd("qs -c nyvorel ipc call TEST_ALIVE || pidof slurp || ~/.config/hypr/hyprland/scripts/snip_to_search.sh"), {})
-- hyprland/keybinds.conf:52
hl.bind("SUPER+SHIFT + X", hl.dsp.global("quickshell:regionOcr"), {})
-- hyprland/keybinds.conf:53
hl.bind("SUPER+SHIFT + T", hl.dsp.global("quickshell:regionOcr"), {})
-- hyprland/keybinds.conf:54
hl.bind("SUPER+SHIFT + X", hl.dsp.exec_cmd("qs -c nyvorel ipc call TEST_ALIVE || pidof slurp || grim -g \"$(slurp $SLURP_ARGS)\" \"/tmp/ocr_image.png\" && tesseract \"/tmp/ocr_image.png\" stdout -l $(tesseract --list-langs | awk 'NR>1{print $1}' | tr '\\\\n' '+' | sed 's/\\\\+$/\\\\n/') | wl-copy && rm \"/tmp/ocr_image.png\""), {})
-- hyprland/keybinds.conf:55
hl.bind("SUPER+SHIFT + T", hl.dsp.exec_cmd("qs -c nyvorel ipc call TEST_ALIVE || pidof slurp || grim -g \"$(slurp $SLURP_ARGS)\" \"/tmp/ocr_image.png\" && tesseract \"/tmp/ocr_image.png\" stdout -l $(tesseract --list-langs | awk 'NR>1{print $1}' | tr '\\\\n' '+' | sed 's/\\\\+$/\\\\n/') | wl-copy && rm \"/tmp/ocr_image.png\""), {})
-- hyprland/keybinds.conf:57
hl.bind("SUPER+SHIFT + C", hl.dsp.exec_cmd("hyprpicker -a"), {["description"] = "Color picker"})
-- hyprland/keybinds.conf:59
hl.bind("Print", hl.dsp.exec_cmd("grim - | wl-copy"), {["locked"] = true})
-- hyprland/keybinds.conf:60
hl.bind("CTRL + Print", hl.dsp.exec_cmd("mkdir -p $(xdg-user-dir PICTURES)/Screenshots && grim $(xdg-user-dir PICTURES)/Screenshots/Screenshot_\"$(date '+%Y-%m-%d_%H.%M.%S')\".png"), {["locked"] = true, ["non_consuming"] = true})
-- hyprland/keybinds.conf:61
hl.bind("CTRL + Print", hl.dsp.exec_cmd("grim - | wl-copy"), {["locked"] = true, ["non_consuming"] = true})
-- hyprland/keybinds.conf:63
hl.bind("SUPER+SHIFT + R", hl.dsp.global("quickshell:regionRecord"), {["locked"] = true})
-- hyprland/keybinds.conf:64
hl.bind("SUPER+SHIFT + R", hl.dsp.exec_cmd("qs -c nyvorel ipc call TEST_ALIVE || ~/.config/quickshell/nyvorel/scripts/videos/record.sh"), {["locked"] = true})
-- hyprland/keybinds.conf:65
hl.bind("SUPER+ALT + R", hl.dsp.global("quickshell:regionRecord"), {["locked"] = true})
-- hyprland/keybinds.conf:66
hl.bind("SUPER+ALT + R", hl.dsp.exec_cmd("qs -c nyvorel ipc call TEST_ALIVE || ~/.config/quickshell/nyvorel/scripts/videos/record.sh"), {["locked"] = true})
-- hyprland/keybinds.conf:67
hl.bind("CTRL+ALT + R", hl.dsp.exec_cmd("~/.config/quickshell/nyvorel/scripts/videos/record.sh --fullscreen"), {["locked"] = true})
-- hyprland/keybinds.conf:68
hl.bind("SUPER+SHIFT+ALT + R", hl.dsp.exec_cmd("~/.config/quickshell/nyvorel/scripts/videos/record.sh --fullscreen --sound"), {["locked"] = true})
-- hyprland/keybinds.conf:70
hl.bind("SUPER+SHIFT+ALT + mouse:273", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/ai/primary-buffer-query.sh"), {["description"] = "Generate AI summary for selected text"})
-- hyprland/keybinds.conf:75
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), {["mouse"] = true})
-- hyprland/keybinds.conf:76
hl.bind("SUPER + mouse:274", hl.dsp.window.drag(), {["mouse"] = true})
-- hyprland/keybinds.conf:77
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), {["mouse"] = true})
-- hyprland/keybinds.conf:79
hl.bind("SUPER + Left", hl.dsp.focus({direction = "left"}), {})
-- hyprland/keybinds.conf:80
hl.bind("SUPER + Right", hl.dsp.focus({direction = "right"}), {})
-- hyprland/keybinds.conf:81
hl.bind("SUPER + Up", hl.dsp.focus({direction = "up"}), {})
-- hyprland/keybinds.conf:82
hl.bind("SUPER + Down", hl.dsp.focus({direction = "down"}), {})
-- hyprland/keybinds.conf:83
hl.bind("SUPER + BracketLeft", hl.dsp.focus({direction = "left"}), {})
-- hyprland/keybinds.conf:84
hl.bind("SUPER + BracketRight", hl.dsp.focus({direction = "right"}), {})
-- hyprland/keybinds.conf:86
hl.bind("SUPER+SHIFT + Left", hl.dsp.window.move({direction = "left"}), {})
-- hyprland/keybinds.conf:87
hl.bind("SUPER+SHIFT + Right", hl.dsp.window.move({direction = "right"}), {})
-- hyprland/keybinds.conf:88
hl.bind("SUPER+SHIFT + Up", hl.dsp.window.move({direction = "up"}), {})
-- hyprland/keybinds.conf:89
hl.bind("SUPER+SHIFT + Down", hl.dsp.window.move({direction = "down"}), {})
-- hyprland/keybinds.conf:90
hl.bind("ALT + F4", hl.dsp.window.close(), {})
-- hyprland/keybinds.conf:91
hl.bind("SUPER + Q", hl.dsp.window.close(), {})
-- hyprland/keybinds.conf:92
hl.bind("SUPER+SHIFT+ALT + Q", hl.dsp.exec_cmd("hyprctl kill"), {})
-- hyprland/keybinds.conf:97
hl.bind("SUPER + Semicolon", hl.dsp.layout("splitratio -0.1"), {["repeating"] = true})
-- hyprland/keybinds.conf:98
hl.bind("SUPER + Apostrophe", hl.dsp.layout("splitratio +0.1"), {["repeating"] = true})
-- hyprland/keybinds.conf:100
hl.bind("SUPER+ALT + Space", hl.dsp.window.float(), {})
-- hyprland/keybinds.conf:101
hl.bind("SUPER + D", hl.dsp.window.fullscreen({mode = "maximized"}), {})
-- hyprland/keybinds.conf:102
hl.bind("SUPER + F", hl.dsp.window.fullscreen({mode = "fullscreen"}), {})
-- hyprland/keybinds.conf:103
hl.bind("SUPER+ALT + F", hl.dsp.window.fullscreen_state({internal = 0, client = 3}), {})
-- hyprland/keybinds.conf:104
-- Project Launcher owns Super+P; pin remains available on Super+Alt+P.
-- hyprland/keybinds.conf:108
hl.bind("SUPER+ALT + code:10", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspacesilent 1"), {})
-- hyprland/keybinds.conf:109
hl.bind("SUPER+ALT + code:11", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspacesilent 2"), {})
-- hyprland/keybinds.conf:110
hl.bind("SUPER+ALT + code:12", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspacesilent 3"), {})
-- hyprland/keybinds.conf:111
hl.bind("SUPER+ALT + code:13", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspacesilent 4"), {})
-- hyprland/keybinds.conf:112
hl.bind("SUPER+ALT + code:14", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspacesilent 5"), {})
-- hyprland/keybinds.conf:113
hl.bind("SUPER+ALT + code:15", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspacesilent 6"), {})
-- hyprland/keybinds.conf:114
hl.bind("SUPER+ALT + code:16", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspacesilent 7"), {})
-- hyprland/keybinds.conf:115
hl.bind("SUPER+ALT + code:17", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspacesilent 8"), {})
-- hyprland/keybinds.conf:116
hl.bind("SUPER+ALT + code:18", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspacesilent 9"), {})
-- hyprland/keybinds.conf:117
hl.bind("SUPER+ALT + code:19", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspacesilent 10"), {})
-- hyprland/keybinds.conf:119
hl.bind("SUPER+ALT + code:87", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspacesilent 1"), {})
-- hyprland/keybinds.conf:120
hl.bind("SUPER+ALT + code:88", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspacesilent 2"), {})
-- hyprland/keybinds.conf:121
hl.bind("SUPER+ALT + code:89", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspacesilent 3"), {})
-- hyprland/keybinds.conf:122
hl.bind("SUPER+ALT + code:83", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspacesilent 4"), {})
-- hyprland/keybinds.conf:123
hl.bind("SUPER+ALT + code:84", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspacesilent 5"), {})
-- hyprland/keybinds.conf:124
hl.bind("SUPER+ALT + code:85", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspacesilent 6"), {})
-- hyprland/keybinds.conf:125
hl.bind("SUPER+ALT + code:79", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspacesilent 7"), {})
-- hyprland/keybinds.conf:126
hl.bind("SUPER+ALT + code:80", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspacesilent 8"), {})
-- hyprland/keybinds.conf:127
hl.bind("SUPER+ALT + code:81", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspacesilent 9"), {})
-- hyprland/keybinds.conf:128
hl.bind("SUPER+ALT + code:90", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspacesilent 10"), {})
-- hyprland/keybinds.conf:131
hl.bind("SUPER+SHIFT + mouse_down", hl.dsp.window.move({workspace = "r-1", follow = true}), {})
-- hyprland/keybinds.conf:132
hl.bind("SUPER+SHIFT + mouse_up", hl.dsp.window.move({workspace = "r+1", follow = true}), {})
-- hyprland/keybinds.conf:133
hl.bind("SUPER+ALT + mouse_down", hl.dsp.window.move({workspace = "-1", follow = true}), {})
-- hyprland/keybinds.conf:134
hl.bind("SUPER+ALT + mouse_up", hl.dsp.window.move({workspace = "+1", follow = true}), {})
-- hyprland/keybinds.conf:137
hl.bind("SUPER+ALT + Page_Down", hl.dsp.window.move({workspace = "+1", follow = true}), {})
-- hyprland/keybinds.conf:138
hl.bind("SUPER+ALT + Page_Up", hl.dsp.window.move({workspace = "-1", follow = true}), {})
-- hyprland/keybinds.conf:139
hl.bind("SUPER+SHIFT + Page_Down", hl.dsp.window.move({workspace = "r+1", follow = true}), {})
-- hyprland/keybinds.conf:140
hl.bind("SUPER+SHIFT + Page_Up", hl.dsp.window.move({workspace = "r-1", follow = true}), {})
-- hyprland/keybinds.conf:141
hl.bind("CTRL+SUPER+SHIFT + Right", hl.dsp.window.move({workspace = "r+1", follow = true}), {})
-- hyprland/keybinds.conf:142
hl.bind("CTRL+SUPER+SHIFT + Left", hl.dsp.window.move({workspace = "r-1", follow = true}), {})
-- hyprland/keybinds.conf:144
hl.bind("SUPER+ALT + S", hl.dsp.window.move({workspace = "special", follow = false}), {})
-- hyprland/keybinds.conf:146
hl.bind("CTRL+SUPER + S", hl.dsp.workspace.toggle_special(""), {})
-- hyprland/keybinds.conf:152
hl.bind("SUPER + code:10", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh workspace 1"), {})
-- hyprland/keybinds.conf:153
hl.bind("SUPER + code:11", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh workspace 2"), {})
-- hyprland/keybinds.conf:154
hl.bind("SUPER + code:12", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh workspace 3"), {})
-- hyprland/keybinds.conf:155
hl.bind("SUPER + code:13", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh workspace 4"), {})
-- hyprland/keybinds.conf:156
hl.bind("SUPER + code:14", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh workspace 5"), {})
-- hyprland/keybinds.conf:157
hl.bind("SUPER + code:15", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh workspace 6"), {})
-- hyprland/keybinds.conf:158
hl.bind("SUPER + code:16", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh workspace 7"), {})
-- hyprland/keybinds.conf:159
hl.bind("SUPER + code:17", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh workspace 8"), {})
-- hyprland/keybinds.conf:160
hl.bind("SUPER + code:18", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh workspace 9"), {})
-- hyprland/keybinds.conf:161
hl.bind("SUPER + code:19", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh workspace 10"), {})
-- hyprland/keybinds.conf:163
hl.bind("SUPER + code:87", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh workspace 1"), {["dont_inhibit"] = true})
-- hyprland/keybinds.conf:164
hl.bind("SUPER + code:88", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh workspace 2"), {["dont_inhibit"] = true})
-- hyprland/keybinds.conf:165
hl.bind("SUPER + code:89", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh workspace 3"), {["dont_inhibit"] = true})
-- hyprland/keybinds.conf:166
hl.bind("SUPER + code:83", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh workspace 4"), {["dont_inhibit"] = true})
-- hyprland/keybinds.conf:167
hl.bind("SUPER + code:84", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh workspace 5"), {["dont_inhibit"] = true})
-- hyprland/keybinds.conf:168
hl.bind("SUPER + code:85", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh workspace 6"), {["dont_inhibit"] = true})
-- hyprland/keybinds.conf:169
hl.bind("SUPER + code:79", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh workspace 7"), {["dont_inhibit"] = true})
-- hyprland/keybinds.conf:170
hl.bind("SUPER + code:80", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh workspace 8"), {["dont_inhibit"] = true})
-- hyprland/keybinds.conf:171
hl.bind("SUPER + code:81", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh workspace 9"), {["dont_inhibit"] = true})
-- hyprland/keybinds.conf:172
hl.bind("SUPER + code:90", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/workspace_action.sh workspace 10"), {["dont_inhibit"] = true})
-- hyprland/keybinds.conf:175
hl.bind("CTRL+SUPER + Right", hl.dsp.focus({workspace = "r+1"}), {})
-- hyprland/keybinds.conf:176
hl.bind("CTRL+SUPER + Left", hl.dsp.focus({workspace = "r-1"}), {})
-- hyprland/keybinds.conf:178
hl.bind("CTRL+SUPER+ALT + Right", hl.dsp.focus({workspace = "m+1"}), {})
-- hyprland/keybinds.conf:179
hl.bind("CTRL+SUPER+ALT + Left", hl.dsp.focus({workspace = "m-1"}), {})
-- hyprland/keybinds.conf:181
hl.bind("SUPER + Page_Down", hl.dsp.focus({workspace = "+1"}), {})
-- hyprland/keybinds.conf:182
hl.bind("SUPER + Page_Up", hl.dsp.focus({workspace = "-1"}), {})
-- hyprland/keybinds.conf:183
hl.bind("CTRL+SUPER + Page_Down", hl.dsp.focus({workspace = "r+1"}), {})
-- hyprland/keybinds.conf:184
hl.bind("CTRL+SUPER + Page_Up", hl.dsp.focus({workspace = "r-1"}), {})
-- hyprland/keybinds.conf:186
hl.bind("SUPER + mouse_up", hl.dsp.focus({workspace = "+1"}), {})
-- hyprland/keybinds.conf:187
hl.bind("SUPER + mouse_down", hl.dsp.focus({workspace = "-1"}), {})
-- hyprland/keybinds.conf:188
hl.bind("CTRL+SUPER + mouse_up", hl.dsp.focus({workspace = "r+1"}), {})
-- hyprland/keybinds.conf:189
hl.bind("CTRL+SUPER + mouse_down", hl.dsp.focus({workspace = "r-1"}), {})
-- hyprland/keybinds.conf:191
hl.bind("SUPER + S", hl.dsp.workspace.toggle_special(""), {})
-- hyprland/keybinds.conf:192
hl.bind("SUPER + mouse:275", hl.dsp.workspace.toggle_special(""), {})
-- hyprland/keybinds.conf:193
hl.bind("CTRL+SUPER + BracketLeft", hl.dsp.focus({workspace = "-1"}), {})
-- hyprland/keybinds.conf:194
hl.bind("CTRL+SUPER + BracketRight", hl.dsp.focus({workspace = "+1"}), {})
-- hyprland/keybinds.conf:195
hl.bind("CTRL+SUPER + Up", hl.dsp.focus({workspace = "r-5"}), {})
-- hyprland/keybinds.conf:196
hl.bind("CTRL+SUPER + Down", hl.dsp.focus({workspace = "r+5"}), {})
-- hyprland/keybinds.conf:199
hl.bind("SUPER+ALT + F1", hl.dsp.exec_cmd("notify-send 'Entered Virtual Machine submap' 'Keybinds disabled. Hit Super+Alt+F1 to escape' -a 'Hyprland' && hyprctl dispatch 'hl.dsp.submap(\"virtual-machine\")'"), {})
-- hyprland/keybinds.conf:200
end)
hl.define_submap("virtual-machine", function()
-- hyprland/keybinds.conf:201
hl.bind("SUPER+ALT + F1", hl.dsp.exec_cmd("notify-send 'Exited Virtual Machine submap' 'Keybinds re-enabled' -a 'Hyprland' && hyprctl dispatch 'hl.dsp.submap(\"global\")'"), {})
-- hyprland/keybinds.conf:202
end)
hl.define_submap("global", function()
-- hyprland/keybinds.conf:206
hl.bind("SUPER+ALT + f11", hl.dsp.exec_cmd("bash -c 'RANDOM_IMAGE=$(find ~/Pictures -type f | grep -v -i \"nipple\" | grep -v -i \"pussy\" | shuf -n 1); ACTION=$(notify-send \"Test notification with body image\" \"This notification should contain your user account <b>image</b> and <a href=\\\"https://discord.com/app\\\">Discord</a> <b>icon</b>. Oh and here is a random image in your Pictures folder: <img src=\\\"$RANDOM_IMAGE\\\" alt=\\\"Testing image\\\"/>\" -a \"Hyprland keybind\" -p -h \"string:image-path:/var/lib/AccountsService/icons/$USER\" -t 6000 -i \"discord\" -A \"openImage=Profile image\" -A \"action2=Open the random image\" -A \"action3=Useless button\"); [[ $ACTION == *openImage ]] && xdg-open \"/var/lib/AccountsService/icons/$USER\"; [[ $ACTION == *action2 ]] && xdg-open \\\"$RANDOM_IMAGE\\\"'"), {})
-- hyprland/keybinds.conf:207
hl.bind("SUPER+ALT + f12", hl.dsp.exec_cmd("bash -c 'RANDOM_IMAGE=$(find ~/Pictures -type f | grep -v -i \"nipple\" | grep -v -i \"pussy\" | shuf -n 1); ACTION=$(notify-send \"Test notification\" \"This notification should contain a random image in your <b>Pictures</b> folder and <a href=\\\"https://discord.com/app\\\">Discord</a> <b>icon</b>.\\n<i>Flick right to dismiss!</i>\" -a \"Discord (fake)\" -p -h \"string:image-path:$RANDOM_IMAGE\" -t 6000 -i \"discord\" -A \"openImage=Profile image\" -A \"action2=Useless button\"); [[ $ACTION == *openImage ]] && xdg-open \"/var/lib/AccountsService/icons/$USER\"'"), {})
-- hyprland/keybinds.conf:208
hl.bind("SUPER+ALT + Equal", hl.dsp.exec_cmd("notify-send \"Urgent notification\" \"Ah hell no\" -u critical -a 'Hyprland keybind'"), {})
-- hyprland/keybinds.conf:211
hl.bind("SUPER + L", hl.dsp.exec_cmd("loginctl lock-session"), {["description"] = "Lock"})
-- hyprland/keybinds.conf:212
hl.bind("SUPER+SHIFT + L", hl.dsp.exec_cmd("systemctl suspend || loginctl suspend"), {["locked"] = true, ["description"] = "Suspend system"})
-- hyprland/keybinds.conf:214
hl.bind("CTRL+SHIFT+ALT+SUPER + Delete", hl.dsp.exec_cmd("systemctl poweroff || loginctl poweroff"), {["description"] = "Shutdown"})
-- hyprland/keybinds.conf:218
hl.bind("SUPER + Minus", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/zoom.sh decrease 0.3"), {["repeating"] = true})
-- hyprland/keybinds.conf:219
hl.bind("SUPER + Equal", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/zoom.sh increase 0.3"), {["repeating"] = true})
-- hyprland/keybinds.conf:221
hl.bind("SUPER + code:82", hl.dsp.exec_cmd("qs -c nyvorel ipc call zoom zoomOut"), {["repeating"] = true})
-- hyprland/keybinds.conf:222
hl.bind("SUPER + code:86", hl.dsp.exec_cmd("qs -c nyvorel ipc call zoom zoomIn"), {["repeating"] = true})
-- hyprland/keybinds.conf:223
hl.bind("SUPER + code:82", hl.dsp.exec_cmd("qs -c nyvorel ipc call TEST_ALIVE || ~/.config/hypr/hyprland/scripts/zoom.sh decrease 0.1"), {["repeating"] = true})
-- hyprland/keybinds.conf:224
hl.bind("SUPER + code:86", hl.dsp.exec_cmd("qs -c nyvorel ipc call TEST_ALIVE || ~/.config/hypr/hyprland/scripts/zoom.sh increase 0.1"), {["repeating"] = true})
-- hyprland/keybinds.conf:227
hl.bind("SUPER+SHIFT + N", hl.dsp.exec_cmd("playerctl next || playerctl position `bc <<< \"100 * $(playerctl metadata mpris:length) / 1000000 / 100\"`"), {["locked"] = true})
-- hyprland/keybinds.conf:228
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next || playerctl position `bc <<< \"100 * $(playerctl metadata mpris:length) / 1000000 / 100\"`"), {["locked"] = true})
-- hyprland/keybinds.conf:229
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), {["locked"] = true})
-- hyprland/keybinds.conf:230
hl.bind("SUPER+SHIFT+ALT + mouse:275", hl.dsp.exec_cmd("playerctl previous"), {})
-- hyprland/keybinds.conf:231
hl.bind("SUPER+SHIFT+ALT + mouse:276", hl.dsp.exec_cmd("playerctl next || playerctl position `bc <<< \"100 * $(playerctl metadata mpris:length) / 1000000 / 100\"`"), {})
-- hyprland/keybinds.conf:232
hl.bind("SUPER+SHIFT + B", hl.dsp.exec_cmd("playerctl previous"), {["locked"] = true})
-- hyprland/keybinds.conf:233
hl.bind("SUPER+SHIFT + P", hl.dsp.exec_cmd("playerctl play-pause"), {["locked"] = true})
-- hyprland/keybinds.conf:234
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), {["locked"] = true})
-- hyprland/keybinds.conf:235
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), {["locked"] = true})
-- hyprland/keybinds.conf:238
hl.bind("SUPER + Return", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/launch_first_available.sh \"${TERMINAL}\" \"kitty -1\" \"foot\" \"alacritty\" \"wezterm\" \"konsole\" \"kgx\" \"uxterm\" \"xterm\""), {})
-- hyprland/keybinds.conf:239
hl.bind("SUPER + T", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/launch_first_available.sh \"${TERMINAL}\" \"kitty -1\" \"foot\" \"alacritty\" \"wezterm\" \"konsole\" \"kgx\" \"uxterm\" \"xterm\""), {})
-- hyprland/keybinds.conf:240
hl.bind("CTRL+ALT + T", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/launch_first_available.sh \"${TERMINAL}\" \"kitty -1\" \"foot\" \"alacritty\" \"wezterm\" \"konsole\" \"kgx\" \"uxterm\" \"xterm\""), {})
-- hyprland/keybinds.conf:241
hl.bind("SUPER + E", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/launch_first_available.sh \"dolphin\" \"nautilus\" \"nemo\" \"thunar\" \"${TERMINAL}\" \"kitty -1 fish -c yazi\""), {})
-- hyprland/keybinds.conf:242
hl.bind("SUPER + W", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/launch_first_available.sh \"google-chrome-stable\" \"zen-browser\" \"firefox\" \"brave\" \"chromium\" \"microsoft-edge-stable\" \"opera\" \"librewolf\""), {})
-- hyprland/keybinds.conf:243
hl.bind("SUPER + C", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/launch_first_available.sh \"antigravity\" \"code\" \"codium\" \"cursor\" \"zed\" \"zedit\" \"zeditor\" \"kate\" \"gnome-text-editor\" \"emacs\" \"command -v nvim && kitty -1 nvim\" \"command -v micro && kitty -1 micro\""), {})
-- hyprland/keybinds.conf:244
hl.bind("CTRL+SUPER+SHIFT+ALT + W", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/launch_first_available.sh \"wps\" \"onlyoffice-desktopeditors\" \"libreoffice\""), {})
-- hyprland/keybinds.conf:245
hl.bind("SUPER + X", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/launch_first_available.sh \"kate\" \"gnome-text-editor\" \"emacs\""), {})
-- hyprland/keybinds.conf:246
hl.bind("CTRL+SUPER + V", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/launch_first_available.sh \"pavucontrol-qt\" \"pavucontrol\""), {})
-- hyprland/keybinds.conf:247
hl.bind("SUPER + I", hl.dsp.exec_cmd("~/.local/bin/nyvorel-settings"), {})
-- hyprland/keybinds.conf:248
hl.bind("CTRL+SHIFT + Escape", hl.dsp.exec_cmd("~/.config/hypr/hyprland/scripts/launch_first_available.sh \"gnome-system-monitor\" \"plasma-systemmonitor --page-name Processes\" \"command -v btop && kitty -1 fish -c btop\""), {})
-- hyprland/keybinds.conf:252
hl.bind("CTRL+SUPER + Backslash", hl.dsp.window.resize({x = 640, y = 480, relative = false}), {})
-- hyprland.conf:20
-- hyprland.conf:21
-- hyprland.conf:22
-- hyprland.conf:23
dofile(nyvorel_config_root .. "/custom/appearance-runtime.lua")
-- hyprland.conf:24
-- hyprland.conf:25
-- custom/keybinds.conf: Project Launcher and desktop tools.
hl.bind("SUPER + P", hl.dsp.global("quickshell:projectsToggle"), { ["description"] = "Project command center" })
hl.bind("SUPER+ALT + P", hl.dsp.window.pin(), {})
hl.bind("SUPER+ALT + T", hl.dsp.global("quickshell:appearanceStudioToggle"), { ["description"] = "Appearance Studio" })
hl.bind("SUPER + Y", hl.dsp.global("quickshell:archRemoteToggle"), { ["description"] = "Arch Remote Control Center" })
hl.bind("SUPER + U", hl.dsp.global("quickshell:backupRecoveryToggle"), { ["description"] = "Backup & Recovery Center" })
-- custom/nyvorel-super-scroll.conf:15
-- custom/nyvorel-super-scroll.conf:18
hl.bind("SUPER + Super_L", hl.dsp.exec_cmd(super_scroll .. " press left"), {["ignore_mods"] = true, ["description"] = "Toggle search on tap"})
-- custom/nyvorel-super-scroll.conf:19
hl.bind("SUPER + Super_R", hl.dsp.exec_cmd(super_scroll .. " press right"), {["ignore_mods"] = true, ["description"] = "Toggle search on tap"})
-- custom/nyvorel-super-scroll.conf:20
hl.bind("SUPER + Super_L", hl.dsp.exec_cmd(super_scroll .. " release left"), {["release"] = true, ["transparent"] = true, ["ignore_mods"] = true, ["description"] = "Toggle search on tap"})
-- custom/nyvorel-super-scroll.conf:21
hl.bind("SUPER + Super_R", hl.dsp.exec_cmd(super_scroll .. " release right"), {["release"] = true, ["transparent"] = true, ["ignore_mods"] = true, ["description"] = "Toggle search on tap"})
-- custom/nyvorel-super-scroll.conf:24
hl.bind("catchall", hl.dsp.exec_cmd(super_scroll .. " cancel"), {["non_consuming"] = true, ["transparent"] = true, ["ignore_mods"] = true})
-- custom/nyvorel-super-scroll.conf:25
hl.bind("CTRL + Super_L", hl.dsp.exec_cmd(super_scroll .. " cancel"), {})
-- custom/nyvorel-super-scroll.conf:26
hl.bind("CTRL + Super_R", hl.dsp.exec_cmd(super_scroll .. " cancel"), {})
-- custom/nyvorel-super-scroll.conf:29
hl.bind("SUPER + mouse:272", hl.dsp.exec_cmd(super_scroll .. " cancel"), {})
-- custom/nyvorel-super-scroll.conf:30
hl.bind("SUPER + mouse:273", hl.dsp.exec_cmd(super_scroll .. " cancel"), {})
-- custom/nyvorel-super-scroll.conf:31
hl.bind("SUPER + mouse:274", hl.dsp.exec_cmd(super_scroll .. " cancel"), {})
-- custom/nyvorel-super-scroll.conf:32
hl.bind("SUPER + mouse:275", hl.dsp.exec_cmd(super_scroll .. " cancel"), {})
-- custom/nyvorel-super-scroll.conf:33
hl.bind("SUPER + mouse:276", hl.dsp.exec_cmd(super_scroll .. " cancel"), {})
-- custom/nyvorel-super-scroll.conf:34
hl.bind("SUPER + mouse:277", hl.dsp.exec_cmd(super_scroll .. " cancel"), {})
-- custom/nyvorel-super-scroll.conf:39
hl.unbind("SUPER + mouse_up")
-- custom/nyvorel-super-scroll.conf:40
hl.unbind("SUPER + mouse_down")
-- custom/nyvorel-super-scroll.conf:41
hl.bind("SUPER + mouse_up", hl.dsp.exec_cmd(super_scroll .. " cancel"), {["non_consuming"] = true})
-- custom/nyvorel-super-scroll.conf:42
hl.bind("SUPER + mouse_down", hl.dsp.exec_cmd(super_scroll .. " cancel"), {["non_consuming"] = true})
-- custom/nyvorel-super-scroll.conf:46
hl.bind("SUPER + mouse_left", hl.dsp.exec_cmd(super_scroll .. " cancel"), {["non_consuming"] = true})
-- custom/nyvorel-super-scroll.conf:47
hl.bind("SUPER + mouse_right", hl.dsp.exec_cmd(super_scroll .. " cancel"), {["non_consuming"] = true})
-- hyprland.conf:28
load_optional(nyvorel_config_root .. "/workspaces.lua")
-- hyprland.conf:29
load_optional(nyvorel_config_root .. "/monitors.lua")
-- hyprland.conf:30
hl.env("_JAVA_AWT_WM_NONREPARENTING", "1")
-- hyprland.conf:33
load_optional(nyvorel_config_root .. "/hyprland-gui.lua")
-- hyprland.conf:36
-- nyvorel-terminal-glass.conf:5
hl.config({["decoration"] = {["blur"] = {["enabled"] = true}}})
-- nyvorel-terminal-glass.conf:6
hl.config({["decoration"] = {["blur"] = {["size"] = 14}}})
-- nyvorel-terminal-glass.conf:7
hl.config({["decoration"] = {["blur"] = {["passes"] = 3}}})
-- nyvorel-terminal-glass.conf:8
hl.config({["decoration"] = {["blur"] = {["ignore_opacity"] = true}}})
-- nyvorel-terminal-glass.conf:9
hl.config({["decoration"] = {["blur"] = {["new_optimizations"] = true}}})
-- hyprland.conf:43
hl.layer_rule({["xray"] = false, ["match"] = {["namespace"] = "quickshell:projectLauncher"}, ["name"] = "nyvorel-79"})
-- hyprland.conf:50
hl.layer_rule({["xray"] = false, ["match"] = {["namespace"] = "^quickshell:sidebarLeft$"}, ["name"] = "nyvorel-80"})
-- hyprland.conf:51
hl.layer_rule({["xray"] = false, ["match"] = {["namespace"] = "^quickshell:sidebarRight$"}, ["name"] = "nyvorel-81"})
-- hyprland.conf:63
hl.layer_rule({["xray"] = false, ["match"] = {["namespace"] = "^quickshell:popup$"}, ["name"] = "nyvorel-82"})
-- hyprland.conf:66
hl.layer_rule({["xray"] = false, ["match"] = {["namespace"] = "^quickshell:notificationPopup$"}, ["name"] = "nyvorel-83"})
-- hyprland.conf:67
hl.layer_rule({["xray"] = false, ["match"] = {["namespace"] = "^quickshell:mediaControls$"}, ["name"] = "nyvorel-84"})
-- hyprland.conf:68
hl.layer_rule({["xray"] = false, ["match"] = {["namespace"] = "^quickshell:onScreenDisplay$"}, ["name"] = "nyvorel-85"})
-- hyprland.conf:69
hl.layer_rule({["xray"] = false, ["match"] = {["namespace"] = "^quickshell:appearanceStudio$"}, ["name"] = "nyvorel-86"})
-- hyprland.conf:75
hl.layer_rule({["xray"] = false, ["match"] = {["namespace"] = "^quickshell:session$"}, ["name"] = "nyvorel-87"})
-- hyprland.conf:81
hl.window_rule({["no_blur"] = false, ["match"] = {["class"] = "^(dev\\.zed\\.Zed)$"}, ["name"] = "nyvorel-65"})
-- hyprland.conf:87
hl.window_rule({["no_blur"] = false, ["match"] = {["class"] = "^(org\\.kde\\.dolphin|dolphin)$"}, ["name"] = "nyvorel-66"})
-- hyprland.conf:94
hl.layer_rule({["no_anim"] = true, ["match"] = {["namespace"] = "^quickshell:(archRemote|backupRecovery|mediaControls|onScreenDisplay)$"}, ["name"] = "nyvorel-88"})
-- hyprland.conf:99
hl.layer_rule({["xray"] = false, ["match"] = {["namespace"] = "^quickshell:(archRemote|backupRecovery)$"}, ["name"] = "nyvorel-89"})
-- hyprland.conf:105
hl.layer_rule({["no_anim"] = true, ["match"] = {["namespace"] = "^quickshell:notificationPopup$"}, ["name"] = "nyvorel-90"})
-- hyprland.conf:110
hl.layer_rule({["blur"] = true, ["match"] = {["namespace"] = "^quickshell:notificationPopup$"}, ["name"] = "nyvorel-91"})
-- hyprland.conf:111
hl.layer_rule({["blur_popups"] = true, ["match"] = {["namespace"] = "^quickshell:notificationPopup$"}, ["name"] = "nyvorel-92"})
-- hyprland.conf:112
hl.layer_rule({["xray"] = false, ["match"] = {["namespace"] = "^quickshell:notificationPopup$"}, ["name"] = "nyvorel-93"})
-- hyprland.conf:113
hl.layer_rule({["ignore_alpha"] = 0.12, ["match"] = {["namespace"] = "^quickshell:notificationPopup$"}, ["name"] = "nyvorel-94"})
-- hyprland.conf:119
hl.window_rule({["float"] = true, ["match"] = {["class"] = "^(pavucontrol-qt)$"}, ["name"] = "nyvorel-67"})
-- hyprland.conf:120
hl.window_rule({["size"] = "(monitor_w*.45) (monitor_h*.45)", ["match"] = {["class"] = "^(pavucontrol-qt)$"}, ["name"] = "nyvorel-68"})
-- hyprland.conf:121
hl.window_rule({["center"] = true, ["match"] = {["class"] = "^(pavucontrol-qt)$"}, ["name"] = "nyvorel-69"})
-- Personal native overrides are user-owned and evaluated after project defaults.
load_optional(nyvorel_config_root .. "/custom/user.lua")
end)
hl.on("hyprland.start", function()
  if NYVOREL_VERIFY_ONLY then return end
  hl.exec_cmd("~/.config/hypr/hyprland/scripts/start_geoclue_agent.sh")
  hl.exec_cmd("sh -lc 'if command -v nyvorel >/dev/null 2>&1; then exec nyvorel activate --session; elif [ -x \"$HOME/.local/bin/nyvorel\" ]; then exec \"$HOME/.local/bin/nyvorel\" activate --session; elif [ -x /usr/bin/nyvorel ]; then exec /usr/bin/nyvorel activate --session; else echo \"Nyvorel CLI is missing; session activation failed.\" >&2; exit 127; fi'")
  hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
  hl.exec_cmd("dbus-update-activation-environment --all")
  hl.exec_cmd("sleep 1 && dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
  hl.exec_cmd("easyeffects --hide-window --service-mode")
  hl.exec_cmd("wl-paste --type text --watch bash -c 'cliphist store && qs -c nyvorel ipc call cliphistService update'")
  hl.exec_cmd("wl-paste --type image --watch bash -c 'cliphist store && qs -c nyvorel ipc call cliphistService update'")
  hl.exec_cmd("numlockx on")
end)
hl.on("config.reloaded", function()
  if NYVOREL_VERIFY_ONLY then return end
  hl.dispatch(hl.dsp.submap("global"))
  hl.exec_cmd(super_scroll .. " reload-reset")
end)
