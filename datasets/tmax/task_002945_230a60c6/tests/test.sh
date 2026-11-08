#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import re
import shutil
import signal
import subprocess
import uuid

import pytest

PROJECT = '/home/user/project'
DATA = '/home/user/data'
PROCESSOR = os.path.join(PROJECT, 'processor')
SOURCE = os.path.join(PROJECT, 'processor.cpp')
RUN_ALL = os.path.join(PROJECT, 'run_all.sh')


def run_with_timeout(argv, **kwargs):
    kwargs.setdefault('text', True)
    kwargs.setdefault('capture_output', True)
    kwargs.setdefault('timeout', 8)
    kwargs.setdefault('start_new_session', True)
    try:
        return subprocess.run(argv, **kwargs)
    except subprocess.TimeoutExpired as exc:
        if exc.pid is not None:
            try:
                os.killpg(exc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        pytest.fail(f'Command did not terminate cleanly: {argv}')


@pytest.fixture(scope='session', autouse=True)
def verify_and_build_processor():
    assert os.path.isfile(SOURCE), f'{SOURCE} is missing'
    assert os.path.isfile(PROCESSOR), f'{PROCESSOR} is missing; processor was not compiled'
    assert os.access(PROCESSOR, os.X_OK), f'{PROCESSOR} is not executable'
    with open(PROCESSOR, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f'{PROCESSOR} is not a compiled executable'
    assert os.stat(PROCESSOR).st_mtime_ns >= os.stat(SOURCE).st_mtime_ns, \
        'processor is older than processor.cpp; it does not appear to have been recompiled'

    verified = '/tmp/verified_processor'
    result = subprocess.run(
        ['g++', SOURCE, '-o', verified],
        cwd=PROJECT,
        text=True,
        capture_output=True,
    )
    assert result.returncode == 0, f'processor.cpp does not compile:\n{result.stderr}'
    shutil.copy2(verified, PROCESSOR)
    os.chmod(PROCESSOR, 0o755)


def test_success_log_exists_and_correct():
    log_file = '/home/user/success.log'
    assert os.path.isfile(log_file), f"Expected output file {log_file} does not exist. Did you run the script and redirect output?"

    with open(log_file, 'r') as f:
        content = f.read()

    assert "/home/user/data/file1.txt: Hello from file1" in content, "Missing expected output for file1.txt in success.log"
    assert "/home/user/data/file 2.txt: Hello from file 2" in content, "Missing expected output for 'file 2.txt' in success.log. Did you fix the quoting issue in run_all.sh?"


def test_run_all_sh_fixed():
    assert os.path.isfile(RUN_ALL), f'{RUN_ALL} is missing'
    assert os.access(RUN_ALL, os.X_OK), f'{RUN_ALL} is not executable'

    with open(RUN_ALL, 'r') as f:
        content = f.read()

    # Retain the original source assertion.
    assert re.search(r'"\$file"|\$\{file\}|"\$\{file\}"', content) is not None, "run_all.sh does not seem to have $file properly quoted to handle spaces."

    token = uuid.uuid4().hex
    injected = os.path.join(DATA, f'verifier {token} [space].txt')
    try:
        with open(injected, 'w') as f:
            f.write(f'first-{token}\nsecond line {token}\n')

        expected = []
        for name in os.listdir(DATA):
            path = os.path.join(DATA, name)
            if not os.path.isfile(path):
                continue
            with open(path, 'r') as f:
                for line in f.read().splitlines():
                    expected.append(f'{path}: {line}')

        result = run_with_timeout([RUN_ALL], cwd=PROJECT)
        assert result.returncode == 0, f'run_all.sh exited with {result.returncode}: {result.stderr}'
        assert result.stderr == '', f'run_all.sh produced unexpected errors: {result.stderr}'
        assert collections.Counter(result.stdout.splitlines()) == collections.Counter(expected), \
            'run_all.sh did not process every data file exactly once with the required filename prefix'
    finally:
        try:
            os.remove(injected)
        except FileNotFoundError:
            pass


def test_processor_cpp_fixed():
    with open(SOURCE, 'r') as f:
        content = f.read()

    # Retain the original source assertions.
    assert re.search(r'retries\s*(==|>=|>)\s*(3|2)', content) is not None, "processor.cpp does not seem to check if retries == 3."
    assert "Error: Could not read" in content, "processor.cpp does not print the required error message."
    assert "cerr" in content, "processor.cpp does not print the error to standard error."

    missing = os.path.join('/tmp', f'missing file {uuid.uuid4().hex}.txt')
    result = run_with_timeout([PROCESSOR, missing], cwd=PROJECT)
    assert result.returncode >= 0, 'processor terminated due to a signal or segmentation fault'
    expected_error = f'Error: Could not read {missing}'
    error_lines = result.stderr.splitlines()
    assert expected_error in error_lines, \
        f'processor did not print the required error after failed retries; stderr was: {result.stderr!r}'
    assert error_lines.count(expected_error) == 1, 'processor printed the final read error more than once'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
