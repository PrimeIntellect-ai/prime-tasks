#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import re
import secrets
import subprocess
import tempfile
import pytest

ORACLE = "/app/oracle_bin"
AGENT = "/home/user/optimized_engine_fixed"
SECRET_DATA = "/app/secret_test_data.csv"
LOSS_RE = re.compile(r"Final loss:\s*([0-9]+\.[0-9]+)")
EXACT_RE = re.compile(r"Final loss: ([0-9]+\.[0-9]+)\n?\Z")


def run_binary(binary_path, data_path, drop_privileges=False):
    preexec_fn = None
    if drop_privileges:
        account = pwd.getpwnam("user")
        def become_user():
            os.setgroups([])
            os.setgid(account.pw_gid)
            os.setuid(account.pw_uid)
        preexec_fn = become_user

    return subprocess.check_output(
        [binary_path, data_path],
        text=True,
        stderr=subprocess.STDOUT,
        timeout=10,
        preexec_fn=preexec_fn,
    )


def get_loss(binary_path, data_path, drop_privileges=False):
    out = run_binary(binary_path, data_path, drop_privileges)
    match = LOSS_RE.search(out)
    if not match:
        return float("inf")
    return float(match.group(1))


def parse_exact_output(out):
    match = EXACT_RE.fullmatch(out)
    assert match, "Output did not exactly match 'Final loss: <float>' followed by an optional newline"
    return float(match.group(1))


def test_fixed_binary_exists_and_executable():
    path = AGENT
    assert os.path.isfile(path), f"Fixed binary not found at {path}"
    assert os.access(path, os.X_OK), f"Fixed binary at {path} is not executable"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Fixed executable must be a compiled ELF binary"

    assert os.path.isfile(ORACLE), f"Oracle binary not found at {ORACLE}"
    with open(path, "rb") as agent_file, open(ORACLE, "rb") as oracle_file:
        assert agent_file.read() != oracle_file.read(), "Fixed binary must not be a byte-identical copy of the oracle"


def test_fixed_binary_loss_metric():
    oracle_path = ORACLE
    agent_path = AGENT
    data_path = SECRET_DATA

    assert os.path.isfile(oracle_path), f"Oracle binary not found at {oracle_path}"
    assert os.path.isfile(agent_path), f"Agent binary not found at {agent_path}"
    assert os.path.isfile(data_path), f"Secret test data not found at {data_path}"

    try:
        oracle_loss = get_loss(oracle_path, data_path)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Oracle binary failed to execute: {e}")

    try:
        agent_loss = get_loss(agent_path, data_path)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Agent binary failed to execute: {e}")

    assert agent_loss != float("inf"), "Agent binary output did not match the expected format 'Final loss: <float>'"
    assert oracle_loss != float("inf"), "Oracle binary output did not match the expected format 'Final loss: <float>'"

    error = abs(oracle_loss - agent_loss)
    threshold = 1e-4
    assert error <= threshold, f"Loss error {error} exceeds threshold {threshold}. Agent loss: {agent_loss}, Oracle loss: {oracle_loss}"


def test_multiple_unpredictable_datasets_without_live_oracle():
    rng = secrets.SystemRandom()
    workdir = tempfile.mkdtemp(prefix="optimization-verifier-")
    os.chmod(workdir, 0o755)
    datasets = []

    try:
        for case_index in range(8):
            path = os.path.join(workdir, f"case-{case_index}.csv")
            slope = rng.uniform(-2.5, 3.5)
            intercept = rng.uniform(-4.0, 4.0)
            count = rng.randint(5, 24)
            with open(path, "w") as f:
                for _ in range(count):
                    x = rng.uniform(-4.0, 4.0)
                    noise = rng.uniform(-0.35, 0.35)
                    y = slope * x + intercept + noise
                    f.write(f"{x:.10f},{y:.10f}\n")
            os.chmod(path, 0o644)
            datasets.append(path)

        expected = []
        for path in datasets:
            try:
                oracle_output = run_binary(ORACLE, path)
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
                pytest.fail(f"Oracle binary failed on generated input: {e}")
            expected.append(parse_exact_output(oracle_output))

        quarantine = os.path.join("/app", ".verifier-oracle-" + secrets.token_hex(16))
        os.mkdir(quarantine, 0o700)
        hidden_oracle = os.path.join(quarantine, "oracle_bin")
        os.rename(ORACLE, hidden_oracle)
        try:
            for path, oracle_loss in zip(datasets, expected):
                try:
                    agent_output = run_binary(AGENT, path, drop_privileges=True)
                except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
                    pytest.fail(f"Agent binary failed on generated input: {e}")
                agent_loss = parse_exact_output(agent_output)
                error = abs(oracle_loss - agent_loss)
                assert error <= 1e-4, (
                    f"Generated-input loss error {error} exceeds threshold 0.0001. "
                    f"Agent loss: {agent_loss}, Oracle loss: {oracle_loss}"
                )
        finally:
            os.rename(hidden_oracle, ORACLE)
            os.rmdir(quarantine)
    finally:
        for path in datasets:
            if os.path.exists(path):
                os.unlink(path)
        if os.path.isdir(workdir):
            os.rmdir(workdir)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
