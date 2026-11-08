#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest

DATA_DIR = Path('/home/user/data')
OUTPUT = Path('/home/user/output/metrics.json')
ETL_DIR = Path('/home/user/etl')
RUN_SCRIPT = Path('/home/user/run_pipeline.sh')


def run_command(command, cwd=None, timeout=120):
    result = subprocess.run(
        command,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Command failed with exit code {result.returncode}: {command}\n{result.stdout}"
    )
    return result


def read_metrics():
    assert OUTPUT.is_file(), f"File {OUTPUT} does not exist. Did the Go program run successfully?"
    try:
        with OUTPUT.open('r', encoding='utf-8') as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"File {OUTPUT} is not valid JSON: {exc}")


def assert_metrics(expected_distance, expected_points, tolerance=1e-9):
    data = read_metrics()
    assert 'aligned_points' in data, "Missing 'aligned_points' key in JSON output."
    assert data['aligned_points'] == expected_points, (
        f"Expected {expected_points} aligned points, got {data['aligned_points']}."
    )
    assert 'distance' in data, "Missing 'distance' key in JSON output."
    actual_distance = data['distance']
    assert isinstance(actual_distance, (int, float)) and not isinstance(actual_distance, bool), \
        "Distance must be a number."
    assert math.isclose(actual_distance, expected_distance, rel_tol=1e-9, abs_tol=tolerance), (
        f"Calculated distance {actual_distance} does not match expected {expected_distance}."
    )


def write_rows(path, rows, encoding):
    text = ''.join(f"{timestamp},{value:.6f},{label}\n" for timestamp, value, label in rows)
    path.write_bytes(text.encode(encoding))


def make_random_case():
    rng = random.Random(secrets.randbits(128))
    start = rng.randint(1700000000, 1900000000)
    timestamps = [start + i * rng.randint(31, 113) for i in range(7)]
    # Ensure timestamps are unique and ordered even though the spacings above vary.
    timestamps = sorted(set(timestamps))
    while len(timestamps) < 7:
        timestamps.append(timestamps[-1] + rng.randint(31, 113))

    a_indices = [0, 1, 2, 4, 6]
    b_indices = [0, 1, 3, 4, 6]
    a_values = {timestamps[i]: rng.uniform(-50.0, 80.0) for i in a_indices}
    b_values = {timestamps[i]: rng.uniform(-50.0, 80.0) for i in b_indices}

    a_labels = ['Température', 'Élevé', 'Très bas', 'Défaut', 'Normal']
    b_labels = ['München', 'Anomalie', 'Crème', 'Normal', 'Réglé']
    rows_a = [(ts, a_values[ts], a_labels[n]) for n, ts in enumerate(sorted(a_values))]
    rows_b = [(ts, b_values[ts], b_labels[n]) for n, ts in enumerate(sorted(b_values))]

    # Expected values are based on the six-decimal representations written to disk.
    rounded_a = {ts: round(value, 6) for ts, value in a_values.items()}
    rounded_b = {ts: round(value, 6) for ts, value in b_values.items()}
    common = sorted(set(rounded_a) & set(rounded_b))
    distance = math.sqrt(sum((rounded_a[ts] - rounded_b[ts]) ** 2 for ts in common))
    return rows_a, rows_b, distance, len(common)


def install_case(rows_a, rows_b):
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    write_rows(DATA_DIR / 'sensor_a.csv', rows_a, 'iso-8859-1')
    write_rows(DATA_DIR / 'sensor_b.csv', rows_b, 'utf-16le')
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    if OUTPUT.exists():
        OUTPUT.unlink()


def install_canonical_case():
    sensor_a = (
        "1600000000,10.5,Température\n"
        "1600000060,11.0,Température\n"
        "1600000120,12.5,Élevé\n"
        "1600000180,10.1,Normal\n"
    )
    sensor_b = (
        "1600000000,10.0,Normal\n"
        "1600000060,11.2,Normal\n"
        "1600000150,13.0,Anomalie\n"
        "1600000180,9.9,Normal\n"
    )
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    (DATA_DIR / 'sensor_a.csv').write_bytes(sensor_a.encode('iso-8859-1'))
    (DATA_DIR / 'sensor_b.csv').write_bytes(sensor_b.encode('utf-16le'))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    if OUTPUT.exists():
        OUTPUT.unlink()


def test_run_pipeline_executable():
    """Keep the original existence and executable assertions."""
    assert RUN_SCRIPT.is_file(), f"Script {RUN_SCRIPT} does not exist."
    assert os.access(RUN_SCRIPT, os.X_OK), f"Script {RUN_SCRIPT} is not executable. Run 'chmod +x {RUN_SCRIPT}'."


