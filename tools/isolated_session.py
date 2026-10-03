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
from datetime import datetime, timezone

PROJECT = Path(__file__).resolve().parents[1]
FAMILY_SNAPSHOT = '.developer-family-snapshot'


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


def family_profile_directory() -> Path:
    godot_dir = 'Godot' if sys.platform in ('darwin', 'win32') else 'godot'
    return user_data_base() / godot_dir / 'app_userdata/SUR'


def _copy_private_tree(source: Path, target: Path) -> None:
    """Copy bytes, never links into the original profile or its working projects."""
    if source.is_symlink():
        raise ValueError('Символические ссылки в семейном хранилище не копируются.')
    if source.is_dir():
        target.mkdir()
        for child in source.iterdir():
            _copy_private_tree(child, target / child.name)
    elif source.is_file():
        shutil.copy2(source, target)
    else:
        raise ValueError('В семейном хранилище найден неподдерживаемый файл.')


def capture_family_snapshot(source: Path | None, profile: Path) -> dict:
    """Read the family once; the running game only sees this private snapshot."""
    snapshot = profile / FAMILY_SNAPSHOT
    info = {'available': False, 'message': 'Сохранение Майи не найдено.'}
    try:
        if source is not None and (source / 'savegame.json').is_file():
            if source.is_symlink() or (source / 'savegame.json').is_symlink():
                raise ValueError('Семейное сохранение не должно быть символической ссылкой.')
            original = (source / 'savegame.json').read_bytes()
            state = json.loads(original)
            if not isinstance(state, dict) or not state:
                raise ValueError('Семейное сохранение не читается.')
            if str(state.get('schema_version', '1.0.0')) not in ('1.0.0', '1.1.0', '1.2.0', '1.3.0'):
                raise ValueError('Для этого сохранения нужна совместимая версия SUR.')
            snapshot.mkdir()
            (snapshot / 'savegame.json').write_bytes(original)
            for name in ('artifacts', 'launch_registry'):
                if (source / name).exists() or (source / name).is_symlink():
                    _copy_private_tree(source / name, snapshot / name)
            if (source / 'savegame.json').read_bytes() != original:
                raise ValueError('Сохранение изменилось во время копирования. Перезапустите тест.')
            info = {'available': True, 'station_name': str(state.get('station_name', 'Станция Майи')),
                    'saved_at': state.get('updated_at', ''),
                    'captured_at': datetime.now(timezone.utc).isoformat()}
    except (OSError, ValueError) as error:
        shutil.rmtree(snapshot, ignore_errors=True)
        info = {'available': False, 'message': 'Копия сохранения недоступна: ' + str(error)}
    (profile / '.developer-family-info.json').write_text(json.dumps(info, ensure_ascii=False))
    return info


@contextlib.contextmanager
def isolated_project(*, developer: bool = False, mode: str = "prologue", family_source: Path | None = None):
    """Tests start empty; only an explicit developer source can seed a session."""
    if family_source is not None and not developer:
        raise ValueError('Family snapshots are only available to developer sessions.')
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
            if developer:
                capture_family_snapshot(family_source, profile)
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
