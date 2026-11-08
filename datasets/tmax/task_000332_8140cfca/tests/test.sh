#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'RUNNER_EOF' > /tmp/run_candidate.py
import os
import runpy
import sys

OUTPUT = os.path.realpath('/home/user/connection_history.json')
WRITE_FLAGS = os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_TRUNC | os.O_APPEND

def resolved(path):
    if isinstance(path, int):
        return None
    try:
        return os.path.realpath(os.fsdecode(path))
    except Exception:
        return None

def audit(event, args):
    if event == 'open':
        path = resolved(args[0])
        mode = args[1]
        flags = args[2]
        writing = (isinstance(mode, str) and any(c in mode for c in 'wax+')) or (isinstance(flags, int) and bool(flags & WRITE_FLAGS))
        if writing and path != OUTPUT:
            raise PermissionError(f'Archive processing must not write files to disk: {path}')
    elif event in {'os.mkdir', 'os.rmdir', 'os.link', 'os.symlink', 'os.truncate'}:
        raise PermissionError(f'Filesystem mutation is not allowed during archive processing: {event}')
    elif event in {'os.remove', 'os.unlink'}:
        if resolved(args[0]) != OUTPUT:
            raise PermissionError(f'Filesystem mutation is not allowed during archive processing: {event}')
    elif event in {'os.rename', 'os.replace'}:
        if resolved(args[0]) != OUTPUT or resolved(args[1]) != OUTPUT:
            raise PermissionError(f'Filesystem mutation is not allowed during archive processing: {event}')
    elif event in {'subprocess.Popen', 'os.system', 'os.posix_spawn', 'os.posix_spawnp'}:
        raise PermissionError('External archive tools are not allowed')

sys.addaudithook(audit)
sys.argv = [sys.argv[1]]
runpy.run_path(sys.argv[0], run_name='__main__')
RUNNER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import io
import json
import os
import random
import subprocess
import tarfile

MASTER = '/home/user/server_history.tar'
OUTPUT = '/home/user/connection_history.json'
RUNNER = '/tmp/run_candidate.py'
ORIGINAL_EXPECTED = {
    'state_01.tar.gz': 150,
    'state_03.tar.gz': 200,
    'state_04.tar.gz': 500,
}

def read_and_assert_output(expected):
    assert os.path.exists(OUTPUT), f'Output file {OUTPUT} does not exist. The script must generate this file.'
    assert os.path.isfile(OUTPUT), f'{OUTPUT} is not a file.'
    try:
        with open(OUTPUT, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'{OUTPUT} is not a valid JSON file.') from exc
    assert data == expected, f'The content of {OUTPUT} is incorrect. Expected {expected}, but got {data}.'

def nested_archive(path, value):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode='w:gz') as tf:
        content = f'PORT=8080\nMAX_CONNECTIONS={value}\n'.encode()
        info = tarfile.TarInfo(path)
        info.size = len(content)
        tf.addfile(info, io.BytesIO(content))
    return buf.getvalue()

def make_dynamic_master():
    rng = random.SystemRandom()
    suffixes = rng.sample(range(10, 99), 4)
    names = [f'state_{n}.tar.gz' for n in suffixes]
    values = rng.sample(range(1001, 9000), 3)
    paths = [
        'etc/app/settings.conf',
        'opt/service/deep/config/settings.conf',
        'var/lib/app/releases/current/settings.conf',
    ]
    entries = {
        names[0]: nested_archive(paths[0], values[0]),
        names[1]: os.urandom(3073),
        names[2]: nested_archive(paths[1], values[1]),
        names[3]: nested_archive(paths[2], values[2]),
    }
    outer = io.BytesIO()
    with tarfile.open(fileobj=outer, mode='w') as tf:
        for name, payload in entries.items():
            info = tarfile.TarInfo(name)
            info.size = len(payload)
            tf.addfile(info, io.BytesIO(payload))
    return outer.getvalue(), {
        names[0]: values[0],
        names[2]: values[1],
        names[3]: values[2],
    }

def candidate_scripts():
    found = []
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if not os.path.islink(os.path.join(root, d))]
        for name in files:
            path = os.path.join(root, name)
            if name.endswith('.py') and os.path.isfile(path) and not os.path.islink(path):
                found.append(path)
    return sorted(found)

def reject_disk_extraction_api(path):
    with open(path, 'r', encoding='utf-8') as f:
        tree = ast.parse(f.read(), filename=path)
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr in {'extract', 'extractall'}:
            raise AssertionError(f'{path} uses tar extraction to disk ({node.func.attr})')

def execute(path):
    if os.path.lexists(OUTPUT):
        os.unlink(OUTPUT)
    env = os.environ.copy()
    env['PYTHONDONTWRITEBYTECODE'] = '1'
    result = subprocess.run(
        ['python3', '-I', RUNNER, path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
        env=env,
    )
    assert result.returncode == 0, f'{path} failed when executed:\n{result.stdout}\n{result.stderr}'

def test_script_executes_and_processes_archives_in_memory():
    scripts = candidate_scripts()
    assert scripts, 'No Python script was created under /home/user.'

    with open(MASTER, 'rb') as f:
        original_master = f.read()
    dynamic_master, dynamic_expected = make_dynamic_master()
    failures = []
    winner = None

    try:
        for script in scripts:
            try:
                reject_disk_extraction_api(script)

                with open(MASTER, 'wb') as f:
                    f.write(original_master)
                execute(script)
                read_and_assert_output(ORIGINAL_EXPECTED)

                with open(MASTER, 'wb') as f:
                    f.write(dynamic_master)
                execute(script)
                read_and_assert_output(dynamic_expected)
                winner = script
                break
            except Exception as exc:
                failures.append(f'{script}: {exc}')

        assert winner is not None, 'No Python script correctly processed both the supplied and dynamically generated archives in memory.\n' + '\n'.join(failures)

        with open(MASTER, 'wb') as f:
            f.write(original_master)
        execute(winner)
        read_and_assert_output(ORIGINAL_EXPECTED)
    finally:
        with open(MASTER, 'wb') as f:
            f.write(original_master)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
