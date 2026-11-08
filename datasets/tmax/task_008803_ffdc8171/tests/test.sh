#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
from pathlib import Path

HOME = Path('/home/user')
RAW = HOME / 'raw_sensor_logs.txt'
CLEAN = HOME / 'clean_logs.csv'
LOG = HOME / 'pipeline.log'
SCRIPT = HOME / 'process_logs.sh'
SOURCE = HOME / 'imputer.c'

ORIGINAL_INPUT = '''1620000000,SENS-ABC-1234,22.5,200
1620000010,SENS-ABC-1234,-,200
1620000020,SENS-ABC-1234,23.0,999
1620000030,BAD-ID-123,24.0,200
1620000040,SENS-XYZ-9876,-,500
1620000050,SENS-XYZ-9876,25.1,404
1620000060,SENS-DEF-0000,-,600
1620000070,SENS-QWE-5555,-,200
'''


def run_pipeline(trace=False):
    command = ['bash', '-x', str(SCRIPT)] if trace else [str(SCRIPT)]
    return subprocess.run(
        command,
        cwd=str(HOME),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
        check=False,
    )


def nonempty_lines(path):
    return [line.strip() for line in Path(path).read_text().splitlines() if line.strip()]


def test_00_execute_original_fixture():
    RAW.write_text(ORIGINAL_INPUT)
    CLEAN.unlink(missing_ok=True)
    LOG.unlink(missing_ok=True)
    result = run_pipeline()
    assert result.returncode == 0, (
        f'process_logs.sh failed on the supplied fixture with exit code '
        f'{result.returncode}. stderr: {result.stderr}'
    )


def test_process_logs_sh_executable():
    path = "/home/user/process_logs.sh"
    assert os.path.exists(path), f"Script {path} does not exist."
    assert os.access(path, os.X_OK), f"Script {path} is not executable."


def test_imputer_c_exists():
    path = "/home/user/imputer.c"
    assert os.path.exists(path), f"C program {path} does not exist."
    assert os.path.isfile(path), f"C program {path} is not a regular file."


def test_clean_logs_csv():
    path = "/home/user/clean_logs.csv"
    assert os.path.exists(path), f"Output file {path} does not exist."

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "1620000000,SENS-ABC-1234,22.5,200",
        "1620000010,SENS-ABC-1234,22.5,200",
        "1620000040,SENS-XYZ-9876,22.5,500",
        "1620000050,SENS-XYZ-9876,25.1,404",
        "1620000070,SENS-QWE-5555,25.1,200"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {path}, but found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch in {path}. Expected '{expected}', got '{actual}'."


def test_pipeline_log():
    path = "/home/user/pipeline.log"
    assert os.path.exists(path), f"Log file {path} does not exist."

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) > 0, f"{path} is empty."

    last_line = lines[-1]
    expected_log = "Discarded: 2, Imputed: 3"
    assert last_line == expected_log, f"Expected last line of {path} to be '{expected_log}', got '{last_line}'."


