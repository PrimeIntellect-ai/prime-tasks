#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import re
import subprocess
import tempfile
from decimal import Decimal
from pathlib import Path

SCRIPT = Path('/home/user/clean_pipeline.sh')
RAW = Path('/home/user/raw_data.csv')
CLEAN = Path('/home/user/clean_data.csv')
LOG = Path('/home/user/experiments.log')


def md5(path):
    h = hashlib.md5()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(4096), b''):
            h.update(chunk)
    return h.hexdigest()


def expected_log(input_path, output_path):
    line_count = len(output_path.read_text().splitlines())
    return f'IN:{md5(input_path)} OUT:{md5(output_path)} LINES:{line_count}'


def test_01_script_exists_and_is_valid_bash():
    assert SCRIPT.is_file(), f'Script {SCRIPT} does not exist.'
    assert not SCRIPT.is_symlink(), f'Script {SCRIPT} must be a regular file, not a symlink.'
    result = subprocess.run(['bash', '-n', str(SCRIPT)], capture_output=True, text=True)
    assert result.returncode == 0, f'Script is not valid Bash: {result.stderr}'

    source = SCRIPT.read_text()
    assignment = re.search(r'(?m)^\s*(?:export\s+)?LC_ALL\s*=\s*["\']?C["\']?\s*(?:;\s*export\s+LC_ALL\s*)?(?:#.*)?$', source)
    export_assignment = re.search(r'(?m)^\s*export\s+LC_ALL\s*=\s*["\']?C["\']?', source)
    separate_export = re.search(r'(?m)^\s*export\s+LC_ALL(?:\s|$)', source)
    assert assignment, 'The script must explicitly set LC_ALL=C.'
    assert export_assignment or separate_export, 'LC_ALL=C must be exported for processing commands.'


def test_02_clean_data_exists_and_correct():
    assert CLEAN.is_file(), f'Output file {CLEAN} does not exist.'
    expected_clean = 'id,value,score\n1,10.5,80\n5,3.14,100\n6,42.0,85\n9,99.9,10\n'
    clean_data = CLEAN.read_text()
    assert clean_data.strip() == expected_clean.strip(), (
        f'Content of {CLEAN} does not match expected output. Ensure filtering logic is correct.'
    )


def test_03_experiments_log_correct_and_exactly_one_line():
    assert RAW.is_file(), f'Input file {RAW} is missing.'
    assert CLEAN.is_file(), f'Output file {CLEAN} is missing.'
    assert LOG.is_file(), f'Log file {LOG} does not exist.'

    expected = expected_log(RAW, CLEAN)
    log_data = LOG.read_text()
    assert expected in log_data, (
        f'experiments.log does not contain the correct tracking string. Expected: {expected!r}'
    )
    assert log_data.splitlines() == [expected], (
        'The required run must append exactly one correctly formatted line to experiments.log.'
    )


def test_04_script_processes_arbitrary_paths_and_appends_once():
    original_log = LOG.read_bytes() if LOG.exists() else None
    rng = random.SystemRandom()
    try:
        for case_number in range(2):
            with tempfile.TemporaryDirectory(prefix='pipeline-check-') as td:
                td = Path(td)
                input_path = td / f'unpredictable-input-{rng.randrange(10**9)}.csv'
                output_path = td / f'custom-output-{rng.randrange(10**9)}.csv'

                rows = [
                    [str(rng.randrange(1000, 9999)), f'{rng.randrange(1, 900)}.25', 'ok'],
                    [str(rng.randrange(1000, 9999)), f'-{rng.randrange(1, 900)}.5', '95'],
                    [str(rng.randrange(1000, 9999)), '0', 'NA'],
                    [str(rng.randrange(1000, 9999)), '-0', 'kept'],
                    [str(rng.randrange(1000, 9999)), '7.75', 'NaN'],
                    [str(rng.randrange(1000, 9999)), '8.5', ''],
                    [str(rng.randrange(1000, 9999)), '1e2', 'nan'],
                    [str(rng.randrange(1000, 9999)), '3.5', 'NA '],
                ]
                rng.shuffle(rows)
                input_text = 'id,value,score\n' + ''.join(','.join(row) + '\n' for row in rows)
                input_path.write_text(input_text)

                kept = [row for row in rows if Decimal(row[1]) >= 0 and row[2] not in ('NaN', 'NA', '')]
                expected_output = 'id,value,score\n' + ''.join(','.join(row) + '\n' for row in kept)

                baseline = f'PREEXISTING-{case_number}\n'
                LOG.write_text(baseline)
                env = os.environ.copy()
                env['LC_ALL'] = 'C.UTF-8'
                result = subprocess.run(
                    ['bash', '-x', str(SCRIPT), str(input_path), str(output_path)],
                    capture_output=True, text=True, env=env, timeout=10
                )
                assert result.returncode == 0, f'Script failed on a valid custom input: {result.stderr}'
                assert output_path.is_file(), 'Script did not create the output path supplied as argument.'
                assert output_path.read_text() == expected_output, 'Filtering failed on a generated custom input.'

                trace = result.stderr
                assert re.search(r'(?m)^\+ .*LC_ALL=C(?:\s|$)', trace), (
                    'The successful execution did not actually execute an LC_ALL=C assignment.'
                )

                tracking = expected_log(input_path, output_path)
                assert LOG.read_text() == baseline + tracking + '\n', (
                    'Each invocation must preserve the existing log and append exactly one formatted line.'
                )
    finally:
        if original_log is None:
            LOG.unlink(missing_ok=True)
        else:
            LOG.write_bytes(original_log)


def test_05_script_rejects_argument_counts_other_than_two():
    original_log = LOG.read_bytes() if LOG.exists() else None
    try:
        with tempfile.TemporaryDirectory(prefix='pipeline-args-') as td:
            td = Path(td)
            input_path = td / 'input.csv'
            output_path = td / 'output.csv'
            input_path.write_text('id,value,score\n1,1,ok\n')

            for args in ([], [str(input_path)], [str(input_path), str(output_path), 'extra']):
                marker = b'ARGUMENT-TEST-BASELINE\n'
                LOG.write_bytes(marker)
                output_path.write_bytes(b'UNCHANGED\n')
                result = subprocess.run(
                    ['bash', str(SCRIPT), *args], cwd=td,
                    capture_output=True, text=True, timeout=10
                )
                assert result.returncode != 0, f'Script accepted invalid argument list: {args!r}'
                assert LOG.read_bytes() == marker, 'Invalid invocation must not append an experiment record.'
                assert output_path.read_bytes() == b'UNCHANGED\n', 'Invalid invocation modified an output file.'
    finally:
        if original_log is None:
            LOG.unlink(missing_ok=True)
        else:
            LOG.write_bytes(original_log)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
