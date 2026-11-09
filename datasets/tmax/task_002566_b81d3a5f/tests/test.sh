#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import stat
import subprocess
from pathlib import Path

import numpy as np

EXPERIMENTS = Path('/home/user/experiments')
OUTPUT = Path('/home/user/valid_models.csv')


def read_rows(path):
    with path.open('r', newline='') as f:
        return list(csv.reader(f))


def assert_original_output():
    assert OUTPUT.is_file(), f'Output file {OUTPUT} does not exist.'
    rows = read_rows(OUTPUT)
    assert len(rows) > 0, 'The output file is empty.'
    assert rows[0] == ['model_name', 'mse'], (
        f"Headers are incorrect. Expected ['model_name', 'mse'], got {rows[0]}."
    )

    data_rows = rows[1:]
    assert len(data_rows) == 3, f'Expected exactly 3 valid models, got {len(data_rows)}.'
    expected_data = [
        ['model_D', '0.0025'],
        ['model_A', '0.0200'],
        ['model_B', '0.2500'],
    ]
    for i, (expected_name, expected_mse) in enumerate(expected_data):
        actual_name, actual_mse = data_rows[i]
        assert actual_name == expected_name, (
            f"Row {i+1}: Expected model_name '{expected_name}', got '{actual_name}'."
        )
        assert actual_mse == expected_mse, (
            f"Row {i+1}: Expected mse '{expected_mse}', got '{actual_mse}'."
        )


def restore_csvs(snapshot):
    EXPERIMENTS.mkdir(parents=True, exist_ok=True)
    for path in EXPERIMENTS.glob('*.csv'):
        path.unlink()
    for name, contents in snapshot.items():
        (EXPERIMENTS / name).write_bytes(contents)


def run_script(script):
    if OUTPUT.exists():
        OUTPUT.unlink()
    result = subprocess.run(
        ['python3', str(script)],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f'Python script {script} exited with status {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert OUTPUT.is_file(), f'Executing {script} did not create {OUTPUT}.'


def python_scripts():
    candidates = []
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if d not in {'.cache', '.local', '__pycache__', '.venv', 'venv'}]
        for filename in files:
            path = Path(root) / filename
            try:
                mode = path.stat().st_mode
                if not stat.S_ISREG(mode):
                    continue
                if path.suffix == '.py':
                    candidates.append(path)
                    continue
                with path.open('rb') as f:
                    first_line = f.readline(200).lower()
                if first_line.startswith(b'#!') and b'python' in first_line:
                    candidates.append(path)
            except (OSError, UnicodeError):
                continue
    return sorted(set(candidates))


def write_fixture(models):
    for path in EXPERIMENTS.glob('*.csv'):
        path.unlink()
    for filename, records in models.items():
        with (EXPERIMENTS / filename).open('w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['id', 'y_true', 'y_pred'])
            for index, (y_true, y_pred) in enumerate(records, 1):
                writer.writerow([index, y_true, y_pred])


def expected_rows_float32(models):
    expected = []
    for filename, records in models.items():
        y_true = np.asarray([r[0] for r in records], dtype=np.float32)
        y_pred = np.asarray([r[1] for r in records], dtype=np.float32)
        mse = np.mean((y_true - y_pred) ** 2)
        if mse < np.float32(0.5):
            expected.append([Path(filename).stem, f'{float(mse):.4f}'])
    expected.sort(key=lambda row: float(row[1]))
    return expected


def test_script_is_executed_and_generalizes_with_float32():
    original_csvs = {p.name: p.read_bytes() for p in EXPERIMENTS.glob('*.csv')}
    initial_output = OUTPUT.read_bytes() if OUTPUT.is_file() else None
    generated_original = None

    try:
        scripts = python_scripts()
        assert scripts, 'No Python script was found under /home/user.'

        selected = None
        errors = []
        for script in scripts:
            restore_csvs(original_csvs)
            try:
                run_script(script)
                assert_original_output()
                selected = script
                generated_original = OUTPUT.read_bytes()
                break
            except Exception as exc:
                errors.append(f'{script}: {exc}')

        assert selected is not None, (
            'No discovered Python script produced the required output when executed.\n'
            + '\n'.join(errors)
        )

        # The large-value probe has MSE 0.0000 only after conversion to float32:
        # 16777217 rounds to 16777216 in float32, while float64 would give MSE 1.0.
        # Multiple additional passing files ensure the script processes all CSV files.
        models = {
            'precision_probe.csv': [(16777216, 16777217)],
            'all_files_one.csv': [(0, 0.1)],
            'all_files_two.csv': [(0, 0.25)],
            'exact_threshold.csv': [(0, 1), (0, 0)],
            'failing_model.csv': [(0, 0.8)],
        }
        write_fixture(models)
        run_script(selected)

        rows = read_rows(OUTPUT)
        assert rows, 'The dynamically generated output is empty.'
        assert rows[0] == ['model_name', 'mse'], 'Dynamic output has incorrect headers.'
        assert all(len(row) == 2 for row in rows), 'Output must contain exactly two columns.'
        expected = expected_rows_float32(models)
        assert rows[1:] == expected, (
            'Output did not match MSEs derived from numpy.float32 arrays for all CSV files. '
            f'Expected {expected}, got {rows[1:]}.'
        )
    finally:
        restore_csvs(original_csvs)
        if generated_original is not None:
            OUTPUT.write_bytes(generated_original)
        elif initial_output is not None:
            OUTPUT.write_bytes(initial_output)
        elif OUTPUT.exists():
            OUTPUT.unlink()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
