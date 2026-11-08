#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
from pathlib import Path

import pytest


def compute_expected_regression(csv_path: str) -> str:
    """Read the CSV, filter for SENS-42, and compute the expected linear regression."""
    with open(csv_path, 'r') as f:
        lines = f.read().strip().split('\n')

    data_lines = lines[1:]
    t_raw = []
    temperatures = []

    for line in data_lines:
        if not line.strip():
            continue
        parts = line.split(',')
        if len(parts) == 3 and parts[1] == 'SENS-42':
            t_raw.append(float(parts[0]))
            temperatures.append(float(parts[2]))

    if not t_raw:
        pytest.fail("No data found for SENS-42 in the CSV.")

    t0 = t_raw[0]
    x = [(t - t0) / 1000.0 for t in t_raw]
    y = temperatures

    n = len(x)
    sum_x = sum(x)
    sum_y = sum(y)
    sum_x2 = sum(xi ** 2 for xi in x)
    sum_xy = sum(xi * yi for xi, yi in zip(x, y))
    denominator = n * sum_x2 - sum_x ** 2
    if denominator == 0:
        pytest.fail("Cannot compute linear regression: denominator is zero.")

    m = (n * sum_xy - sum_x * sum_y) / denominator
    c = (sum_y - m * sum_x) / n
    return f"Slope: {m:.4f}, Intercept: {c:.4f}"


def test_rust_file_exists():
    """Test that the Rust source file was created."""
    file_path = "/home/user/trend_fitter.rs"
    assert os.path.exists(file_path), f"Rust source file {file_path} is missing."
    assert os.path.isfile(file_path), f"Path {file_path} is not a file."


def test_regression_results():
    """Test that the submitted regression result is correct."""
    results_path = "/home/user/regression_results.txt"
    csv_path = "/home/user/raw_sensor_data.csv"

    assert os.path.exists(results_path), f"Results file {results_path} is missing."
    assert os.path.isfile(results_path), f"Path {results_path} is not a file."

    expected_output = compute_expected_regression(csv_path)
    with open(results_path, 'r') as f:
        content = f.read().strip()

    assert content == expected_output, (
        f"Content of {results_path} is incorrect.\n"
        f"Expected: '{expected_output}'\n"
        f"Got: '{content}'"
    )


def _render_reshaped(original: str, raw_csv: str) -> str:
    """Regenerate a submitted reshaping file while preserving its basic layout."""
    raw_rows = [line.split(',') for line in raw_csv.strip().splitlines()[1:]]
    selected = [row for row in raw_rows if len(row) == 3 and row[1] == 'SENS-42']
    t0 = float(selected[0][0])

    lines = [line for line in original.splitlines() if line.strip()]
    comma_separated = not lines or ',' in lines[0]
    sep = ',' if comma_separated else ' '
    first_parts = (lines[0].split(',') if comma_separated else lines[0].split()) if lines else []
    has_header = not first_parts or not re.fullmatch(r"[-+]?\d+(?:\.\d+)?", first_parts[0].strip())

    data_parts = None
    for line in lines[1:] if has_header else lines:
        parts = line.split(',') if comma_separated else line.split()
        if parts:
            data_parts = parts
            break

    # Three-column files are raw/filtered CSV. Two-column files are the usual
    # timestamp-or-relative-time plus temperature reshaping.
    if data_parts and len(data_parts) >= 3:
        rows = selected
        default_header = ['timestamp_ms', 'sensor_id', 'temperature']
    else:
        use_absolute_time = False
        if data_parts and data_parts[0].strip():
            try:
                use_absolute_time = abs(float(data_parts[0])) >= 100.0
            except ValueError:
                pass
        rows = []
        for timestamp, _sensor, temperature in selected:
            time_value = timestamp if use_absolute_time else str((float(timestamp) - t0) / 1000.0)
            rows.append([time_value, temperature])
        default_header = ['timestamp_ms' if use_absolute_time else 't_relative', 'temperature']

    output = []
    if has_header:
        output.append(lines[0] if lines else sep.join(default_header))
    output.extend(sep.join(row) for row in rows)
    return '\n'.join(output) + '\n'


