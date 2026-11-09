#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import json
import os
import runpy
import secrets
import subprocess
import sys
import tempfile
import threading

HOME = "/home/user"
LOG_DIR = os.path.join(HOME, "logs")
FUZZER = os.path.join(HOME, "fuzzer.py")
AGGREGATOR = os.path.join(HOME, "log_aggregator.py")
SUMMARY = os.path.join(HOME, "summary.json")
RESOLUTION = os.path.join(HOME, "ticket_resolution.txt")
LEVELS = ("ERROR", "WARN", "INFO")


def check_source_lock():
    assert os.path.isfile(AGGREGATOR), f"Script {AGGREGATOR} is missing."
    with open(AGGREGATOR, "r", encoding="utf-8") as f:
        content = f.read()
    assert "Lock" in content, "No thread lock found in the fixed script."
    if "time.sleep" in content:
        assert "acquire" in content or "with " in content, \
            "Race condition doesn't seem to be mitigated (Lock not acquired)."


def inspect_logs():
    assert os.path.isdir(LOG_DIR), f"Logs directory {LOG_DIR} is missing."
    files = sorted(f for f in os.listdir(LOG_DIR) if f.endswith(".log"))
    assert len(files) == 50, f"Expected 50 log files in {LOG_DIR}, found {len(files)}."

    counts = {level: 0 for level in LEVELS}
    for name in files:
        path = os.path.join(LOG_DIR, name)
        assert os.path.isfile(path), f"{path} is not a regular file."
        with open(path, "r", encoding="utf-8") as f:
            lines = f.readlines()
        assert len(lines) == 1000, f"Expected 1000 lines in {name}, found {len(lines)}."
        for number, line in enumerate(lines, 1):
            text = line.rstrip("\r\n")
            level, separator, message = text.partition("|")
            assert separator and level in counts and message, \
                f"Invalid log format in {name} at line {number}: {text!r}"
            counts[level] += 1
    assert sum(counts.values()) == 50000
    return files, counts


def read_summary():
    assert os.path.isfile(SUMMARY), f"Summary file {SUMMARY} is missing."
    try:
        with open(SUMMARY, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"File {SUMMARY} is not valid JSON: {exc}")
    assert all(level in data for level in LEVELS), \
        "JSON must contain ERROR, WARN, and INFO keys."
    assert all(type(data[level]) is int for level in LEVELS), \
        "Summary counts must be integers."
    assert sum(data.values()) == 50000, \
        f"Expected 50000 total logs, got {sum(data.values())}."
    return data


def check_resolution(data):
    assert os.path.isfile(RESOLUTION), f"Resolution file {RESOLUTION} is missing."
    with open(RESOLUTION, "r", encoding="utf-8") as f:
        content = f.read().strip()
    assert content.isdigit(), f"Content of {RESOLUTION} is not a valid integer."
    assert int(content) == data["ERROR"], \
        f"Expected {data['ERROR']} in resolution, got {content}."


def clear_logs():
    for name in os.listdir(LOG_DIR):
        if name.endswith(".log"):
            path = os.path.join(LOG_DIR, name)
            if os.path.isdir(path) and not os.path.islink(path):
                raise AssertionError(f"Unexpected directory with .log suffix: {path}")
            os.unlink(path)


def run_aggregator(expected):
    # Run the submitted program while counting actual Thread.start calls. This
    # preserves the required one-thread-per-file architecture check.
    with tempfile.NamedTemporaryFile(delete=False) as trace:
        trace_path = trace.name
    runner = r'''
import runpy
import sys
import threading

count = 0
original_start = threading.Thread.start

def tracked_start(self, *args, **kwargs):
    global count
    count += 1
    return original_start(self, *args, **kwargs)

threading.Thread.start = tracked_start
runpy.run_path(sys.argv[1], run_name="__main__")
with open(sys.argv[2], "w", encoding="ascii") as f:
    f.write(str(count))
'''
    try:
        subprocess.run(
            [sys.executable, "-c", runner, AGGREGATOR, trace_path],
            cwd=HOME,
            check=True,
            timeout=30,
        )
        with open(trace_path, "r", encoding="ascii") as f:
            starts = int(f.read())
    finally:
        try:
            os.unlink(trace_path)
        except FileNotFoundError:
            pass
    assert starts == 50, \
        f"Expected one worker thread per log file (50 starts), observed {starts}."
    actual = read_summary()
    assert actual == expected, f"Aggregator produced {actual}; log contents require {expected}."


# Retain all original final-state checks, and additionally derive the expected
# counts from the actual submitted logs rather than trusting summary.json.
assert os.path.isfile(FUZZER), f"Fuzzer script {FUZZER} is missing."
check_source_lock()
initial_files, initial_expected = inspect_logs()
initial_summary = read_summary()
assert initial_summary == initial_expected, \
    f"Initial summary {initial_summary} does not match log contents {initial_expected}."
check_resolution(initial_summary)

# Preserve the valid submitted final state so behavioral probing is non-destructive.
initial_log_bytes = {}
for name in initial_files:
    with open(os.path.join(LOG_DIR, name), "rb") as f:
        initial_log_bytes[name] = f.read()
with open(SUMMARY, "rb") as f:
    initial_summary_bytes = f.read()

# Actually execute fuzzer.py from an empty log directory and validate every line.
clear_logs()
subprocess.run([sys.executable, FUZZER], cwd=HOME, check=True, timeout=30)
_, fuzz_counts = inspect_logs()
check_source_lock()
run_aggregator(fuzz_counts)

# Replace fuzzer output with verifier-generated, unpredictable valid inputs.
# Repeated executions must reproduce exact counts derived from those inputs.
clear_logs()
probe_counts = {level: 0 for level in LEVELS}
for file_number in range(50):
    path = os.path.join(LOG_DIR, f"probe_{file_number + 1}.log")
    with open(path, "w", encoding="utf-8") as f:
        for line_number in range(1000):
            level = LEVELS[secrets.randbelow(len(LEVELS))]
            probe_counts[level] += 1
            f.write(f"{level}|verifier-{file_number}-{line_number}-{secrets.token_hex(4)}\n")

for _ in range(4):
    check_source_lock()
    run_aggregator(probe_counts)

# Restore the agent's already-validated final artifacts.
clear_logs()
for name, content in initial_log_bytes.items():
    with open(os.path.join(LOG_DIR, name), "wb") as f:
        f.write(content)
with open(SUMMARY, "wb") as f:
    f.write(initial_summary_bytes)
check_resolution(read_summary())
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
