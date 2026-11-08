#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import pathlib
import random
import re
import shutil
import subprocess
import tempfile

import pytest

WORKSPACE = pathlib.Path('/home/user/migration')


def run(cmd, **kwargs):
    kwargs.setdefault('text', True)
    kwargs.setdefault('stdout', subprocess.PIPE)
    kwargs.setdefault('stderr', subprocess.STDOUT)
    kwargs.setdefault('timeout', 120)
    result = subprocess.run(cmd, **kwargs)
    assert result.returncode == 0, f"Command failed ({result.returncode}): {cmd}\n{result.stdout}"
    return result


@pytest.fixture(scope='session', autouse=True)
def build_and_exercise_submission():
    cmake_file = WORKSPACE / 'CMakeLists.txt'
    extension_file = WORKSPACE / 'extension.c'
    test_file = WORKSPACE / 'test.py'
    assert cmake_file.is_file(), 'CMakeLists.txt is missing.'
    assert extension_file.is_file(), 'extension.c is missing.'
    assert test_file.is_file(), 'test.py is missing.'

    build_dir = pathlib.Path(tempfile.mkdtemp(prefix='migration-build-'))
    run([
        'cmake', '-S', str(WORKSPACE), '-B', str(build_dir),
        '-DCMAKE_BUILD_TYPE=Debug', '-DCMAKE_EXPORT_COMPILE_COMMANDS=ON'
    ])
    run(['cmake', '--build', str(build_dir), '--clean-first', '--parallel', '2'])

    compile_commands = build_dir / 'compile_commands.json'
    assert compile_commands.is_file(), 'The CMake build did not emit compile_commands.json.'
    commands = json.loads(compile_commands.read_text(encoding='utf-8'))
    compiled_files = {pathlib.Path(entry['file']).resolve() for entry in commands}
    assert extension_file.resolve() in compiled_files, 'The CMake target did not compile extension.c.'

    candidates = [pathlib.Path(p) for p in glob.glob(str(build_dir / '**' / 'string_ops*.so'), recursive=True)]
    assert candidates, 'The fresh CMake build did not produce a string_ops shared module.'
    module = max(candidates, key=lambda p: p.stat().st_mtime_ns)
    assert module.read_bytes()[:4] == b'\x7fELF', 'string_ops is not a native ELF shared module.'

    dynamic_info = run(['readelf', '-d', str(module)]).stdout
    assert re.search(r'NEEDED.*libpython3', dynamic_info, re.IGNORECASE), \
        'The string_ops module is not linked against a Python 3 shared library.'
    assert not re.search(r'NEEDED.*libpython2', dynamic_info, re.IGNORECASE), \
        'The string_ops module is still linked against Python 2.'

    for old_module in WORKSPACE.glob('string_ops*.so'):
        old_module.unlink()
    installed_module = WORKSPACE / module.name
    shutil.copy2(module, installed_module)

    # Execute the requested command against the freshly built extension. This
    # overwrites any fabricated or stale success.log before its assertions run.
    exact_command = 'valgrind --leak-check=full python3 test.py > /home/user/migration/success.log 2>&1'
    result = subprocess.run(['bash', '-c', exact_command], cwd=WORKSPACE, timeout=120)
    assert result.returncode == 0, 'The required valgrind command failed.'

    # Independently exercise the native module on verifier-generated inputs and
    # repeat calls enough that the original strdup leak is detected by Valgrind.
    probe_dir = pathlib.Path(tempfile.mkdtemp(prefix='migration-probe-'))
    probe_module = probe_dir / module.name
    shutil.copy2(module, probe_module)
    rng = random.Random(918273)
    values = ['', 'a', 'ab', 'Happy Python Migration!', '0123456789']
    alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 !?_-'
    values.extend(''.join(rng.choice(alphabet) for _ in range(rng.randint(1, 96))) for _ in range(80))
    probe = probe_dir / 'probe.py'
    probe.write_text(
        'import string_ops\n'
        f'values = {values!r}\n'
        'for _ in range(200):\n'
        '    for value in values:\n'
        '        actual = string_ops.reverse_string(value)\n'
        '        expected = value[::-1]\n'
        '        if actual != expected:\n'
        '            raise AssertionError((value, actual, expected))\n',
        encoding='utf-8'
    )
    env = os.environ.copy()
    env['PYTHONNOUSERSITE'] = '1'
    checked = subprocess.run([
        'valgrind', '--leak-check=full', '--show-leak-kinds=definite',
        '--errors-for-leak-kinds=definite', '--error-exitcode=97',
        'python3', str(probe)
    ], cwd=probe_dir, env=env, text=True, stdout=subprocess.PIPE,
       stderr=subprocess.STDOUT, timeout=180)
    assert checked.returncode == 0, f'Behavioral or Valgrind check failed:\n{checked.stdout}'
    assert 'definitely lost: 0 bytes in 0 blocks' in checked.stdout, \
        f'The freshly built extension definitely leaks memory:\n{checked.stdout}'


def test_success_log_exists():
    path = "/home/user/migration/success.log"
    assert os.path.isfile(path), f"File {path} does not exist. Ensure you ran the exact valgrind command to generate this log file."


def test_success_log_output():
    path = "/home/user/migration/success.log"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()

    assert "Happy Python Migration!" in content, "The log does not contain the correctly processed string 'Happy Python Migration!'. Check if the C extension works correctly."


def test_success_log_valgrind_leak_check():
    path = "/home/user/migration/success.log"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()

    expected_leak_status = "definitely lost: 0 bytes in 0 blocks"
    assert expected_leak_status in content, f"The Valgrind leak check did not report '{expected_leak_status}'. The memory leak might not be fixed properly, or the valgrind command was not run correctly."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
