#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import secrets
import stat
import subprocess
import uuid
from collections import Counter
from datetime import datetime, timedelta
from decimal import Decimal
from pathlib import Path


def test_scripts_exist():
    run_etl_path = '/home/user/run_etl.sh'
    process_py_path = '/home/user/process.py'

    assert os.path.exists(run_etl_path), f"Required script {run_etl_path} is missing."
    assert os.path.exists(process_py_path), f"Required script {process_py_path} is missing."


def test_filtered_data_log():
    filtered_path = '/home/user/filtered_data.log'
    assert os.path.exists(filtered_path), f"Intermediate file {filtered_path} is missing."

    with open(filtered_path, 'r') as f:
        content = f.read()

    assert "Status:ERROR" not in content, "filtered_data.log still contains 'Status:ERROR'"
    assert "Status:FAIL" not in content, "filtered_data.log still contains 'Status:FAIL'"
    assert "TRK-001" in content, "filtered_data.log seems to be missing valid lines."


def test_processed_csv():
    processed_path = '/home/user/processed.csv'
    assert os.path.exists(processed_path), f"Final output file {processed_path} is missing."

    with open(processed_path, 'r') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "processed.csv is empty."

    header = rows[0]
    expected_header = ['truck_id', 'timestamp', 'temperature']
    assert header == expected_header, f"Header row is incorrect. Expected {expected_header}, got {header}."

    data_rows = rows[1:]
    expected_data = [
        ['TRK-001', '2023-10-01 10:00:00', '10.00'],
        ['TRK-001', '2023-10-01 10:05:00', '12.00'],
        ['TRK-001', '2023-10-01 10:10:00', '14.00'],
        ['TRK-001', '2023-10-01 10:15:00', '16.00'],
        ['TRK-002', '2023-10-01 11:00:00', '20.00'],
        ['TRK-002', '2023-10-01 11:05:00', '21.00'],
        ['TRK-002', '2023-10-01 11:10:00', '22.00'],
        ['TRK-003', '2023-10-01 12:00:00', '5.00'],
        ['TRK-003', '2023-10-01 12:05:00', '7.50'],
        ['TRK-003', '2023-10-01 12:10:00', '10.00'],
        ['TRK-003', '2023-10-01 12:15:00', '12.50'],
        ['TRK-003', '2023-10-01 12:20:00', '15.00']
    ]

    assert len(data_rows) == len(expected_data), f"Expected {len(expected_data)} data rows, got {len(data_rows)}."

    for i, (actual, expected) in enumerate(zip(data_rows, expected_data)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, got {actual}."


def _expected_rows(observations):
    rows = []
    for truck_id in sorted(observations):
        points = sorted(observations[truck_id])
        for segment_index, ((start, start_value), (end, end_value)) in enumerate(zip(points, points[1:])):
            intervals = int((end - start).total_seconds() // 300)
            first_step = 0 if segment_index == 0 else 1
            for step in range(first_step, intervals + 1):
                timestamp = start + timedelta(minutes=5 * step)
                value = start_value + (end_value - start_value) * Decimal(step) / Decimal(intervals)
                value = value.quantize(Decimal('0.01'))
                rows.append([
                    truck_id,
                    timestamp.strftime('%Y-%m-%d %H:%M:%S'),
                    format(value, '.2f'),
                ])
    return rows


def test_pipeline_executes_on_unseen_input():
    run_path = Path('/home/user/run_etl.sh')
    process_path = Path('/home/user/process.py')
    raw_path = Path('/home/user/raw_data.log')
    filtered_path = Path('/home/user/filtered_data.log')
    processed_path = Path('/home/user/processed.csv')

    assert run_path.is_file(), 'run_etl.sh is not a regular script file.'
    assert process_path.is_file(), 'process.py is not a regular script file.'
    assert run_path.stat().st_size > 0, 'run_etl.sh is empty.'
    assert process_path.stat().st_size > 0, 'process.py is empty.'

    tracked = [raw_path, filtered_path, processed_path, process_path]
    backups = {}
    for path in tracked:
        if path.exists():
            backups[path] = (path.read_bytes(), stat.S_IMODE(path.stat().st_mode))
        else:
            backups[path] = None

    token = uuid.uuid4().hex
    submitted_process = Path('/tmp') / f'submitted_process_{token}.py'
    marker = Path('/tmp') / f'process_invoked_{token}'

    try:
        # Randomized IDs, date, and temperatures prevent a fixed-output solution.
        numbers = secrets.SystemRandom().sample(range(110, 990), 3)
        trucks = [f'TRK-{number:03d}' for number in numbers]
        year = secrets.choice([2022, 2024, 2025])
        month = secrets.choice([2, 4, 7, 9, 11])
        day = secrets.choice(range(2, 20))
        base = datetime(year, month, day, 8, 0, 0)

        a = Decimal(secrets.choice(range(-5, 16)))
        b = Decimal(secrets.choice(range(18, 31)))
        c = Decimal(secrets.choice(range(3, 13)))
        observations = {
            trucks[0]: [
                (base, a),
                (base + timedelta(minutes=10), a + Decimal('4')),
                (base + timedelta(minutes=25), a + Decimal('10')),
            ],
            trucks[1]: [
                (base + timedelta(hours=1), b),
                (base + timedelta(hours=1, minutes=15), b + Decimal('3')),
            ],
            trucks[2]: [
                (base + timedelta(hours=2), c),
                (base + timedelta(hours=2, minutes=20), c + Decimal('5')),
            ],
        }

        def iso(dt):
            return dt.strftime('%Y-%m-%dT%H:%M:%SZ')

        def us(dt):
            return dt.strftime('%m/%d/%Y %H:%M:%S')

        o0, o1, o2 = observations[trucks[0]], observations[trucks[1]], observations[trucks[2]]
        valid_lines = [
            f'[{trucks[1]}] {iso(o1[1][0])} Temp:{o1[1][1]}C Status:OK',
            f'[{trucks[0]}] {us(o0[1][0])} Temp:{o0[1][1]}C Status:OK',
            f'[{trucks[2]}] {iso(o2[0][0])} Temp:{o2[0][1]}C Status:OK',
            f'[{trucks[0]}] {iso(o0[0][0])} Temp:{o0[0][1]}C Status:OK',
            f'[{trucks[1]}] {us(o1[0][0])} Temp:{o1[0][1]}C Status:OK',
            f'[{trucks[2]}] {us(o2[1][0])} Temp:{o2[1][1]}C Status:OK',
            f'[{trucks[0]}] {iso(o0[2][0])} Temp:{o0[2][1]}C Status:OK',
        ]
        rejected_lines = [
            f'[{trucks[0]}] {us(base + timedelta(minutes=5))} Temp:999.9C Status:ERROR',
            f'[{trucks[1]}] {iso(base + timedelta(hours=1, minutes=5))} Temp:-999.9C Status:FAIL',
        ]
        raw_lines = [valid_lines[0], rejected_lines[0], *valid_lines[1:5], rejected_lines[1], *valid_lines[5:]]
        raw_path.write_text('\n'.join(raw_lines) + '\n')
        filtered_path.unlink(missing_ok=True)
        processed_path.unlink(missing_ok=True)

        # Wrap the submitted Python program so the orchestration test also proves
        # that run_etl.sh actually invokes process.py.
        submitted_process.write_bytes(process_path.read_bytes())
        wrapper = (
            'from pathlib import Path\n'
            f'Path({str(marker)!r}).write_text("invoked")\n'
            f'_source = Path({str(submitted_process)!r}).read_bytes()\n'
            f'exec(compile(_source, {str(process_path)!r}, "exec"), '
            f'{{"__name__": "__main__", "__file__": {str(process_path)!r}}})\n'
        )
        process_path.write_text(wrapper)
        process_path.chmod(0o755)

        result = subprocess.run(
            ['bash', str(run_path)],
            cwd='/home/user',
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=180,
        )
        assert result.returncode == 0, f'run_etl.sh failed on unseen input:\n{result.stdout}'
        assert marker.exists(), 'run_etl.sh did not execute /home/user/process.py.'

        assert filtered_path.exists(), 'run_etl.sh did not create filtered_data.log.'
        filtered_lines = filtered_path.read_text().splitlines()
        assert Counter(filtered_lines) == Counter(valid_lines), (
            'filtered_data.log must contain all and only lines without Status:ERROR or Status:FAIL.'
        )

        assert processed_path.exists(), 'The executed pipeline did not create processed.csv.'
        with processed_path.open(newline='') as handle:
            actual = list(csv.reader(handle))
        expected = [['truck_id', 'timestamp', 'temperature']] + _expected_rows(observations)
        assert actual == expected, f'Pipeline output for unseen input is incorrect.\nExpected: {expected}\nActual: {actual}'
    finally:
        submitted_process.unlink(missing_ok=True)
        marker.unlink(missing_ok=True)
        for path, backup in backups.items():
            if backup is None:
                path.unlink(missing_ok=True)
            else:
                data, mode = backup
                path.write_bytes(data)
                path.chmod(mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
