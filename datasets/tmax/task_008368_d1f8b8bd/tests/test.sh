#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import shutil
import subprocess
import tempfile
import pytest

RAW_PATH = "/home/user/raw_data.csv"
CSV_PATH = "/home/user/clean_data.csv"
METRICS_PATH = "/home/user/run_metrics.json"
SOURCE_PATH = "/home/user/etl_clean.c"
EXECUTABLE_PATH = "/home/user/etl_clean"


def test_executable_exists():
    executable_path = EXECUTABLE_PATH
    assert os.path.exists(executable_path), f"Executable {executable_path} is missing."
    assert os.path.isfile(executable_path), f"{executable_path} is not a file."
    assert os.access(executable_path, os.X_OK), f"{executable_path} is not executable."


def test_clean_data_csv():
    file_path = CSV_PATH
    assert os.path.exists(file_path), f"File {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

    expected_content = """id,measurement
1,10.5
3,12.2
5,15.8
7,20.0
9,22.5"""

    with open(file_path, "r") as f:
        actual_content = f.read()

    expected_lines = [line.strip() for line in expected_content.strip().split('\n') if line.strip()]
    actual_lines = [line.strip() for line in actual_content.strip().split('\n') if line.strip()]

    assert actual_lines == expected_lines, f"Content of {file_path} does not match expected valid rows."


def test_run_metrics_json():
    file_path = METRICS_PATH
    assert os.path.exists(file_path), f"File {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

    with open(file_path, "r") as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{file_path} is not valid JSON.")

    assert "valid_count" in metrics, "Key 'valid_count' missing in run_metrics.json"
    assert "mean" in metrics, "Key 'mean' missing in run_metrics.json"
    assert "sample_variance" in metrics, "Key 'sample_variance' missing in run_metrics.json"

    assert metrics["valid_count"] == 5, f"Expected valid_count to be 5, got {metrics['valid_count']}"
    assert math.isclose(metrics["mean"], 16.2000, abs_tol=1e-4), f"Expected mean to be ~16.2000, got {metrics['mean']}"
    assert math.isclose(metrics["sample_variance"], 25.6950, abs_tol=1e-4), f"Expected sample_variance to be ~25.6950, got {metrics['sample_variance']}"


def _remove_output(path):
    if os.path.lexists(path):
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)


def _make_case():
    rng = secrets.SystemRandom()
    base = rng.randrange(1000, 9000)
    valid_values = [rng.randrange(0, 700) / 10.0 for _ in range(6)]
    rows = []
    for index, value in enumerate(valid_values):
        rows.append((base + index, f"{value:.1f}", value))
    rows.extend([
        (base + 20, "NaN", None),
        (base + 21, "Infinity", None),
        (base + 22, "-Infinity", None),
        (base + 23, f"-{rng.randrange(1, 400) / 10.0:.1f}", None),
    ])
    rng.shuffle(rows)
    return rows


def _exercise(executable, rows):
    raw = "id,measurement\n" + "\n".join(f"{row_id},{text}" for row_id, text, _ in rows) + "\n"
    with open(RAW_PATH, "w", encoding="utf-8") as f:
        f.write(raw)

    _remove_output(CSV_PATH)
    _remove_output(METRICS_PATH)
    result = subprocess.run(
        [executable], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert result.returncode == 0, f"{executable} failed: {result.stderr}"

    assert os.path.isfile(CSV_PATH), "Executable did not create clean_data.csv"
    assert os.path.isfile(METRICS_PATH), "Executable did not create run_metrics.json"

    expected_lines = ["id,measurement"] + [
        f"{row_id},{value:.1f}" for row_id, _, value in rows if value is not None
    ]
    with open(CSV_PATH, "r", encoding="utf-8") as f:
        actual_lines = [line.strip() for line in f.read().strip().splitlines() if line.strip()]
    assert actual_lines == expected_lines, "clean_data.csv is incorrect for a verifier-generated input"

    with open(METRICS_PATH, "r", encoding="utf-8") as f:
        metrics = json.load(f)
    assert set(metrics.keys()) == {"valid_count", "mean", "sample_variance"}

    values = [value for _, _, value in rows if value is not None]
    mean = sum(values) / len(values)
    variance = sum((value - mean) ** 2 for value in values) / (len(values) - 1)
    assert metrics["valid_count"] == len(values)
    assert math.isclose(metrics["mean"], mean, rel_tol=0.0, abs_tol=1.1e-4)
    assert math.isclose(metrics["sample_variance"], variance, rel_tol=0.0, abs_tol=1.1e-4)


def test_source_and_program_process_generated_inputs():
    assert os.path.exists(SOURCE_PATH), f"Source file {SOURCE_PATH} is missing."
    assert os.path.isfile(SOURCE_PATH), f"{SOURCE_PATH} is not a file."
    with open(EXECUTABLE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE_PATH} is not a compiled executable."

    backups = {}
    for path in (RAW_PATH, CSV_PATH, METRICS_PATH):
        backups[path] = open(path, "rb").read() if os.path.isfile(path) else None

    try:
        with tempfile.TemporaryDirectory() as temp_dir:
            rebuilt = os.path.join(temp_dir, "etl_clean_rebuilt")
            build = subprocess.run(
                ["gcc", "-std=c11", "-O2", SOURCE_PATH, "-o", rebuilt, "-lm"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
            )
            assert build.returncode == 0, f"etl_clean.c does not compile with the math library: {build.stderr}"

            for _ in range(2):
                _exercise(EXECUTABLE_PATH, _make_case())
                _exercise(rebuilt, _make_case())
    finally:
        for path, content in backups.items():
            _remove_output(path)
            if content is not None:
                with open(path, "wb") as f:
                    f.write(content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