def test_go_module_and_program_on_unpredictable_inputs():
    """Build and execute the submitted Go program against verifier-generated data."""
    assert ETL_DIR.is_dir(), f"Go module directory {ETL_DIR} does not exist."
    assert (ETL_DIR / 'go.mod').is_file(), f"Go module file {ETL_DIR / 'go.mod'} does not exist."
    assert (ETL_DIR / 'main.go').is_file(), f"Go program {ETL_DIR / 'main.go'} does not exist."

    binary = Path(tempfile.mkdtemp(prefix='etl-verifier-')) / 'etl-program'
    try:
        run_command(['go', 'build', '-o', str(binary), '.'], cwd=str(ETL_DIR))
        assert binary.is_file() and os.access(binary, os.X_OK), "go build did not create an executable."

        for _ in range(2):
            rows_a, rows_b, expected_distance, expected_points = make_random_case()
            install_case(rows_a, rows_b)
            run_command([str(binary)], cwd='/home/user')
            assert_metrics(expected_distance, expected_points)
    finally:
        shutil.rmtree(binary.parent, ignore_errors=True)


def test_run_script_builds_and_executes_go_program():
    """Replace the module temporarily with a sentinel Go module and require the script to run it."""
    token = secrets.token_hex(8)
    backup = Path(f'/home/user/.etl-verifier-backup-{token}')
    sentinel_distance = random.Random(secrets.randbits(128)).uniform(1000.0, 9000.0)
    sentinel_points = random.Random(secrets.randbits(128)).randint(101, 999)

    assert not backup.exists()
    ETL_DIR.rename(backup)
    try:
        ETL_DIR.mkdir(parents=True)
        (ETL_DIR / 'go.mod').write_text('module verifier-sentinel\n\ngo 1.18\n', encoding='utf-8')
        metrics_literal = json.dumps({
            'distance': sentinel_distance,
            'aligned_points': sentinel_points,
        }, separators=(',', ':'))
        source = f'''package main
import "os"
func main() {{
    _ = os.MkdirAll("/home/user/output", 0755)
    if err := os.WriteFile("/home/user/output/metrics.json", []byte(`{metrics_literal}`), 0644); err != nil {{ panic(err) }}
}}
'''
        (ETL_DIR / 'main.go').write_text(source, encoding='utf-8')
        if OUTPUT.exists():
            OUTPUT.unlink()
        run_command([str(RUN_SCRIPT)], cwd='/home/user')
        assert_metrics(sentinel_distance, sentinel_points)
    finally:
        shutil.rmtree(ETL_DIR, ignore_errors=True)
        backup.rename(ETL_DIR)


def test_metrics_json():
    """Run the pipeline on the supplied case and retain the original metric assertions."""
    install_canonical_case()
    run_command([str(RUN_SCRIPT)], cwd='/home/user')

    data = read_metrics()
    assert 'aligned_points' in data, "Missing 'aligned_points' key in JSON output."
    assert data['aligned_points'] == 3, f"Expected 3 aligned points, got {data['aligned_points']}."
    assert 'distance' in data, "Missing 'distance' key in JSON output."
    expected_distance = 0.5744562646538029
    actual_distance = data['distance']
    assert isinstance(actual_distance, (int, float)), "Distance must be a number."
    assert math.isclose(actual_distance, expected_distance, abs_tol=0.001), \
        f"Calculated distance {actual_distance} is not within 0.001 of expected {expected_distance}."


def test_pipeline_on_unpredictable_input():
    """Ensure the complete submitted pipeline derives results instead of emitting constants."""
    rows_a, rows_b, expected_distance, expected_points = make_random_case()
    install_case(rows_a, rows_b)
    run_command([str(RUN_SCRIPT)], cwd='/home/user')
    assert_metrics(expected_distance, expected_points)


def test_pipeline_cron():
    """Retain the original cron assertions."""
    path = Path('/home/user/pipeline.cron')
    assert path.is_file(), f"Cron file {path} does not exist."

    content = path.read_text(encoding='utf-8').strip()
    lines = [line.strip() for line in content.split('\n') if line.strip() and not line.strip().startswith('#')]
    assert len(lines) == 1, f"Expected exactly one active cron line in {path}, found {len(lines)}."

    line = lines[0]
    assert '/home/user/run_pipeline.sh' in line, \
        f"Cron line does not execute /home/user/run_pipeline.sh. Line: {line}"

    parts = line.split()
    assert len(parts) >= 6, f"Cron line does not have enough fields (expected at least 6). Line: {line}"

    minute_field = parts[0]
    valid_minutes = ['*/15', '0,15,30,45']
    assert minute_field in valid_minutes, \
        f"Minute field '{minute_field}' does not schedule every 15 minutes. Expected '*/15' or '0,15,30,45'."
    assert parts[1:5] == ['*', '*', '*', '*'], \
        f"Cron line scheduling fields (hour, day, month, dow) should be '* * * *'. Got: {' '.join(parts[1:5])}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
