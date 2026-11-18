#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import hashlib
import os
from pathlib import Path
import secrets
import subprocess

HOME = Path('/home/user')
INPUT = HOME / 'sensor_logs.csv'
OUTPUT = HOME / 'clean_sensors.csv'
LOG = HOME / 'pipeline.log'

EXPECTED_ORIGINAL_ROWS = [
    ['tx_id', 'timestamp_ms', 'sensor_type', 'normalized_value'],
    ['tx01', '1625000001', 'TEMP', '25.00'],
    ['tx03', '1625001500', 'PRESSURE', '68.95'],
    ['tx07', '1625005000', 'TEMP', '20.00'],
]
EXPECTED_ORIGINAL_LOG = '[INFO] Processed 3 valid rows, dropped 2 duplicates, dropped 2 malformed.'


def assert_outputs(expected_rows, expected_log):
    assert OUTPUT.exists(), f'Output file {OUTPUT} is missing.'
    assert OUTPUT.is_file(), f'{OUTPUT} is not a file.'
    with OUTPUT.open('r', newline='') as f:
        actual_rows = list(csv.reader(f))
    assert actual_rows == expected_rows, (
        f'Contents of {OUTPUT} do not match expected output.\n'
        f'Expected: {expected_rows}\nActual: {actual_rows}'
    )

    assert LOG.exists(), f'Log file {LOG} is missing.'
    assert LOG.is_file(), f'{LOG} is not a file.'
    with LOG.open('r') as f:
        lines = f.read().splitlines()
    actual_lines = [line for line in lines if line.strip()]
    assert len(actual_lines) == 1, (
        f'Expected exactly one non-empty line in {LOG}, but found {len(actual_lines)}.'
    )
    assert actual_lines[0] == expected_log, (
        f'Log file content does not match expected format.\n'
        f'Expected: {expected_log}\nActual: {actual_lines[0]}'
    )


def test_01_original_clean_sensors_csv_exists_and_correct():
    assert_outputs(EXPECTED_ORIGINAL_ROWS, EXPECTED_ORIGINAL_LOG)


def find_python_scripts():
    excluded = {INPUT.resolve(), OUTPUT.resolve(), LOG.resolve()}
    scripts = []
    for path in HOME.rglob('*'):
        if not path.is_file() or path.is_symlink():
            continue
        try:
            if path.resolve() in excluded or path.stat().st_size > 2_000_000:
                continue
            source = path.read_text(encoding='utf-8')
            ast.parse(source, filename=str(path))
        except (OSError, UnicodeError, SyntaxError):
            continue
        if path.suffix == '.py' or source.startswith('#!') or source.strip():
            scripts.append(path)
    return scripts


def derive_expected(rows):
    output_rows = [['tx_id', 'timestamp_ms', 'sensor_type', 'normalized_value']]
    seen = set()
    duplicates = 0
    malformed = 0

    for tx_id, timestamp, sensor_type, value, unit in rows:
        try:
            numeric_value = float(value)
        except ValueError:
            malformed += 1
            continue

        if sensor_type == 'TEMP' and unit == 'F':
            normalized = (numeric_value - 32) * 5 / 9
        elif sensor_type == 'TEMP' and unit == 'C':
            normalized = numeric_value
        elif sensor_type == 'PRESSURE' and unit == 'PSI':
            normalized = numeric_value * 6.89476
        elif sensor_type == 'PRESSURE' and unit == 'kPa':
            normalized = numeric_value
        else:
            malformed += 1
            continue

        normalized_text = f'{normalized:.2f}'
        timestamp_number = int(timestamp)
        timestamp_rounded = ((timestamp_number + 500) // 1000) * 1000
        material = f'{sensor_type}:{normalized_text}:{timestamp_rounded}'
        digest = hashlib.sha256(material.encode()).hexdigest()
        if digest in seen:
            duplicates += 1
            continue
        seen.add(digest)
        output_rows.append([tx_id, timestamp, sensor_type, normalized_text])

    expected_log = (
        f'[INFO] Processed {len(output_rows) - 1} valid rows, '
        f'dropped {duplicates} duplicates, dropped {malformed} malformed.'
    )
    return output_rows, expected_log


def write_fixture(rows):
    with INPUT.open('w', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerow(['tx_id', 'timestamp_ms', 'sensor_type', 'value', 'unit'])
        writer.writerows(rows)


def run_script(path):
    for artifact in (OUTPUT, LOG):
        try:
            artifact.unlink()
        except FileNotFoundError:
            pass
    return subprocess.run(
        ['python3', str(path)],
        cwd=str(HOME),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
        check=False,
    )


def test_02_script_executes_pipeline_on_unseen_input():
    scripts = find_python_scripts()
    assert scripts, 'No Python script was found under /home/user.'

    original_input = INPUT.read_bytes()
    base = secrets.randbelow(500_000) * 1000 + 1_700_000_000
    temp_c = secrets.randbelow(26) + 5
    temp_f = temp_c * 9 / 5 + 32
    pressure_psi = secrets.randbelow(10) + 6
    pressure_kpa = pressure_psi * 6.89476
    boundary_value = secrets.randbelow(30) + 10.25
    distinct_temp = secrets.randbelow(20) - 5.5

    def tx():
        return 'tx_' + secrets.token_hex(6)

    rows = [
        [tx(), str(base + 123), 'TEMP', f'{temp_f:.6f}', 'F'],
        [tx(), str(base + 401), 'TEMP', str(temp_c), 'C'],
        [tx(), str(base + 1450), 'PRESSURE', str(pressure_psi), 'PSI'],
        [tx(), str(base + 1499), 'PRESSURE', f'{pressure_kpa:.5f}', 'kPa'],
        [tx(), str(base + 2500), 'TEMP', str(boundary_value), 'C'],
        [tx(), str(base + 3001), 'TEMP', str(boundary_value), 'C'],
        [tx(), str(base + 4100), 'TEMP', str(distinct_temp), 'C'],
        [tx(), str(base + 5200), 'TEMP', 'not-a-number', 'C'],
        [tx(), str(base + 5300), 'TEMP', '20', 'K'],
        [tx(), str(base + 5400), 'PRESSURE', '9', 'BAR'],
        [tx(), str(base + 5500), 'HUMIDITY', '50', 'percent'],
    ]
    expected_rows, expected_log = derive_expected(rows)
    errors = []
    winner = None

    try:
        for script in scripts:
            write_fixture(rows)
            try:
                result = run_script(script)
                if result.returncode != 0:
                    errors.append(f'{script}: exit {result.returncode}: {result.stderr[-300:]}')
                    continue
                assert_outputs(expected_rows, expected_log)
                winner = script
                break
            except Exception as exc:
                errors.append(f'{script}: {type(exc).__name__}: {exc}')

        assert winner is not None, (
            'No discovered Python script correctly processed the unseen fixture.\n' +
            '\n'.join(errors[-10:])
        )

        INPUT.write_bytes(original_input)
        result = run_script(winner)
        assert result.returncode == 0, (
            f'{winner} failed on the original fixture with exit {result.returncode}: '
            f'{result.stderr}'
        )
        assert_outputs(EXPECTED_ORIGINAL_ROWS, EXPECTED_ORIGINAL_LOG)
    finally:
        INPUT.write_bytes(original_input)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
