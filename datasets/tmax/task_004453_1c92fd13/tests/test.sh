#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess

ORACLE_PATH = "/app/gelman_rubin_oracle"
AGENT_PATH = "/home/user/gelman_rubin"
SOURCE_PATH = "/home/user/gelman_rubin.cpp"
REBUILT_PATH = "/tmp/gelman_rubin_from_source"


def test_final_state():
    # Preserve the original artifact checks.
    assert os.path.isfile(AGENT_PATH), f"Agent binary not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary at {AGENT_PATH} is not executable"
    assert os.path.isfile(ORACLE_PATH), f"Oracle binary missing at {ORACLE_PATH}"

    # The requested source must exist and independently produce an executable.
    assert os.path.isfile(SOURCE_PATH), f"Source code not found at {SOURCE_PATH}"
    build = subprocess.run(
        ["g++", "-O3", SOURCE_PATH, "-o", REBUILT_PATH],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert build.returncode == 0, f"Source failed to compile:\n{build.stderr}"
    assert os.path.isfile(REBUILT_PATH), "Compilation did not produce an executable"
    assert os.access(REBUILT_PATH, os.X_OK), "Compiled source output is not executable"

    with open(ORACLE_PATH, "rb") as f:
        oracle_bytes = f.read()
    with open(AGENT_PATH, "rb") as f:
        agent_bytes = f.read()
    with open(REBUILT_PATH, "rb") as f:
        rebuilt_bytes = f.read()
    assert agent_bytes != oracle_bytes, "Agent binary is byte-identical to the oracle"
    assert rebuilt_bytes != oracle_bytes, "Binary compiled from submitted source is byte-identical to the oracle"

    random.seed(42)
    cases = []
    for i in range(1000):
        M = random.randint(2, 5)
        N = random.randint(5, 20)
        args = [str(M), str(N)]
        for _ in range(M * N):
            val = random.uniform(-10.0, 10.0)
            args.append(f"{val:.6f}")

        oracle_res = subprocess.run(
            [ORACLE_PATH] + args,
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert oracle_res.returncode == 0, f"Oracle failed on input: {' '.join(args)}"
        cases.append((args, oracle_res.stdout.strip()))

    # Expected outputs are now fixed. Remove the oracle before either submitted
    # artifact is run so a forwarding implementation cannot use it.
    os.unlink(ORACLE_PATH)
    assert not os.path.exists(ORACLE_PATH)

    for executable in (AGENT_PATH, REBUILT_PATH):
        for i, (args, oracle_out) in enumerate(cases):
            agent_res = subprocess.run(
                [executable] + args,
                capture_output=True,
                text=True,
                timeout=10,
            )
            assert agent_res.returncode == 0, (
                f"Agent program {executable} failed on input: {' '.join(args)}\n"
                f"Stderr: {agent_res.stderr}"
            )
            agent_out = agent_res.stdout.strip()
            assert oracle_out == agent_out, (
                f"Mismatch from {executable} on test {i+1}/{len(cases)}!\n"
                f"Input args: {' '.join(args)}\n"
                f"Oracle output: {oracle_out}\n"
                f"Agent output:  {agent_out}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
