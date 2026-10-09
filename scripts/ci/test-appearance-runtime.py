#!/usr/bin/env python3
"""Integration fixture: real color engines, synthetic templates, isolated session.

This is not a clean-install or visual desktop test. No packages are installed,
and the explicitly supplied Python environment is used without modification.
"""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
import importlib.util, json, os, shutil, subprocess, tempfile
from unittest.mock import patch
root=Path(__file__).resolve().parents[2]
import argparse
parser = argparse.ArgumentParser(description="Real generators in a disposable home; compositor calls are stubbed.")
parser.add_argument('--venv', required=True, type=Path, help='Existing Python environment providing Pillow and materialyoucolor (read-only)')
color_env = parser.parse_args().venv.expanduser().resolve()
if not (color_env / 'bin/activate').is_file():
 raise SystemExit('Missing existing color environment: ' + str(color_env))
for command in ('matugen', 'jq', 'bc', 'magick'):
 if not shutil.which(command): raise SystemExit('Missing test prerequisite: ' + command)
with tempfile.TemporaryDirectory(prefix='nyvorel-runtime-') as temp:
 home=Path(temp); config=home/'.config'; state=home/'.local/state'; cache=home/'.cache'
 shell=config/'quickshell/nyvorel'; shutil.copytree(root/'quickshell',shell)
 for name in ('nyvorel-glass-runtime','nyvorel-fluid-runtime','nyvorel-terminal-theme-sync'):
  target=home/'.local/bin'/name; target.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(root/'bin'/name,target)
 runtime=home/'runtime';runtime.mkdir(mode=0o700)
 shutil.copytree(root/'hypr',config/'hypr')
 (config/'nyvorel').mkdir(); (config/'nyvorel/config.json').write_text('{}')
 commands=home/'commands'; commands.mkdir()
 stubs={'hyprctl': '#!/bin/sh\ncase "$1" in\nmonitors) echo \'[{"name":"TEST","focused":true,"scale":1,"x":0,"y":0,"width":1280,"height":720}]\';;\ncursorpos) echo \'{"x":0,"y":0}\';;\n*) echo ok;;\nesac\n', 'gsettings':'#!/bin/sh\nexit 0\n','pkill':'#!/bin/sh\nexit 0\n'}
 for name,body in stubs.items():
  p=commands/name;p.write_text(body);p.chmod(0o755)
 env={**os.environ,'HOME':temp,'XDG_CONFIG_HOME':str(config),'XDG_STATE_HOME':str(state),'XDG_CACHE_HOME':str(cache),'XDG_RUNTIME_DIR':str(runtime),'NYVOREL_VIRTUAL_ENV':str(color_env),'PATH':str(commands)+':'+os.environ['PATH'],'DBUS_SESSION_BUS_ADDRESS':'unix:path=/nonexistent','WAYLAND_DISPLAY':'','HYPRLAND_INSTANCE_SIGNATURE':''}
 with patch.dict(os.environ,env):
  spec=importlib.util.spec_from_file_location('studio',shell/'scripts/appearance-studio/appearance_studio.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
  shutil.copytree(root/'matugen',config/'matugen')
  generated=subprocess.run(['matugen','color','hex','#5368B7','--mode','dark','--type','scheme-tonal-spot'],env=env,text=True,capture_output=True,timeout=30)
  assert generated.returncode==0,generated.stderr
  for output in (m.COLORS_JSON,config/'hypr/hyprland/colors.conf',config/'hypr/hyprlock/colors.conf',config/'fuzzel/fuzzel_theme.ini',config/'gtk-3.0/gtk.css',config/'gtk-4.0/gtk.css',m.COLOR_TXT,m.WALLPAPER_TXT):
   assert output.is_file() and output.stat().st_size>0,output
  assert set(m.REQUIRED_PREVIEW_ROLES)<=set(json.loads(m.COLORS_JSON.read_text()))
  print('PASS source-owned Matugen templates and all eight outputs',flush=True)
  s=m._load_state();s['targets']={k:k=='shell' for k in ['shell','hyprland','hyprlock','gtk','fuzzel','qt','terminal','editors']};m._save_state(s)
  with patch.object(m,'_launch_preview_watchdog'):
   for profile in ['default','inlay','prism','fluid']:
    for mode in ['dark','light']:
     r=m.apply_theme(source='preset',preset='midnight',mode=mode,scheme='auto',ui_snapshot=m.UI_PROFILES[profile]['patch'])
     assert r['ok'] and m.COLORS_JSON.is_file() and m.MATERIAL_SCSS.stat().st_size>100
     assert m._load_state()['active']['uiProfile']==profile
     print('PASS real generators, preset',mode,profile,flush=True)
   baseline=m._read_json(m.COLORS_JSON,{})
   m.apply_theme(source='preset',preset='ocean',mode='dark',scheme='auto',preview=True)
   assert m._read_json(m.COLORS_JSON,{}) != baseline
   m.revert_preview();assert m._read_json(m.COLORS_JSON,{})==baseline
   print('PASS preview and cancel restored palette',flush=True)
   m.apply_theme(source='preset',preset='ocean',mode='dark',scheme='auto',preview=True)
   m.keep_preview();assert m._load_state()['active']['preset']=='ocean'
   print('PASS preview keep',flush=True)
   m.apply_theme(source='wallpaper',wallpaper=str(shell/'assets/images/default_wallpaper.png'),mode='dark',scheme='scheme-tonal-spot')
   print('PASS real wallpaper profiling and palette application',flush=True)
   baseline=m._capture_files(m._all_transaction_files())
   with patch.object(m,'_run_switchwall',side_effect=RuntimeError('injected failure')):
    try:m.apply_theme(source='preset',preset='midnight',mode='light',scheme='auto')
    except RuntimeError:pass
    else:raise AssertionError('expected failure')
   assert m._capture_files(m._all_transaction_files())==baseline
   print('PASS failed apply restored transaction',flush=True)
