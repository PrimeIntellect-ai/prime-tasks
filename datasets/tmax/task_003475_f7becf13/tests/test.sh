#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/verifier_hooks
cat <<'HOOK_EOF' > /tmp/verifier_hooks/sitecustomize.py
import json
import os

_trace_path = os.environ.get("ORGANIZER_RENAME_TRACE")
_original_rename = os.rename
_original_replace = os.replace

def _record_and_call(operation, original, src, dst, *args, **kwargs):
    if _trace_path:
        try:
            src_path = os.fspath(src)
            dst_path = os.fspath(dst)
            record = {
                "operation": operation,
                "src": os.path.abspath(src_path),
                "dst": os.path.abspath(dst_path),
                "src_exists": os.path.isfile(src_path),
                "src_size": os.path.getsize(src_path) if os.path.isfile(src_path) else None,
            }
            with open(_trace_path, "a", encoding="utf-8") as trace:
                trace.write(json.dumps(record) + "\n")
        except Exception:
            pass
    return original(src, dst, *args, **kwargs)

def traced_rename(src, dst, *args, **kwargs):
    return _record_and_call("rename", _original_rename, src, dst, *args, **kwargs)

def traced_replace(src, dst, *args, **kwargs):
    return _record_and_call("replace", _original_replace, src, dst, *args, **kwargs)

os.rename = traced_rename
os.replace = traced_replace
HOOK_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
import uuid

SCRIPT = "/home/user/organizer.py"
RULES = "/home/user/rules.json"
INCOMING = "/home/user/incoming"
PROCESSED = "/home/user/processed"
TRACE = "/tmp/organizer_rename_trace.jsonl"


def wait_for(predicate, description, process=None, timeout=9):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return
        if process is not None and process.poll() is not None:
            raise AssertionError(f"organizer.py exited early with status {process.returncode} while waiting for {description}")
        time.sleep(0.15)
    raise AssertionError(f"Timed out waiting for {description}")


def read_rows(path):
    with open(path, "r", newline="", encoding="utf-8") as handle:
        return [row for row in csv.reader(handle) if row]


def stop_existing_organizers():
    own_pid = os.getpid()
    victims = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == own_pid:
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as handle:
                args = [part.decode(errors="ignore") for part in handle.read().split(b"\0") if part]
            if SCRIPT in args:
                os.kill(int(entry), signal.SIGTERM)
                victims.append(int(entry))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    time.sleep(0.3)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def assert_atomic_renames(final_paths):
    assert os.path.exists(TRACE), "No actual rename operations were observed while organizer.py ran."
    records = []
    with open(TRACE, "r", encoding="utf-8") as handle:
        for line in handle:
            if line.strip():
                records.append(json.loads(line))

    for final_path in final_paths:
        final_path = os.path.abspath(final_path)
        matching = [record for record in records if record.get("dst") == final_path]
        assert matching, f"No actual os.rename/os.replace operation created {final_path}."
        assert any(
            record.get("src_exists")
            and record.get("src") != final_path
            and os.path.dirname(record.get("src", "")) == os.path.dirname(final_path)
            for record in matching
        ), f"{final_path} was not atomically renamed from an existing temporary file in the output directory."


