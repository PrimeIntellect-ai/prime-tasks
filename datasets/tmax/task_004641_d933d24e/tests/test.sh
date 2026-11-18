#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
import tempfile
import pytest


def test_fuzz_equivalence():
    oracle = "/app/wal_archive_tool"
    source = "/home/user/custom_archive_tool.cpp"
    agent = "/home/user/custom_archive_tool"

    # Preserve the original artifact assertions and require the requested source.
    assert os.path.exists(agent), f"Agent binary not found at {agent}"
    assert os.access(agent, os.X_OK), f"Agent binary is not executable at {agent}"
    assert os.path.exists(oracle), f"Oracle binary not found at {oracle}"
    assert os.path.isfile(source), f"C++ source not found at {source}"

    with open(oracle, "rb") as f:
        oracle_binary = f.read()
    with open(agent, "rb") as f:
        submitted_binary = f.read()
    assert submitted_binary != oracle_binary, "Submitted executable is byte-identical to the legacy oracle"

    random.seed(42)

    with tempfile.TemporaryDirectory() as tmpdir:
        cases = []

        # Produce all expected answers first, retain them only in verifier memory,
        # and remove each oracle output before the submitted program can run.
        for i in range(100):
            if i == 0:
                length = 0
            elif i < 10:
                length = random.randint(1, 1000)
            else:
                length = random.randint(1000, 500000)

            data = bytearray()
            while len(data) < length:
                chunk_type = random.choice(['random', 'repeat', 'nulls', 'ascii'])
                if chunk_type == 'random':
                    l = min(length - len(data), random.randint(1, 100))
                    data.extend(random.getrandbits(8) for _ in range(l))
                elif chunk_type == 'repeat':
                    l = min(length - len(data), random.randint(1, 1000))
                    b = random.getrandbits(8)
                    data.extend([b] * l)
                elif chunk_type == 'nulls':
                    l = min(length - len(data), random.randint(1, 1000))
                    data.extend([0] * l)
                else:
                    l = min(length - len(data), random.randint(1, 100))
                    data.extend(random.randint(32, 126) for _ in range(l))

            input_path = os.path.join(tmpdir, f"input_{i}.bin")
            oracle_out = os.path.join(tmpdir, f"oracle_{i}.bin")
            with open(input_path, "wb") as f:
                f.write(data)

            try:
                subprocess.run([oracle, input_path, oracle_out], check=True, capture_output=True)
            except subprocess.CalledProcessError:
                pytest.fail(f"Oracle failed on input {i} (length {length}). This should not happen.")

            with open(oracle_out, "rb") as f:
                expected = f.read()
            os.unlink(oracle_out)
            cases.append((i, length, input_path, expected))

        # The oracle was needed during the task for reverse engineering, but it
        # must not remain available while compiling or exercising the replacement.
        os.unlink(oracle)
        assert not os.path.exists(oracle), "Oracle remained accessible during replacement testing"

        build_path = os.path.join(tmpdir, "rebuilt_custom_archive_tool")
        try:
            compile_res = subprocess.run(
                ["/usr/bin/g++", "-O2", source, "-o", build_path],
                capture_output=True,
                text=True,
                timeout=30,
            )
        except subprocess.TimeoutExpired:
            pytest.fail("Compilation of custom_archive_tool.cpp timed out")

        assert compile_res.returncode == 0, (
            "Failed to compile custom_archive_tool.cpp.\n"
            f"Stderr: {compile_res.stderr}"
        )
        assert os.path.isfile(build_path), "Compilation did not produce an executable"
        with open(build_path, "rb") as f:
            rebuilt_binary = f.read()
        assert rebuilt_binary.startswith(b"\x7fELF"), "Compiled replacement is not an ELF executable"
        assert rebuilt_binary != oracle_binary, "Rebuilt executable is byte-identical to the legacy oracle"

        # Replace the submitted executable safely, avoiding following a submitted symlink.
        os.chmod(build_path, 0o755)
        os.replace(build_path, agent)
        assert os.access(agent, os.X_OK), f"Rebuilt agent binary is not executable at {agent}"

        for i, length, input_path, expected in cases:
            assert not os.path.exists(oracle), "Oracle was restored during replacement testing"
            agent_out = os.path.join(tmpdir, f"agent_{i}.bin")

            # Trace process execution and reject wrappers or embedded launchers
            # that delegate the work to another executable.
            try:
                res = subprocess.run(
                    ["/usr/bin/strace", "-f", "-qq", "-e", "trace=execve,execveat", agent, input_path, agent_out],
                    capture_output=True,
                    timeout=10,
                )
            except subprocess.TimeoutExpired:
                pytest.fail(f"Agent timed out on input {i} (length {length}).")

            trace = res.stderr.decode("utf-8", errors="replace")
            exec_calls = re.findall(r"\bexecve(?:at)?\(", trace)
            assert len(exec_calls) == 1, (
                f"Agent delegated to another executable on input {i}; "
                "the replacement must implement the algorithm itself."
            )
            assert res.returncode == 0, (
                f"Agent failed with return code {res.returncode} on input {i} "
                f"(length {length}).\nStderr/trace: {trace}"
            )
            assert os.path.exists(agent_out), f"Agent did not create output file for input {i}"

            with open(agent_out, "rb") as f:
                agent_data = f.read()

            if expected != agent_data:
                for j in range(min(len(expected), len(agent_data))):
                    if expected[j] != agent_data[j]:
                        pytest.fail(
                            f"Mismatch on input {i} (length {length}) at byte {j}.\n"
                            f"Oracle byte: {hex(expected[j])}\n"
                            f"Agent byte: {hex(agent_data[j])}"
                        )
                pytest.fail(
                    f"Mismatch on input {i} (length {length}).\n"
                    f"Oracle output length: {len(expected)}\n"
                    f"Agent output length: {len(agent_data)}"
                )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
