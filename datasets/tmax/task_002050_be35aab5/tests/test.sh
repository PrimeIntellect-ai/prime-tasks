#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import subprocess
import sys
from pathlib import Path

import pytest

ORACLE_PATH = "/tests/oracle_processor"
AGENT_PATH = "/home/user/processor/target/release/processor"
PROCESSOR_MANIFEST = "/home/user/processor/Cargo.toml"
LIB_MANIFEST = "/app/anonymizer_lib/Cargo.toml"
LIB_SOURCE = Path("/app/anonymizer_lib/src/lib.rs")


def run_oracle(input_str):
    assert os.path.isfile(ORACLE_PATH), f"Oracle not found at {ORACLE_PATH}"
    proc = subprocess.run(
        [sys.executable, ORACLE_PATH],
        input=input_str,
        text=True,
        capture_output=True,
    )
    assert proc.returncode == 0, f"Oracle failed with error: {proc.stderr}"
    return proc.stdout


def generate_input():
    """Generates a single line of input matching the required regex pattern."""
    id_val = random.randint(0, 9999)
    user_len = random.randint(3, 8)
    user = "".join(random.choices("abcdefghijklmnopqrstuvwxyz", k=user_len))
    ip = f"{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}"

    def gen_sensor():
        if random.random() < 0.3:
            return "NA"
        return f"{random.randint(0, 999)}.{random.randint(0, 9)}"

    s1, s2, s3 = gen_sensor(), gen_sensor(), gen_sensor()
    return f"ID:{id_val};USER:{user};IP:{ip};S1:{s1};S2:{s2};S3:{s3}"


