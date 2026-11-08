#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import subprocess
import uuid
import pytest


def test_debug_report_json():
    report_path = "/home/user/debug_report.json"
    assert os.path.isfile(report_path), f"Report file {report_path} is missing."

    with open(report_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Report file {report_path} is not valid JSON.")

    assert "debug_token" in data, "Key 'debug_token' is missing in the JSON report."
    assert data["debug_token"] == "a1b2c3d4-8f9e-4a5b-9c8d-7e6f5a4b3c2d", "Incorrect debug_token in JSON report."

    assert "crash_fragment" in data, "Key 'crash_fragment' is missing in the JSON report."
    assert data["crash_fragment"] == "critical", "Incorrect crash_fragment in JSON report."


def test_scan_script_fixed():
    script_path = "/home/user/service_repo/scan.sh"
    repo_dir = "/home/user/service_repo"
    data_dir = os.path.join(repo_dir, "data")

    assert os.path.isfile(script_path), f"Script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."
    assert os.path.isdir(data_dir), f"Data directory {data_dir} is missing."

    # Add unpredictable filenames so a script cannot pass by printing a fixed subset.
    marker = uuid.uuid4().hex
    probe_names = [
        f"verification {marker} spaced file.txt",
        f"verification-{marker}-glob[*?] backup.dat",
        f"verification  {marker}  multiple spaces.bin",
    ]
    probe_paths = [os.path.join(data_dir, name) for name in probe_names]

    try:
        for path in probe_paths:
            with open(path, "wb") as f:
                f.write(b"verification fixture\n")

        expected_names = sorted(
            entry.name for entry in os.scandir(data_dir)
            if entry.is_file(follow_symlinks=True)
        )

        try:
            result = subprocess.run(
                [script_path],
                cwd=repo_dir,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=True,
                timeout=30
            )
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Script {script_path} failed to execute properly. Return code: {e.returncode}\nOutput: {e.stdout}\nError: {e.stderr}")
        except subprocess.TimeoutExpired as e:
            pytest.fail(f"Script {script_path} timed out, suggesting runaway processing.\nOutput: {e.stdout}\nError: {e.stderr}")

        output = result.stdout + result.stderr

        # The original buggy script outputs "Error: data/critical not found."
        # The fixed script should not output any errors related to file not found.
        assert "Error:" not in output, f"Script output contains errors, indicating it still fails on spaces:\n{output}"
        assert "not found" not in output, f"Script output contains 'not found', indicating it still fails on spaces:\n{output}"

        # Ensure it actually ran and did something (did not just exit empty)
        assert "Processing" in output or "backup.tar.gz" in output or "report 2023.dat" in output, "Script did not seem to process the files as expected."

        # Every regular file must be represented intact on its own processing line.
        # This catches fixed-output stubs and filename splitting while allowing either
        # basenames or paths in the script's normal Processing message.
        processing_lines = [line for line in output.splitlines() if "Processing" in line]
        matched_line_indexes = set()
        missing = []
        for name in expected_names:
            indexes = [i for i, line in enumerate(processing_lines) if name in line]
            if not indexes:
                missing.append(name)
            else:
                matched_line_indexes.add(indexes[0])

        assert not missing, f"The script did not process these filenames intact: {missing}\nOutput:\n{output}"
        assert len(matched_line_indexes) == len(expected_names), (
            "Each file must be processed separately rather than combining filenames "
            f"into a single message. Expected {len(expected_names)} distinct processing lines.\nOutput:\n{output}"
        )
    finally:
        for path in probe_paths:
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
