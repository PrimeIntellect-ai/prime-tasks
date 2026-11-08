#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
from pathlib import Path

JOINED = Path('/home/user/data/joined.csv')
SENSORS = Path('/home/user/data/sensors.csv')
LABELS = Path('/home/user/data/labels.csv')
SOURCE = Path('/home/user/normalize.c')
EXECUTABLE = Path('/home/user/normalize')
PREDICTIONS = Path('/home/user/predictions.csv')
MEAN_FILE = Path('/home/user/mean_used.txt')
REPORT = Path('/home/user/report.txt')
SOURCE_EXECUTABLE = Path('/tmp/normalize_from_source')


def read_nonempty(path):
    return [line.strip() for line in path.read_text().splitlines() if line.strip()]


def expected_join():
    sensor_rows = []
    for line in read_nonempty(SENSORS):
        parts = line.split(',')
        assert len(parts) == 2, f'Invalid sensors.csv row: {line}'
        sensor_rows.append((int(parts[0]), parts[1]))

    labels = {}
    for line in read_nonempty(LABELS):
        parts = line.split(',')
        assert len(parts) == 2, f'Invalid labels.csv row: {line}'
        row_id = int(parts[0])
        assert row_id not in labels, f'Duplicate label ID: {row_id}'
        labels[row_id] = parts[1]

    assert len(sensor_rows) == 100
    assert len(labels) == 100
    assert {row_id for row_id, _ in sensor_rows} == set(labels)
    return [f'{row_id},{value},{labels[row_id]}' for row_id, value in sensor_rows]


def remove_outputs():
    for path in (PREDICTIONS, MEAN_FILE):
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def run_program(program):
    remove_outputs()
    subprocess.run([str(program)], check=True, timeout=10)
    assert PREDICTIONS.is_file(), f'{program} did not create predictions.csv'
    assert MEAN_FILE.is_file(), f'{program} did not create mean_used.txt'


def validate_outputs(rows):
    expected_mean = sum(value for _, value, _ in rows[:80]) / 80.0

    mean_lines = read_nonempty(MEAN_FILE)
    assert len(mean_lines) == 1, 'mean_used.txt must contain one non-empty line'
    actual_mean = float(mean_lines[0])
    assert abs(actual_mean - expected_mean) <= 0.000051, (
        f'Expected training mean {expected_mean:.4f}, found {actual_mean}'
    )

    lines = read_nonempty(PREDICTIONS)
    assert len(lines) == len(rows), (
        f'Expected {len(rows)} prediction rows, found {len(lines)}'
    )

    for index, (line, (expected_id, value, expected_label)) in enumerate(zip(lines, rows), 1):
        parts = line.split(',')
        assert len(parts) == 3, f'Prediction row {index} does not have 3 columns: {line}'
        assert int(parts[0]) == expected_id, f'Wrong ID in prediction row {index}'
        assert int(parts[2]) == expected_label, f'Wrong label in prediction row {index}'
        actual_value = float(parts[1])
        expected_value = value - expected_mean
        assert abs(actual_value - expected_value) <= 0.000051, (
            f'Wrong normalized value in prediction row {index}: '
            f'expected {expected_value:.4f}, found {actual_value}'
        )


def make_unpredictable_rows():
    count = 90 + secrets.randbelow(31)
    rows = []
    current_id = 1000 + secrets.randbelow(500)
    for index in range(count):
        current_id += 1 + secrets.randbelow(4)
        if index < 80:
            value = float(secrets.randbelow(401) - 200)
        else:
            value = float(10000 + secrets.randbelow(5001))
        label = secrets.randbelow(2)
        rows.append((current_id, value, label))
    return rows


def test_complete_pipeline():
    # Preserve and extend the original joined.csv assertions.
    assert JOINED.is_file(), f'The file {JOINED} is missing.'
    expected_lines = expected_join()
    joined_lines = read_nonempty(JOINED)
    assert len(joined_lines) == 100, f'Expected 100 lines in {JOINED}, found {len(joined_lines)}.'
    assert joined_lines[0] == '1,2.0,1', f'First line of joined.csv is incorrect: {joined_lines[0]}'
    assert joined_lines[79] == '80,160.0,0', f'80th line of joined.csv is incorrect: {joined_lines[79]}'
    assert joined_lines[99] == '100,200.0,0', f'Last line of joined.csv is incorrect: {joined_lines[99]}'
    assert joined_lines == expected_lines, 'joined.csv is not the complete ID join of sensors.csv and labels.csv'

    # The requested executable must exist, be executable, and actually be a compiled binary.
    assert EXECUTABLE.is_file(), f'The compiled executable {EXECUTABLE} is missing.'
    assert os.access(EXECUTABLE, os.X_OK), f'The file {EXECUTABLE} is not executable.'
    assert EXECUTABLE.read_bytes()[:4] == b'\x7fELF', 'normalize is not an ELF executable compiled by gcc'

    # normalize.c itself must compile successfully.
    assert SOURCE.is_file(), f'The source file {SOURCE} is missing.'
    subprocess.run(
        ['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', str(SOURCE), '-o', str(SOURCE_EXECUTABLE)],
        check=True,
        timeout=20,
    )

    baseline_rows = []
    for line in expected_lines:
        row_id, value, label = line.split(',')
        baseline_rows.append((int(row_id), float(value), int(label)))

    original_joined = JOINED.read_bytes()
    try:
        # Execute the submitted artifact and validate every baseline prediction.
        run_program(EXECUTABLE)
        validate_outputs(baseline_rows)

        # Exercise both the submitted binary and freshly compiled source on an
        # unpredictable dataset whose test values strongly differ from training.
        dynamic_rows = make_unpredictable_rows()
        JOINED.write_text(''.join(f'{row_id},{value:.1f},{label}\n' for row_id, value, label in dynamic_rows))

        run_program(EXECUTABLE)
        validate_outputs(dynamic_rows)

        run_program(SOURCE_EXECUTABLE)
        validate_outputs(dynamic_rows)
    finally:
        JOINED.write_bytes(original_joined)
        # Leave the required outputs generated by the submitted executable for
        # the real task dataset.
        run_program(EXECUTABLE)

    validate_outputs(baseline_rows)

    # Preserve the original fixed-value assertions, including the 81st row.
    prediction_lines = read_nonempty(PREDICTIONS)
    parts = prediction_lines[80].split(',')
    assert len(parts) == 3, f'81st row does not have 3 columns: {prediction_lines[80]}'
    assert parts[0] == '81', f'81st row ID is incorrect: {parts[0]}'
    assert float(parts[1]) == 81.0, f'81st row normalized value is incorrect: {parts[1]}'
    assert parts[2] == '1', f'81st row label is incorrect: {parts[2]}'
    assert float(MEAN_FILE.read_text().strip()) == 81.0

    assert REPORT.is_file(), f'The file {REPORT} is missing.'
    report_lines = REPORT.read_text().splitlines()
    assert len(report_lines) == 2, f'Expected exactly 2 lines in {REPORT}, found {len(report_lines)}.'
    assert report_lines[0].strip() and report_lines[1].strip(), 'report.txt contains an empty line'
    assert float(report_lines[0]) == 81.0, f'Line 1 of report.txt is incorrect: {report_lines[0]}'
    assert float(report_lines[1]) == 81.0, f'Line 2 of report.txt is incorrect: {report_lines[1]}'
PY_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