def test_organizer_end_to_end():
    # Preserve the original existence assertions before the verifier creates fixtures.
    assert os.path.exists(SCRIPT), "The script /home/user/organizer.py does not exist."
    assert os.path.isfile(SCRIPT), "/home/user/organizer.py is not a regular file."
    assert os.path.exists(RULES), "The configuration /home/user/rules.json does not exist."

    # Preserve the original source assertions, while behavioral checks below ensure
    # these operations are genuinely executed rather than merely mentioned.
    with open(SCRIPT, "r", encoding="utf-8") as handle:
        code = handle.read()
    has_temp = bool(re.search(r'(\.tmp|NamedTemporaryFile|temp)', code, re.IGNORECASE))
    assert has_temp, "No temporary file usage detected in organizer.py for atomic writes."
    has_rename = bool(re.search(r'(os\.rename|shutil\.move|os\.replace|Path\.rename)', code))
    assert has_rename, "No atomic rename (e.g., os.rename, shutil.move, os.replace) detected in organizer.py."

    stop_existing_organizers()
    os.makedirs(INCOMING, exist_ok=True)
    os.makedirs(PROCESSED, exist_ok=True)
    for directory in (INCOMING, PROCESSED):
        for name in os.listdir(directory):
            path = os.path.join(directory, name)
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)
    if os.path.exists(TRACE):
        os.unlink(TRACE)

    with open(RULES, "w", encoding="utf-8") as handle:
        json.dump({"output_dir": PROCESSED, "json_extract_keys": ["id", "status"]}, handle)

    token = uuid.uuid4().hex[:10]
    startup_name = f"startup_{token}.json"
    startup_input = os.path.join(INCOMING, startup_name)
    startup_output = os.path.join(PROCESSED, startup_name + ".processed.csv")
    startup_status = f"queued,{token}"
    with open(startup_input, "w", encoding="utf-8") as handle:
        json.dump([{"id": 731, "status": startup_status, "ignored": "do-not-copy"}], handle)

    env = os.environ.copy()
    env["PYTHONPATH"] = "/tmp/verifier_hooks" + (":" + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    env["ORGANIZER_RENAME_TRACE"] = TRACE
    process = subprocess.Popen(
        [sys.executable, SCRIPT],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    changed_dir = f"/home/user/processed_changed_{token}"
    try:
        # This file existed before startup, proving startup processing.
        wait_for(lambda: os.path.exists(startup_output) and not os.path.exists(startup_input), "startup file processing", process)
        assert read_rows(startup_output) == [["id", "status"], ["731", startup_status]]

        # Recreate the exact fixtures used by the original verifier after the daemon
        # is running, proving continuous watching rather than a precomputed result.
        test1_input = os.path.join(INCOMING, "test1.json")
        test1_output = os.path.join(PROCESSED, "test1.json.processed.csv")
        with open(test1_input, "w", encoding="utf-8") as handle:
            handle.write('[{"id": 1, "status": "active", "secret": "hide_me"}, {"id": 2, "status": "inactive", "secret": "hide_me"}]')
        wait_for(lambda: os.path.exists(test1_output) and not os.path.exists(test1_input), "test1.json processing", process)

        test2_input = os.path.join(INCOMING, "test2.log")
        test2_output = os.path.join(PROCESSED, "test2.log.processed.csv")
        with open(test2_input, "w", encoding="utf-8") as handle:
            handle.write("[2023-10-01 10:00:00] ERROR\nDatabase connection failed.\nRetrying in 5 seconds.\n===\n[2023-10-01 10:00:05] INFO\nConnection established.\n===\n")
        wait_for(lambda: os.path.exists(test2_output) and not os.path.exists(test2_input), "test2.log processing", process)

        # Preserve all original final-state assertions.
        assert not os.path.exists(test1_input), "The file test1.json was not deleted from /home/user/incoming/."
        assert not os.path.exists(test2_input), "The file test2.log was not deleted from /home/user/incoming/."
        assert os.path.exists(test1_output), f"Output file {test1_output} is missing."
        rows = read_rows(test1_output)
        assert len(rows) >= 3, "JSON CSV output does not have the expected number of rows."
        assert rows[0] == ["id", "status"], f"Expected headers ['id', 'status'], got {rows[0]}"
        assert rows[1] == ["1", "active"], f"Expected row 1 ['1', 'active'], got {rows[1]}"
        assert rows[2] == ["2", "inactive"], f"Expected row 2 ['2', 'inactive'], got {rows[2]}"
        assert os.path.exists(test2_output), f"Output file {test2_output} is missing."
        rows = read_rows(test2_output)
        assert len(rows) >= 3, "Log CSV output does not have the expected number of rows."
        assert rows[0] == ["timestamp", "level", "message"], f"Expected log headers, got {rows[0]}"
        assert rows[1] == ["2023-10-01 10:00:00", "ERROR", "Database connection failed. Retrying in 5 seconds."], f"Expected row 1 to match log entry 1, got {rows[1]}"
        assert rows[2] == ["2023-10-01 10:00:05", "INFO", "Connection established."], f"Expected row 2 to match log entry 2, got {rows[2]}"

        # Change rules while the daemon is active and use unpredictable content.
        os.makedirs(changed_dir, exist_ok=True)
        with open(RULES, "w", encoding="utf-8") as handle:
            json.dump({"output_dir": changed_dir, "json_extract_keys": ["id", "status"]}, handle)
        changed_name = f"changed_{token}.json"
        changed_input = os.path.join(INCOMING, changed_name)
        changed_output = os.path.join(changed_dir, changed_name + ".processed.csv")
        changed_status = f"live-{token}"
        with open(changed_input, "w", encoding="utf-8") as handle:
            json.dump([{"secret": token, "status": changed_status, "id": 9842}], handle)
        wait_for(lambda: os.path.exists(changed_output) and not os.path.exists(changed_input), "processing after configuration change", process)
        assert read_rows(changed_output) == [["id", "status"], ["9842", changed_status]]

        assert_atomic_renames([startup_output, test1_output, test2_output, changed_output])
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=2)
        shutil.rmtree(changed_dir, ignore_errors=True)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
