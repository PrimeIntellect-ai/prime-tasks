#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import json
import os
import re
import shutil
import subprocess
import time
import uuid


def test_01_critical_archive_contents():
    archive_path = "/home/user/critical_archive.txt"
    assert os.path.isfile(archive_path), f"Output file {archive_path} does not exist."

    with open(archive_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "CRITICAL [REDACTED] Disk full",
        "CRITICAL [REDACTED] Memory out of bounds"
    ]

    assert len(lines) == 2, f"Expected exactly 2 lines in {archive_path}, but found {len(lines)}. Contents: {lines}"

    for expected in expected_lines:
        assert expected in lines, f"Expected line '{expected}' not found in {archive_path}. Contents: {lines}"


def test_02_last_run_stamp_updated():
    stamp_path = "/home/user/last_run.stamp"
    assert os.path.isfile(stamp_path), f"File {stamp_path} does not exist."

    with open(stamp_path, "r") as f:
        content = f.read().strip()

    try:
        new_stamp = float(content)
    except ValueError:
        raise AssertionError(f"Content of {stamp_path} is not a valid float: '{content}'")

    assert new_stamp > 1700000000.0, f"Expected {stamp_path} to be updated to a timestamp > 1700000000.0, but got {new_stamp}"


def test_03_script_behavior_on_fresh_dynamic_backlog():
    script_path = "/home/user/process_backups.py"
    drop_path = "/home/user/backup_drop"
    archive_path = "/home/user/critical_archive.txt"
    stamp_path = "/home/user/last_run.stamp"

    assert os.path.isfile(script_path), f"Required script {script_path} does not exist or is not a regular file."
    with open(script_path, "rb") as f:
        source = f.read()
    assert source.strip(), f"Required script {script_path} is empty."

    shutil.rmtree(drop_path, ignore_errors=True)
    os.makedirs(drop_path)

    baseline = 1700000000.0
    with open(stamp_path, "w") as f:
        f.write(str(baseline))

    seed_line = "PREEXISTING archive marker"
    with open(archive_path, "w") as f:
        f.write(seed_line + "\n")

    token_gz = "gzip-" + uuid.uuid4().hex
    token_plain = "plain-" + uuid.uuid4().hex
    token_bad = "invalid-" + uuid.uuid4().hex
    token_old = "old-" + uuid.uuid4().hex
    token_equal = "equal-" + uuid.uuid4().hex

    # Extension is intentionally misleading: this is genuinely gzip data.
    gzip_file = os.path.join(drop_path, "compressed_as_text.txt")
    with gzip.open(gzip_file, "wt") as f:
        f.write("INFO 10.1.1.1 ignored\n")
        f.write(f"CRITICAL 203.0.113.17 {token_gz}\n")

    # This .gz file is actually a valid plain log, identified by its '--' header.
    plain_file = os.path.join(drop_path, "plain_as_gzip.gz")
    with open(plain_file, "w") as f:
        f.write("-- APP LOG --\n")
        f.write(f"CRITICAL {token_plain} 198.51.100.9 and 192.0.2.44\n")
        f.write("WARN 10.0.0.2 ignored\n")

    invalid_file = os.path.join(drop_path, "invalid_header.gz")
    with open(invalid_file, "w") as f:
        f.write(f"XX CRITICAL 1.2.3.4 {token_bad}\n")

    old_file = os.path.join(drop_path, "old_but_valid.txt")
    with open(old_file, "w") as f:
        f.write("-- OLD LOG --\n")
        f.write(f"CRITICAL 8.8.8.8 {token_old}\n")

    equal_file = os.path.join(drop_path, "equal_mtime.txt")
    with open(equal_file, "w") as f:
        f.write("-- EQUAL LOG --\n")
        f.write(f"CRITICAL 9.9.9.9 {token_equal}\n")

    os.utime(gzip_file, (1750000010, 1750000010))
    os.utime(plain_file, (1750000020, 1750000020))
    os.utime(invalid_file, (1750000030, 1750000030))
    os.utime(old_file, (1600000000, 1600000000))
    os.utime(equal_file, (baseline, baseline))

    hook_dir = "/tmp/process_backups_hook_" + uuid.uuid4().hex
    os.makedirs(hook_dir)
    trace_path = os.path.join(hook_dir, "subprocess.jsonl")
    sitecustomize = r'''
import json
import os
import subprocess

_real_popen = subprocess.Popen
_trace = os.environ.get("PROCESS_BACKUPS_SUBPROCESS_TRACE")

def _logged_popen(*args, **kwargs):
    if args:
        command = args[0]
    else:
        command = kwargs.get("args")
    try:
        with open(_trace, "a") as log:
            json.dump({"command": command, "shell": bool(kwargs.get("shell", False))}, log, default=repr)
            log.write("\\n")
    except Exception:
        pass
    return _real_popen(*args, **kwargs)

subprocess.Popen = _logged_popen
'''
    with open(os.path.join(hook_dir, "sitecustomize.py"), "w") as f:
        f.write(sitecustomize)

    env = os.environ.copy()
    env["PYTHONPATH"] = hook_dir + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    env["PROCESS_BACKUPS_SUBPROCESS_TRACE"] = trace_path

    before_run = time.time()
    result = subprocess.run(
        ["python3", script_path],
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    after_run = time.time()
    assert result.returncode == 0, (
        f"Running {script_path} on a fresh backlog failed with status {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )

    with open(archive_path, "r") as f:
        actual = [line.strip() for line in f if line.strip()]

    expected = [
        seed_line,
        f"CRITICAL [REDACTED] {token_gz}",
        f"CRITICAL {token_plain} [REDACTED] and [REDACTED]",
    ]
    assert sorted(actual) == sorted(expected), (
        "Fresh dynamic backlog was not filtered, redacted, skipped, and appended correctly. "
        f"Expected {expected}, got {actual}"
    )

    with open(stamp_path, "r") as f:
        updated_text = f.read().strip()
    try:
        updated_stamp = float(updated_text)
    except ValueError:
        raise AssertionError(f"Updated stamp is not numeric: {updated_text!r}")
    assert updated_stamp > baseline, "The script did not advance last_run.stamp."
    assert before_run - 2 <= updated_stamp <= after_run + 2, (
        f"Stamp {updated_stamp} is not the current system time for this execution."
    )

    assert os.path.isfile(trace_path), "No subprocess invocation was observed while processing valid files."
    with open(trace_path, "r") as f:
        records = [json.loads(line) for line in f if line.strip()]
    rendered_commands = "\n".join(repr(record.get("command")) for record in records)

    def command_was_invoked(name):
        pattern = rf"(?<![A-Za-z0-9_])(?:/[A-Za-z0-9_.-]+)*/*{re.escape(name)}(?![A-Za-z0-9_])"
        return re.search(pattern, rendered_commands) is not None

    for required_command in ("zcat", "cat", "awk", "sed"):
        assert command_was_invoked(required_command), (
            f"Required subprocess pipeline command {required_command!r} was not observed. "
            f"Observed subprocess commands: {rendered_commands}"
        )

    # A second run must not reprocess files whose mtimes are no longer newer than the state stamp.
    first_archive = open(archive_path, "rb").read()
    second = subprocess.run(
        ["python3", script_path],
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert second.returncode == 0, (
        f"Second execution failed with status {second.returncode}. "
        f"stdout={second.stdout!r}, stderr={second.stderr!r}"
    )
    second_archive = open(archive_path, "rb").read()
    assert second_archive == first_archive, "Files were reprocessed on a subsequent run despite the updated stamp."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
