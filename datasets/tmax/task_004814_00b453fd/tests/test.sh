#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import re
import subprocess
import tempfile
from zoneinfo import ZoneInfo

BASE = "/home/user/capacity"
TRACKER_SOURCE = f"{BASE}/tracker.c"
TRACKER = f"{BASE}/tracker"
LOG_FILE = f"{BASE}/logs/resource.log"

LINE_RE = re.compile(
    r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) HST\] LOAD: (\d+\.\d+)$"
)


def current_load_token():
    with open("/proc/loadavg", "r", encoding="utf-8") as f:
        return f.read().split()[0]


def assert_tracker_invocation(executable):
    env = os.environ.copy()
    env["TZ"] = "Pacific/Honolulu"

    with tempfile.TemporaryDirectory() as td:
        output = os.path.join(td, "tracker.log")
        seed = "existing log content"
        with open(output, "w", encoding="utf-8") as f:
            f.write(seed + "\n")

        before_load = current_load_token()
        before_time = datetime.datetime.now(datetime.timezone.utc)
        result = subprocess.run(
            [executable, output], env=env, capture_output=True, text=True, timeout=10
        )
        after_time = datetime.datetime.now(datetime.timezone.utc)
        after_load = current_load_token()

        assert result.returncode == 0, (
            f"{executable} failed with one argument: {result.stderr}"
        )
        with open(output, "r", encoding="utf-8") as f:
            lines = f.read().splitlines()
        assert lines[0] == seed, "Tracker did not preserve existing log contents."
        assert len(lines) == 2, "Tracker must append exactly one line per invocation."

        match = LINE_RE.fullmatch(lines[1])
        assert match, f"Tracker produced an invalid line: {lines[1]!r}"
        emitted_load = match.group(2)
        assert emitted_load in {before_load, after_load}, (
            f"Tracker emitted load {emitted_load}, but /proc/loadavg reported "
            f"{before_load} immediately before and {after_load} immediately after execution."
        )

        emitted_time = datetime.datetime.strptime(
            match.group(1), "%Y-%m-%d %H:%M:%S"
        ).replace(tzinfo=ZoneInfo("Pacific/Honolulu")).astimezone(datetime.timezone.utc)
        assert before_time - datetime.timedelta(seconds=2) <= emitted_time <= after_time + datetime.timedelta(seconds=2), (
            "Tracker timestamp is not the current Pacific/Honolulu local time."
        )


def test_directories_and_symlink():
    archive_dir = f"{BASE}/logs/archive"
    symlink_path = f"{BASE}/active_logs"
    target_dir = f"{BASE}/logs"

    assert os.path.isdir(archive_dir), f"Directory {archive_dir} does not exist."
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink."
    target = os.readlink(symlink_path)
    assert target == target_dir, (
        f"Symlink {symlink_path} points to {target}, expected {target_dir}."
    )


def test_c_program_exists_and_executable():
    assert os.path.isfile(TRACKER_SOURCE), f"Source file {TRACKER_SOURCE} does not exist."
    assert os.path.isfile(TRACKER), f"Executable {TRACKER} does not exist."
    assert os.access(TRACKER, os.X_OK), f"File {TRACKER} is not executable."

    with open(TRACKER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "tracker is not a compiled ELF executable."

    with open(TRACKER_SOURCE, "r", encoding="utf-8") as f:
        source = f.read()
    assert "/proc/loadavg" in source, "tracker.c does not read /proc/loadavg."
    assert "%Z" in source, "tracker.c does not use the required strftime %Z specifier."

    rebuilt = "/tmp/tracker_rebuilt"
    result = subprocess.run(
        ["gcc", TRACKER_SOURCE, "-o", rebuilt], capture_output=True, text=True, timeout=20
    )
    assert result.returncode == 0, f"tracker.c does not compile with gcc: {result.stderr}"
    assert_tracker_invocation(rebuilt)


def test_tracker_argument_handling_and_behavior():
    with tempfile.TemporaryDirectory() as td:
        unexpected = os.path.join(td, "unexpected.log")
        no_arg = subprocess.run([TRACKER], capture_output=True, text=True, timeout=10)
        assert no_arg.returncode != 0, "Tracker must reject invocation with no arguments."

        two_args = subprocess.run(
            [TRACKER, unexpected, os.path.join(td, "extra")],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert two_args.returncode != 0, "Tracker must reject invocation with two arguments."
        assert not os.path.exists(unexpected), (
            "Tracker wrote output despite receiving the wrong number of arguments."
        )

    assert_tracker_invocation(TRACKER)


def test_log_output_and_format():
    assert os.path.isfile(LOG_FILE), f"Log file {LOG_FILE} does not exist. Did you run the tracker?"
    with open(LOG_FILE, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()

    assert len(lines) == 1, "resource.log must contain exactly one tracker execution line."
    assert LINE_RE.fullmatch(lines[0]), f"Log line {lines[0]!r} does not match expected format."


def test_rotate_script_and_execution():
    script_path = f"{BASE}/rotate.sh"
    rotated_file = f"{BASE}/logs/archive/resource_rotated.log"

    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    result = subprocess.run([script_path], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"Script {script_path} failed to execute properly."
    assert not os.path.isfile(LOG_FILE), f"Log file {LOG_FILE} still exists after running rotate.sh."
    assert os.path.isfile(rotated_file), f"Rotated log file {rotated_file} does not exist after running rotate.sh."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
