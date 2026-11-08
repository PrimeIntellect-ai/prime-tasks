#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import math
import csv
import stat
import subprocess
import pytest

SCRIPT_PATH = "/home/user/clean_data.sh"
RAW_PATH = "/home/user/raw_sensors.csv"
OUT_PATH = "/home/user/cleaned_sensors.csv"


def run_submission():
    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"clean_data.sh exited with status {result.returncode}. "
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )


@pytest.fixture(scope="session", autouse=True)
def execute_pipeline_on_original_input():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"Path {SCRIPT_PATH} is not a file."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."

    if os.path.lexists(OUT_PATH) and not os.path.isdir(OUT_PATH):
        os.unlink(OUT_PATH)
    run_submission()


def verify_cleaned_content(raw_path, out_path):
    raw_rows = []
    with open(raw_path, "r") as f:
        reader = csv.reader(f)
        header = next(reader)
        for row in reader:
            if not row:
                continue
            id_, x, y, z, ts = row
            mag = math.sqrt(float(x) ** 2 + float(y) ** 2 + float(z) ** 2)
            raw_rows.append((row, mag))

    sample_mags = [
        mag for i, (row, mag) in enumerate(raw_rows, start=1) if i % 7 == 0
    ]

    n = len(sample_mags)
    assert n > 0, "No samples found, raw data might be empty or too short."
    mean = sum(sample_mags) / n
    variance = sum((m - mean) ** 2 for m in sample_mags) / n
    std = math.sqrt(variance)

    lower_bound = mean - 1.5 * std
    upper_bound = mean + 1.5 * std

    expected_kept = []
    for row, mag in raw_rows:
        if lower_bound < mag < upper_bound:
            expected_kept.append(row + [f"{mag:.4f}"])

    with open(out_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 2, "Output file must contain at least a header and a stats line."

    out_header = lines[0]
    assert out_header == "id,x,y,z,timestamp,magnitude", f"Incorrect header: {out_header}"

    stats_line = lines[-1]
    expected_stats = f"# STATS: mean={mean:.4f}, std={std:.4f}"
    assert stats_line == expected_stats, (
        f"Incorrect stats line. Expected '{expected_stats}', got '{stats_line}'"
    )

    data_lines = lines[1:-1]
    assert len(data_lines) == len(expected_kept), (
        f"Expected {len(expected_kept)} data rows, but found {len(data_lines)}."
    )

    for i, (actual, expected) in enumerate(zip(data_lines, expected_kept)):
        actual_parts = actual.split(",")
        assert len(actual_parts) == 6, f"Row {i + 1} does not have 6 columns: {actual}"
        assert actual_parts[:5] == expected[:5], (
            f"Original columns do not match in row {i + 1}. "
            f"Expected {expected[:5]}, got {actual_parts[:5]}"
        )
        actual_mag = float(actual_parts[5])
        expected_mag = float(expected[5])
        assert math.isclose(actual_mag, expected_mag, abs_tol=1e-4), (
            f"Magnitude mismatch in row {i + 1}. "
            f"Expected ~{expected_mag}, got {actual_mag}"
        )


def test_script_exists_and_executable():
    """Check that the script exists and is executable."""
    script_path = "/home/user/clean_data.sh"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.path.isfile(script_path), f"Path {script_path} is not a file."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."


def test_cleaned_csv_exists():
    """Check that the output file exists."""
    out_path = "/home/user/cleaned_sensors.csv"
    assert os.path.exists(out_path), f"Output file {out_path} does not exist."
    assert os.path.isfile(out_path), f"Path {out_path} is not a file."


def test_cleaned_csv_content():
    """Verify the content of the cleaned dataset according to the task rules."""
    verify_cleaned_content(RAW_PATH, OUT_PATH)


def test_pipeline_runs_autonomously_on_changed_input():
    """Reject scripts that merely recreate a hard-coded answer for the original CSV."""
    with open(RAW_PATH, "rb") as f:
        original_raw = f.read()

    challenge_lines = ["id,x,y,z,timestamp"]
    for i in range(1, 29):
        x = ((i * 7) % 19) - 5
        y = ((i * 3) % 11) - 4
        z = ((i * 5) % 13) - 6
        challenge_lines.append(f"c{i},{x}.25,{y}.5,{z}.75,{9000 + i}")
    challenge_data = "\n".join(challenge_lines) + "\n"

    try:
        with open(RAW_PATH, "w") as f:
            f.write(challenge_data)
        if os.path.lexists(OUT_PATH) and not os.path.isdir(OUT_PATH):
            os.unlink(OUT_PATH)
        run_submission()
        assert os.path.exists(OUT_PATH), f"Output file {OUT_PATH} does not exist."
        assert os.path.isfile(OUT_PATH), f"Path {OUT_PATH} is not a file."
        verify_cleaned_content(RAW_PATH, OUT_PATH)
    finally:
        with open(RAW_PATH, "wb") as f:
            f.write(original_raw)
        if os.path.lexists(OUT_PATH) and not os.path.isdir(OUT_PATH):
            os.unlink(OUT_PATH)
        try:
            run_submission()
        except Exception:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
