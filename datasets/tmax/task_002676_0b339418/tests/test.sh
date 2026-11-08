#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/app/legacy_checker"
SOURCE_PATH = "/home/user/policy_check.go"
AGENT_PATH = "/home/user/policy_check"
NUM_ITERATIONS = 1000


def test_agent_executable_exists():
    """Ensure the student's compiled Go program exists and is executable."""
    assert os.path.exists(AGENT_PATH), f"Compiled binary not found at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"{AGENT_PATH} is not a file"
    assert os.access(AGENT_PATH, os.X_OK), f"File {AGENT_PATH} is not executable"


def test_fuzz_equivalence():
    """Fuzz both the oracle and the agent program to ensure bit-exact equivalence."""
    assert os.path.exists(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"

    random.seed(42)
    hex_chars = "0123456789ABCDEF"

    for _ in range(NUM_ITERATIONS):
        test_input = "".join(random.choices(hex_chars, k=12))

        oracle_result = subprocess.run(
            [ORACLE_PATH, test_input],
            capture_output=True,
            text=True,
            timeout=2
        )
        agent_result = subprocess.run(
            [AGENT_PATH, test_input],
            capture_output=True,
            text=True,
            timeout=2
        )

        assert agent_result.returncode == 0, (
            f"Agent failed on input {test_input} with stderr: {agent_result.stderr}"
        )
        assert agent_result.stdout == oracle_result.stdout, (
            f"Output mismatch on input {test_input}.\n"
            f"Expected (Oracle): {repr(oracle_result.stdout)}\n"
            f"Got (Agent): {repr(agent_result.stdout)}"
        )


def test_go_source_and_native_implementation():
    """Rebuild the submitted Go source and run both artifacts without host executables."""
    assert os.path.exists(SOURCE_PATH), f"Go source not found at {SOURCE_PATH}"
    assert os.path.isfile(SOURCE_PATH), f"{SOURCE_PATH} is not a regular file"
    assert not os.path.islink(SOURCE_PATH), f"{SOURCE_PATH} must not be a symlink"

    metadata = subprocess.run(
        ["go", "version", "-m", AGENT_PATH],
        capture_output=True,
        text=True,
        timeout=10
    )
    assert metadata.returncode == 0 and "go1" in metadata.stdout, (
        f"{AGENT_PATH} is not a compiled Go executable"
    )

    with tempfile.TemporaryDirectory(prefix="policy-native-") as work:
        rebuilt = os.path.join(work, "rebuilt_policy_check")
        build = subprocess.run(
            ["go", "build", "-trimpath", "-o", rebuilt, SOURCE_PATH],
            capture_output=True,
            text=True,
            timeout=30,
            env={**os.environ, "CGO_ENABLED": "0"}
        )
        assert build.returncode == 0, f"Go source failed to compile: {build.stderr}"

        roots = []
        for name, artifact in (("submitted", AGENT_PATH), ("rebuilt", rebuilt)):
            root = os.path.join(work, name)
            os.mkdir(root)
            isolated_binary = os.path.join(root, "policy_check")
            shutil.copy2(artifact, isolated_binary)
            os.chmod(isolated_binary, 0o755)
            roots.append((name, root))

        random.seed(42)
        hex_chars = "0123456789ABCDEF"
        for _ in range(NUM_ITERATIONS):
            test_input = "".join(random.choices(hex_chars, k=12))
            oracle_result = subprocess.run(
                [ORACLE_PATH, test_input],
                capture_output=True,
                text=True,
                timeout=2
            )
            assert oracle_result.returncode == 0

            for name, root in roots:
                result = subprocess.run(
                    ["chroot", root, "/policy_check", test_input],
                    capture_output=True,
                    text=True,
                    timeout=2
                )
                assert result.returncode == 0, (
                    f"{name} artifact failed in isolation on {test_input}: {result.stderr}"
                )
                assert result.stdout == oracle_result.stdout, (
                    f"{name} artifact mismatch in isolation on {test_input}.\n"
                    f"Expected: {repr(oracle_result.stdout)}\n"
                    f"Got: {repr(result.stdout)}"
                )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
