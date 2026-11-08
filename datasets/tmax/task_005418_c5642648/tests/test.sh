#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import string
import subprocess
import pytest

AGENT_SRC = "/home/user/replica.c"
AGENT_BIN = "/home/user/replica"
ORACLE_BIN = "/app/waf_cookie_hasher"
N_FUZZ = 5000

def compile_agent():
    if not os.path.exists(AGENT_BIN) or os.path.getmtime(AGENT_SRC) > os.path.getmtime(AGENT_BIN):
        assert os.path.exists(AGENT_SRC), f"Agent source file {AGENT_SRC} is missing."
        result = subprocess.run(
            ["gcc", "-O2", AGENT_SRC, "-o", AGENT_BIN],
            capture_output=True,
            text=True
        )
        assert result.returncode == 0, f"Compilation of {AGENT_SRC} failed:\n{result.stderr}"

def generate_fuzz_inputs(n):
    random.seed(42)
    charset = string.ascii_letters + string.digits + " =;-_"
    inputs = []

    for _ in range(n):
        length = random.randint(0, 512)
        if random.random() < 0.5:
            # Purely random
            inp = "".join(random.choices(charset, k=length))
        else:
            # Pseudo-valid
            base = "".join(random.choices(charset, k=max(0, length - 8)))
            insert_idx = random.randint(0, len(base))
            keyword = random.choice(["payload=", "session="])
            inp = base[:insert_idx] + keyword + base[insert_idx:]
            # Trim to length if necessary, though it might be slightly longer, which is fine
            inp = inp[:512]
        inputs.append(inp)

    # Also add some edge cases explicitly
    inputs.extend([
        "",
        "payload=",
        "payload=;",
        "session=abc; payload=xyz;",
        "payload=1234567890",
        ";payload=a;",
    ])
    return inputs

@pytest.fixture(scope="session", autouse=True)
def setup_and_compile():
    assert os.path.exists(ORACLE_BIN), f"Oracle binary {ORACLE_BIN} is missing."
    assert os.access(ORACLE_BIN, os.X_OK), f"Oracle binary {ORACLE_BIN} is not executable."
    compile_agent()
    assert os.path.exists(AGENT_BIN), f"Agent binary {AGENT_BIN} is missing after compilation attempt."
    assert os.access(AGENT_BIN, os.X_OK), f"Agent binary {AGENT_BIN} is not executable."

def run_bin(binary, arg=None):
    cmd = [binary]
    if arg is not None:
        cmd.append(arg)

    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        errors='replace'
    )
    return result.returncode, result.stdout, result.stderr

def test_fuzz_equivalence():
    inputs = generate_fuzz_inputs(N_FUZZ)

    # Test argc != 2 case
    rc_o, out_o, err_o = run_bin(ORACLE_BIN)
    rc_a, out_a, err_a = run_bin(AGENT_BIN)

    assert rc_o == rc_a, f"Return code mismatch on no arguments. Oracle: {rc_o}, Agent: {rc_a}"
    assert out_o == out_a, f"Stdout mismatch on no arguments. Oracle: {repr(out_o)}, Agent: {repr(out_a)}"
    assert err_o == err_a, f"Stderr mismatch on no arguments. Oracle: {repr(err_o)}, Agent: {repr(err_a)}"

    for i, inp in enumerate(inputs):
        rc_o, out_o, err_o = run_bin(ORACLE_BIN, inp)
        rc_a, out_a, err_a = run_bin(AGENT_BIN, inp)

        error_msg = (
            f"Mismatch on input {i}: {repr(inp)}\n"
            f"Oracle -> RC: {rc_o}, STDOUT: {repr(out_o)}, STDERR: {repr(err_o)}\n"
            f"Agent  -> RC: {rc_a}, STDOUT: {repr(out_a)}, STDERR: {repr(err_a)}"
        )

        assert rc_o == rc_a, error_msg
        assert out_o == out_a, error_msg
        assert err_o == err_a, error_msg
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
