"""Process-level developer launcher and cleanup checks; never write a family file."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import time
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from isolated_session import isolated_project, run_godot, family_profile_directory, FAMILY_SNAPSHOT


def family_fingerprint():
    root = family_profile_directory()
    paths = list(root.glob('savegame*'))
    for child in ['artifacts', 'launch_registry']:
        if (root / child).is_dir():
            paths.extend((root / child).rglob('*'))
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in paths if p.is_file()}


class IsolationTests(unittest.TestCase):
    def setUp(self):
        self.before = family_fingerprint()

    def tearDown(self):
        self.assertEqual(self.before, family_fingerprint(), 'Family files changed')

    def test_real_developer_game_and_fresh_second_session(self):
        with isolated_project(developer=True, mode='adventures') as (project, profile):
            result = run_godot(project, ['--headless', '--quit-after', '8'], timeout=30)
            self.assertEqual(result, 0)
            import json
            state = json.loads((profile / 'savegame.json').read_text())
            self.assertEqual(state['station_name'], 'Тест трёх историй')
            self.assertEqual(len(state['phase_b']['published_versions']), 3)
            first_profile, first_project = profile, project
        self.assertFalse(first_profile.exists())
        self.assertFalse(first_project.exists())
        with isolated_project(developer=True) as (project, profile):
            self.assertNotEqual(profile, first_profile)
            self.assertFalse((profile / 'savegame.json').exists())
            self.assertEqual(run_godot(project, ['--headless', '--quit-after', '8'], timeout=30), 0)
            import json
            state = json.loads((profile / 'savegame.json').read_text())
            self.assertFalse(state['puzzle_solved'])
            self.assertEqual(state['phase_b']['quest_instances'], {})

    def test_overlapping_sessions_and_exception_cleanup(self):
        with isolated_project() as (project_a, profile_a):
            with self.assertRaisesRegex(RuntimeError, 'forced cleanup'):
                with isolated_project() as (project_b, profile_b):
                    self.assertNotEqual(profile_a, profile_b)
                    (profile_b / 'savegame.json').write_text('disposable')
                    self.assertFalse((profile_a / 'savegame.json').exists())
                    raise RuntimeError('forced cleanup')
            self.assertFalse(profile_b.exists())
            self.assertFalse(project_b.exists())
            self.assertTrue(profile_a.exists())

    def test_family_snapshot_is_private_and_refreshed_each_launch(self):
        with tempfile.TemporaryDirectory(prefix='sur-family-fixture-') as temporary:
            source = Path(temporary)
            state = {'schema_version': '1.3.0', 'station_name': 'Семейный образец',
                     'station_emblem': 'feather', 'desk_prop_id': 'owl',
                     'settings': {'muted': True}, 'family_marker': {'progress': 17}}
            (source / 'savegame.json').write_text(json.dumps(state, ensure_ascii=False))
            (source / 'artifacts').mkdir()
            (source / 'artifacts/drawing.png').write_bytes(b'original media')
            (source / 'launch_registry/working').mkdir(parents=True)
            (source / 'launch_registry/working/source.gd').write_text('original source')
            def fingerprint():
                return {str(p.relative_to(source)): p.read_bytes() for p in source.rglob('*') if p.is_file()}
            before = fingerprint()
            with isolated_project(developer=True, mode='family', family_source=source) as (project, profile):
                self.assertEqual((profile / FAMILY_SNAPSHOT / 'savegame.json').read_bytes(), before['savegame.json'])
                self.assertEqual(run_godot(project, ['--headless', '--quit-after', '8'], timeout=30), 0)
                copied = json.loads((profile / 'savegame.json').read_text())
                self.assertEqual(copied['station_name'], state['station_name'])
                self.assertEqual(copied['family_marker'], state['family_marker'])
                self.assertEqual((profile / 'artifacts/drawing.png').read_bytes(), b'original media')
                self.assertEqual((profile / 'launch_registry/working/source.gd').read_text(), 'original source')
                (profile / 'savegame.json').write_text('{}')
                (profile / 'artifacts/drawing.png').write_bytes(b'test changes')
                (profile / 'launch_registry/working/source.gd').write_text('test changes')
                self.assertEqual(before, fingerprint())
                self.assertEqual((profile / FAMILY_SNAPSHOT / 'artifacts/drawing.png').read_bytes(), b'original media')
            self.assertFalse(profile.exists())
            state['station_name'] = 'Новый семейный прогресс'
            (source / 'savegame.json').write_text(json.dumps(state, ensure_ascii=False))
            with isolated_project(developer=True, mode='auto', family_source=source) as (project, profile):
                self.assertEqual(run_godot(project, ['--headless', '--quit-after', '8'], timeout=30), 0)
                self.assertEqual(json.loads((profile / 'savegame.json').read_text())['station_name'], state['station_name'])

    def test_unavailable_family_source_is_explicit_and_safe(self):
        with tempfile.TemporaryDirectory(prefix='sur-family-fixture-') as temporary:
            source = Path(temporary)
            for contents in ('broken json', '{"schema_version":"99.0.0"}'):
                (source / 'savegame.json').write_text(contents)
                with isolated_project(developer=True, mode='auto', family_source=source) as (project, profile):
                    info = json.loads((profile / '.developer-family-info.json').read_text())
                    self.assertFalse(info['available'])
                    self.assertTrue(info['message'])
                    self.assertFalse((profile / FAMILY_SNAPSHOT).exists())
                    self.assertEqual(run_godot(project, ['--headless', '--quit-after', '8'], timeout=30), 0)
                self.assertEqual((source / 'savegame.json').read_text(), contents)

    @unittest.skipUnless(os.name == 'posix', 'symlink fixtures')
    def test_family_media_links_never_become_writable_session_links(self):
        with tempfile.TemporaryDirectory(prefix='sur-family-fixture-') as temporary:
            source = Path(temporary)
            (source / 'savegame.json').write_text('{"schema_version":"1.3.0"}')
            (source / 'real-media').mkdir()
            (source / 'real-media/keep').write_text('original')
            (source / 'artifacts').symlink_to(source / 'real-media', target_is_directory=True)
            with isolated_project(developer=True, family_source=source) as (_, profile):
                self.assertFalse(json.loads((profile / '.developer-family-info.json').read_text())['available'])
                self.assertFalse((profile / FAMILY_SNAPSHOT).exists())
            self.assertEqual((source / 'real-media/keep').read_text(), 'original')

    def test_developer_mode_refuses_unverified_directory(self):
        with isolated_project(developer=True) as (project, profile):
            (profile / '.sur-temporary-session.json').unlink()
            self.assertEqual(run_godot(project, ['--headless', '--quit-after', '8'], timeout=30), 1)
            self.assertFalse((profile / 'savegame.json').exists())

    @unittest.skipUnless(os.name == 'posix', 'POSIX process groups')
    def test_child_process_stops_when_session_ends(self):
        with isolated_project(developer=True) as (project, profile):
            (project / 'child_check.gd').write_text('''extends SceneTree
func _init(): call_deferred("run")
func run():
 var save = load("res://scripts/services/save_service.gd")
 save.use_test_storage("user://child_check_")
 var app = load("res://scenes/app/app_root.tscn").instantiate()
 root.add_child(app)
 var controller = app.adventure_controller
 var entry = controller._launcher().register_starter()
 if not entry.ok: quit(1); return
 controller._on_command("launch_work", {"launch_entry_id":entry.launch_entry_id})
 if controller.launched_processes.is_empty(): quit(1); return
 var f = FileAccess.open("user://child.pid", FileAccess.WRITE)
 f.store_string(str(controller.launched_processes[0]))
 f.close()
 await create_timer(0.3).timeout
 quit()
''')
            self.assertEqual(run_godot(project, ['--headless', '--script', 'child_check.gd'], timeout=10), 0)
            pid = int((profile / 'child.pid').read_text())
            self.assertGreater(pid, 0)
            running = True
            for _ in range(20):
                try:
                    os.kill(pid, 0)
                except ProcessLookupError:
                    running = False
                    break
                time.sleep(0.05)
            self.assertFalse(running, 'Session left its child process running')

    @unittest.skipUnless(sys.platform == 'darwin', 'macOS desktop entry')
    def test_installed_desktop_entry_twice(self):
        executable = Path.home() / 'Desktop/SUR — Разработчик.app/Contents/MacOS/SURDeveloper'
        self.assertTrue(executable.is_file(), 'Install via tools/install_developer_launcher.py')
        profiles = []
        for _ in range(2):
            result = subprocess.run([str(executable), '--headless', '--quit-after', '8'], timeout=30)
            self.assertEqual(result.returncode, 0)
            log = (Path(os.environ.get('TMPDIR', '/tmp')) / 'sur-developer-launch.log').read_text()
            self.assertNotIn('SCRIPT ERROR:', log)
            self.assertNotIn('\nERROR:', log)
            path = Path(next(line.split(': ', 1)[1] for line in log.splitlines()
                             if line.startswith('Временное хранилище: ')))
            profiles.append(path)
            self.assertFalse(path.exists(), 'Desktop session data survives exit')
        self.assertNotEqual(*profiles)


if __name__ == '__main__':
    unittest.main(verbosity=2)
