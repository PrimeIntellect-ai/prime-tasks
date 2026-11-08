#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
from pathlib import Path

SCRIPT = Path('/home/user/run_project.py')
PROJECT = Path('/home/user/legacy_project')
LOG = Path('/home/user/execution_log.txt')


def test_script_exists():
    assert SCRIPT.is_file(), f'The script {SCRIPT} does not exist.'


def install_and_run(files, expected):
    shutil.rmtree(PROJECT, ignore_errors=True)
    PROJECT.mkdir(parents=True)

    for relative_path, contents in files.items():
        destination = PROJECT / relative_path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(contents)

    if LOG.exists():
        LOG.unlink()

    result = subprocess.run(
        ['python3', str(SCRIPT)],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f'Interpreter exited with status {result.returncode}. '
        f'stdout={result.stdout!r}, stderr={result.stderr!r}'
    )
    assert LOG.is_file(), f'The execution log {LOG} does not exist. Did the script run?'

    with LOG.open() as f:
        lines = [line.strip() for line in f if line.strip()]
    assert lines == [str(value) for value in expected], (
        f'The execution log content is incorrect. '
        f'Expected {[str(value) for value in expected]}, but got {lines}.'
    )


def randomized_case():
    token = secrets.token_hex(6)
    dep_a = f'alpha_{token}.lasm'
    dep_b = f'beta_{token}.lasm'
    shared = f'shared_{token}.lasm'

    a = 7 + secrets.randbelow(80)
    b = 7 + secrets.randbelow(80)
    c = 1 + secrets.randbelow(30)
    d = 1 + secrets.randbelow(30)
    e = 7 + secrets.randbelow(80)
    f = 1 + secrets.randbelow(30)
    g = 7 + secrets.randbelow(80)
    h = 7 + secrets.randbelow(80)

    files = {
        f'entry/{token}/main.lasm': (
            f'INC X {a}\n'
            f'RUN {dep_a}\n'
            'OUT X\n'
            f'RUN {dep_b}\n'
            'OUT Y\n'
            f'DEC Z {d}\n'
            'OUT Z\n'
        ),
        f'one/deep/{dep_a}': (
            f'INC Y {b}\n'
            f'RUN {shared}\n'
            f'DEC X {c}\n'
            'OUT Y\n'
        ),
        f'two/{dep_b}': (
            f'RUN {shared}\n'
            f'INC X {e}\n'
            f'DEC Y {f}\n'
            'OUT X\n'
        ),
        f'elsewhere/more/{shared}': (
            f'INC X {g}\n'
            f'INC Z {h}\n'
            'OUT Z\n'
        ),
    }
    expected = [h, b, a + g - c, a + g - c + e, b - f, h - d]
    return files, expected


def test_interpreter_and_execution_log():
    # Private generated projects exercise recursive RUN ordering, basename lookup,
    # global state, integer INC/DEC operands, OUT order, and execute-once behavior.
    for _ in range(2):
        files, expected = randomized_case()
        install_and_run(files, expected)

    # Recreate the supplied project with the malformed register-valued DEC operand
    # corrected to the specified integer form, and retain the original log check.
    canonical = {
        'main.lasm': 'RUN init.lasm\nRUN compute.lasm\nINC X 10\nOUT X\n',
        'setup/init.lasm': 'INC X 5\nINC Y 2\n',
        'math/compute.lasm': 'RUN init.lasm\nRUN helper.lasm\nDEC X 5\nINC Z 20\nOUT Z\n',
        'utils/helper.lasm': 'INC Y 3\n',
    }
    install_and_run(canonical, [20, 10])
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
