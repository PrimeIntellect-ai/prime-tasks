#!/bin/bash
set -e
mkdir -p /logs/verifier
reward=0
trap 'echo "$reward" > /logs/verifier/reward.txt' EXIT

verifier_tmp="$(mktemp -d /tmp/ema-verifier.XXXXXX)"
trap 'echo "$reward" > /logs/verifier/reward.txt; rm -rf "$verifier_tmp"' EXIT

cat << 'ORACLE_EOF' > "$verifier_tmp/oracle.cpp"
#include <iostream>

int main() {
    std::ios_base::sync_with_stdio(false);
    std::cin.tie(NULL);

    float alpha = 0.8f;
    float current_x;
    float previous_y = 0.0f;
    bool is_first = true;

    while (std::cin.read(reinterpret_cast<char*>(&current_x), sizeof(float))) {
        float y;
        if (is_first) {
            y = current_x;
            is_first = false;
        } else {
            y = alpha * current_x + (1.0f - alpha) * previous_y;
        }
        previous_y = y;
        std::cout.write(reinterpret_cast<const char*>(&y), sizeof(float));
    }
    return 0;
}
ORACLE_EOF

g++ -O3 "$verifier_tmp/oracle.cpp" -o "$verifier_tmp/oracle_ema"
export ORACLE_PATH="$verifier_tmp/oracle_ema"

cat << 'TEST_EOF' > "$verifier_tmp/test_final_state.py"
import os
import subprocess
import random
import struct
import pytest


def test_source_file_exists():
    """Verify that the student wrote the C++ source file."""
    source_path = "/home/user/ema_filter.cpp"
    assert os.path.exists(source_path), f"Source file missing: {source_path}"
    assert os.path.isfile(source_path), f"Path is not a file: {source_path}"


def test_executable_exists():
    """Verify that the student compiled the executable."""
    exec_path = "/home/user/ema_filter"
    assert os.path.exists(exec_path), f"Executable missing: {exec_path}"
    assert os.path.isfile(exec_path), f"Path is not a file: {exec_path}"
    assert os.access(exec_path, os.X_OK), f"File is not executable: {exec_path}"


def test_fuzz_equivalence():
    """Fuzz the agent's executable against the verification-time oracle."""
    oracle_path = os.environ["ORACLE_PATH"]
    agent_path = "/home/user/ema_filter"

    assert os.path.exists(oracle_path), f"Oracle missing: {oracle_path}"
    assert os.access(oracle_path, os.X_OK), f"Oracle not executable: {oracle_path}"

    random.seed(42)
    num_tests = 100

    for i in range(num_tests):
        num_floats = random.randint(1, 1024)
        input_floats = [random.uniform(-1000.0, 1000.0) for _ in range(num_floats)]
        input_bytes = struct.pack(f"<{num_floats}f", *input_floats)

        oracle_proc = subprocess.run(
            [oracle_path],
            input=input_bytes,
            capture_output=True,
            timeout=2
        )
        assert oracle_proc.returncode == 0, "Oracle failed to execute."
        oracle_out = oracle_proc.stdout

        agent_proc = subprocess.run(
            [agent_path],
            input=input_bytes,
            capture_output=True,
            timeout=2
        )
        assert agent_proc.returncode == 0, f"Agent program failed with return code {agent_proc.returncode}."
        agent_out = agent_proc.stdout

        if oracle_out != agent_out:
            if len(oracle_out) == len(agent_out) and len(oracle_out) % 4 == 0:
                oracle_floats = struct.unpack(f"<{len(oracle_out)//4}f", oracle_out)
                agent_floats = struct.unpack(f"<{len(agent_out)//4}f", agent_out)

                for idx, (o_val, a_val) in enumerate(zip(oracle_floats, agent_floats)):
                    if o_val != a_val:
                        pytest.fail(
                            f"Output mismatch at float index {idx}.\n"
                            f"Input float at index {idx}: {input_floats[idx]}\n"
                            f"Expected output: {o_val}\n"
                            f"Agent output: {a_val}"
                        )
            else:
                pytest.fail(
                    f"Output byte length mismatch.\n"
                    f"Expected {len(oracle_out)} bytes, got {len(agent_out)} bytes."
                )
TEST_EOF

if python3 -m pytest "$verifier_tmp/test_final_state.py" -x --tb=short 2>&1; then
    reward=1
fi
