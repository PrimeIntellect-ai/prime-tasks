#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import stat
import subprocess
import string
import pytest

ORACLE_PATH = "/app/oracle_tracker_hidden"
EXTRACTED_ORACLE_PATH = "/home/user/oracle_tracker"
AGENT_SOURCE_PATH = "/home/user/doc_tracker.cpp"
AGENT_PATH = "/home/user/doc_tracker"
REBUILT_AGENT_PATH = "/tmp/verifier_doc_tracker"


def generate_random_path(existing_paths, action):
    if action == "DELETE" and existing_paths:
        return random.choice(list(existing_paths))
    elif action == "MODIFY" and existing_paths:
        return random.choice(list(existing_paths))
    else:
        depth = random.randint(1, 4)
        parts = []
        for _ in range(depth):
            name_len = random.randint(3, 8)
            name = ''.join(random.choices(string.ascii_letters + string.digits, k=name_len))
            parts.append(name)
        if random.choice([True, False]):
            parts[-1] += ".txt"
        return "/" + "/".join(parts)


def generate_fuzz_input(num_lines):
    lines = []
    existing_paths = set()
    timestamp = 1
    for _ in range(num_lines):
        if not existing_paths:
            action = "CREATE"
        else:
            action = random.choices(["CREATE", "MODIFY", "DELETE"], weights=[50, 30, 20])[0]

        path = generate_random_path(existing_paths, action)

        if action == "CREATE":
            existing_paths.add(path)
            size = random.randint(1, 10000)
        elif action == "MODIFY":
            size = random.randint(1, 10000)
        else:
            existing_paths.remove(path)
            size = 0

        lines.append(f"[{timestamp}] {action} {path} {size}")
        timestamp += random.randint(1, 5)

    return "\n".join(lines) + "\n"


def regular_file(path):
    try:
        return stat.S_ISREG(os.lstat(path).st_mode)
    except OSError:
        return False


@pytest.fixture(scope="session")
def rebuilt_agent():
    assert regular_file(AGENT_SOURCE_PATH), \
        f"C++ source not found as a regular file at {AGENT_SOURCE_PATH}"

    proc = subprocess.run(
        ["g++", "-O2", "-std=c++17", AGENT_SOURCE_PATH, "-o", REBUILT_AGENT_PATH],
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert proc.returncode == 0, \
        f"Failed to compile {AGENT_SOURCE_PATH}:\n{proc.stdout}\n{proc.stderr}"
    assert regular_file(REBUILT_AGENT_PATH)
    assert os.access(REBUILT_AGENT_PATH, os.X_OK)
    return REBUILT_AGENT_PATH


def test_extracted_oracle_exists_and_executable():
    path = EXTRACTED_ORACLE_PATH
    assert regular_file(path), f"Extracted oracle not found at {path}"
    assert os.access(path, os.X_OK), f"Extracted oracle at {path} is not executable"
    assert regular_file(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    with open(path, "rb") as extracted, open(ORACLE_PATH, "rb") as reference:
        assert extracted.read() == reference.read(), \
            "The extracted oracle does not match the executable attached to the screencast"


def test_agent_executable_exists():
    path = AGENT_PATH
    assert regular_file(path), f"Agent executable not found at {path}"
    assert os.access(path, os.X_OK), f"Agent executable at {path} is not executable"


def test_agent_source_exists_and_compiles(rebuilt_agent):
    assert regular_file(AGENT_SOURCE_PATH)
    assert os.path.isfile(rebuilt_agent)
    assert os.access(rebuilt_agent, os.X_OK)


def test_agent_is_not_copied_oracle(rebuilt_agent):
    with open(ORACLE_PATH, "rb") as f:
        oracle_bytes = f.read()
    with open(AGENT_PATH, "rb") as f:
        agent_bytes = f.read()
    with open(rebuilt_agent, "rb") as f:
        rebuilt_bytes = f.read()
    assert agent_bytes != oracle_bytes, \
        "doc_tracker must not be a byte-for-byte copy of the reference executable"
    assert rebuilt_bytes != oracle_bytes, \
        "The executable compiled from doc_tracker.cpp must not be the reference executable"


def run_program(path, input_data, description):
    try:
        return subprocess.run(
            [path],
            input=input_data,
            text=True,
            capture_output=True,
            timeout=2,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{description} timed out on fuzz input.")


def test_fuzz_equivalence(rebuilt_agent):
    assert os.path.isfile(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    assert os.path.isfile(AGENT_PATH), f"Agent executable missing at {AGENT_PATH}"

    random.seed(42)
    N = 500

    for _ in range(N):
        num_lines = random.randint(10, 200)
        input_data = generate_fuzz_input(num_lines)

        oracle_proc = run_program(ORACLE_PATH, input_data, "Oracle")
        agent_proc = run_program(AGENT_PATH, input_data, "Agent executable")
        rebuilt_proc = run_program(rebuilt_agent, input_data, "Executable rebuilt from doc_tracker.cpp")

        oracle_out = oracle_proc.stdout.strip()
        agent_out = agent_proc.stdout.strip()
        rebuilt_out = rebuilt_proc.stdout.strip()

        assert agent_proc.returncode == oracle_proc.returncode, \
            f"Return code mismatch on input:\n{input_data}\nExpected: {oracle_proc.returncode}, Got: {agent_proc.returncode}"
        assert agent_out == oracle_out, \
            f"Output mismatch on input:\n{input_data}\nExpected:\n{oracle_out}\nGot:\n{agent_out}"

        assert rebuilt_proc.returncode == oracle_proc.returncode, \
            f"Rebuilt source return code mismatch on input:\n{input_data}\nExpected: {oracle_proc.returncode}, Got: {rebuilt_proc.returncode}"
        assert rebuilt_out == oracle_out, \
            f"Rebuilt source output mismatch on input:\n{input_data}\nExpected:\n{oracle_out}\nGot:\n{rebuilt_out}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
