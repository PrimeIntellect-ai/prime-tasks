#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import string
import pytest
import tempfile

def test_bash_ini_parser_fixed():
    """Check that bash-ini-parser.sh is fixed and installed in the correct location."""
    target_path = "/home/user/.local/lib/bash-ini-parser.sh"
    assert os.path.isfile(target_path), f"File not found: {target_path}"

    with open(target_path, "r") as f:
        content = f.read()

    # Check that the syntax error is fixed
    assert 'if [ "$IN_SECTION" = true ]; then' in content, "The syntax error in bash-ini-parser.sh was not correctly fixed."
    assert 'if [ "$IN_SECTION" = true ; then' not in content, "The original syntax error is still present."

def test_filesystem_mounted():
    """Check that the ext4 sparse file is mounted using fuse2fs."""
    img_path = "/home/user/restore_vol.img"
    mnt_path = "/home/user/mnt/restore_target"

    assert os.path.isfile(img_path), f"Image file not found: {img_path}"
    assert os.path.isdir(mnt_path), f"Mount point not found: {mnt_path}"

    # Check if mounted with fuse2fs
    # fuse2fs might show up in mount or df
    mount_output = subprocess.check_output(["mount"]).decode()
    assert mnt_path in mount_output, f"{mnt_path} is not mounted."
    assert "fuse2fs" in mount_output or "fuse" in mount_output, "Mount does not appear to use fuse2fs."

def test_systemd_service():
    """Check the systemd user service configuration and execution."""
    # Check if service is active or ran successfully
    try:
        # systemctl --user status might return non-zero if it's oneshot and exited, check show
        output = subprocess.check_output(
            ["systemctl", "--user", "show", "restore-test.service", "--property=Environment", "--property=Result"],
            env=dict(os.environ, XDG_RUNTIME_DIR="/run/user/1000")
        ).decode()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to query systemd service: {e}")

    assert "PATH=/home/user/.local/bin" in output, "The systemd service Environment does not explicitly include PATH=/home/user/.local/bin"

    # Check if do_restore.sh created the log
    log_path = "/home/user/mnt/restore_target/restore.log"
    assert os.path.isfile(log_path), f"Restore log not found at {log_path}. Did the service run?"
    with open(log_path, "r") as f:
        log_content = f.read()
    assert "SUCCESS" in log_content, "The string 'SUCCESS' was not found in the restore log."

def generate_fuzz_input():
    job_id = random.randint(1, 99999)
    total_restored = random.randint(0, 500000)
    num_errors = random.randint(0, 10)

    lines = []
    lines.append(f"[INFO] Starting restore job {job_id}")

    failed_files = []
    for _ in range(num_errors):
        path_len = random.randint(5, 20)
        path = "/" + "".join(random.choices(string.ascii_letters + string.digits, k=path_len))
        lines.append(f"[ERROR] Failed to extract: {path} (Random error)")
        failed_files.append(path)

    lines.append(f"[INFO] Restored {total_restored} files")
    lines.append(f"[INFO] Job finished with {num_errors} errors.")

    # Shuffle some lines but keep start/end logical if needed, or just leave as is since grep is line-independent mostly
    return "\n".join(lines) + "\n"

def oracle_analyze(input_str):
    """Python implementation of the oracle logic."""
    import re

    job_id_match = re.search(r"Starting restore job (\d+)", input_str)
    job_id = job_id_match.group(1) if job_id_match else ""

    restored_match = re.search(r"Restored (\d+) files", input_str)
    total_restored = restored_match.group(1) if restored_match else ""

    error_match = re.search(r"Job finished with (\d+) errors\.", input_str)
    error_count = error_match.group(1) if error_match else "0"

    failed_files = re.findall(r"Failed to extract: ([^\s]+)", input_str)
    failed_files_str = ",".join(failed_files) if failed_files else "NONE"

    output = []
    output.append(f"JOB: {job_id}")
    output.append(f"TOTAL_RESTORED: {total_restored}")
    output.append(f"ERROR_COUNT: {error_count}")
    output.append(f"FAILED_FILES: {failed_files_str}")

    return "\n".join(output) + "\n"

def test_analyze_restore_fuzzing():
    """Fuzz equivalence test for analyze_restore.sh"""
    agent_script = "/home/user/bin/analyze_restore.sh"
    assert os.path.isfile(agent_script), f"Agent script not found at {agent_script}"
    assert os.access(agent_script, os.X_OK), f"Agent script is not executable: {agent_script}"

    random.seed(42)

    for i in range(100):
        fuzz_input = generate_fuzz_input()

        expected_output = oracle_analyze(fuzz_input)

        try:
            proc = subprocess.run(
                [agent_script],
                input=fuzz_input.encode(),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=2
            )
            actual_output = proc.stdout.decode()
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out on input:\n{fuzz_input}")

        if actual_output != expected_output:
            pytest.fail(
                f"Mismatch on fuzz iteration {i}.\n"
                f"Input:\n{fuzz_input}\n"
                f"Expected Output:\n{expected_output}\n"
                f"Actual Output:\n{actual_output}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