def test_projects_build_and_local_library_is_a_dependency():
    assert os.path.isfile(LIB_MANIFEST), "anonymizer_lib Cargo.toml is missing"
    lib_check = subprocess.run(
        ["cargo", "check", "--manifest-path", LIB_MANIFEST],
        text=True,
        capture_output=True,
    )
    assert lib_check.returncode == 0, f"anonymizer_lib does not compile:\n{lib_check.stderr}"

    assert os.path.isfile(PROCESSOR_MANIFEST), "Processor Cargo.toml is missing"
    build = subprocess.run(
        ["cargo", "build", "--release", "--manifest-path", PROCESSOR_MANIFEST],
        text=True,
        capture_output=True,
    )
    assert build.returncode == 0, f"Processor release build failed:\n{build.stderr}"

    metadata_proc = subprocess.run(
        ["cargo", "metadata", "--format-version", "1", "--manifest-path", PROCESSOR_MANIFEST],
        text=True,
        capture_output=True,
    )
    assert metadata_proc.returncode == 0, f"Could not inspect processor dependencies: {metadata_proc.stderr}"
    metadata = json.loads(metadata_proc.stdout)
    processor_manifest = os.path.realpath(PROCESSOR_MANIFEST)
    processor_pkg = next(
        (p for p in metadata["packages"] if os.path.realpath(p["manifest_path"]) == processor_manifest),
        None,
    )
    assert processor_pkg is not None, "Processor package is missing from cargo metadata"
    expected_lib_manifest = os.path.realpath(LIB_MANIFEST)
    assert any(
        dep.get("name") == "anonymizer_lib"
        and dep.get("path")
        and os.path.realpath(os.path.join(dep["path"], "Cargo.toml")) == expected_lib_manifest
        for dep in processor_pkg["dependencies"]
    ), "Processor must depend on the local /app/anonymizer_lib crate"

    assert os.path.isfile(AGENT_PATH), f"Agent binary not found at {AGENT_PATH}. Did you build in release mode?"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary is not executable: {AGENT_PATH}"
    with open(AGENT_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Release processor must be a compiled native binary"


def test_fuzz_equivalence():
    """Test that the agent's processor exactly matches the oracle's output on random inputs."""
    random.seed(42)
    num_iterations = 1000
    inputs = [generate_input() for _ in range(num_iterations)]
    input_str = "\n".join(inputs) + "\n"

    assert os.path.exists(ORACLE_PATH), f"Oracle binary not found at {ORACLE_PATH}"
    assert os.path.exists(AGENT_PATH), f"Agent binary not found at {AGENT_PATH}. Did you build in release mode?"

    oracle_out = run_oracle(input_str).strip().split("\n")
    agent_proc = subprocess.run([AGENT_PATH], input=input_str, text=True, capture_output=True)
    assert agent_proc.returncode == 0, f"Agent failed with error: {agent_proc.stderr}"
    agent_out = agent_proc.stdout.strip().split("\n")

    if oracle_out == [""]:
        oracle_out = []
    if agent_out == [""]:
        agent_out = []

    assert len(oracle_out) == len(agent_out), f"Output line count mismatch. Expected {len(oracle_out)}, got {len(agent_out)}"

    for i, (o, a) in enumerate(zip(oracle_out, agent_out)):
        input_idx = i // 3
        assert o == a, (
            f"Mismatch at output line {i+1}.\n"
            f"Input: {inputs[input_idx]}\n"
            f"Expected: {o}\n"
            f"Got:      {a}"
        )


def test_processor_actually_uses_anonymizer_library():
    original = LIB_SOURCE.read_bytes()
    probe_source = b'''pub fn mask_pii(_user: &str, _ip: &str) -> (String, String) {\n    ("LIB_USER_PROBE".to_string(), "LIB_IP_PROBE".to_string())\n}\n'''
    try:
        LIB_SOURCE.write_bytes(probe_source)
        build = subprocess.run(
            ["cargo", "build", "--release", "--manifest-path", PROCESSOR_MANIFEST],
            text=True,
            capture_output=True,
        )
        assert build.returncode == 0, f"Processor failed to rebuild against anonymizer_lib: {build.stderr}"
        sample = "ID:7;USER:alice;IP:1.2.3.4;S1:1;S2:2;S3:3\n"
        proc = subprocess.run([AGENT_PATH], input=sample, text=True, capture_output=True)
        assert proc.returncode == 0, proc.stderr
        rows = proc.stdout.strip().splitlines()
        assert len(rows) == 3
        assert all(",LIB_USER_PROBE,LIB_IP_PROBE," in row for row in rows), (
            "Processor output does not use values returned by anonymizer_lib::mask_pii"
        )
    finally:
        LIB_SOURCE.write_bytes(original)
        restore = subprocess.run(
            ["cargo", "build", "--release", "--manifest-path", PROCESSOR_MANIFEST],
            text=True,
            capture_output=True,
        )
        assert restore.returncode == 0, f"Failed to restore the release build: {restore.stderr}"


def test_run_pipeline_script():
    script = "/home/user/run_pipeline.sh"
    assert os.path.isfile(script), f"Pipeline script {script} is missing"
    assert os.access(script, os.X_OK), f"Pipeline script {script} is not executable"
    content = Path(script).read_text()
    assert "/tmp/input.log" in content
    assert AGENT_PATH in content
    assert "/tmp/output.csv" in content

    input_path = Path("/tmp/input.log")
    output_path = Path("/tmp/output.csv")
    old_input = input_path.read_bytes() if input_path.exists() else None
    old_output = output_path.read_bytes() if output_path.exists() else None
    sample = "ID:402;USER:alice;IP:192.168.1.5;S1:10.5;S2:NA;S3:12.5\n"
    try:
        input_path.write_text(sample)
        if output_path.exists():
            output_path.unlink()
        proc = subprocess.run([script], text=True, capture_output=True)
        assert proc.returncode == 0, f"Pipeline script failed: {proc.stderr}"
        assert output_path.is_file(), "Pipeline script did not create /tmp/output.csv"
        assert output_path.read_text() == run_oracle(sample)
    finally:
        if old_input is None:
            input_path.unlink(missing_ok=True)
        else:
            input_path.write_bytes(old_input)
        if old_output is None:
            output_path.unlink(missing_ok=True)
        else:
            output_path.write_bytes(old_output)


def test_cron_job_setup():
    """Test that the cron job file exists and contains the correct schedule and command."""
    cron_path = "/etc/cron.d/sensor_processor"
    assert os.path.exists(cron_path), f"Cron file {cron_path} is missing."

    with open(cron_path, "r") as f:
        content = f.read()

    expected_pattern = "*/5 * * * * user /home/user/run_pipeline.sh"
    assert expected_pattern in content, (
        f"Cron file {cron_path} does not contain the expected pattern.\n"
        f"Expected to find: '{expected_pattern}'\n"
        f"Actual content:\n{content}"
    )
    assert any(
        re.fullmatch(r"\s*\*/5\s+\*\s+\*\s+\*\s+\*\s+user\s+/home/user/run_pipeline\.sh\s*", line)
        for line in content.splitlines()
        if not line.lstrip().startswith("#")
    ), "The required cron entry must be an active cron line"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
