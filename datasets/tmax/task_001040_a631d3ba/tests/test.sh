#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import stat
import subprocess
from pathlib import Path

import pytest

HOME = Path('/home/user')
DATA = HOME / 'data'
SOURCE = HOME / 'process_data.c'
SCRIPT = HOME / 'run_experiments.sh'
RESULTS = HOME / 'results.log'
BINARY = HOME / 'process_data'


def oracle(values):
    mean = 0.0
    variance = 100.0
    valid = missing = outliers = 0
    for value in values:
        if value is None:
            missing += 1
            continue
        if abs(value - mean) > 3.0 * math.sqrt(variance + 10.0):
            outliers += 1
            continue
        valid += 1
        mean = (10.0 * mean + variance * value) / (variance + 10.0)
        variance = (variance * 10.0) / (variance + 10.0)
    return f'Valid: {valid}, Missing: {missing}, Outliers: {outliers}, Final Mean: {mean:.2f}'


def read_values(path):
    values = []
    with open(path, 'r') as f:
        for raw in f:
            raw = raw.rstrip('\r\n')
            _, value = raw.split(',', 1)
            values.append(None if value == '' else int(value))
    return values


def write_csv(path, values):
    with open(path, 'w') as f:
        for i, value in enumerate(values, 1):
            f.write(f'{i},{"" if value is None else value}\n')


def save_path(path):
    if not path.exists():
        return None
    return (path.read_bytes(), stat.S_IMODE(path.stat().st_mode))


def restore_path(path, saved):
    if saved is None:
        if path.exists():
            path.unlink()
    else:
        data, mode = saved
        path.write_bytes(data)
        os.chmod(path, mode)


def test_process_data_c_exists():
    assert os.path.isfile('/home/user/process_data.c'), '/home/user/process_data.c is missing.'


def test_run_experiments_sh_exists():
    assert os.path.isfile('/home/user/run_experiments.sh'), '/home/user/run_experiments.sh is missing.'


def test_results_log_exists_and_correct():
    log_path = '/home/user/results.log'
    assert os.path.isfile(log_path), f'{log_path} is missing. Did you run the script?'

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        'File: exp1.csv | Valid: 3, Missing: 1, Outliers: 1, Final Mean: 4.84',
        'File: exp2.csv | Valid: 2, Missing: 2, Outliers: 0, Final Mean: 4.76'
    ]

    assert len(lines) == len(expected_lines), f'Expected {len(expected_lines)} lines in {log_path}, found {len(lines)}.'

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f'Line {i+1} in {log_path} is incorrect.\nExpected: {expected}\nActual: {actual}'


def test_c_program_compiles_and_handles_unseen_data(tmp_path):
    executable = tmp_path / 'process_data_test'
    compiled = subprocess.run(
        ['gcc', '-O2', str(SOURCE), '-lm', '-o', str(executable)],
        text=True, capture_output=True, timeout=20
    )
    assert compiled.returncode == 0, f'process_data.c did not compile:\n{compiled.stderr}'

    base = secrets.randbelow(17) - 8
    cases = [
        [base, None, base + 1, 700 + secrets.randbelow(200), base - 1,
         -800 - secrets.randbelow(200), base + 2],
        [30, 0, None, 29, 28],
        [None, None, None],
    ]

    for index, values in enumerate(cases):
        csv_path = tmp_path / f'case_{index}_{secrets.token_hex(5)}.csv'
        write_csv(csv_path, values)
        run = subprocess.run(
            [str(executable), str(csv_path)], text=True,
            capture_output=True, timeout=10
        )
        assert run.returncode == 0, f'Program failed on {csv_path}:\n{run.stderr}'
        assert run.stderr == '', f'Program unexpectedly wrote to stderr: {run.stderr!r}'
        assert run.stdout == oracle(values) + '\n', (
            f'Incorrect output for unseen input {values}.\n'
            f'Expected: {oracle(values)!r}\nActual: {run.stdout!r}'
        )


def test_experiment_script_runs_pipeline_appends_and_sorts():
    saved_results = save_path(RESULTS)
    saved_binary = save_path(BINARY)
    added = []
    token = secrets.token_hex(6)
    datasets = {
        f'audit_{token}_b.csv': [4, None, 5, 900, 3],
        f'audit_{token}_a.csv': [None, 12, 11, -900, 10],
    }

    try:
        for name, values in datasets.items():
            path = DATA / name
            write_csv(path, values)
            added.append(path)

        marker = f'APPEND-MARKER-{token}'
        RESULTS.write_text(marker + '\n')
        if BINARY.exists():
            BINARY.unlink()

        run = subprocess.run(
            ['bash', str(SCRIPT)], cwd=str(HOME), text=True,
            capture_output=True, timeout=30
        )
        assert run.returncode == 0, f'run_experiments.sh failed:\n{run.stdout}\n{run.stderr}'
        assert BINARY.is_file(), 'run_experiments.sh did not create /home/user/process_data'
        assert os.access(BINARY, os.X_OK), 'The compiled process_data is not executable'
        assert BINARY.read_bytes()[:4] == b'\x7fELF', 'process_data is not a compiled executable'

        csv_paths = sorted(DATA.glob('*.csv'), key=lambda p: p.name)
        expected = [marker] + [
            f'File: {path.name} | {oracle(read_values(path))}' for path in csv_paths
        ]
        actual = RESULTS.read_text().splitlines()
        assert actual == expected, (
            'run_experiments.sh must append one result for every CSV in alphabetical order.\n'
            f'Expected: {expected!r}\nActual: {actual!r}'
        )
    finally:
        for path in added:
            if path.exists():
                path.unlink()
        restore_path(RESULTS, saved_results)
        restore_path(BINARY, saved_binary)


def test_script_really_compiles_and_executes_the_c_artifact():
    saved_source = save_path(SOURCE)
    saved_results = save_path(RESULTS)
    saved_binary = save_path(BINARY)
    token = secrets.token_hex(12)
    extra = DATA / f'probe_{secrets.token_hex(6)}.csv'

    probe_source = f'''#include <stdio.h>
#include <string.h>
int main(int argc, char **argv) {{
    if (argc != 2) return 2;
    const char *name = strrchr(argv[1], '/');
    name = name ? name + 1 : argv[1];
    printf("PROBE-{token}-%s\\n", name);
    return 0;
}}
'''

    try:
        SOURCE.write_text(probe_source)
        extra.write_text('1,1\n')
        RESULTS.write_text(f'PROBE-MARKER-{token}\n')
        if BINARY.exists():
            BINARY.unlink()

        run = subprocess.run(
            ['bash', str(SCRIPT)], cwd=str(HOME), text=True,
            capture_output=True, timeout=30
        )
        assert run.returncode == 0, f'run_experiments.sh failed its compile/run probe:\n{run.stderr}'
        csv_names = sorted(path.name for path in DATA.glob('*.csv'))
        expected = [f'PROBE-MARKER-{token}'] + [
            f'File: {name} | PROBE-{token}-{name}' for name in csv_names
        ]
        assert RESULTS.read_text().splitlines() == expected, (
            'The script did not compile and execute process_data.c for each CSV in alphabetical order.'
        )
        assert BINARY.is_file() and BINARY.read_bytes()[:4] == b'\x7fELF'
    finally:
        if extra.exists():
            extra.unlink()
        restore_path(SOURCE, saved_source)
        restore_path(RESULTS, saved_results)
        restore_path(BINARY, saved_binary)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
