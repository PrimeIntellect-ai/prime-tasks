#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import subprocess
import tempfile


def test_user_cleaner_exists_and_executable():
    path = "/home/user/cleaner"
    assert os.path.exists(path), f"Missing required file: {path}"
    assert os.path.isfile(path), f"Expected {path} to be a file"
    assert os.access(path, os.X_OK), f"File {path} must be executable"


def test_no_subprocess_invocation():
    agent_path = "/home/user/cleaner"
    if os.path.exists(agent_path):
        with open(agent_path, "rb") as f:
            content = f.read()
        assert b"legacy_cleaner" not in content, "Agent program must not invoke the legacy_cleaner as a subprocess."


def test_fuzz_equivalence():
    oracle_path = "/app/legacy_cleaner"
    agent_path = "/home/user/cleaner"

    assert os.path.exists(oracle_path), f"Oracle missing: {oracle_path}"
    assert os.path.exists(agent_path), f"Agent missing: {agent_path}"

    with open(oracle_path, "rb") as f:
        oracle_content = f.read()
    with open(agent_path, "rb") as f:
        agent_content = f.read()
    assert agent_content != oracle_content, "Agent submission must not be a byte-identical copy of the legacy binary."

    rng = random.Random(42)
    cases = []

    # Derive all expected outputs while the oracle is available.
    for i in range(100):
        length = rng.randint(0, 10000)
        input_data = bytes(rng.randint(0, 255) for _ in range(length))
        try:
            oracle_proc = subprocess.run(
                [oracle_path],
                input=input_data,
                capture_output=True,
                timeout=5,
                check=False,
            )
        except subprocess.TimeoutExpired:
            assert False, f"Oracle timed out on iteration {i}"
        cases.append((i, length, input_data, oracle_proc.stdout))

    # Make /app/legacy_cleaner unavailable while executing the submitted program.
    # The hidden location is root-only, and the submission itself runs as user.
    hidden_dir = tempfile.mkdtemp(prefix="cleaner-oracle-", dir="/root")
    os.chmod(hidden_dir, 0o700)
    hidden_oracle = os.path.join(hidden_dir, "oracle")
    os.rename(oracle_path, hidden_oracle)

    user = pwd.getpwnam("user")

    def drop_privileges():
        os.setgroups([])
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    try:
        for i, length, input_data, oracle_out in cases:
            try:
                agent_proc = subprocess.run(
                    [agent_path],
                    input=input_data,
                    capture_output=True,
                    timeout=5,
                    check=False,
                    preexec_fn=drop_privileges,
                    env={**os.environ, "HOME": user.pw_dir, "USER": user.pw_name, "LOGNAME": user.pw_name},
                )
                agent_out = agent_proc.stdout
            except subprocess.TimeoutExpired:
                assert False, f"Agent timed out on iteration {i} (input length {length})"

            assert oracle_out == agent_out, (
                f"Mismatch on iteration {i} (input length {length}).\n"
                f"Input (first 50 bytes): {input_data[:50]!r}...\n"
                f"Oracle output (first 50 bytes): {oracle_out[:50]!r}...\n"
                f"Agent output (first 50 bytes): {agent_out[:50]!r}..."
            )
    finally:
        if os.path.exists(hidden_oracle):
            os.rename(hidden_oracle, oracle_path)
        os.rmdir(hidden_dir)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
