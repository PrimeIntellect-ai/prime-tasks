#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pathlib
import random
import secrets
import subprocess

import pytest


def test_jq_installed_and_executable():
    """Assert /home/user/bin/jq exists and is executable."""
    jq_path = "/home/user/bin/jq"
    assert os.path.isfile(jq_path), f"jq binary not found at {jq_path}"
    assert os.access(jq_path, os.X_OK), f"jq binary at {jq_path} is not executable"


def test_jq_is_working_version_1_6():
    """Execute the installed jq and verify its version and basic JSON behavior."""
    jq_path = "/home/user/bin/jq"
    with open(jq_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Installed jq must be a linux64 binary"

    version = subprocess.run(
        [jq_path, "--version"], capture_output=True, text=True, timeout=10
    )
    assert version.returncode == 0, f"jq --version failed: {version.stderr}"
    assert version.stdout.strip() == "jq-1.6", f"Expected jq-1.6, got {version.stdout.strip()!r}"

    probe = subprocess.run(
        [jq_path, "-c", "[.[] | {run: .id, loss: (.loss // 0.5), acc: .acc}]"],
        input='[{"id":"probe","loss":null,"acc":0.25}]',
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert probe.returncode == 0, f"jq functional probe failed: {probe.stderr}"
    assert json.loads(probe.stdout) == [{"run": "probe", "loss": 0.5, "acc": 0.25}]


def test_scripts_exist():
    """Assert the required Bash scripts exist."""
    process_script = "/home/user/process_metrics.sh"
    test_script = "/home/user/test_pipeline.sh"

    assert os.path.isfile(process_script), f"Process script not found at {process_script}"
    assert os.path.isfile(test_script), f"Test script not found at {test_script}"


def test_cleaned_metrics_json():
    """Assert /home/user/cleaned_metrics.json is valid JSON and matches expected records."""
    json_path = "/home/user/cleaned_metrics.json"
    assert os.path.isfile(json_path), f"JSON output not found at {json_path}"

    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} does not contain valid JSON.")

    assert isinstance(data, list), f"JSON root must be an array, got {type(data)}"
    assert len(data) == 4, f"Expected 4 records in JSON array, found {len(data)}"

    expected_records = [
        {"run": "runA", "loss": 0.85, "acc": 0.72},
        {"run": "runA", "loss": 0.5, "acc": 0.75},
        {"run": "runB", "loss": 0.9, "acc": 0.6},
        {"run": "runB", "loss": 0.5, "acc": 0.85}
    ]

    for i, expected in enumerate(expected_records):
        record = data[i]
        assert record.get("run") == expected["run"], f"Record {i}: expected run '{expected['run']}', got '{record.get('run')}'"
        assert float(record.get("loss")) == expected["loss"], f"Record {i}: expected loss {expected['loss']}, got {record.get('loss')}"
        assert float(record.get("acc")) == expected["acc"], f"Record {i}: expected acc {expected['acc']}, got {record.get('acc')}"


def test_test_results_log():
    """Assert /home/user/test_results.log contains the expected test output."""
    log_path = "/home/user/test_results.log"
    assert os.path.isfile(log_path), f"Test results log not found at {log_path}"

    with open(log_path, 'r') as f:
        content = f.read().strip()

    expected_str = "Test passed: 4 valid records found."
    assert expected_str in content, f"Expected string '{expected_str}' not found in {log_path}. Content was: '{content}'"


def test_scripts_execute_on_unseen_metrics():
    """Run both submitted scripts against an unpredictable CSV fixture."""
    csv_path = pathlib.Path("/home/user/ml_metrics.csv")
    json_path = pathlib.Path("/home/user/cleaned_metrics.json")
    log_path = pathlib.Path("/home/user/test_results.log")
    paths = (csv_path, json_path, log_path)
    backups = {p: p.read_bytes() if p.exists() else None for p in paths}

    try:
        rng = random.SystemRandom()
        token = secrets.token_hex(6)
        valid_count = rng.randint(3, 7)
        rows = []

        for i in range(valid_count):
            run_id = f"dynamic_{token}_{i}"
            loss = "" if i % 2 == 0 else f"{rng.randint(1, 950) / 1000:.3f}"
            if i == 0:
                accuracy = "0.0"
            elif i == 1:
                accuracy = "1.0"
            else:
                accuracy = f"{rng.randint(1, 999) / 1000:.3f}"
            rows.append((run_id, str(rng.randint(1, 50)), loss, accuracy, True))

        rows.extend([
            (f"too_high_{token}", "51", "0.321", f"{1 + rng.randint(1, 500) / 1000:.3f}", False),
            (f"too_low_{token}", "52", "", f"{-rng.randint(1, 500) / 1000:.3f}", False),
        ])
        rng.shuffle(rows)

        expected = []
        csv_lines = ["run_id,epoch,loss,accuracy"]
        for run_id, epoch, loss, accuracy, retained in rows:
            csv_lines.append(",".join((run_id, epoch, loss, accuracy)))
            if retained:
                expected.append({
                    "run": run_id,
                    "loss": 0.5 if loss == "" else float(loss),
                    "acc": float(accuracy),
                })

        csv_path.write_text("\n".join(csv_lines) + "\n")
        json_path.unlink(missing_ok=True)
        log_path.unlink(missing_ok=True)

        env = "HOME=/home/user"
        path_env = "PATH=/home/user/bin:/usr/bin:/bin"
        process_run = subprocess.run(
            ["runuser", "-u", "user", "--", "env", env, path_env,
             "bash", "/home/user/process_metrics.sh"],
            cwd="/home/user", capture_output=True, text=True, timeout=20,
        )
        assert process_run.returncode == 0, (
            f"process_metrics.sh failed on an unseen fixture: {process_run.stderr}"
        )
        assert json_path.is_file(), "process_metrics.sh did not create cleaned_metrics.json"

        try:
            actual = json.loads(json_path.read_text())
        except json.JSONDecodeError as exc:
            pytest.fail(f"process_metrics.sh produced invalid JSON: {exc}")

        assert isinstance(actual, list), "Dynamic output root must be a JSON array"
        assert len(actual) == len(expected), (
            f"Expected {len(expected)} dynamically retained rows, got {len(actual)}"
        )
        for i, (record, wanted) in enumerate(zip(actual, expected)):
            assert isinstance(record, dict), f"Dynamic record {i} is not an object"
            assert set(record) == {"run", "loss", "acc"}, (
                f"Dynamic record {i} must have exactly run, loss, and acc keys"
            )
            assert record["run"] == wanted["run"]
            assert isinstance(record["run"], str)
            assert isinstance(record["loss"], (int, float)) and not isinstance(record["loss"], bool)
            assert isinstance(record["acc"], (int, float)) and not isinstance(record["acc"], bool)
            assert float(record["loss"]) == wanted["loss"]
            assert float(record["acc"]) == wanted["acc"]

        test_run = subprocess.run(
            ["runuser", "-u", "user", "--", "env", env, path_env,
             "bash", "/home/user/test_pipeline.sh"],
            cwd="/home/user", capture_output=True, text=True, timeout=20,
        )
        assert test_run.returncode == 0, f"test_pipeline.sh failed: {test_run.stderr}"
        expected_message = f"Test passed: {len(expected)} valid records found."
        assert test_run.stdout.strip() == expected_message, (
            f"Expected exactly {expected_message!r}, got {test_run.stdout.strip()!r}"
        )
    finally:
        for path, content in backups.items():
            if content is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(content)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
