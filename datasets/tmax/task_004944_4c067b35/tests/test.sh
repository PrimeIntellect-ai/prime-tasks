#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import secrets
import shlex
import subprocess
from collections import Counter
from pathlib import Path

SCRIPT = Path('/home/user/process_logs.sh')
INPUT = Path('/home/user/system_logs.csv')
OUTPUT = Path('/home/user/error_counts.csv')


def test_process_logs_script_exists_and_executable():
    """Verify that process_logs.sh exists, is executable, and is a bash script."""
    assert os.path.exists(SCRIPT), f"Script {SCRIPT} is missing."
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is not a file."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."

    first_line = SCRIPT.read_bytes().splitlines()[0].decode('utf-8')
    assert first_line.startswith('#!'), 'process_logs.sh must have a shebang.'
    shebang = shlex.split(first_line[2:].strip())
    assert any(os.path.basename(token) == 'bash' for token in shebang), \
        'process_logs.sh must be an executable bash script.'


def test_error_counts_output():
    """Verify the originally generated output has the correct aggregated counts."""
    output_file = "/home/user/error_counts.csv"
    assert os.path.exists(output_file), f"Output file {output_file} is missing."
    assert os.path.isfile(output_file), f"{output_file} is not a file."

    expected_data = [
        ['service', 'count'],
        ['auth-service', '93'],
        ['db-worker', '105'],
        ['frontend-app', '114'],
        ['payment-gateway', '109']
    ]

    actual_data = []
    with open(output_file, 'r', newline='') as f:
        reader = csv.reader(f)
        for row in reader:
            actual_data.append(row)

    assert actual_data == expected_data, f"Output file content does not match expected. Got: {actual_data}"


def test_script_processes_changed_csv_input():
    """Run the submitted script on unpredictable CSV data, including multiline fields."""
    original_input = INPUT.read_bytes()
    original_output = OUTPUT.read_bytes() if OUTPUT.exists() else None

    rng = random.Random(secrets.randbits(128))
    suffix = secrets.token_hex(5)
    services = [
        f'zeta-{suffix}',
        f'alpha-{suffix}',
        f'middle-{suffix}',
        f'unused-{suffix}',
    ]
    levels = ['ERROR', 'Error', 'error', 'WARNING', 'warning', 'INFO', 'info']

    rows = [
        ['2026-01-01T00:00:00Z', 'Error', services[1],
         f'first line\n2026-01-01T00:00:01Z,ERROR,injected-{suffix},not a real record\nlast line'],
        ['2026-01-01T00:00:02Z', 'ERROR', services[0],
         'message with, commas and "quotes"\nand another line'],
        ['2026-01-01T00:00:03Z', 'error', services[2], 'ordinary error'],
        ['2026-01-01T00:00:04Z', 'WARNING', services[3], 'must not appear'],
    ]

    for i in range(300):
        service = rng.choice(services[:3])
        level = rng.choice(levels)
        message = f'event {i}, token {secrets.token_hex(3)}'
        if i % 7 == 0:
            message += f'\ncontinuation {i}\nERROR,{services[3]},still part of message'
        rows.append([f'2026-02-01T00:{i % 60:02d}:{i % 60:02d}Z', level, service, message])

    expected_counts = Counter()
    for _timestamp, level, service, _message in rows:
        if level.upper() == 'ERROR':
            expected_counts[service] += 1
    expected = [['service', 'count']] + [
        [service, str(expected_counts[service])]
        for service in sorted(expected_counts)
    ]

    try:
        with INPUT.open('w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['timestamp', 'level', 'service', 'message'])
            writer.writerows(rows)

        if OUTPUT.exists():
            OUTPUT.unlink()

        result = subprocess.run(
            [str(SCRIPT)],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f'process_logs.sh exited with {result.returncode}. '
            f'stdout: {result.stdout!r} stderr: {result.stderr!r}'
        )
        assert OUTPUT.exists(), 'Running process_logs.sh did not create error_counts.csv.'
        assert OUTPUT.is_file(), f'{OUTPUT} is not a file.'

        with OUTPUT.open('r', newline='') as f:
            actual = list(csv.reader(f))
        assert actual == expected, f'Changed-input output is incorrect. Expected {expected}, got {actual}'
    finally:
        INPUT.write_bytes(original_input)
        if original_output is None:
            if OUTPUT.exists():
                OUTPUT.unlink()
        else:
            OUTPUT.write_bytes(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
