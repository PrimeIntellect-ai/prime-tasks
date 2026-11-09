#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import shutil
import subprocess
import pytest


def test_aggregator_patched():
    """Verify that aggregator.py is patched and respects CAP_PLAN_DIR."""
    aggregator_path = "/app/vendor/cap-plan-tools-1.0.0/aggregator.py"
    assert os.path.isfile(aggregator_path), "aggregator.py is missing."

    test_dir = "/tmp/test_cap_plan"
    shutil.rmtree(test_dir, ignore_errors=True)
    os.makedirs(test_dir, exist_ok=True)

    env = os.environ.copy()
    env["CAP_PLAN_DIR"] = test_dir

    result = subprocess.run(
        ["python3", aggregator_path, "--verify"],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )

    assert result.returncode == 0, f"aggregator.py failed with exit code {result.returncode}. Stderr: {result.stderr.decode()}"
    assert os.path.isfile(os.path.join(test_dir, "state.db")), "state.db was not created in the specified CAP_PLAN_DIR."


def test_aggregator_fallback_path():
    """Verify that an unset CAP_PLAN_DIR falls back to /home/user/cap_plan."""
    aggregator_path = "/app/vendor/cap-plan-tools-1.0.0/aggregator.py"
    fallback_dir = "/home/user/cap_plan"
    fallback_state = os.path.join(fallback_dir, "state.db")
    os.makedirs(fallback_dir, exist_ok=True)
    if os.path.exists(fallback_state):
        os.remove(fallback_state)

    env = os.environ.copy()
    env.pop("CAP_PLAN_DIR", None)
    result = subprocess.run(
        ["python3", aggregator_path, "--verify"],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )

    assert result.returncode == 0, f"aggregator.py failed using its fallback: {result.stderr.decode()}"
    assert os.path.isfile(fallback_state), "state.db was not created in /home/user/cap_plan when CAP_PLAN_DIR was unset."


def test_sanitize_exists_and_executable():
    """Verify that sanitize.py exists and is executable."""
    sanitize_path = "/home/user/sanitize.py"
    assert os.path.isfile(sanitize_path), f"{sanitize_path} is missing."
    assert os.access(sanitize_path, os.X_OK), f"{sanitize_path} is not executable."


def test_cap_plan_logs_dir_exists():
    """Verify that the logs directory was created."""
    logs_dir = "/home/user/cap_plan/logs/"
    assert os.path.isdir(logs_dir), f"Directory {logs_dir} is missing."


def test_adversarial_corpus_clean():
    """Verify that all clean records are perfectly preserved."""
    clean_dir = "/app/corpora/clean"
    sanitize_path = "/home/user/sanitize.py"

    if not os.path.isdir(clean_dir):
        pytest.skip("Clean corpus directory not found.")

    clean_files = [f for f in os.listdir(clean_dir) if f.endswith(".jsonl")]
    modified_files = []

    for filename in clean_files:
        filepath = os.path.join(clean_dir, filename)
        with open(filepath, "r") as f:
            input_data = f.read()

        result = subprocess.run(
            ["python3", sanitize_path],
            input=input_data,
            text=True,
            capture_output=True
        )

        input_lines = [json.loads(line) for line in input_data.strip().split("\n") if line.strip()]
        try:
            output_lines = [json.loads(line) for line in result.stdout.strip().split("\n") if line.strip()]
        except json.JSONDecodeError:
            modified_files.append(filename)
            continue

        if input_lines != output_lines:
            modified_files.append(filename)

    assert not modified_files, f"{len(modified_files)} of {len(clean_files)} clean modified. Offending files: {', '.join(modified_files)}"


def test_adversarial_corpus_evil():
    """Verify that all evil records are completely rejected."""
    evil_dir = "/app/corpora/evil"
    sanitize_path = "/home/user/sanitize.py"

    if not os.path.isdir(evil_dir):
        pytest.skip("Evil corpus directory not found.")

    evil_files = [f for f in os.listdir(evil_dir) if f.endswith(".jsonl")]
    bypassed_files = []

    for filename in evil_files:
        filepath = os.path.join(evil_dir, filename)
        with open(filepath, "r") as f:
            input_data = f.read()

        result = subprocess.run(
            ["python3", sanitize_path],
            input=input_data,
            text=True,
            capture_output=True
        )

        if result.stdout.strip():
            bypassed_files.append(filename)

    assert not bypassed_files, f"{len(bypassed_files)} of {len(evil_files)} evil bypassed. Offending files: {', '.join(bypassed_files)}"


def test_sanitizer_dynamic_per_line_filtering():
    """Exercise every rule in mixed, unpredictable streams and preserve valid neighbors."""
    sanitize_path = "/home/user/sanitize.py"
    token = secrets.token_hex(12)

    valid_records = [
        {"process_name": f"worker_{token}_zero", "cpu_percent": 0, "memory_mb": 0, "tag": token},
        {"process_name": f"worker_{token}_max", "cpu_percent": 100, "memory_mb": 1.25},
        {"process_name": f"worker_{token}_mid", "cpu_percent": 37.125, "memory_mb": 9876, "nested": {"id": token}},
    ]

    bad_records = [
        {"process_name": f"bad_{token}_negcpu", "cpu_percent": -0.01, "memory_mb": 20},
        {"process_name": f"bad_{token}_highcpu", "cpu_percent": 100.01, "memory_mb": 20},
        {"process_name": f"bad_{token}_negmem", "cpu_percent": 20, "memory_mb": -0.01},
        {"process_name": f"bad_{token}_missingcpu", "memory_mb": 20},
        {"process_name": f"bad_{token}_missingmem", "cpu_percent": 20},
    ]
    for metachar in ";&|<>":
        bad_records.append({
            "process_name": f"bad_{token}{metachar}payload",
            "cpu_percent": 20,
            "memory_mb": 20,
        })

    entries = [(json.dumps(record), record) for record in valid_records]
    entries.extend((json.dumps(record), None) for record in bad_records)
    entries.append((f"not-json-{token} {{{{", None))
    random.SystemRandom().shuffle(entries)

    input_data = "\n".join(line for line, _ in entries) + "\n"
    expected = [record for _, record in entries if record is not None]

    result = subprocess.run(
        [sanitize_path],
        input=input_data,
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert result.returncode == 0, f"sanitize.py exited with {result.returncode}: {result.stderr}"

    try:
        actual = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
    except json.JSONDecodeError as exc:
        pytest.fail(f"sanitize.py emitted non-JSON output: {exc}")

    assert actual == expected, f"Per-line filtering mismatch. Expected {expected!r}, got {actual!r}"


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