def test_c_program_compiles_and_processes_unseen_stream(tmp_path):
    executable = tmp_path / 'imputer_test'
    compiled = subprocess.run(
        ['gcc', '-std=c11', str(SOURCE), '-o', str(executable)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
        check=False,
    )
    assert compiled.returncode == 0, f'imputer.c did not compile: {compiled.stderr}'

    base = secrets.randbelow(500000000) + 1700000000
    first_temp = (secrets.randbelow(190) + 251) / 10.0
    last_temp = -(secrets.randbelow(80) + 11) / 10.0
    input_lines = [
        f'{base},SENS-RND-1000,-,100',
        f'{base+1},SENS-RND-1000,{first_temp:.1f},200',
        f'{base+2},SENS-RND-1000,-,99',
        f'{base+3},SENS-RND-1000,91.3,600',
        f'{base+4},SENS-RND-1000,-,599',
        f'{base+5},SENS-RND-1000,{last_temp:.1f},404',
        f'{base+6},SENS-RND-1000,-,500',
    ]
    expected = [
        f'{base},SENS-RND-1000,20.0,100',
        f'{base+1},SENS-RND-1000,{first_temp:.1f},200',
        f'{base+4},SENS-RND-1000,{first_temp:.1f},599',
        f'{base+5},SENS-RND-1000,{last_temp:.1f},404',
        f'{base+6},SENS-RND-1000,{last_temp:.1f},500',
    ]

    LOG.unlink(missing_ok=True)
    result = subprocess.run(
        [str(executable)],
        input='\n'.join(input_lines) + '\n',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
        check=False,
    )
    assert result.returncode == 0, f'Compiled imputer failed: {result.stderr}'
    assert result.stdout.splitlines() == expected, (
        f'Compiled imputer produced unexpected output. Expected {expected}, '
        f'got {result.stdout.splitlines()}'
    )
    assert LOG.exists(), 'Compiled imputer did not create pipeline.log.'
    assert nonempty_lines(LOG) == ['Discarded: 2, Imputed: 3'], (
        'Compiled imputer must append exactly one correct summary for this run.'
    )


def test_pipeline_on_unseen_fixture_uses_compiler_grep_and_c_behavior():
    base = secrets.randbelow(500000000) + 2200000000
    letters = ''.join(secrets.choice('ABCDEFGHIJKLMNOPQRSTUVWXYZ') for _ in range(3))
    digits1 = f'{secrets.randbelow(10000):04d}'
    digits2 = f'{secrets.randbelow(10000):04d}'
    valid1 = f'SENS-{letters}-{digits1}'
    valid2 = f'SENS-ZYX-{digits2}'
    temp1 = (secrets.randbelow(180) + 301) / 10.0
    temp2 = -(secrets.randbelow(70) + 12) / 10.0

    fixture = [
        f'{base},{valid1},-,200',
        f'{base+1},X{valid1},88.8,200',
        f'{base+2},{valid1}X,77.7,200',
        f'{base+3},SENS-aBC-1234,66.6,200',
        f'{base+4},SENS-ABC-123,55.5,200',
        f'{base+5},{valid1},{temp1:.1f},100',
        f'{base+6},{valid2},-,99',
        f'{base+7},{valid2},-,599',
        f'{base+8},{valid2},{temp2:.1f},404',
        f'{base+9},{valid1},-,500',
        f'{base+10},{valid1},93.2,600',
    ]
    expected = [
        f'{base},{valid1},20.0,200',
        f'{base+5},{valid1},{temp1:.1f},100',
        f'{base+7},{valid2},{temp1:.1f},599',
        f'{base+8},{valid2},{temp2:.1f},404',
        f'{base+9},{valid1},{temp2:.1f},500',
    ]

    RAW.write_text('\n'.join(fixture) + '\n')
    CLEAN.unlink(missing_ok=True)
    LOG.unlink(missing_ok=True)
    result = run_pipeline(trace=True)
    assert result.returncode == 0, (
        f'process_logs.sh failed on an unseen fixture: {result.stderr}'
    )
    assert CLEAN.exists(), 'Pipeline did not create clean_logs.csv.'
    assert CLEAN.read_text().splitlines() == expected, (
        f'Pipeline output on unseen input was wrong. Expected {expected}, '
        f'got {CLEAN.read_text().splitlines()}'
    )
    assert LOG.exists(), 'Pipeline did not create pipeline.log on the unseen run.'
    assert nonempty_lines(LOG) == ['Discarded: 2, Imputed: 3'], (
        'Each run must append exactly one summary with only status-discard counts.'
    )

    trace_lines = result.stderr.splitlines()
    used_grep = any(re.search(r'(^|[\s/])grep(?:\s|$)', line) for line in trace_lines)
    compiled_c = any(
        re.search(r'(^|[\s/])(?:gcc|cc|clang)(?:\s|$)', line) and 'imputer.c' in line
        for line in trace_lines
    )
    used_make = any(re.search(r'(^|[\s/])make(?:\s|$)', line) for line in trace_lines)
    script_text = SCRIPT.read_text(errors='replace')

    assert used_grep, 'process_logs.sh did not invoke grep while processing the input.'
    assert compiled_c or (used_make and 'imputer.c' in script_text), (
        'process_logs.sh did not compile imputer.c during the run.'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
