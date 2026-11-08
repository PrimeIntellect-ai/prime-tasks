#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import os
import random
import shutil
import string
import subprocess
import tempfile

import pytest

ORACLE_PATH = "/app/legacy_rotator"
AGENT_PATH = "/home/user/new_rotator"
SOURCE_PATH = "/home/user/new_rotator.c"
FUZZ_ITERATIONS = 1000
MIN_LEN = 8
MAX_LEN = 64


def test_agent_binary_exists_and_executable():
    """Verify that the agent has compiled the target binary and it is executable."""
    assert os.path.exists(AGENT_PATH), f"Agent binary missing at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"{AGENT_PATH} is not a file"
    assert os.access(AGENT_PATH, os.X_OK), f"{AGENT_PATH} is not executable"


def test_fuzz_equivalence():
    """Fuzz the agent's binary against the oracle to ensure bit-exact equivalence."""
    assert os.path.exists(ORACLE_PATH), f"Oracle binary missing at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"{ORACLE_PATH} is not executable"
    assert not filecmp.cmp(AGENT_PATH, ORACLE_PATH, shallow=False), (
        "Agent binary must not be a byte-identical copy of the legacy binary"
    )

    random.seed(42)
    charset = string.ascii_letters + string.digits

    for i in range(FUZZ_ITERATIONS):
        length = random.randint(MIN_LEN, MAX_LEN)
        seed_str = "".join(random.choices(charset, k=length))

        try:
            oracle_res = subprocess.run(
                [ORACLE_PATH, seed_str],
                capture_output=True,
                text=True,
                check=True
            )
            oracle_output = oracle_res.stdout
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on input '{seed_str}': {e.stderr}")

        try:
            agent_res = subprocess.run(
                [AGENT_PATH, seed_str],
                capture_output=True,
                text=True,
                check=True
            )
            agent_output = agent_res.stdout
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent binary failed on input '{seed_str}': {e.stderr}")

        assert agent_output == oracle_output, (
            f"Output mismatch on iteration {i+1}.\n"
            f"Input seed: '{seed_str}'\n"
            f"Oracle output: {repr(oracle_output)}\n"
            f"Agent output:  {repr(agent_output)}"
        )


def expected_output(seed):
    state = list(b"SEC_ROT_2024_!@#")
    data = seed.encode("ascii")
    for i, value in enumerate(data):
        slot = i % 16
        state[slot] = ((state[slot] + value) ^ (i & 0xff)) & 0xff
    return "".join(f"{value:02x}" for value in state) + "\n"


def copy_runtime_dependencies(binary, root):
    result = subprocess.run(
        ["ldd", binary], capture_output=True, text=True, check=True
    )
    dependencies = set()
    for raw_line in result.stdout.splitlines():
        line = raw_line.strip()
        if "=>" in line:
            candidate = line.split("=>", 1)[1].strip().split()[0]
        else:
            candidate = line.split()[0] if line else ""
        if candidate.startswith("/"):
            dependencies.add(candidate)

    for dependency in dependencies:
        destination = os.path.join(root, dependency.lstrip("/"))
        os.makedirs(os.path.dirname(destination), exist_ok=True)
        shutil.copy2(os.path.realpath(dependency), destination)


def test_source_builds_and_runs_without_legacy_oracle():
    """Compile the submitted C source and exercise it in an oracle-free filesystem."""
    assert os.path.exists(SOURCE_PATH), f"Source missing at {SOURCE_PATH}"
    assert os.path.isfile(SOURCE_PATH), f"{SOURCE_PATH} is not a file"

    with tempfile.TemporaryDirectory(prefix="rotator-build-") as workdir:
        rebuilt = os.path.join(workdir, "new_rotator")
        compile_res = subprocess.run(
            ["gcc", "-std=c11", "-O2", SOURCE_PATH, "-o", rebuilt],
            capture_output=True,
            text=True,
            timeout=30
        )
        assert compile_res.returncode == 0, (
            "Submitted C source failed to compile:\n"
            + compile_res.stdout + compile_res.stderr
        )
        assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)

        jail = os.path.join(workdir, "jail")
        os.makedirs(jail)
        os.chmod(jail, 0o755)
        jailed_binary = os.path.join(jail, "new_rotator")
        shutil.copy2(rebuilt, jailed_binary)
        os.chmod(jailed_binary, 0o755)
        copy_runtime_dependencies(rebuilt, jail)

        rng = random.Random(8675309)
        charset = string.ascii_letters + string.digits
        seeds = []
        for i in range(300):
            length = MIN_LEN + (i % (MAX_LEN - MIN_LEN + 1))
            seeds.append("".join(rng.choices(charset, k=length)))

        for i, seed in enumerate(seeds):
            result = subprocess.run(
                ["chroot", "--userspec=65534:65534", jail, "/new_rotator", seed],
                capture_output=True,
                text=True,
                timeout=5
            )
            assert result.returncode == 0, (
                f"Source-built binary failed in oracle-free environment on case {i+1}: "
                f"{result.stderr}"
            )
            assert result.stdout == expected_output(seed), (
                f"Source-built output mismatch on case {i+1}.\n"
                f"Input seed: '{seed}'\n"
                f"Expected: {expected_output(seed)!r}\n"
                f"Actual:   {result.stdout!r}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
