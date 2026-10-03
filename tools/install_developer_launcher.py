#!/usr/bin/env python3
"""Install a separate macOS desktop launcher without altering SUR.app."""
from pathlib import Path
import plistlib
import shlex
import shutil
import sys


def main() -> None:
    if sys.platform != 'darwin':
        raise SystemExit('This desktop bundle is for macOS. Use tools/launch_developer.py directly.')
    project = Path(__file__).resolve().parents[1]
    app = Path.home() / 'Desktop/SUR — Разработчик.app'
    bundle_id = 'local.family.sur.developer'
    plist_path = app / 'Contents/Info.plist'
    if app.exists():
        if not plist_path.is_file() or plistlib.loads(plist_path.read_bytes()).get('CFBundleIdentifier') != bundle_id:
            raise SystemExit('A different application already uses this name: ' + str(app))
    executable = app / 'Contents/MacOS/SURDeveloper'
    executable.parent.mkdir(parents=True, exist_ok=True)
    resources = app / 'Contents/Resources'
    resources.mkdir(exist_ok=True)
    plist = {'CFBundleName': 'SUR — Разработчик', 'CFBundleDisplayName': 'SUR — Разработчик',
             'CFBundleIdentifier': bundle_id, 'CFBundleExecutable': 'SURDeveloper',
             'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': '0.4.0',
             'CFBundleVersion': '1', 'NSHighResolutionCapable': True, 'LSMultipleInstancesProhibited': False}
    original = Path.home() / 'Desktop/SUR.app/Contents/Resources'
    icons = list(original.glob('*.icns'))
    if icons:
        shutil.copy2(icons[0], resources / 'SURDeveloper.icns')
        plist['CFBundleIconFile'] = 'SURDeveloper.icns'
    plist_path.write_bytes(plistlib.dumps(plist))
    executable.write_text('#!/bin/bash\nexec ' + shlex.quote(sys.executable) + ' '
        + shlex.quote(str(project / 'tools/launch_developer.py'))
        + ' "$@" > "${TMPDIR:-/tmp/}sur-developer-launch.log" 2>&1\n')
    executable.chmod(0o755)
    print(app)


if __name__ == '__main__':
    main()
