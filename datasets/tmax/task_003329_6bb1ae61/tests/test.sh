#!/bin/bash
set -e
mkdir -p /logs/verifier

# The oracle must remain available for the reverse-engineering task, but the
# submitted program must not be able to invoke it during verification.
chmod 700 /app/priv_checker
trap 'chmod 755 /app/priv_checker 2>/dev/null || true' EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pwd
import subprocess
import random
import base64
import string
import pytest

ORACLE_PATH = "/app/priv_checker"
AGENT_PATH = "/home/user/priv_checker.py"
N_TESTS = 1000
USER = pwd.getpwnam("user")

def generate_random_bytes(length):
    return bytes(random.getrandbits(8) for _ in range(length))

def generate_random_string(length):
    return ''.join(random.choices(string.ascii_letters + string.digits + string.punctuation + ' ', k=length))

def generate_fuzz_inputs(n):
    random.seed(42)
    inputs = []

    # Edge cases
    inputs.append(None) # No arguments
    inputs.append("") # Empty argument

    for _ in range(n - 2):
        choice = random.random()
        if choice < 0.2:
            # Random bytes (might not be valid base64)
            length = random.randint(1, 1000)
            raw_bytes = generate_random_bytes(length).replace(b'\x00', b'\x01')
            try:
                inputs.append(raw_bytes.decode('utf-8', errors='surrogateescape'))
            except Exception:
                inputs.append(generate_random_string(length))
        elif choice < 0.4:
            # Valid base64 of random bytes
            length = random.randint(10, 500)
            raw_bytes = generate_random_bytes(length)
            inputs.append(base64.b64encode(raw_bytes).decode('ascii'))
        elif choice < 0.6:
            # Valid base64 of string with pipes
            length = random.randint(10, 500)
            s = generate_random_string(length) + "|" + generate_random_string(10) + "|" + generate_random_string(10)
            inputs.append(base64.b64encode(s.encode('utf-8')).decode('ascii'))
        elif choice < 0.8:
            # Valid base64 of almost correct format
            cert_sn = str(random.randint(0, 10))
            csp = "default-src 'none'" if random.random() > 0.5 else "default-src *"
            priv = random.choice(["root", "admin", "user", "guest"])
            s = f"{cert_sn}|{csp}|{priv}"
            inputs.append(base64.b64encode(s.encode('utf-8')).decode('ascii'))
        else:
            # Valid base64 of random string
            length = random.randint(10, 500)
            inputs.append(base64.b64encode(generate_random_string(length).encode('utf-8')).decode('ascii'))

    return inputs

def demote_to_user():
    os.setgroups([])
    os.setgid(USER.pw_gid)
    os.setuid(USER.pw_uid)

def run_program(executable, arg, as_agent=False):
    cmd = [executable]
    if arg is not None:
        cmd.append(arg)

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=False,
            timeout=2,
            preexec_fn=demote_to_user if as_agent else None,
        )
        return {
            'stdout': result.stdout,
            'stderr': result.stderr,
            'returncode': result.returncode
        }
    except subprocess.TimeoutExpired:
        return {
            'stdout': b'',
            'stderr': b'Timeout',
            'returncode': -1
        }

def test_agent_script_exists_and_executable():
    assert os.path.isfile(AGENT_PATH), f"Agent script not found at {AGENT_PATH}"
    assert not os.path.islink(AGENT_PATH), "Agent submission must be a Python script, not a symlink"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent script at {AGENT_PATH} is not executable"
    with open(AGENT_PATH, 'rb') as f:
        first_line = f.readline(256).lower()
    assert first_line.startswith(b'#!') and b'python' in first_line, "Agent script must have a Python shebang"
    with open(AGENT_PATH, 'rb') as agent, open(ORACLE_PATH, 'rb') as oracle:
        assert agent.read() != oracle.read(), "Agent submission must not be the oracle binary"

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle binary not found at {ORACLE_PATH}"
    assert os.path.isfile(AGENT_PATH), f"Agent script not found at {AGENT_PATH}"

    inputs = generate_fuzz_inputs(N_TESTS)

    for i, arg in enumerate(inputs):
        oracle_res = run_program(ORACLE_PATH, arg)
        # Run the submission as the unprivileged task user. The root-owned,
        # mode-700 oracle cannot be executed or read by a forwarding wrapper.
        agent_res = run_program(AGENT_PATH, arg, as_agent=True)

        error_msg = f"Mismatch on input #{i}: {repr(arg)}\n"
        error_msg += f"Oracle output: stdout={oracle_res['stdout']}, stderr={oracle_res['stderr']}, code={oracle_res['returncode']}\n"
        error_msg += f"Agent output: stdout={agent_res['stdout']}, stderr={agent_res['stderr']}, code={agent_res['returncode']}"

        assert oracle_res['returncode'] == agent_res['returncode'], error_msg
        assert oracle_res['stdout'] == agent_res['stdout'], error_msg
        assert oracle_res['stderr'] == agent_res['stderr'], error_msg
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
