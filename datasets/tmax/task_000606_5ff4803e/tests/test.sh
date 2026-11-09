#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import glob
import random
import secrets
import shutil
import subprocess
import pytest

SCRIPT_PATH = "/home/user/audit_sim.sh"
REPORT_PATH = "/home/user/report.json"
LOG_DIR = "/home/user/sim_logs"


def compute_expected_violations(log_dir=LOG_DIR):
    """Computes the expected violations dynamically from the log files."""
    expected = {}
    log_files = glob.glob(os.path.join(log_dir, "node_*.log"))

    for filepath in log_files:
        filename = os.path.basename(filepath)
        node_name = filename.replace(".log", "")

        violations = 0
        prev_error = 0.0
        prev_step = 0.0

        with open(filepath, "r") as f:
            for i, line in enumerate(f):
                parts = line.strip().split()
                if len(parts) != 3:
                    continue

                step = float(parts[1])
                error = float(parts[2])

                if i > 0 and prev_error > 0.005:
                    # Using a small epsilon to handle floating point inaccuracies
                    if step > (prev_step * 0.5) + 1e-7:
                        violations += 1

                prev_error = error
                prev_step = step

        if violations > 0:
            expected[node_name] = violations

    return expected


def run_audit():
    return subprocess.run(
        [SCRIPT_PATH],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )


def load_report():
    try:
        with open(REPORT_PATH, "r") as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {REPORT_PATH} does not contain valid JSON.")


def test_audit_script_exists_and_executable():
    """Test that the audit script exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_audit_script_runs_on_original_logs():
    """Execute the submitted script and ensure it audits the supplied logs."""
    expected_before = compute_expected_violations()
    log_snapshot = {
        path: open(path, "rb").read()
        for path in glob.glob(os.path.join(LOG_DIR, "node_*.log"))
    }

    result = run_audit()
    assert result.returncode == 0, (
        f"Audit script exited with {result.returncode}. stderr: {result.stderr}"
    )
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."
    assert load_report() == expected_before, "Script output is incorrect for the supplied logs."

    current_paths = set(glob.glob(os.path.join(LOG_DIR, "node_*.log")))
    assert current_paths == set(log_snapshot), "Audit script modified the set of input logs."
    for path, content in log_snapshot.items():
        with open(path, "rb") as f:
            assert f.read() == content, f"Audit script modified input log {path}."


def test_report_json_exists():
    """Test that the report.json file exists."""
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."


def test_report_json_content():
    """Test that the report.json contains the correct violation counts."""
    actual_report = load_report()
    expected_report = compute_expected_violations()

    assert isinstance(actual_report, dict), "The JSON report should be a dictionary."
    assert actual_report == expected_report, f"Report content mismatch. Expected: {expected_report}, but got: {actual_report}"


def test_script_processes_fresh_runtime_logs():
    """Exercise the script on newly generated inputs and independently derive answers."""
    backup_dir = f"/tmp/sim_logs_backup_{secrets.token_hex(8)}"
    old_report = None
    if os.path.exists(REPORT_PATH):
        with open(REPORT_PATH, "rb") as f:
            old_report = f.read()

    os.rename(LOG_DIR, backup_dir)
    os.mkdir(LOG_DIR)

    try:
        rng = random.Random(secrets.randbits(128))

        for node_number in range(1, 6):
            path = os.path.join(LOG_DIR, f"node_{node_number:02d}.log")
            step = rng.uniform(0.04, 0.2)
            rows = []

            for iteration in range(24):
                # Force violations on nodes 2-5, while node 1 is always compliant.
                if iteration == 0 and node_number > 1:
                    error = rng.uniform(0.006, 0.012)
                    next_factor = rng.uniform(0.65, 0.9)
                else:
                    error_kind = rng.choice(["low", "boundary", "high"])
                    if error_kind == "low":
                        error = rng.uniform(0.001, 0.0048)
                    elif error_kind == "boundary":
                        error = 0.005
                    else:
                        error = rng.uniform(0.0055, 0.012)

                    if error > 0.005:
                        if node_number == 1 or rng.random() < 0.55:
                            next_factor = rng.uniform(0.25, 0.48)
                        else:
                            next_factor = rng.uniform(0.62, 0.9)
                    else:
                        next_factor = rng.uniform(0.7, 1.25)

                rows.append((iteration, step, error))
                step *= next_factor

            with open(path, "w") as f:
                for iteration, row_step, error in rows:
                    f.write(f"{iteration} {row_step:.12f} {error:.12f}\n")

        expected = compute_expected_violations()
        assert "node_01" not in expected
        assert all(f"node_{n:02d}" in expected for n in range(2, 6))

        result = run_audit()
        assert result.returncode == 0, (
            f"Audit script failed on fresh logs with {result.returncode}. stderr: {result.stderr}"
        )
        assert os.path.isfile(REPORT_PATH), "Script did not generate report.json."
        actual = load_report()
        assert isinstance(actual, dict), "The JSON report should be a dictionary."
        assert actual == expected, (
            f"Script failed on fresh runtime-generated logs. Expected: {expected}, got: {actual}"
        )
    finally:
        shutil.rmtree(LOG_DIR, ignore_errors=True)
        os.rename(backup_dir, LOG_DIR)
        if old_report is None:
            try:
                os.remove(REPORT_PATH)
            except FileNotFoundError:
                pass
        else:
            with open(REPORT_PATH, "wb") as f:
                f.write(old_report)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
