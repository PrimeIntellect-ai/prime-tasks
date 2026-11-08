#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import string
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/app/loc_filter"
AGENT_PATH = "/home/user/solution"
SOURCE_PATH = "/home/user/solution.cpp"


def generate_fuzz_input(seed):
    random.seed(seed)
    target_length = random.randint(1024, 10240)
    out = []
    current_length = 0

    while current_length < target_length:
        id_str = ''.join(random.choices(string.ascii_letters + string.digits, k=random.randint(1, 10)))
        has_comma = random.random() < 0.9

        text_len = random.randint(10, 100)
        text_chars = []
        for _ in range(text_len):
            r = random.random()
            if r < 0.05:
                text_chars.append('\n')
            elif r < 0.10:
                text_chars.append(
                    ''.join(random.choices(string.ascii_lowercase, k=5)) + '@' +
                    ''.join(random.choices(string.ascii_lowercase, k=5)) + '.com'
                )
            else:
                text_chars.append(random.choice(string.ascii_letters + string.digits + " !#$%&'()*+-./:;<=>?@[\\]^_`{|}~"))

        text_str = ''.join(text_chars)
        line = id_str + (',' if has_comma else '') + text_str + '\n'
        out.append(line)
        current_length += len(line)

    return ''.join(out).encode('utf-8')


def test_agent_solution_exists():
    assert os.path.exists(AGENT_PATH), f"Agent binary {AGENT_PATH} does not exist."
    assert os.path.isfile(AGENT_PATH), f"{AGENT_PATH} is not a file."
    assert not os.path.islink(AGENT_PATH), f"{AGENT_PATH} must not be a symlink."
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary {AGENT_PATH} is not executable."

    assert os.path.exists(SOURCE_PATH), f"Agent source {SOURCE_PATH} does not exist."
    assert os.path.isfile(SOURCE_PATH), f"{SOURCE_PATH} is not a file."
    assert not os.path.islink(SOURCE_PATH), f"{SOURCE_PATH} must not be a symlink."

    assert os.path.exists(ORACLE_PATH), f"Oracle binary {ORACLE_PATH} missing."
    assert not os.path.samefile(AGENT_PATH, ORACLE_PATH), "Agent binary must be independent of the oracle."
    with open(AGENT_PATH, 'rb') as agent_file, open(ORACLE_PATH, 'rb') as oracle_file:
        assert agent_file.read() != oracle_file.read(), "Agent binary must not be a byte-for-byte copy of the oracle."


def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle binary {ORACLE_PATH} missing."
    assert os.path.exists(AGENT_PATH), f"Agent binary {AGENT_PATH} missing."
    assert os.path.exists(SOURCE_PATH), f"Agent source {SOURCE_PATH} missing."

    # Rebuild the submitted C++ source as a static executable. It is then run in
    # an empty chroot, where neither /app/loc_filter nor agent-created wrapper
    # targets or copied executables are available.
    sandbox = tempfile.mkdtemp(prefix="loc_filter_verify_")
    rebuilt_path = os.path.join(sandbox, "solution")
    try:
        compile_proc = subprocess.run(
            ["g++", "-O3", "-static", SOURCE_PATH, "-o", rebuilt_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=120,
        )
        assert compile_proc.returncode == 0, (
            "Failed to compile /home/user/solution.cpp:\n" +
            compile_proc.stderr.decode('utf-8', errors='replace')
        )
        assert os.path.isfile(rebuilt_path), "Rebuilt solution was not produced."
        assert os.access(rebuilt_path, os.X_OK), "Rebuilt solution is not executable."

        chroot_cmd = shutil.which("chroot")
        assert chroot_cmd is not None, "chroot utility is unavailable."

        num_iterations = 1000
        for i in range(num_iterations):
            input_data = generate_fuzz_input(i)

            oracle_proc = subprocess.run(
                [ORACLE_PATH],
                input=input_data,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=30,
            )

            agent_proc = subprocess.run(
                [chroot_cmd, sandbox, "/solution"],
                input=input_data,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=30,
            )

            if oracle_proc.stdout != agent_proc.stdout:
                try:
                    input_str = input_data.decode('utf-8')
                    oracle_out = oracle_proc.stdout.decode('utf-8')
                    agent_out = agent_proc.stdout.decode('utf-8')
                except UnicodeDecodeError:
                    input_str = repr(input_data)
                    oracle_out = repr(oracle_proc.stdout)
                    agent_out = repr(agent_proc.stdout)

                if len(input_str) > 500:
                    input_str = input_str[:500] + "... [truncated]"
                if len(oracle_out) > 500:
                    oracle_out = oracle_out[:500] + "... [truncated]"
                if len(agent_out) > 500:
                    agent_out = agent_out[:500] + "... [truncated]"

                pytest.fail(
                    f"Mismatch on fuzz iteration {i} (seed {i}).\n"
                    f"Input:\n{input_str}\n\n"
                    f"Expected Output (Oracle):\n{oracle_out}\n\n"
                    f"Actual Output (Agent):\n{agent_out}\n\n"
                    f"Agent stderr:\n{agent_proc.stderr.decode('utf-8', errors='replace')[:500]}"
                )
    finally:
        shutil.rmtree(sandbox, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
