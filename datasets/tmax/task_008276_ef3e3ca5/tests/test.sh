#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
from pathlib import Path
import secrets
import shutil
import subprocess

import pytest


def test_summary_json_exists():
    """Check if the output summary file exists."""
    assert os.path.isfile("/home/user/summary.json"), "The file /home/user/summary.json does not exist."


def test_summary_json_content():
    """Validate the structure and values of the summary JSON file."""
    file_path = "/home/user/summary.json"

    try:
        with open(file_path, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {file_path} does not contain valid JSON.")

    expected_keys = {"valid_count", "invalid_count", "average_joint_prob"}
    actual_keys = set(data.keys())

    assert expected_keys.issubset(actual_keys), f"Missing keys in summary.json. Expected: {expected_keys}, Found: {actual_keys}"
    assert data["valid_count"] == 5, f"Expected valid_count to be 5, but got {data['valid_count']}."
    assert data["invalid_count"] == 3, f"Expected invalid_count to be 3, but got {data['invalid_count']}."

    expected_avg = 0.332
    actual_avg = data["average_joint_prob"]
    assert math.isclose(actual_avg, expected_avg, rel_tol=1e-3, abs_tol=1e-3), \
        f"Expected average_joint_prob to be near {expected_avg}, but got {actual_avg}."


def test_go_script_exists():
    """Check if the Go pipeline script was created."""
    assert os.path.isfile("/home/user/etl_pipeline.go"), "The Go script /home/user/etl_pipeline.go does not exist."


def test_compiled_pipeline_on_unseen_data():
    """Run the compiled submission against fresh data and derive the expected result."""
    rng = secrets.SystemRandom()
    vals = [rng.randint(101, 899) / 1000.0 for _ in range(8)]

    valid = [
        {"id": 9001, "prior": vals[0], "likelihood": vals[1], "actual_class": 1},
        {"id": 9002, "prior": vals[2], "likelihood": vals[3], "actual_class": 0},
        {"id": 9003, "prior": 0.0, "likelihood": 1.0, "actual_class": 1},
        {"id": 9004, "prior": 1.0, "likelihood": 0.0, "actual_class": 0},
        {"id": 9005, "prior": vals[4], "likelihood": vals[5], "actual_class": 1},
        {"id": 9006, "prior": vals[6], "likelihood": vals[7], "actual_class": 0},
    ]
    invalid = [
        {"id": 9101, "prior": -0.01, "likelihood": 0.5, "actual_class": 1},
        {"id": 9102, "prior": 1.01, "likelihood": 0.5, "actual_class": 0},
        {"id": 9103, "prior": 0.5, "likelihood": 1.01, "actual_class": 1},
        {"id": 9104, "prior": 0.5, "likelihood": 0.5, "actual_class": 2},
    ]

    joints = []
    for record in valid:
        if record["actual_class"] == 1:
            joints.append(record["prior"] * record["likelihood"])
        else:
            joints.append((1.0 - record["prior"]) * (1.0 - record["likelihood"]))
    expected_average = sum(joints) / len(joints)

    raw_dir = Path("/home/user/raw_data")
    backup_dir = Path(f"/home/user/raw_data.verifier-backup-{os.getpid()}")
    summary = Path("/home/user/summary.json")
    prior_summary = summary.read_bytes() if summary.exists() else None

    assert not backup_dir.exists()
    raw_dir.rename(backup_dir)
    raw_dir.mkdir()
    try:
        (raw_dir / "unseen_a.json").write_text(json.dumps(valid[:3] + invalid[:2]))
        (raw_dir / "unseen_b.json").write_text(json.dumps(valid[3:] + invalid[2:]))
        # A non-JSON file must not be extracted.
        (raw_dir / "ignored.txt").write_text(json.dumps([
            {"id": 9999, "prior": -50, "likelihood": -50, "actual_class": 9}
        ]))

        if summary.exists():
            summary.unlink()
        subprocess.run(
            ["/tmp/etl_pipeline_submission"],
            cwd="/home/user",
            check=True,
            timeout=15,
        )

        assert summary.is_file(), "The compiled pipeline did not create /home/user/summary.json"
        with summary.open() as f:
            result = json.load(f)

        assert set(result.keys()) == {"valid_count", "invalid_count", "average_joint_prob"}
        assert result["valid_count"] == len(valid)
        assert result["invalid_count"] == len(invalid)
        assert math.isclose(
            result["average_joint_prob"], expected_average,
            rel_tol=1e-9, abs_tol=1e-9,
        )
    finally:
        shutil.rmtree(raw_dir, ignore_errors=True)
        backup_dir.rename(raw_dir)
        if prior_summary is None:
            summary.unlink(missing_ok=True)
        else:
            summary.write_bytes(prior_summary)
TEST_EOF

if (
    set -e
    test -f /home/user/etl_pipeline.go
    cd /home/user
    go build -o /tmp/etl_pipeline_submission ./etl_pipeline.go
    rm -f /home/user/summary.json
    timeout 15 /tmp/etl_pipeline_submission
    python3 -m pytest /tmp/test_final_state.py -x --tb=short
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
