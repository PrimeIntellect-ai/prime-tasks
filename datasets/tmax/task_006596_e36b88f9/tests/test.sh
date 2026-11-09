#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import pytest

CONFIG_LOG = "/home/user/config_log.txt"
METADATA = "/home/user/metadata.txt"
OUTPUT = "/home/user/processed_logs.csv"
SOURCE = "/home/user/process_configs.c"
EXECUTABLE = "/home/user/process_configs"


def derive_expected(config_text, metadata_text):
    metadata = {}
    for line in metadata_text.splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.split("|")
        if len(parts) >= 2:
            metadata[parts[0]] = parts[1]

    expected_lines = []
    server_counts = {}
    for line in config_text.splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.split("|")
        if len(parts) < 3:
            continue

        timestamp = parts[0]
        server_id = parts[1]
        raw_config = parts[2]
        email = metadata.get(server_id, "unknown@unknown.com")

        if "@" in email:
            local_part, domain = email.split("@", 1)
            if len(local_part) > 0:
                masked_email = f"{local_part[0]}*@{domain}"
            else:
                masked_email = f"*@{domain}"
        else:
            masked_email = email

        cleaned_config = re.sub(r'[^a-zA-Z0-9]', '', raw_config).lower()
        server_counts[server_id] = server_counts.get(server_id, 0) + 1
        cumulative_changes = server_counts[server_id]
        expected_lines.append(
            f"{timestamp},{server_id},{masked_email},{cleaned_config},{cumulative_changes}"
        )

    return expected_lines


def assert_output_matches(expected_lines):
    assert os.path.exists(OUTPUT), f"Missing output file {OUTPUT}"
    with open(OUTPUT, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} rows in CSV, but got {len(actual_lines)}"
    )
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Row {i+1} mismatch.\nExpected: {expected}\nActual:   {actual}"
        )


def run_and_check(program):
    with open(CONFIG_LOG, "r") as f:
        config_text = f.read()
    with open(METADATA, "r") as f:
        metadata_text = f.read()
    expected_lines = derive_expected(config_text, metadata_text)

    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)

    try:
        result = subprocess.run(
            [program], cwd="/home/user", stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=10
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Program {program} timed out")

    assert result.returncode == 0, (
        f"Program {program} exited with status {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    with open(CONFIG_LOG, "r") as f:
        assert f.read() == config_text, "Program modified config_log.txt"
    with open(METADATA, "r") as f:
        assert f.read() == metadata_text, "Program modified metadata.txt"
    assert_output_matches(expected_lines)


def test_c_program_exists():
    c_source_path = "/home/user/process_configs.c"
    c_exec_path = "/home/user/process_configs"

    assert os.path.exists(c_source_path), f"C source file missing at {c_source_path}"
    assert os.path.exists(c_exec_path), f"Compiled executable missing at {c_exec_path}"
    assert os.access(c_exec_path, os.X_OK), f"File {c_exec_path} is not executable"
    with open(c_exec_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {c_exec_path} is not a compiled ELF executable"


def test_submitted_executable_produces_output():
    run_and_check(EXECUTABLE)


def test_submitted_c_source_produces_output():
    rebuilt = "/tmp/process_configs_rebuilt"
    result = subprocess.run(
        ["gcc", SOURCE, "-o", rebuilt], stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True
    )
    assert result.returncode == 0, (
        f"C source did not compile.\nstdout: {result.stdout}\nstderr: {result.stderr}"
    )
    run_and_check(rebuilt)


def test_processed_logs_csv_correctness():
    config_log_path = "/home/user/config_log.txt"
    metadata_path = "/home/user/metadata.txt"
    output_csv_path = "/home/user/processed_logs.csv"

    assert os.path.exists(config_log_path), f"Missing {config_log_path}"
    assert os.path.exists(metadata_path), f"Missing {metadata_path}"
    assert os.path.exists(output_csv_path), f"Missing output file {output_csv_path}"

    metadata = {}
    with open(metadata_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split("|")
            if len(parts) >= 2:
                metadata[parts[0]] = parts[1]

    expected_lines = []
    server_counts = {}
    with open(config_log_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split("|")
            if len(parts) < 3:
                continue

            timestamp = parts[0]
            server_id = parts[1]
            raw_config = parts[2]
            email = metadata.get(server_id, "unknown@unknown.com")

            if "@" in email:
                local_part, domain = email.split("@", 1)
                if len(local_part) > 0:
                    masked_email = f"{local_part[0]}*@{domain}"
                else:
                    masked_email = f"*@{domain}"
            else:
                masked_email = email

            cleaned_config = re.sub(r'[^a-zA-Z0-9]', '', raw_config).lower()
            server_counts[server_id] = server_counts.get(server_id, 0) + 1
            cumulative_changes = server_counts[server_id]
            expected_lines.append(
                f"{timestamp},{server_id},{masked_email},{cleaned_config},{cumulative_changes}"
            )

    with open(output_csv_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} rows in CSV, but got {len(actual_lines)}"
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Row {i+1} mismatch.\nExpected: {expected}\nActual:   {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