def test_rust_program_compiles_and_computes_regression():
    """Compile and exercise the Rust artifact on verifier-selected sensor data."""
    source = Path('/home/user/trend_fitter.rs')
    binary = Path('/tmp/verified_trend_fitter')
    compile_result = subprocess.run(
        ['rustc', str(source), '-o', str(binary)],
        text=True, capture_output=True, timeout=30
    )
    assert compile_result.returncode == 0, (
        "trend_fitter.rs did not compile with rustc:\n" + compile_result.stderr
    )
    assert binary.is_file(), "rustc did not create the trend fitter executable."

    dynamic_raw = (
        "timestamp_ms,sensor_id,temperature\n"
        "10000,SENS-42,31.2\n"
        "10500,SENS-01,99.0\n"
        "11250,SENS-42,32.0\n"
        "12500,SENS-02,-10.0\n"
        "14000,SENS-42,34.1\n"
        "17500,SENS-42,36.0\n"
    )
    dynamic_raw_path = Path('/tmp/verifier_raw_sensor_data.csv')
    dynamic_raw_path.write_text(dynamic_raw)
    expected = compute_expected_regression(str(dynamic_raw_path))

    relative_header = Path('/tmp/verifier_reshaped.csv')
    relative_header.write_text(_render_reshaped('t_relative,temperature\n0,0\n', dynamic_raw))
    relative_no_header = Path('/tmp/verifier_reshaped_no_header.csv')
    relative_no_header.write_text(_render_reshaped('0,0\n', dynamic_raw))

    raw_path = Path('/home/user/raw_sensor_data.csv')
    result_path = Path('/home/user/regression_results.txt')
    original_result = result_path.read_bytes() if result_path.exists() else None

    # Update hard-coded reshaping files named by the submitted source, allowing
    # either the bash-reshaped-file design or a Rust program that reads raw CSV.
    source_text = source.read_text(errors='replace')
    candidates = {raw_path}
    for name in re.findall(r'["\']([^"\'\n]+\.(?:csv|txt))["\']', source_text):
        path = Path(name)
        if not path.is_absolute():
            path = Path('/home/user') / path
        try:
            path.resolve().relative_to(Path('/home/user').resolve())
        except ValueError:
            continue
        if path != result_path:
            candidates.add(path)

    backups = {}
    created = []
    try:
        for path in candidates:
            if path.exists() and path.is_file():
                backups[path] = path.read_bytes()
            else:
                created.append(path)
                path.parent.mkdir(parents=True, exist_ok=True)

            if path == raw_path:
                path.write_text(dynamic_raw)
            else:
                old_text = backups.get(path, b'').decode(errors='replace')
                path.write_text(_render_reshaped(old_text, dynamic_raw))

        attempts = [
            ([], relative_no_header, None),
            ([str(relative_header)], relative_header, None),
            ([str(relative_no_header)], relative_no_header, None),
            ([str(dynamic_raw_path)], dynamic_raw_path, None),
            ([str(relative_header), str(result_path)], relative_header, result_path),
            ([str(dynamic_raw_path), str(result_path)], dynamic_raw_path, result_path),
        ]

        observed = []
        for args, stdin_path, _output_arg in attempts:
            if result_path.exists():
                result_path.unlink()
            try:
                run = subprocess.run(
                    [str(binary), *args], cwd='/home/user',
                    input=stdin_path.read_text(), text=True,
                    capture_output=True, timeout=10
                )
            except subprocess.TimeoutExpired:
                observed.append('execution timed out')
                continue

            stdout = run.stdout.strip()
            if stdout:
                observed.append(stdout)
                if stdout == expected:
                    return
            if result_path.exists() and result_path.is_file():
                produced = result_path.read_text().strip()
                observed.append(produced)
                if produced == expected:
                    return

        pytest.fail(
            "The compiled Rust program did not compute the regression for "
            f"verifier-selected input. Expected '{expected}'. Observed: {observed}"
        )
    finally:
        for path, content in backups.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
        for path in created:
            if path.exists() and path.is_file():
                path.unlink()
        if original_result is None:
            if result_path.exists():
                result_path.unlink()
        else:
            result_path.write_bytes(original_result)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
