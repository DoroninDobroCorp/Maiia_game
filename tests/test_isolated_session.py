"""Process-level developer launcher and cleanup checks; never write a family file."""
from pathlib import Path
import hashlib
import os
import subprocess
import sys
import time
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from isolated_session import isolated_project, run_godot, user_data_base


def family_fingerprint():
    root = user_data_base() / ('Godot/app_userdata/SUR' if sys.platform == 'darwin' else 'godot/app_userdata/SUR')
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
