#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import base64
import subprocess
import tempfile
import filecmp
import pytest

AGENT_SOURCE = "/home/user/filter.go"
AGENT_BIN = "/home/user/filter_bin"
ORACLE_BIN = "/app/proxy_oracle"

@pytest.fixture(scope="session")
def rebuilt_bin():
    assert os.path.isfile(AGENT_SOURCE), f"Go source missing at {AGENT_SOURCE}"
    assert not os.path.islink(AGENT_SOURCE), f"Go source must not be a symlink: {AGENT_SOURCE}"

    temp_dir = tempfile.mkdtemp(prefix="filter_rebuild_")
    output = os.path.join(temp_dir, "filter_bin")
    proc = subprocess.run(
        ["go", "build", "-o", output, "filter.go"],
        cwd="/home/user",
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, (
        f"Could not build {AGENT_SOURCE} as a Go program.\n"
        f"stdout: {proc.stdout}\nstderr: {proc.stderr}"
    )
    assert os.path.isfile(output) and os.access(output, os.X_OK), "Rebuilt Go program is not executable"
    return output

def test_directories_and_symlink():
    logs_dir = "/home/user/edge_deploy/logs"
    conf_dir = "/home/user/edge_deploy/conf"
    bin_dir = "/home/user/edge_deploy/bin"

    assert os.path.isdir(logs_dir), f"Directory missing: {logs_dir}"
    assert os.path.isdir(conf_dir), f"Directory missing: {conf_dir}"
    assert os.path.isdir(bin_dir), f"Directory missing: {bin_dir}"

    symlink_path = "/home/user/edge_deploy/bin/filter_bin"
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink"

    target = os.readlink(symlink_path)
    assert target == "/home/user/filter_bin", f"Symlink {symlink_path} points to {target} instead of /home/user/filter_bin"

def test_agent_artifacts(rebuilt_bin):
    assert os.path.isfile(AGENT_BIN), f"Agent binary missing at {AGENT_BIN}"
    assert not os.path.islink(AGENT_BIN), f"Agent binary must not be a symlink: {AGENT_BIN}"
    assert os.access(AGENT_BIN, os.X_OK), f"Agent binary not executable at {AGENT_BIN}"
    assert not os.path.samefile(AGENT_BIN, ORACLE_BIN), "Agent binary must not be the oracle"
    assert not filecmp.cmp(AGENT_BIN, ORACLE_BIN, shallow=False), "Agent binary is byte-identical to the oracle"

    go_info = subprocess.run(["go", "version", "-m", AGENT_BIN], capture_output=True, text=True)
    assert go_info.returncode == 0, f"{AGENT_BIN} is not a valid Go executable: {go_info.stderr}"

def test_fuzz_equivalence(rebuilt_bin):
    random.seed(42)
    printable = string.printable.encode('ascii')

    patterns = [
        b"ssh-rsa root",
        b"GET /api/v1/status",
        b"admin " + b"A" * 25,
        b"just some random text"
    ]

    for i in range(5000):
        length = random.randint(0, 100)

        if random.random() < 0.5:
            if random.random() < 0.2 and length > 20:
                raw = random.choice(patterns)
            else:
                raw = bytes(random.choice(printable) for _ in range(length))
            inp = base64.b64encode(raw)
        else:
            inp = bytes(random.randint(0, 255) for _ in range(length))

        proc_oracle = subprocess.run([ORACLE_BIN], input=inp, capture_output=True)
        proc_agent = subprocess.run([AGENT_BIN], input=inp, capture_output=True)
        proc_rebuilt = subprocess.run([rebuilt_bin], input=inp, capture_output=True)

        assert proc_oracle.stdout == proc_agent.stdout, (
            f"Output mismatch on input {inp!r}.\n"
            f"Oracle stdout: {proc_oracle.stdout!r}\n"
            f"Agent stdout: {proc_agent.stdout!r}"
        )
        assert proc_oracle.stdout == proc_rebuilt.stdout, (
            f"Go source output mismatch on input {inp!r}.\n"
            f"Oracle stdout: {proc_oracle.stdout!r}\n"
            f"Rebuilt source stdout: {proc_rebuilt.stdout!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
