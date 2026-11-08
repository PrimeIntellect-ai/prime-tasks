#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import tempfile
import pytest


def get_detect_script():
    user_dir = "/home/user"
    if not os.path.isdir(user_dir):
        return None
    for file in os.listdir(user_dir):
        if file.startswith("detect_leak"):
            full_path = os.path.join(user_dir, file)
            if os.path.isfile(full_path) and os.access(full_path, os.X_OK):
                return full_path
    # Preserve the original fallback so the existence assertion remains intact.
    for file in os.listdir(user_dir):
        if file.startswith("detect_leak") and file.endswith(".py"):
            return os.path.join(user_dir, file)
    return None


def run_script(script_path, *args):
    if script_path.endswith(".py") and not os.access(script_path, os.X_OK):
        cmd = ["python3", script_path, *args]
    else:
        cmd = [script_path, *args]
    return subprocess.run(cmd, capture_output=True, timeout=5)


def test_detect_leak_executable_exists():
    script_path = get_detect_script()
    assert script_path is not None, "Could not find an executable script starting with 'detect_leak' in /home/user/"
    assert os.access(script_path, os.X_OK), "Detector script must be executable"


def test_adversarial_corpus():
    script_path = get_detect_script()
    assert script_path is not None, "Script not found."

    evil_dir = "/app/eval/evil"
    clean_dir = "/app/eval/clean"

    assert os.path.isdir(evil_dir), f"Missing evil eval directory at {evil_dir}"
    assert os.path.isdir(clean_dir), f"Missing clean eval directory at {clean_dir}"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    evil_bypassed = []
    clean_modified = []

    for filepath in evil_files:
        code = run_script(script_path, filepath).returncode
        if code != 1:
            evil_bypassed.append(os.path.basename(filepath))

    for filepath in clean_files:
        code = run_script(script_path, filepath).returncode
        if code != 0:
            clean_modified.append(os.path.basename(filepath))

    total_evil = len(evil_files)
    total_clean = len(clean_files)

    error_msg = []
    if evil_bypassed:
        error_msg.append(f"{len(evil_bypassed)} of {total_evil} evil bypassed (expected exit code 1): {', '.join(evil_bypassed[:5])}")
    if clean_modified:
        error_msg.append(f"{len(clean_modified)} of {total_clean} clean modified/rejected (expected exit code 0): {', '.join(clean_modified[:5])}")

    if error_msg:
        pytest.fail(" | ".join(error_msg))


def expected_code(lines):
    split_positions = [i for i, operation in enumerate(lines) if operation == "train_test_split"]
    leaked = any("fit" in lines[i] for split in split_positions for i in range(split))
    return 1 if leaked else 0


def safe_operation():
    # The random suffix alphabet cannot accidentally introduce the substring 'fit'.
    prefix = random.SystemRandom().choice(["load", "clean", "encode", "normalize", "predict", "validate"])
    suffix = "".join(random.SystemRandom().choice("abcdeghjklmnopqrsuvwxyz0123456789") for _ in range(12))
    return f"{prefix}_{suffix}"


def test_runtime_generated_logs_and_argument_count():
    script_path = get_detect_script()
    assert script_path is not None, "Script not found."

    rng = random.SystemRandom()
    workdir = tempfile.mkdtemp(prefix="pipeline_logs_", dir="/tmp")
    cases = []

    for case_number in range(32):
        before = [safe_operation() for _ in range(rng.randint(1, 6))]
        after = [safe_operation() for _ in range(rng.randint(1, 6))]
        fit_operation = f"transform_fit_{secrets.token_hex(8)}"

        if case_number % 2 == 0:
            before.insert(rng.randrange(len(before) + 1), fit_operation)
        elif case_number % 4 == 1:
            after.insert(rng.randrange(len(after) + 1), fit_operation)

        lines = before + ["train_test_split"] + after
        filepath = os.path.join(workdir, secrets.token_hex(16) + ".txt")
        with open(filepath, "w", encoding="utf-8") as handle:
            handle.write("\n".join(lines) + "\n")
        cases.append((filepath, expected_code(lines)))

    rng.shuffle(cases)
    failures = []
    for filepath, expected in cases:
        actual = run_script(script_path, filepath).returncode
        if actual != expected:
            failures.append(f"{os.path.basename(filepath)}: expected {expected}, got {actual}")

    assert not failures, "Generated log classification failures: " + " | ".join(failures[:8])

    valid_path = cases[0][0]
    assert run_script(script_path).returncode != 0, "Detector must reject invocation with no log argument"
    assert run_script(script_path, valid_path, valid_path).returncode != 0, "Detector must reject invocation with more than one argument"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
