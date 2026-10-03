#!/usr/bin/env python3
"""Desktop developer launcher: every invocation starts an expendable session."""
import argparse
from isolated_session import isolated_project, run_godot, family_profile_directory


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', choices=['family', 'prologue', 'adventures'], default=None)
    parser.add_argument('--headless', action='store_true')
    parser.add_argument('--quit-after', type=int)
    args = parser.parse_args()
    with isolated_project(developer=True, mode=args.mode or 'auto',
                          family_source=family_profile_directory()) as (project, profile):
        print('SUR: временная сессия разработчика. Прогресс удалится после выхода.', flush=True)
        print('Временное хранилище:', profile, flush=True)
        options = ['--headless'] if args.headless else []
        if args.quit_after is not None:
            options += ['--quit-after', str(args.quit_after)]
        return run_godot(project, options)


if __name__ == '__main__':
    raise SystemExit(main())
