#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
from datetime import datetime, timedelta

import pytest

SCRIPT_PATH = "/home/user/capacity_monitor.py"
LOG_PATH = "/home/user/memory_capacity.log"


def test_script_exists_and_executable():
    """Verify the script exists and is executable."""
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_crontab_entry():
    """Verify the crontab contains the correct entry."""
    result = subprocess.run(['crontab', '-l'], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to read crontab. Ensure a crontab is set."

    crontab_content = result.stdout.strip().split('\n')
    found = False
    cron_regex = re.compile(r'^\s*\*\s+\*\s+\*\s+\*\s+\*\s+/usr/bin/python3\s+/home/user/capacity_monitor\.py\s*$')

    for line in crontab_content:
        if line.strip().startswith('#'):
            continue
        if cron_regex.match(line):
            found = True
            break

    assert found, "Crontab does not contain the correct entry for every minute using /usr/bin/python3."


def test_script_execution_and_log_format():
    """Execute the script manually and verify the log format."""
    result = subprocess.run(['/usr/bin/python3', SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"Script execution failed with output: {result.stderr}"

    assert os.path.exists(LOG_PATH), f"Log file {LOG_PATH} was not created."

    with open(LOG_PATH, 'r') as f:
        lines = f.readlines()

    assert len(lines) > 0, f"Log file {LOG_PATH} is empty."
    last_line = lines[-1].strip()
    log_regex = re.compile(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \| Used: \d+\.\d{2}%$')
    assert log_regex.match(last_line), f"Log entry format is incorrect. Got: '{last_line}'"


def test_error_handling_logic():
    """Retain the original source-level error handling assertions."""
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."

    with open(SCRIPT_PATH, 'r') as f:
        content = f.read()

    expected_error_msg = "ERROR: Cannot read meminfo"
    assert expected_error_msg in content, f"Script does not contain the expected error message: '{expected_error_msg}'"
    assert "try:" in content or "try " in content, "Script does not appear to use a try/except block for error handling."
    assert "except" in content, "Script does not appear to use a try/except block for error handling."


def run_with_meminfo(meminfo_data=None, fail_read=False):
    """Run the submitted artifact while controlling reads of /proc/meminfo."""
    old_log = b""
    if os.path.exists(LOG_PATH):
        with open(LOG_PATH, "rb") as f:
            old_log = f.read()

    with tempfile.TemporaryDirectory() as hook_dir:
        fixture_path = os.path.join(hook_dir, "meminfo_fixture")
        if meminfo_data is not None:
            with open(fixture_path, "wb") as f:
                f.write(meminfo_data.encode("ascii"))

        hook = f'''
import builtins
import io
import os

_real_builtin_open = builtins.open
_real_io_open = io.open
_real_os_open = os.open
_TARGET = "/proc/meminfo"
_FIXTURE = {fixture_path!r}
_FAIL = {fail_read!r}
_DATA = {meminfo_data!r}

def _is_target(path):
    try:
        value = os.fspath(path)
        if isinstance(value, bytes):
            value = os.fsdecode(value)
        return value == _TARGET
    except (TypeError, ValueError):
        return False

def _fake_open(path, mode="r", *args, **kwargs):
    if not _is_target(path):
        return _real_builtin_open(path, mode, *args, **kwargs)
    if _FAIL:
        raise OSError("simulated meminfo read failure")
    if "b" in mode:
        return io.BytesIO(_DATA.encode("ascii"))
    return io.StringIO(_DATA)

def _fake_io_open(path, mode="r", *args, **kwargs):
    if not _is_target(path):
        return _real_io_open(path, mode, *args, **kwargs)
    return _fake_open(path, mode, *args, **kwargs)

def _fake_os_open(path, flags, mode=0o777, *, dir_fd=None):
    if not _is_target(path):
        if dir_fd is None:
            return _real_os_open(path, flags, mode)
        return _real_os_open(path, flags, mode, dir_fd=dir_fd)
    if _FAIL:
        raise OSError("simulated meminfo read failure")
    return _real_os_open(_FIXTURE, flags, mode)

builtins.open = _fake_open
io.open = _fake_io_open
os.open = _fake_os_open
'''
        with open(os.path.join(hook_dir, "sitecustomize.py"), "w") as f:
            f.write(hook)

        env = os.environ.copy()
        env["PYTHONPATH"] = hook_dir
        before = datetime.now()
        result = subprocess.run(
            ['/usr/bin/python3', SCRIPT_PATH],
            capture_output=True,
            text=True,
            env=env,
        )
        after = datetime.now()

    assert result.returncode == 0, f"Script execution failed: {result.stderr}"
    assert os.path.exists(LOG_PATH), f"Log file {LOG_PATH} was not created."
    with open(LOG_PATH, "rb") as f:
        new_log = f.read()

    assert new_log.startswith(old_log), "The script did not append to the existing log."
    appended = new_log[len(old_log):].decode("utf-8")
    lines = appended.splitlines()
    assert len(lines) == 1, f"Expected exactly one appended log entry, got: {appended!r}"
    return lines[0], before, after


def assert_timestamp_is_current(line, before, after):
    timestamp = datetime.strptime(line[:19], "%Y-%m-%d %H:%M:%S")
    assert before - timedelta(seconds=1) <= timestamp <= after + timedelta(seconds=1), \
        f"Log timestamp is not the current local time: {line!r}"


def test_calculation_uses_memtotal_and_memavailable():
    """Exercise the artifact with unpredictable meminfo values and verify the formula."""
    total = secrets.randbelow(8_000_000) + 1_000_000
    available = secrets.randbelow(total - 1) + 1
    meminfo = (
        f"MemTotal:       {total} kB\n"
        f"MemFree:        12345 kB\n"
        f"MemAvailable:   {available} kB\n"
        f"Buffers:        6789 kB\n"
    )
    expected = ((total - available) / total) * 100
    line, before, after = run_with_meminfo(meminfo)
    assert line == f"{line[:19]} | Used: {expected:.2f}%", \
        f"Incorrect memory calculation or formatting. Got: {line!r}"
    assert_timestamp_is_current(line, before, after)


@pytest.mark.parametrize(
    "meminfo_data,fail_read",
    [
        (None, True),
        ("MemTotal: not-a-number kB\nMemAvailable: 100 kB\n", False),
    ],
)
def test_error_handling_is_exercised(meminfo_data, fail_read):
    """Verify both read and parse failures produce the required error entry."""
    line, before, after = run_with_meminfo(meminfo_data, fail_read=fail_read)
    assert line == f"{line[:19]} | ERROR: Cannot read meminfo", \
        f"Incorrect error log entry. Got: {line!r}"
    assert_timestamp_is_current(line, before, after)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
