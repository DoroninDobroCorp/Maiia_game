#!/usr/bin/env python3
"""Run Godot checks with a disposable project and a separate entire user://."""
import argparse
import hashlib
import json
from pathlib import Path
from isolated_session import isolated_project, run_godot

DEFAULTS = ['test_save_isolation', 'test_phase_a', 'test_phase_b', 'test_phase_c',
            'test_adventure_infrastructure', 'test_adventures_core',
            'test_adventure_content', 'test_adventure_journeys', 'test_adventure_ui',
            'test_adventure_app', 'test_adventure_authoring', 'test_adventure_experience',
            'test_adventure_scale']


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('suites', nargs='*', default=DEFAULTS)
    parser.add_argument('--render', action='store_true')
    parser.add_argument('--developer', action='store_true', help='Enable isolated developer UI for test_developer_session')
    parser.add_argument('--logs', type=Path)
    args = parser.parse_args()
    if args.logs:
        args.logs.mkdir(parents=True, exist_ok=True)
    with isolated_project(developer=args.developer) as (project, profile):
        print('ISOLATED user://', profile, flush=True)
        sentinel = json.dumps({'schema_version': '1.3.0', 'station_name': 'Family sentinel',
                               'station_emblem': 'feather', 'desk_prop_id': 'owl'})
        sentinels = ['savegame.json', 'savegame.backup.1.json', 'savegame.backup.2.json',
                     'savegame.backup.3.json', 'savegame.backup.json']
        for name in sentinels:
            (profile / name).write_text(sentinel)
        expected = {name: hashlib.sha256((profile / name).read_bytes()).hexdigest() for name in sentinels}
        for suite in args.suites:
            name = Path(suite).stem
            path = project / 'tests' / (name + '.gd')
            if not path.is_file():
                raise ValueError('Unknown test: ' + suite)
            options = [] if args.render else ['--headless']
            options += ['--script', 'tests/' + path.name]
            if args.render:
                options += ['--', '--render']
            print('RUN', name, flush=True)
            if args.logs:
                log = args.logs / (name + '.log')
                with log.open('w') as stream:
                    result = run_godot(project, options, timeout=180, stdout=stream, stderr=stream)
                output = log.read_text()
                errors = any(token in output for token in ['SCRIPT ERROR:', '\nERROR:', '[FAIL]'])
                print('EXIT', result, 'runtime_errors=', errors, log, flush=True)
                if errors:
                    return 1
            else:
                result = run_godot(project, options, timeout=180)
            if result:
                return result
            actual = {name: hashlib.sha256((profile / name).read_bytes()).hexdigest()
                      if (profile / name).is_file() else 'MISSING' for name in sentinels}
            if actual != expected:
                raise RuntimeError(name + ': changed default family sentinel files')
            print('DEFAULT PROFILE + BACKUPS UNCHANGED', flush=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
