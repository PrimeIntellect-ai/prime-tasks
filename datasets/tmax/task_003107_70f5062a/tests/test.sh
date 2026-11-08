#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
import pytest

EVIL_DIR = "/app/corpora/evil/"
CLEAN_DIR = "/app/corpora/clean/"
SCRIPT_PATH = "/home/user/classify_hog.py"


def run_script(input_data):
    """Helper to run the student script with given standard input."""
    result = subprocess.run(
        [SCRIPT_PATH],
        input=input_data.encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    return result.stdout.decode("utf-8").strip()


def expected_result(cpu, mem, command):
    ignored = re.match(r"^/usr/libexec/.*", command) is not None
    return "REJECT" if (cpu > 75.0 or mem > 40.0) and not ignored else "ACCEPT"


def test_script_exists_and_executable():
    """Check that the classification script exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"


def test_evil_corpus_rejected():
    """Ensure all evil inputs (exceeding limits and not ignored) are REJECTED."""
    assert os.path.isdir(EVIL_DIR), f"Evil corpus directory missing: {EVIL_DIR}"

    evil_files = [f for f in os.listdir(EVIL_DIR) if os.path.isfile(os.path.join(EVIL_DIR, f))]
    assert len(evil_files) > 0, "Evil corpus is empty"

    bypassed = []
    for filename in evil_files:
        filepath = os.path.join(EVIL_DIR, filename)
        with open(filepath, "r") as f:
            content = f.read()

        try:
            output = run_script(content)
            if output != "REJECT":
                bypassed.append(filename)
        except Exception as e:
            bypassed.append(f"{filename} (Error: {str(e)})")

    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil bypassed. Offending files: {', '.join(bypassed)}")


def test_clean_corpus_accepted():
    """Ensure all clean inputs (within limits or matching ignore path) are ACCEPTED."""
    assert os.path.isdir(CLEAN_DIR), f"Clean corpus directory missing: {CLEAN_DIR}"

    clean_files = [f for f in os.listdir(CLEAN_DIR) if os.path.isfile(os.path.join(CLEAN_DIR, f))]
    assert len(clean_files) > 0, "Clean corpus is empty"

    modified = []
    for filename in clean_files:
        filepath = os.path.join(CLEAN_DIR, filename)
        with open(filepath, "r") as f:
            content = f.read()

        try:
            output = run_script(content)
            if output != "ACCEPT":
                modified.append(filename)
        except Exception as e:
            modified.append(f"{filename} (Error: {str(e)})")

    if modified:
        pytest.fail(f"{len(modified)} of {len(clean_files)} clean modified/rejected. Offending files: {', '.join(modified)}")


def test_boundaries_and_ignore_regex_with_reused_pid():
    """Exercise threshold boundaries and regex semantics independently of PID."""
    pid = random.SystemRandom().randint(10000, 999999)
    cases = [
        (75.0, 40.0, "/opt/workload"),
        (75.0001, 40.0, "/opt/workload"),
        (75.0, 40.0001, "/opt/workload"),
        (99.9, 99.9, "/usr/libexec/daemon"),
        (99.9, 99.9, "/usr/libexec/"),
        (99.9, 99.9, "/usr/libexec"),
        (99.9, 99.9, "/usr/libexec2/daemon"),
        (99.9, 99.9, "x/usr/libexec/daemon"),
    ]
    for cpu, mem, command in cases:
        line = f"{pid},runtimeuser,{cpu},{mem},{command}\n"
        assert run_script(line) == expected_result(cpu, mem, command), line


def test_runtime_generated_processes():
    """Check fresh process records whose expected labels are derived at test time."""
    rng = random.SystemRandom()
    normal_commands = [
        "/opt/apps/worker",
        "/bin/bash",
        "/srv/jobs/task-runner",
        "/usr/local/bin/service",
        "/tmp/process",
        "/usr/libexec-not-ignored/tool",
    ]
    ignored_commands = [
        "/usr/libexec/system-daemon",
        "/usr/libexec/helpers/worker",
        "/usr/libexec/",
    ]

    cases = []
    for _ in range(30):
        cases.append((rng.uniform(0, 75), rng.uniform(0, 40), rng.choice(normal_commands)))
        cases.append((rng.uniform(75.001, 180), rng.uniform(0, 40), rng.choice(normal_commands)))
        cases.append((rng.uniform(0, 75), rng.uniform(40.001, 120), rng.choice(normal_commands)))
        cases.append((rng.uniform(75.001, 180), rng.uniform(40.001, 120), rng.choice(ignored_commands)))

    rng.shuffle(cases)
    for cpu, mem, command in cases:
        pid = rng.randint(1, 2000000000)
        user = f"user{rng.randint(1, 999999)}"
        line = f"{pid},{user},{cpu:.6f},{mem:.6f},{command}\n"
        expected = expected_result(float(f"{cpu:.6f}"), float(f"{mem:.6f}"), command)
        assert run_script(line) == expected, line
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
