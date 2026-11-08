#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/verifier_hooks
cat << 'HOOK_EOF' > /tmp/verifier_hooks/sitecustomize.py
import os

_trace = os.environ.get("ARCHIVE_LOCK_TRACE")
if _trace:
    try:
        import fcntl

        def _wrap_lock(name):
            original = getattr(fcntl, name)
            def wrapped(*args, **kwargs):
                result = original(*args, **kwargs)
                try:
                    fd = os.open(_trace, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o666)
                    try:
                        os.write(fd, (str(os.getpid()) + " " + name + "\n").encode("ascii"))
                    finally:
                        os.close(fd)
                except Exception:
                    pass
                return result
            setattr(fcntl, name, wrapped)

        _wrap_lock("flock")
        _wrap_lock("lockf")
    except Exception:
        pass
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import glob
import gzip
import os
import shutil
import subprocess
import sys
import uuid

import pytest

RAW_LOGS = "/home/user/backup_data/raw_logs"
OUTPUT = "/home/user/critical_events.txt"
SCRIPT = "/home/user/archive_processor.py"


def test_script_processes_real_gzip_inputs_concurrently_and_renames_only_on_success():
    assert os.path.isfile(SCRIPT), f"Script file {SCRIPT} does not exist."

    backup_dir = os.path.join(
        "/home/user/backup_data", ".raw_logs_verifier_backup_" + uuid.uuid4().hex
    )
    output_existed = os.path.exists(OUTPUT)
    output_data = None
    if output_existed:
        with open(OUTPUT, "rb") as f:
            output_data = f.read()

    os.rename(RAW_LOGS, backup_dir)
    os.mkdir(RAW_LOGS)
    trace_file = "/tmp/archive_lock_trace_" + uuid.uuid4().hex

    try:
        expected = []
        # Enough independent files and work are supplied to ensure that a real
        # process pool distributes work among multiple worker processes.
        for i in range(32):
            path = os.path.join(RAW_LOGS, f"probe_{i:02d}.log.gz")
            lines = [
                f"probe {i:02d} info record {j:04d}\n" for j in range(1000)
            ]
            critical = [
                f"probe {i:02d} event A [CRITICAL] derived-{i:02d}-alpha\n",
                f"probe {i:02d} [CRITICAL] derived-{i:02d}-beta\n",
                f"probe {i:02d} event C [CRITICAL] derived-{i:02d}-gamma\n",
            ]
            lines[137:137] = critical[:1]
            lines[613:613] = critical[1:]
            expected.extend(critical)
            with gzip.open(path, "wt", encoding="utf-8", newline="") as f:
                f.writelines(lines)

        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        if os.path.exists(trace_file):
            os.remove(trace_file)

        env = os.environ.copy()
        env["PYTHONPATH"] = "/tmp/verifier_hooks" + (
            os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else ""
        )
        env["ARCHIVE_LOCK_TRACE"] = trace_file

        completed = subprocess.run(
            [sys.executable, SCRIPT],
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=90,
        )
        assert completed.returncode == 0, (
            "archive_processor.py failed on valid gzip inputs:\n"
            + completed.stdout + completed.stderr
        )

        assert os.path.isfile(OUTPUT), "The executed script did not create critical_events.txt."
        with open(OUTPUT, "r", encoding="utf-8", newline="") as f:
            actual = f.readlines()
        assert collections.Counter(actual) == collections.Counter(expected), (
            "critical_events.txt does not exactly contain the critical lines "
            "derived from the verifier's gzip inputs."
        )
        assert len(actual) == len(expected)
        assert not glob.glob(os.path.join(RAW_LOGS, "*.log.gz"))
        assert len(glob.glob(os.path.join(RAW_LOGS, "*.archived.gz"))) == 32

        assert os.path.exists(trace_file), "No actual fcntl locking operation was observed."
        with open(trace_file, "r", encoding="ascii") as f:
            locking_pids = {
                int(line.split()[0]) for line in f if line.strip()
            }
        assert len(locking_pids) >= 2, (
            "File locking was not exercised by multiple worker processes; "
            f"observed locking PIDs: {sorted(locking_pids)}"
        )

        # A parse failure must not be marked as successfully archived.
        bad_log = os.path.join(RAW_LOGS, "broken_probe.log.gz")
        with open(bad_log, "wb") as f:
            f.write(b"this is not a gzip stream")
        subprocess.run(
            [sys.executable, SCRIPT],
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=90,
        )
        assert os.path.exists(bad_log), "A gzip file that failed parsing was renamed."
        assert not os.path.exists(os.path.join(RAW_LOGS, "broken_probe.archived.gz"))
    finally:
        shutil.rmtree(RAW_LOGS, ignore_errors=True)
        os.rename(backup_dir, RAW_LOGS)
        if output_existed:
            with open(OUTPUT, "wb") as f:
                f.write(output_data)
        elif os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        try:
            os.remove(trace_file)
        except FileNotFoundError:
            pass


def test_critical_events_file():
    """Verify the critical events output file exists and has the correct content."""
    output_file = "/home/user/critical_events.txt"
    assert os.path.exists(output_file), f"Output file {output_file} does not exist."

    with open(output_file, "r") as f:
        lines = f.readlines()

    assert len(lines) == 60, f"Expected 60 critical event lines, but found {len(lines)}."

    for i, line in enumerate(lines):
        assert "[CRITICAL]" in line, f"Line {i+1} does not contain '[CRITICAL]': {line.strip()}"


def test_archived_files():
    """Verify all 20 log files have been renamed to .archived.gz."""
    raw_logs_dir = "/home/user/backup_data/raw_logs/"
    archived_files = glob.glob(os.path.join(raw_logs_dir, "*.archived.gz"))
    assert len(archived_files) == 20, f"Expected 20 .archived.gz files, found {len(archived_files)}."


def test_no_log_gz_files():
    """Verify no .log.gz files remain in the raw logs directory."""
    raw_logs_dir = "/home/user/backup_data/raw_logs/"
    log_files = glob.glob(os.path.join(raw_logs_dir, "*.log.gz"))
    assert len(log_files) == 0, f"Found {len(log_files)} .log.gz files remaining, expected 0."


def test_script_requirements():
    """Verify the script exists and uses concurrency and fcntl."""
    script_file = "/home/user/archive_processor.py"
    assert os.path.exists(script_file), f"Script file {script_file} does not exist."

    with open(script_file, "r") as f:
        content = f.read()

    assert "fcntl" in content, "The script does not appear to use 'fcntl' for file locking."

    has_concurrency = "multiprocessing" in content or "concurrent.futures" in content
    assert has_concurrency, "The script does not appear to use 'multiprocessing' or 'concurrent.futures'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
