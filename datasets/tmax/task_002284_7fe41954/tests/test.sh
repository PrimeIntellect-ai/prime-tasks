#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import stat
import subprocess
import random
import string
import pytest

ORACLE_PATH = "/app/oracle_router.sh"
AGENT_PATH = "/home/user/router.sh"

def setup_oracle():
    oracle_content = """#!/bin/bash
URI="$1"
if [[ "$URI" == /api/v2* ]]; then
    echo "8082"
elif [[ "$URI" == /api/v1* ]]; then
    echo "8081"
elif [[ "$URI" == /admin* ]]; then
    echo "9000"
elif [[ "$URI" == /static* ]]; then
    echo "8080"
else
    echo "8000"
fi
"""
    os.makedirs(os.path.dirname(ORACLE_PATH), exist_ok=True)
    with open(ORACLE_PATH, "w") as f:
        f.write(oracle_content)
    st = os.stat(ORACLE_PATH)
    os.chmod(ORACLE_PATH, st.st_mode | stat.S_IEXEC)

def generate_fuzz_inputs(n=100):
    fixed_inputs = [
        "/admin", "/admin/users", "/api/v1", "/api/v1/data/123",
        "/api/v2/auth", "/static/style.css", "/static/img/logo.png",
        "/api/v3/new", "/unknown/path", "/", "/administrator",
        "admin", "/api/v12", "/static_files"
    ]

    inputs = list(fixed_inputs)

    random.seed(42)
    charset = string.ascii_lowercase + string.digits + "/"
    prefixes = ["/admin", "/api/v1", "/api/v2", "/static", "/"]

    while len(inputs) < n:
        prefix = random.choices(prefixes, weights=[0.15, 0.15, 0.15, 0.15, 0.40], k=1)[0]
        length = random.randint(1, 50)
        suffix = ''.join(random.choices(charset, k=length))
        inputs.append(prefix + suffix)

    return inputs[:n]

def test_agent_script_exists_and_executable():
    assert os.path.exists(AGENT_PATH), f"Agent script not found at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"Agent script {AGENT_PATH} is not a file"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent script {AGENT_PATH} is not executable"

def test_fuzz_equivalence():
    setup_oracle()
    inputs = generate_fuzz_inputs(100)

    for uri in inputs:
        oracle_proc = subprocess.run([ORACLE_PATH, uri], capture_output=True, text=True)
        agent_proc = subprocess.run([AGENT_PATH, uri], capture_output=True, text=True)

        oracle_out = oracle_proc.stdout.strip()
        agent_out = agent_proc.stdout.strip()

        assert oracle_proc.returncode == 0, f"Oracle failed on input {uri}"
        assert agent_proc.returncode == 0, f"Agent script failed on input {uri}. Stderr: {agent_proc.stderr}"

        assert agent_out == oracle_out, f"Mismatch on input: '{uri}'. Expected: '{oracle_out}', Got: '{agent_out}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
