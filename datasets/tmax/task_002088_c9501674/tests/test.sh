#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import secrets
import shutil
import subprocess

PIPELINE = "/home/user/pipeline"
SCRIPT = os.path.join(PIPELINE, "ingest.sh")
DATA = os.path.join(PIPELINE, "data")
SUMMARY = os.path.join(PIPELINE, "out", "summary.txt")


def run_ingest():
    return subprocess.run(
        [SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )


def read_summary():
    assert os.path.isfile(SUMMARY), (
        f"The summary file {SUMMARY} does not exist. Did the ingest script generate it?"
    )
    with open(SUMMARY, "r") as f:
        return f.read().strip().splitlines()


def test_pipeline_final_state_and_behavior():
    bad_file_quarantine = os.path.join(PIPELINE, "quarantine", "file_37.enc")
    bad_file_data = os.path.join(DATA, "file_37.enc")

    assert os.path.isfile(bad_file_quarantine), (
        f"The bad file was not moved to {bad_file_quarantine}"
    )
    assert not os.path.exists(bad_file_data), (
        f"The bad file still exists in {bad_file_data}, it should have been moved."
    )

    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} is missing"
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable"

    # Execute the submitted script on the real data rather than trusting a staged summary.
    result = run_ingest()
    assert result.returncode == 0, (
        f"The ingest script exited with {result.returncode}. stderr: {result.stderr}"
    )
    lines = read_summary()
    assert len(lines) == 1, (
        f"Expected exactly 1 line in summary.txt, but found {len(lines)} lines. "
        "The state leakage might not be fixed."
    )
    assert lines[0] == "file_15.enc: CRITICAL", (
        f"Expected 'file_15.enc: CRITICAL' in summary.txt, but got '{lines[0]}'."
    )

    # Exercise loop-state isolation using fresh filenames and a CRITICAL record followed
    # by OK records. The expected output is derived from the generated probe data.
    token = secrets.token_hex(6)
    critical_name = f"a_{token}.enc"
    ok_names = [f"m_{token}.enc", f"z_{token}.enc"]
    backup = DATA + ".verifier_backup_" + token
    os.rename(DATA, backup)
    os.mkdir(DATA)

    probe_result = None
    probe_lines = None
    try:
        records = [(critical_name, "STATUS: CRITICAL\n")]
        records.extend((name, "STATUS: OK\n") for name in ok_names)
        for name, decoded in records:
            with open(os.path.join(DATA, name), "wb") as f:
                f.write(base64.b64encode(decoded.encode()) + b"\n")

        probe_result = run_ingest()
        if os.path.isfile(SUMMARY):
            with open(SUMMARY, "r") as f:
                probe_lines = f.read().strip().splitlines()
    finally:
        if os.path.isdir(DATA):
            shutil.rmtree(DATA)
        os.rename(backup, DATA)

    # Leave the requested final artifact generated from the real data.
    final_result = run_ingest()

    assert probe_result is not None and probe_result.returncode == 0, (
        "The ingest script failed on valid base64 probe files: "
        + (probe_result.stderr if probe_result is not None else "no result")
    )
    assert probe_lines == [f"{critical_name}: CRITICAL"], (
        f"State leaked between loop iterations; expected only {critical_name}, "
        f"but summary contained {probe_lines}."
    )
    assert final_result.returncode == 0, (
        f"The final ingest run exited with {final_result.returncode}. "
        f"stderr: {final_result.stderr}"
    )
    final_lines = read_summary()
    assert len(final_lines) == 1, (
        f"Expected exactly 1 line in final summary.txt, but found {len(final_lines)}."
    )
    assert final_lines[0] == "file_15.enc: CRITICAL", (
        f"Expected 'file_15.enc: CRITICAL' in final summary.txt, got '{final_lines[0]}'."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
