#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import random
import secrets
import string
import subprocess
import pytest

def test_gunicorn_fix():
    """Verify that the Gunicorn Unix socket parsing bug is fixed."""
    # Run the specific snippet to check the parsed address
    cmd = [
        "python3", "-c",
        "from gunicorn.sock import UnixSocket; s = UnixSocket('unix:/tmp/fuzz_test.sock', None, None); print(s.cfg_addr)"
    ]
    env = os.environ.copy()
    env["PYTHONPATH"] = "/app/gunicorn"

    result = subprocess.run(cmd, env=env, capture_output=True, text=True)
    assert result.returncode == 0, f"Failed to import or run UnixSocket test: {result.stderr}"

    output = result.stdout.strip()
    assert output == "/tmp/fuzz_test.sock", f"Expected '/tmp/fuzz_test.sock', got '{output}'. The unix: prefix parsing is still incorrect."

def test_gunicorn_fix_general_addresses():
    """Exercise unix: prefix parsing on independently generated socket paths."""
    env = os.environ.copy()
    env["PYTHONPATH"] = "/app/gunicorn"
    code = (
        "import os; "
        "from gunicorn.sock import UnixSocket; "
        "s = UnixSocket(os.environ['TEST_UNIX_ADDRESS'], None, None); "
        "print(s.cfg_addr)"
    )

    alphabet = string.ascii_letters + string.digits
    paths = [
        "/tmp/a.sock",
        "/tmp/unix-prefix-check.sock",
        "/run/gunicorn/example.socket",
    ]
    for _ in range(64):
        name = ''.join(secrets.choice(alphabet) for _ in range(secrets.randbelow(30) + 1))
        paths.append(f"/tmp/gunicorn_{name}.sock")

    for path in paths:
        env["TEST_UNIX_ADDRESS"] = "unix:" + path
        result = subprocess.run(
            ["python3", "-c", code],
            env=env,
            capture_output=True,
            text=True,
        )
        try:
            assert result.returncode == 0, (
                f"Failed to parse generated Unix socket address {'unix:' + path!r}: "
                f"{result.stderr}"
            )
            assert result.stdout.strip() == path, (
                f"Expected generated address {path!r}, got {result.stdout.strip()!r}. "
                "The unix: prefix must be removed for all socket paths."
            )
        finally:
            if os.path.lexists(path):
                os.unlink(path)

def generate_random_string(min_len, max_len):
    length = random.randint(min_len, max_len)
    return ''.join(random.choice(string.ascii_lowercase) for _ in range(length))

def generate_fuzz_input():
    num_users = random.randint(0, 20)
    users = []
    for _ in range(num_users):
        user = generate_random_string(3, 10)
        if random.choice([True, False]):
            sock = f"/tmp/{generate_random_string(5, 10)}.sock"
        else:
            sock = f"/run/user/{generate_random_string(5, 10)}/app.sock"
        quota_used = random.randint(0, 2000000)
        users.append({
            "user": user,
            "sock": sock,
            "quota_used": quota_used
        })
    return users

def test_fuzz_equivalence_gen_upstreams():
    """Verify that the agent script exactly matches the oracle output for random inputs."""
    oracle_path = "/app/oracle_gen"
    agent_path = "/home/user/gen_upstreams.py"

    assert os.path.isfile(agent_path), f"Agent script not found at {agent_path}"

    random.seed(42)

    for i in range(100):
        input_data = generate_fuzz_input()
        input_json = json.dumps(input_data)

        # Run oracle
        oracle_result = subprocess.run(
            [oracle_path],
            input=input_json,
            capture_output=True,
            text=True
        )
        assert oracle_result.returncode == 0, f"Oracle failed on iteration {i}"
        oracle_output = oracle_result.stdout

        # Run agent
        agent_result = subprocess.run(
            ["python3", agent_path],
            input=input_json,
            capture_output=True,
            text=True
        )
        assert agent_result.returncode == 0, f"Agent script failed on iteration {i}:\n{agent_result.stderr}"
        agent_output = agent_result.stdout

        assert agent_output == oracle_output, (
            f"Mismatch on iteration {i}.\n"
            f"Input JSON:\n{input_json}\n\n"
            f"Oracle Output:\n{oracle_output}\n\n"
            f"Agent Output:\n{agent_output}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
