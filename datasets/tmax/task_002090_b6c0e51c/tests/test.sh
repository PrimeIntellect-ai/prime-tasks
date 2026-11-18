#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess
from pathlib import Path

HOME = Path('/home/user')
INPUT = HOME / 'sensor_data.csv'
OUTPUT = HOME / 'anomalies.csv'

ORIGINAL_INPUT = '''timestamp,sensor_id,value
1000, s1 ,10.0
1000,s1,10.0
1001,S1,12.0
1002,S1,11.0
1002,S1,11.0
1003,s1,-5.0
1004,S1,30.0
1005,s2,50.0
1006,S2,bad
1007,S2,52.0
1008,S2,110.0
1005,S2,50.0
1009,S1,15.0
1010,S1,50.0
'''

ORIGINAL_EXPECTED = '''timestamp,sensor_id,value,rolling_avg
1004,S1,30.00,11.00
1008,S2,110.00,51.00
1010,S1,50.00,18.67'''


def normalized_lines(content):
    return [line.strip() for line in content.strip().splitlines() if line.strip()]


def assert_original_output():
    assert OUTPUT.is_file(), f'Output file {OUTPUT} is missing.'
    actual_lines = normalized_lines(OUTPUT.read_text())
    expected_lines = normalized_lines(ORIGINAL_EXPECTED)
    assert len(actual_lines) == len(expected_lines), (
        f'Expected {len(expected_lines)} lines in anomalies.csv, got {len(actual_lines)}.'
    )
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f'Mismatch on line {i + 1}:\nExpected: {expected}\nActual:   {actual}'
        )


def derive_expected(csv_text):
    last_timestamp = {}
    windows = {}
    output = ['timestamp,sensor_id,value,rolling_avg']

    for raw_line in csv_text.splitlines()[1:]:
        if not raw_line.strip():
            continue
        fields = raw_line.split(',')
        assert len(fields) == 3
        timestamp_text, sensor_text, value_text = fields
        timestamp = int(timestamp_text)
        sensor = sensor_text.strip().upper()
        try:
            value = float(value_text)
        except ValueError:
            continue
        if value < 0:
            continue
        if sensor in last_timestamp and timestamp <= last_timestamp[sensor]:
            continue

        previous = windows.setdefault(sensor, [])
        if previous:
            rolling_avg = sum(previous) / len(previous)
            if value > 2.0 * rolling_avg:
                output.append(f'{timestamp},{sensor},{value:.2f},{rolling_avg:.2f}')

        last_timestamp[sensor] = timestamp
        previous.append(value)
        if len(previous) > 3:
            del previous[0]

    return '\n'.join(output)


def make_hidden_fixture():
    rng = random.SystemRandom()
    token_a = ''.join(rng.choice(string.ascii_lowercase) for _ in range(9))
    token_b = ''.join(rng.choice(string.ascii_lowercase) for _ in range(9))
    base_a = rng.randrange(2000, 200000)
    base_b = base_a + rng.randrange(100, 500)

    rows = [
        (base_a, f'  {token_a.lower()}  ', '100'),
        (base_b, f' {token_b.lower()} ', '4'),
        (base_a, token_a.upper(), '777'),
        (base_a + 1, token_a.upper(), '1'),
        (base_b + 1, token_b.upper(), '6'),
        (base_a + 2, token_a.lower(), '-7'),
        (base_a + 2, f' {token_a.upper()} ', '1'),
        (base_b + 2, token_b.lower(), '8'),
        (base_a + 3, token_a.lower(), '1'),
        (base_b + 3, f'  {token_b.upper()} ', '12'),
        (base_a + 4, token_a.upper(), '3'),
        (base_b + 4, token_b.lower(), '30'),
        (base_a + 1, token_a.lower(), '999'),
        (base_b + 5, token_b.upper(), 'bad'),
        (base_b + 5, token_b.lower(), '2'),
        (base_b + 6, f' {token_b.upper()} ', '50'),
    ]
    return 'timestamp,sensor_id,value\n' + ''.join(
        f'{timestamp},{sensor},{value}\n' for timestamp, sensor, value in rows
    )


def run_program(binary, fixture):
    INPUT.write_text(fixture)
    try:
        OUTPUT.unlink()
    except FileNotFoundError:
        pass
    result = subprocess.run(
        [str(binary)], cwd=str(HOME), stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=5
    )
    assert result.returncode == 0, (
        f'Program exited with {result.returncode}. stderr: {result.stderr}'
    )
    assert OUTPUT.is_file(), 'Program did not create /home/user/anomalies.csv.'


def test_cpp_program_compiles_runs_and_implements_etl():
    sources = sorted(
        p for p in HOME.rglob('*.cpp')
        if p.is_file() and not p.is_symlink()
    )
    assert sources, 'No C++ source file was found under /home/user.'

    hidden_fixture = make_hidden_fixture()
    hidden_expected = normalized_lines(derive_expected(hidden_fixture))
    failures = []
    winner = None

    for index, source in enumerate(sources):
        binary = Path(f'/tmp/submission_program_{index}')
        compile_result = subprocess.run(
            ['g++', '-std=c++17', '-O2', str(source), '-o', str(binary)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
        )
        if compile_result.returncode != 0:
            failures.append(f'{source}: compilation failed: {compile_result.stderr[-1000:]}')
            continue

        try:
            run_program(binary, ORIGINAL_INPUT)
            assert_original_output()

            run_program(binary, hidden_fixture)
            actual_hidden = normalized_lines(OUTPUT.read_text())
            assert actual_hidden == hidden_expected, (
                'Incorrect output for an additional generated fixture.\n'
                f'Expected: {hidden_expected}\nActual: {actual_hidden}'
            )
            winner = binary
            break
        except (AssertionError, subprocess.TimeoutExpired) as exc:
            failures.append(f'{source}: {exc}')

    assert winner is not None, 'No C++ source passed compilation and execution tests:\n' + '\n'.join(failures)

    # Leave the required output generated from the original supplied input.
    run_program(winner, ORIGINAL_INPUT)
    assert_original_output()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
