#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import subprocess
import tempfile
import uuid

SCRIPT_PATH = "/home/user/validate_configs.py"
POLICY_PATH = "/app/policy_rules.png"
EVIL_DIR = "/app/configs/evil/"
CLEAN_DIR = "/app/configs/clean/"


def read_policy():
    text = subprocess.check_output(
        ["tesseract", POLICY_PATH, "stdout"], text=True, stderr=subprocess.DEVNULL
    )
    patterns = {
        "default": r"Imputation\s+Default\s*:\s*(\d+)",
        "max_cpu": r"Max\s+CPU\s+Threshold\s*:\s*(\d+)",
        "max_delta": r"Max\s+Aggregated\s+Delta\s*:\s*(\d+)",
    }
    values = {}
    for key, pattern in patterns.items():
        match = re.search(pattern, text, re.IGNORECASE)
        assert match, f"Could not extract {key} from policy image OCR: {text!r}"
        values[key] = int(match.group(1))
    return values


POLICY = read_policy()


def run_script(directory):
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    result = subprocess.run(
        ["python3", SCRIPT_PATH, directory],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, result.stderr
    return result.stdout


def parse_output(output):
    results = {}
    for line in output.strip().split("\n"):
        if not line.strip() or ": " not in line:
            continue
        filename, status = line.split(": ", 1)
        filename = filename.strip()
        # The required output spelling encloses the filename in brackets.
        if filename.startswith("[") and filename.endswith("]"):
            filename = filename[1:-1].strip()
        results[filename] = status.strip()
    return results


def classify(states):
    missing = sum(
        int("cpu" not in state) + int("memory" not in state)
        for state in states
    )
    memories = [state.get("memory", POLICY["default"]) for state in states]
    delta = sum(abs(b - a) for a, b in zip(memories, memories[1:]))
    cpu_exceeded = any(
        "cpu" in state and state["cpu"] > POLICY["max_cpu"]
        for state in states
    )
    return "INVALID" if cpu_exceeded or delta > POLICY["max_delta"] or missing > 2 else "VALID"


def test_evil_corpus():
    stdout = run_script(EVIL_DIR)
    results = parse_output(stdout)

    evil_files = [f for f in os.listdir(EVIL_DIR) if f.endswith(".json")]
    bypassed = []
    for filename in evil_files:
        if results.get(filename) != "INVALID":
            bypassed.append(filename)

    assert not bypassed, f"{len(bypassed)} of {len(evil_files)} evil bypassed: {bypassed}"


def test_clean_corpus():
    stdout = run_script(CLEAN_DIR)
    results = parse_output(stdout)

    clean_files = [f for f in os.listdir(CLEAN_DIR) if f.endswith(".json")]
    modified = []
    for filename in clean_files:
        if results.get(filename) != "VALID":
            modified.append(filename)

    assert not modified, f"{len(modified)} of {len(clean_files)} clean modified/rejected: {modified}"


def test_generated_corpus():
    default = POLICY["default"]
    max_cpu = POLICY["max_cpu"]
    max_delta = POLICY["max_delta"]

    cases = [
        [{"cpu": max_cpu, "memory": default}],
        [{"cpu": max_cpu + 1, "memory": default}],
        [{"cpu": 1, "memory": default}, {"cpu": 1, "memory": default + max_delta}],
        [{"cpu": 1, "memory": default}, {"cpu": 1, "memory": default + max_delta + 1}],
        [{}, {"cpu": 1, "memory": default}],
        [{}, {"memory": default}],
        [{"cpu": 1}, {"cpu": 1, "memory": default + max_delta + 1}],
        [
            {"cpu": 1, "memory": default},
            {"cpu": 1, "memory": default + max_delta},
            {"cpu": 1, "memory": default},
        ],
    ]

    rng = random.SystemRandom()
    counts = {"VALID": 0, "INVALID": 0}
    while min(counts.values()) < 12:
        states = []
        for _ in range(rng.randint(1, 6)):
            state = {}
            if rng.random() < 0.8:
                state["cpu"] = rng.randint(0, max_cpu + 5)
            if rng.random() < 0.8:
                state["memory"] = rng.randint(0, default + max_delta + 500)
            states.append(state)
        label = classify(states)
        if counts[label] < 12:
            cases.append(states)
            counts[label] += 1

    with tempfile.TemporaryDirectory(prefix="config-validation-") as directory:
        expected = {}
        for states in cases:
            filename = f"case_{uuid.uuid4().hex}.json"
            with open(os.path.join(directory, filename), "w", encoding="utf-8") as handle:
                json.dump(states, handle)
            expected[filename] = classify(states)

        stdout = run_script(directory)
        results = parse_output(stdout)
        wrong = {
            filename: (expected_status, results.get(filename))
            for filename, expected_status in expected.items()
            if results.get(filename) != expected_status
        }
        assert not wrong, f"Generated configurations misclassified: {wrong}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
