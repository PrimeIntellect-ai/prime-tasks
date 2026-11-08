#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat


def test_critical_utc_log_exists():
    """Test that the critical_utc.log file exists."""
    log_file = "/home/user/critical_utc.log"
    assert os.path.isfile(log_file), f"File {log_file} does not exist. The script might not have created it."


def test_critical_utc_log_permissions():
    """Test that the critical_utc.log file has 600 permissions."""
    log_file = "/home/user/critical_utc.log"
    assert os.path.isfile(log_file), f"File {log_file} does not exist."
    st = os.stat(log_file)
    permissions = stat.S_IMODE(st.st_mode)
    assert permissions == 0o600, f"Permissions of {log_file} are {oct(permissions)}, expected 0o600."


def test_critical_utc_log_content():
    """Test that the critical_utc.log file has the correct content."""
    log_file = "/home/user/critical_utc.log"
    assert os.path.isfile(log_file), f"File {log_file} does not exist."

    expected_lines = [
        "2023-11-01 03:45:00 UTC | Payment gateway timeout",
        "2023-11-01 16:30:00 UTC | Disk space critically low on /dev/sda1"
    ]

    with open(log_file, "r") as f:
        content = f.read().strip().splitlines()

    assert len(content) == len(expected_lines), f"Expected {len(expected_lines)} lines, but found {len(content)}."

    for i, (actual, expected) in enumerate(zip(content, expected_lines)):
        assert actual.strip() == expected, f"Line {i+1} mismatch. Expected: '{expected}', Got: '{actual.strip()}'"


def test_migrate_logs_sh_exists_and_executable():
    """Test that the migrate_logs.sh script exists and is executable."""
    script_file = "/home/user/migrate_logs.sh"
    assert os.path.isfile(script_file), f"Script {script_file} does not exist."

    st = os.stat(script_file)
    is_executable = bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH))
    assert is_executable, f"Script {script_file} is not executable."
TEST_EOF

cat << 'TEST_EOF' > /tmp/test_script_behavior.py
import os
import shutil
import stat
import subprocess
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

SCRIPT = Path("/home/user/migrate_logs.sh")
SOURCE = Path("/home/user/legacy_app.log")
OUTPUT = Path("/home/user/critical_utc.log")


def snapshot(path):
    if not path.exists() and not path.is_symlink():
        return None
    st = path.stat()
    return (path.read_bytes(), stat.S_IMODE(st.st_mode), st.st_uid, st.st_gid)


def remove_path(path):
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    elif path.exists() or path.is_symlink():
        path.unlink()


def restore(path, saved):
    remove_path(path)
    if saved is not None:
        data, mode, uid, gid = saved
        path.write_bytes(data)
        os.chmod(path, mode)
        os.chown(path, uid, gid)


def expected_for(lines):
    result = []
    tokyo = ZoneInfo("Asia/Tokyo")
    utc = ZoneInfo("UTC")
    for line in lines:
        marker = " [CRITICAL] "
        if marker not in line:
            continue
        timestamp_text, message = line.split(marker, 1)
        local_time = datetime.strptime(timestamp_text, "%Y-%m-%d %H:%M:%S").replace(tzinfo=tokyo)
        timestamp = local_time.astimezone(utc).strftime("%Y-%m-%d %H:%M:%S UTC")
        result.append(f"{timestamp} | {message}")
    return result


def run_case(lines):
    SOURCE.write_text("\n".join(lines) + "\n", encoding="utf-8")
    os.chmod(SOURCE, 0o644)
    remove_path(OUTPUT)

    env = os.environ.copy()
    env["TZ"] = "UTC"
    completed = subprocess.run(
        [str(SCRIPT)],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert completed.returncode == 0, (
        f"Script exited with {completed.returncode}. "
        f"stdout={completed.stdout!r}, stderr={completed.stderr!r}"
    )
    assert OUTPUT.is_file(), "Script did not create /home/user/critical_utc.log"
    assert stat.S_IMODE(OUTPUT.stat().st_mode) == 0o600
    assert OUTPUT.read_text(encoding="utf-8").splitlines() == expected_for(lines)


def test_script_processes_changed_inputs_and_empty_results():
    source_saved = snapshot(SOURCE)
    output_saved = snapshot(OUTPUT)
    try:
        run_case([
            "2024-01-01 00:05:07 [CRITICAL] New year rollover failure",
            "2024-07-15 23:59:59 [INFO] Routine heartbeat",
            "2024-07-16 08:01:02 [CRITICAL] Literal shell text: $HOME; * [x]",
            "2025-03-03 12:34:56 [ERROR] Ordinary error",
        ])
        run_case([
            "2026-05-10 10:20:30 [INFO] No critical events",
            "2026-05-10 10:21:30 [WARNING] Still healthy",
        ])
    finally:
        restore(SOURCE, source_saved)
        restore(OUTPUT, output_saved)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py /tmp/test_script_behavior.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
