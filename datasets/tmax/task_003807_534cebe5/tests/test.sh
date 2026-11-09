#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import uuid
import pytest

def test_env_txt_content():
    env_path = "/home/user/pipeline/env.txt"
    assert os.path.isfile(env_path), f"File {env_path} is missing."

    with open(env_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {env_path}, but found {len(lines)}."
    assert lines[0] == "X_PIPELINE_AUTH_KEY_V2", f"Expected first line to be 'X_PIPELINE_AUTH_KEY_V2', got '{lines[0]}'."
    assert lines[1] == "CS_8x99y2z1a4", f"Expected second line to be 'CS_8x99y2z1a4', got '{lines[1]}'."

def test_recover_go_exists():
    go_path = "/home/user/pipeline/recover.go"
    assert os.path.isfile(go_path), f"Go source file {go_path} is missing."

def test_recover_go_compiles_and_filters_dynamic_input():
    go_path = "/home/user/pipeline/recover.go"
    binary_path = "/tmp/recover_verified"
    input_path = "/home/user/pipeline/data/input.log"
    output_path = "/home/user/pipeline/data/output.log"
    secret = "CS_8x99y2z1a4"

    subprocess.run(
        ["go", "build", "-o", binary_path, go_path],
        cwd="/home/user/pipeline",
        check=True,
        timeout=30,
        capture_output=True,
        text=True,
    )

    marker = uuid.uuid4().hex
    expected_lines = [
        f"[AUTH] dynamic-{marker} {secret}",
        f"{secret} trailing-{marker}",
    ]
    challenge_lines = [
        f"[INFO] unrelated-{marker}",
        expected_lines[0],
        f"[AUTH] wrong-secret-{marker} CS_0000000000",
        expected_lines[1],
        f"[DEBUG] finished-{marker}",
    ]

    with open(input_path, "rb") as f:
        original_input = f.read()

    try:
        with open(input_path, "w") as f:
            f.write("\n".join(challenge_lines) + "\n")
        if os.path.exists(output_path):
            os.remove(output_path)

        subprocess.run(
            [binary_path],
            cwd="/home/user/pipeline",
            check=True,
            timeout=10,
            capture_output=True,
            text=True,
        )
        assert os.path.isfile(output_path), "recover.go did not create output.log when executed."
        with open(output_path, "r") as f:
            actual_lines = f.read().splitlines()
        assert actual_lines == expected_lines, (
            f"Compiled recover.go produced {actual_lines} for dynamic input; "
            f"expected {expected_lines}."
        )
    finally:
        with open(input_path, "wb") as f:
            f.write(original_input)
        if os.path.exists(output_path):
            os.remove(output_path)
        subprocess.run(
            [binary_path],
            cwd="/home/user/pipeline",
            check=True,
            timeout=10,
            capture_output=True,
            text=True,
        )

def test_output_log_content():
    output_path = "/home/user/pipeline/data/output.log"
    assert os.path.isfile(output_path), f"Output log {output_path} is missing."

    expected_lines = [
        "[AUTH] User login successful CS_8x99y2z1a4",
        "[AUTH] Token refreshed CS_8x99y2z1a4"
    ]

    with open(output_path, "r") as f:
        content = f.read().strip()

    actual_lines = [line.strip() for line in content.split("\n") if line.strip()]

    assert actual_lines == expected_lines, f"Expected output log lines {expected_lines}, but got {actual_lines}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
