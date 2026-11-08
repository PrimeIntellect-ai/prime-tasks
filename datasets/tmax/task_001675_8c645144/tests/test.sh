#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import shutil
import stat
import subprocess
import tempfile

SCRIPT = '/home/user/plan_build.py'
REPO = '/home/user/polybuild'
PLAN = '/home/user/build_plan.sh'
NEW_CACHE = '/home/user/new_cache.json'


def run_planner():
    assert os.path.isfile(SCRIPT), f'{SCRIPT} does not exist or is not a regular file.'
    result = subprocess.run(
        ['python3', SCRIPT],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f'{SCRIPT} failed with exit code {result.returncode}. '
        f'stdout={result.stdout!r}, stderr={result.stderr!r}'
    )


def read_plan():
    assert os.path.exists(PLAN), f'{PLAN} does not exist.'
    with open(PLAN, 'r') as f:
        return [line.strip() for line in f if line.strip()]


def read_cache():
    assert os.path.exists(NEW_CACHE), f'{NEW_CACHE} does not exist.'
    with open(NEW_CACHE, 'r') as f:
        return json.load(f)


def test_original_fixture_outputs():
    run_planner()

    lines = read_plan()
    expected_lines = [
        '#!/bin/bash',
        'python build_api.py',
        'npm run build'
    ]
    assert lines == expected_lines, (
        f'Contents of {PLAN} are incorrect. Got {lines}, expected {expected_lines}.'
    )

    cache_data = read_cache()
    expected_cache = {
        'utils': 'gcc -o utils utils.c',
        'core': 'gcc -o core core.c',
        'api': 'python build_api.py',
        'frontend': 'npm run build',
        'docs': 'mkdocs build'
    }
    assert cache_data == expected_cache, (
        f'Contents of {NEW_CACHE} are incorrect. Got {cache_data}, expected {expected_cache}.'
    )


def test_planner_on_changed_repository_and_cache():
    token = secrets.token_hex(6)
    names = {key: f'{key}_{token}' for key in 'abcdefg'}
    targets = [
        {'name': names['a'], 'deps': [], 'cmd': f'echo clean-root-{token}'},
        {'name': names['b'], 'deps': [], 'cmd': f'echo changed-root-{token}'},
        {'name': names['c'], 'deps': [names['a']], 'cmd': f'echo clean-child-{token}'},
        {'name': names['d'], 'deps': [names['b']], 'cmd': f'echo direct-cascade-{token}'},
        {'name': names['e'], 'deps': [names['d'], names['c']], 'cmd': f'echo transitive-cascade-{token}'},
        {'name': names['f'], 'deps': [names['a']], 'cmd': f'echo uncached-{token}'},
        {'name': names['g'], 'deps': [names['c']], 'cmd': f'echo clean-deep-{token}'},
    ]

    cache = {target['name']: target['cmd'] for target in targets}
    cache[names['b']] = f'echo old-command-{token}'
    del cache[names['f']]
    cache[f'stale_{token}'] = f'echo stale-{token}'

    backup_root = tempfile.mkdtemp(prefix='polybuild-verifier-')
    repo_backup = os.path.join(backup_root, 'polybuild')
    shutil.copytree(REPO, repo_backup)

    saved_outputs = {}
    for path in (PLAN, NEW_CACHE):
        if os.path.exists(path):
            with open(path, 'rb') as f:
                saved_outputs[path] = (f.read(), stat.S_IMODE(os.stat(path).st_mode))
        else:
            saved_outputs[path] = None

    try:
        shutil.rmtree(REPO)
        os.makedirs(REPO)

        shuffled = list(targets)
        random.SystemRandom().shuffle(shuffled)
        for index, target in enumerate(shuffled):
            directory = os.path.join(REPO, f'group_{index % 3}', f'component_{index}')
            os.makedirs(directory, exist_ok=True)
            with open(os.path.join(directory, 'build.json'), 'w') as f:
                json.dump(target, f)

        with open(os.path.join(REPO, 'cache.json'), 'w') as f:
            json.dump(cache, f)

        for path in (PLAN, NEW_CACHE):
            if os.path.lexists(path):
                os.remove(path)

        run_planner()

        # Independently derive dirty targets from the generated graph and cache.
        by_name = {target['name']: target for target in targets}
        expected_cache = {name: target['cmd'] for name, target in by_name.items()}
        dirty = {
            name
            for name, target in by_name.items()
            if name not in cache or cache[name] != target['cmd']
        }
        changed = True
        while changed:
            changed = False
            for name, target in by_name.items():
                if name not in dirty and any(dep in dirty for dep in target['deps']):
                    dirty.add(name)
                    changed = True

        lines = read_plan()
        assert lines and lines[0] == '#!/bin/bash', 'Build plan must begin with #!/bin/bash.'
        commands = lines[1:]
        command_to_name = {target['cmd']: target['name'] for target in targets}
        expected_commands = {by_name[name]['cmd'] for name in dirty}

        assert len(commands) == len(set(commands)), 'Build plan contains duplicate commands.'
        assert set(commands) == expected_commands, (
            f'Build plan commands are incorrect. Got {commands}, expected only {expected_commands}.'
        )

        positions = {command_to_name[command]: index for index, command in enumerate(commands)}
        for name in dirty:
            for dependency in by_name[name]['deps']:
                if dependency in dirty:
                    assert positions[dependency] < positions[name], (
                        f'Dependency {dependency} must be built before {name}.'
                    )

        assert read_cache() == expected_cache, (
            'new_cache.json must contain exactly every current target and its current command.'
        )
    finally:
        if os.path.exists(REPO):
            shutil.rmtree(REPO)
        shutil.copytree(repo_backup, REPO)

        for path, saved in saved_outputs.items():
            if os.path.lexists(path):
                os.remove(path)
            if saved is not None:
                data, mode = saved
                with open(path, 'wb') as f:
                    f.write(data)
                os.chmod(path, mode)
        shutil.rmtree(backup_root)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
