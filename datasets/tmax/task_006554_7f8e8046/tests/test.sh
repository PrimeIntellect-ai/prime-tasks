#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import shutil
import string
import subprocess
import tempfile

MOCKS_DIR = "/home/user/api_mocks"
PROJECT_DIR = "/home/user/latency_analyzer"
MERGED_PATH = "/home/user/merged_latencies.txt"
BASELINE_PATH = "/home/user/baseline_latencies.txt"
PATCH_PATH = "/home/user/latency_diff.patch"

EXPECTED_PAYLOADS = {
    "payload_a.json": {"api_version": "1.2.5", "data": [45, 60, 32]},
    "payload_b.json": {"api_version": "1.4.1", "data": [55, 42, 88]},
    "payload_c.json": {"api_version": "1.5.0", "data": [12, 18]},
    "payload_d.json": {"api_version": "2.0.1", "data": [99, 100, 101]},
    "payload_e.json": {"api_version": "1.9.9", "data": [77, 81]},
}


def run_analyzer():
    if os.path.exists(MERGED_PATH):
        os.remove(MERGED_PATH)
    result = subprocess.run(
        ["cargo", "run", "--quiet"],
        cwd=PROJECT_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"Rust analyzer failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(MERGED_PATH), "Running the Rust analyzer did not create merged_latencies.txt."


def read_merged():
    with open(MERGED_PATH, "r") as f:
        return f.read().strip().split("\n")


def test_api_mocks_and_baseline_exist():
    """Verify the api_mocks directory, its files, and the baseline file exist with correct contents."""
    assert os.path.isdir(MOCKS_DIR), f"Directory {MOCKS_DIR} does not exist."

    for filename, expected_content in EXPECTED_PAYLOADS.items():
        filepath = os.path.join(MOCKS_DIR, filename)
        assert os.path.isfile(filepath), f"Mock file {filepath} is missing."
        with open(filepath, "r") as f:
            content = json.load(f)
        assert content == expected_content, f"Content of {filepath} does not match expected."

    assert os.path.isfile(BASELINE_PATH), f"Baseline file {BASELINE_PATH} is missing."
    with open(BASELINE_PATH, "r") as f:
        baseline_content = f.read().strip().split("\n")
    assert baseline_content == ["12", "15", "18", "42", "55", "77", "88"], "Baseline content is incorrect."


def test_rust_project_exists():
    """Verify the Rust project directory and basic files exist."""
    assert os.path.isdir(PROJECT_DIR), f"Rust project directory {PROJECT_DIR} does not exist."
    assert os.path.isfile(os.path.join(PROJECT_DIR, "Cargo.toml")), "Cargo.toml is missing."
    assert os.path.isfile(os.path.join(PROJECT_DIR, "src", "main.rs")), "src/main.rs is missing."


def test_merged_latencies_correct():
    """Verify the submitted merged_latencies.txt has the correct sorted integers."""
    assert os.path.isfile(MERGED_PATH), f"Merged latencies file {MERGED_PATH} is missing."
    expected_lines = ["12", "18", "42", "55", "77", "81", "88"]
    lines = read_merged()
    assert lines == expected_lines, f"Content of {MERGED_PATH} is incorrect. Expected {expected_lines}, got {lines}."


def test_latency_diff_patch_correct():
    """Verify the latency_diff.patch file exists and is the actual unified diff."""
    assert os.path.isfile(PATCH_PATH), f"Diff patch file {PATCH_PATH} is missing."

    with open(PATCH_PATH, "r") as f:
        patch_content = f.read()

    assert "--- /home/user/baseline_latencies.txt" in patch_content, "Patch missing baseline file header."
    assert "+++ /home/user/merged_latencies.txt" in patch_content, "Patch missing merged file header."

    lines = patch_content.split("\n")
    assert "-15" in lines, "Patch is missing the removed line '-15'."
    assert "+81" in lines, "Patch is missing the added line '+81'."

    expected = subprocess.run(
        ["diff", "-u", BASELINE_PATH, MERGED_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert expected.returncode == 1, f"diff failed unexpectedly: {expected.stderr}"
    assert patch_content == expected.stdout, "latency_diff.patch is not the exact output of diff -u for the submitted files."


def test_rust_analyzer_executes_and_handles_derived_inputs():
    """Build and run the analyzer, then exercise it on unpredictable compatible and incompatible versions."""
    run_analyzer()
    expected_original = ["12", "18", "42", "55", "77", "81", "88"]
    assert read_merged() == expected_original, "Running the analyzer on the required fixtures produced incorrect output."

    rng = random.SystemRandom()
    token = "".join(rng.choice(string.ascii_lowercase) for _ in range(10))
    values = [rng.randrange(100, 10000) for _ in range(12)]
    dynamic_payloads = [
        ({"api_version": f"1.3.{rng.randrange(0, 100)}", "data": values[0:2]}, False),
        ({"api_version": f"1.4.{rng.randrange(0, 100)}", "data": values[2:5]}, True),
        ({"api_version": f"1.{rng.randrange(5, 99)}.{rng.randrange(0, 100)}", "data": values[5:8]}, True),
        ({"api_version": f"2.{rng.randrange(0, 10)}.{rng.randrange(0, 100)}", "data": values[8:10]}, False),
        ({"api_version": f"0.{rng.randrange(0, 99)}.{rng.randrange(0, 100)}", "data": values[10:12]}, False),
    ]
    expected_dynamic = sorted(
        number
        for payload, included in dynamic_payloads
        if included
        for number in payload["data"]
    )

    backup_parent = tempfile.mkdtemp(prefix="latency-verifier-")
    backup_dir = os.path.join(backup_parent, "api_mocks")
    shutil.copytree(MOCKS_DIR, backup_dir)
    try:
        shutil.rmtree(MOCKS_DIR)
        os.makedirs(MOCKS_DIR)
        for index, (payload, _) in enumerate(dynamic_payloads):
            path = os.path.join(MOCKS_DIR, f"derived_{token}_{index}.json")
            with open(path, "w") as f:
                json.dump(payload, f)

        run_analyzer()
        expected_lines = [str(number) for number in expected_dynamic]
        actual_lines = read_merged()
        assert actual_lines == expected_lines, (
            "Analyzer failed derived semantic-version filtering/merging/sorting test. "
            f"Expected {expected_lines}, got {actual_lines}."
        )
    finally:
        if os.path.exists(MOCKS_DIR):
            shutil.rmtree(MOCKS_DIR)
        shutil.copytree(backup_dir, MOCKS_DIR)
        shutil.rmtree(backup_parent)

    run_analyzer()
    assert read_merged() == expected_original, "Analyzer did not reproduce the required output after fixture restoration."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
