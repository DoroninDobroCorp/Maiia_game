"""Fresh project AND user:// for a developer session or automated checks."""
from __future__ import annotations

import contextlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import uuid

PROJECT = Path(__file__).resolve().parents[1]


def godot_binary() -> str:
    candidates = [os.environ.get("SUR_GODOT_BIN", ""),
                  "/Applications/Godot.app/Contents/MacOS/Godot",
                  "/opt/homebrew/bin/godot", shutil.which("godot")]
    for candidate in candidates:
        if candidate and os.access(candidate, os.X_OK):
            return candidate
    raise RuntimeError("Не найден Godot. Установите Godot или задайте SUR_GODOT_BIN.")


def user_data_base() -> Path:
    if sys.platform == "darwin":
        return Path.home() / "Library/Application Support"
    if sys.platform == "win32":
        return Path(os.environ["APPDATA"])
    return Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))


@contextlib.contextmanager
def isolated_project(*, developer: bool = False, mode: str = "prologue"):
    """Never reuse another session or copy the family profile into a fixture."""
    token = uuid.uuid4().hex
    relative_user = "SUR Developer/sessions/" + token
    profile = user_data_base() / relative_user
    profile.mkdir(parents=True, exist_ok=False)
    with tempfile.TemporaryDirectory(prefix="sur-session-") as temporary:
        project = Path(temporary).resolve() / "project"
        try:
            shutil.copytree(PROJECT, project, ignore=shutil.ignore_patterns(
                ".git", "__pycache__", "*.pyc", "*.log", ".DS_Store", "screenshots", "build"))
            config_path = project / "project.godot"
            config = config_path.read_text()
            config = re.sub(r'^config/(?:use_custom_user_dir|custom_user_dir_name)=.*\n',
                            '', config, flags=re.MULTILINE)
            config = config.replace('[application]', '[application]\n'
                'config/use_custom_user_dir=true\n'
                'config/custom_user_dir_name=' + json.dumps(relative_user) + '\n', 1)
            config += '\n[sur]\n' + '\n'.join([
                'isolated_user_dir=' + json.dumps(str(profile)),
                'developer_session=' + ('true' if developer else 'false'),
                'developer_start=' + json.dumps(mode),
            ]) + '\n'
            config_path.write_text(config)
            (profile / '.sur-temporary-session.json').write_text(json.dumps({
                'kind': 'sur_temporary_session', 'project': str(project),
                'user_dir': str(profile), 'session_id': token,
            }))
            probe = project / '_isolation_probe.gd'
            probe.write_text('extends SceneTree\nfunc _init():\n'
                ' var expected = ProjectSettings.get_setting("sur/isolated_user_dir", "")\n'
                ' var ok = OS.get_user_data_dir() == expected and '
                'FileAccess.file_exists("user://.sur-temporary-session.json")\n'
                ' if not ok: printerr("SUR: user directory isolation failed")\n'
                ' quit(0 if ok else 1)\n')
            checked = subprocess.run([godot_binary(), '--headless', '--path', str(project),
                '--script', str(probe)], capture_output=True, text=True, timeout=30)
            probe.unlink()
            if checked.returncode or 'SCRIPT ERROR:' in checked.stderr:
                raise RuntimeError('Изоляция не подтверждена; запуск отменён.\n' + checked.stderr)
            yield project, profile
        finally:
            # Delete only the exact directory created by this invocation.
            shutil.rmtree(profile)


def run_godot(project: Path, arguments: list[str], *, timeout: int | None = None, **kwargs) -> int:
    """Stop the engine's group; AdventureController stops detached dev games."""
    process = subprocess.Popen([godot_binary(), '--path', str(project), *arguments],
                               start_new_session=True, **kwargs)
    try:
        return process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        print('SUR: test process timed out', file=sys.stderr, flush=True)
        return 124
    except (KeyboardInterrupt, SystemExit):
        return 130
    finally:
        if os.name == 'posix':
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        elif process.poll() is None:
            process.terminate()
        if process.poll() is None:
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
