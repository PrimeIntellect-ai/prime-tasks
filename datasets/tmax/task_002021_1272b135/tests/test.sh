#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
import pytest

QA_DIR = '/home/user/qa'
RUNNER = f'{QA_DIR}/test_runner.sh'
RAW_LOG = f'{QA_DIR}/raw_benchmark.log'
PARSER = f'{QA_DIR}/parser.awk'
FINAL_REPORT = f'{QA_DIR}/final_report.txt'


def run_parser(input_path):
    result = subprocess.run(
        ['awk', '-f', PARSER, input_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
        check=False,
    )
    assert result.returncode == 0, f'parser.awk failed: {result.stderr}'
    return result.stdout


def test_runner_patched():
    path = RUNNER
    assert os.path.isfile(path), f'{path} is missing.'
    with open(path, 'r') as f:
        content = f.read()
    assert '<<< END COMPONENT' in content, 'test_runner.sh was not patched correctly (missing <<< END COMPONENT).'
    assert '<<< FINISH COMPONENT' not in content, 'test_runner.sh still contains <<< FINISH COMPONENT.'


def test_raw_benchmark_log_exists():
    path = RAW_LOG
    assert os.path.isfile(path), f'{path} is missing.'
    with open(path, 'r') as f:
        content = f.read()
    assert '<<< END COMPONENT' in content, 'raw_benchmark.log does not contain the expected markers from the patched runner.'


def test_parser_awk_exists():
    path = PARSER
    assert os.path.isfile(path), f'{path} is missing.'


def test_final_report_correct():
    path = FINAL_REPORT
    assert os.path.isfile(path), f'{path} is missing.'

    expected = [
        'C_Core_TOTAL:15ms',
        'Python_Worker_TOTAL:87ms',
        'Go_Service_TOTAL:33ms'
    ]

    with open(path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == expected, f'final_report.txt content is incorrect. Expected {expected}, got {lines}.'


def test_log_is_actual_runner_output():
    result = subprocess.run(
        [RUNNER],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=False,
    )
    assert result.returncode == 0, f'test_runner.sh failed: {result.stderr.decode(errors="replace")}'
    with open(RAW_LOG, 'rb') as f:
        saved_log = f.read()
    assert saved_log == result.stdout, 'raw_benchmark.log is not the standard output of the patched test_runner.sh.'


def test_saved_report_was_generated_by_parser():
    generated = run_parser(RAW_LOG)
    with open(FINAL_REPORT, 'r') as f:
        saved = f.read()
    assert saved == generated, 'final_report.txt does not exactly match parser.awk output for raw_benchmark.log.'
    expected = 'C_Core_TOTAL:15ms\nPython_Worker_TOTAL:87ms\nGo_Service_TOTAL:33ms\n'
    assert saved == expected, 'final_report.txt must contain exactly the required report and no extra text.'


def test_parser_state_machine_on_derived_random_input():
    token = secrets.token_hex(6)
    components = [f'Alpha_{token}', f'Beta_{token}', f'Gamma_{token}']
    values = [
        [secrets.randbelow(80) + 1, secrets.randbelow(80) + 1],
        [secrets.randbelow(80) + 1, secrets.randbelow(80) + 1, secrets.randbelow(80) + 1],
        [secrets.randbelow(80) + 1],
    ]

    lines = [
        '[NOISE] verifier setup',
        f'Iteration: {secrets.randbelow(900) + 100}ms',
    ]
    for index, (component, times) in enumerate(zip(components, values)):
        lines.append(f'>>> START COMPONENT: {component}')
        lines.append(f'[NOISE] block {index} warmup')
        for position, value in enumerate(times):
            lines.append(f'Iteration: {value}ms')
            lines.append(f'[NOISE] after sample {position}')
        lines.append('this Iteration: 99999ms line is noise')
        lines.append('<<< END COMPONENT')
        lines.append(f'Iteration: {secrets.randbelow(900) + 100}ms')
        lines.append('[NOISE] between blocks')

    expected = ''.join(
        f'{component}_TOTAL:{sum(times)}ms\n'
        for component, times in zip(components, values)
    )

    with tempfile.NamedTemporaryFile('w', delete=False) as f:
        f.write('\n'.join(lines) + '\n')
        path = f.name
    try:
        actual = run_parser(path)
    finally:
        os.unlink(path)

    assert actual == expected, (
        'parser.awk did not correctly enter component blocks, sum iteration times, '
        'ignore noise/out-of-block iterations, exit at end markers, and preserve block order. '
        f'Expected {expected!r}, got {actual!r}.'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
