#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "numpy:numpy"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import struct
import subprocess
import numpy as np
import pytest

ORACLE_PATH = "/app/dim_reducer_oracle"
AGENT_PATH = "/home/user/dim_reducer"


def test_agent_binary_exists_and_executable():
    assert os.path.exists(AGENT_PATH), f"Agent binary is missing at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"Path {AGENT_PATH} exists but is not a file"
    assert stat.S_ISREG(os.lstat(AGENT_PATH).st_mode), f"Agent path {AGENT_PATH} must be a regular file"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary at {AGENT_PATH} is not executable"
    with open(AGENT_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Agent executable must be a compiled ELF binary"


def generate_cases():
    np.random.seed(42)
    for i in range(100):
        N = np.random.randint(1, 1001)
        if i == 0:
            floats = np.zeros(N * 128, dtype=np.float32)
        elif i == 1:
            floats = np.ones(N * 128, dtype=np.float32)
        else:
            floats = (np.random.rand(N * 128).astype(np.float32) - 0.5) * 1000.0
        yield i, N, struct.pack('<I', N) + floats.tobytes()


def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle binary missing at {ORACLE_PATH}"

    assert not os.path.samefile(AGENT_PATH, ORACLE_PATH), "Agent binary must not be the oracle"
    with open(AGENT_PATH, "rb") as f:
        agent_bytes = f.read()
    with open(ORACLE_PATH, "rb") as f:
        oracle_bytes = f.read()
    assert agent_bytes != oracle_bytes, "Agent binary is byte-identical to the oracle"

    # Compute all expected results first. The oracle is then removed before any
    # invocation of the submitted program, so the submission cannot forward to it.
    expected_outputs = []
    for i, N, input_bytes in generate_cases():
        oracle_res = subprocess.run(
            [ORACLE_PATH],
            input=input_bytes,
            capture_output=True,
            check=False
        )
        assert oracle_res.returncode == 0, f"Oracle crashed on iteration {i} with N={N}"
        expected_outputs.append(oracle_res.stdout)

    os.unlink(ORACLE_PATH)
    assert not os.path.exists(ORACLE_PATH), "Oracle remained accessible during agent execution"

    for (i, N, input_bytes), expected in zip(generate_cases(), expected_outputs):
        agent_res = subprocess.run(
            [AGENT_PATH],
            input=input_bytes,
            capture_output=True,
            check=False
        )
        assert agent_res.returncode == 0, f"Agent crashed on iteration {i} with N={N}"

        if expected != agent_res.stdout:
            pytest.fail(
                f"Mismatch on iteration {i} with N={N}.\n"
                f"Oracle output length: {len(expected)}\n"
                f"Agent output length: {len(agent_res.stdout)}\n"
                f"Outputs differ. Agent did not match oracle bit-exactly."
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
