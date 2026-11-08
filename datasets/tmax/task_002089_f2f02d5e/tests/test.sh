#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import math
import os
import re
import signal
import statistics
import subprocess
import tempfile
import time

import pytest

PIPELINE_DIR = "/home/user/pipeline"
DATA_FILE = os.path.join(PIPELINE_DIR, "data.txt")
WORKER_SCRIPT = os.path.join(PIPELINE_DIR, "worker.sh")
RESULT_FILE = os.path.join(PIPELINE_DIR, "result.txt")
STRACE_FILE = os.path.join(PIPELINE_DIR, "worker.strace")
TIMELINE_FILE = os.path.join(PIPELINE_DIR, "timeline.log")
METRICS_FILE = os.path.join(PIPELINE_DIR, "metrics.log")
SERVER_SCRIPT = os.path.join(PIPELINE_DIR, "metrics_server.sh")
TS_RE = re.compile(r"(?:^|\s)(\d{2}):(\d{2}):(\d{2})\.(\d+)")


def read_lines(path):
    with open(path, "r", errors="replace") as f:
        return [line.rstrip("\n") for line in f if line.rstrip("\n")]


def timestamp(line):
    match = TS_RE.search(line)
    assert match, f"Log line has no -tt-style timestamp: {line!r}"
    fraction = (match.group(4) + "000000000")[:9]
    return tuple(map(int, match.group(1, 2, 3))) + (int(fraction),)


def read_float_result():
    with open(RESULT_FILE, "r") as f:
        content = f.read().strip()
    try:
        value = float(content)
    except ValueError:
        pytest.fail(f"Content of {RESULT_FILE} is not a valid float: {content}")
    assert math.isfinite(value), f"Result is not finite: {content}"
    return value


def test_result_file_correct():
    assert os.path.isfile(RESULT_FILE), f"File {RESULT_FILE} does not exist."
    val = read_float_result()

    with open(DATA_FILE) as f:
        values = [float(line) for line in f if line.strip()]
    expected = statistics.pstdev(values)

    # Preserve the original assertion and also derive the answer from data.txt.
    assert round(val, 3) == 0.001, f"Expected standard deviation around 0.001, but got {val}"
    assert round(val, 3) == round(expected, 3), (
        f"Expected population standard deviation {expected}, but got {val}"
    )


def test_worker_strace_exists_and_is_genuine_trace():
    assert os.path.isfile(STRACE_FILE), f"File {STRACE_FILE} does not exist. Did you run strace?"
    assert os.path.getsize(STRACE_FILE) > 0, f"File {STRACE_FILE} is empty."

    lines = read_lines(STRACE_FILE)
    timestamped = [line for line in lines if TS_RE.search(line)]
    syscall_lines = [
        line for line in timestamped
        if re.search(r"\b[A-Za-z_][A-Za-z0-9_]*\(.*\)\s+=", line)
    ]
    assert len(syscall_lines) >= 10, "worker.strace is not a substantive strace -tt trace"
    assert any("execve(" in line and "worker.sh" in line for line in lines), (
        "worker.strace does not show worker.sh being executed"
    )
    assert any("fatal" in line.lower() for line in lines), (
        "worker.strace does not contain the traced awk fatal error"
    )


def test_timeline_log_exists_and_content():
    assert os.path.isfile(TIMELINE_FILE), f"File {TIMELINE_FILE} does not exist."
    lines = read_lines(TIMELINE_FILE)
    assert len(lines) > 0, f"File {TIMELINE_FILE} is empty."

    # Preserve the original content assertion.
    has_processed = any("processed" in line for line in lines)
    has_fatal = any("fatal" in line.lower() for line in lines)
    assert has_processed or has_fatal, (
        "timeline.log does not seem to contain expected merged content from metrics.log and worker.strace."
    )

    assert os.path.isfile(METRICS_FILE), "metrics.log is missing"
    metric_lines = read_lines(METRICS_FILE)
    trace_lines = read_lines(STRACE_FILE)
    fatal_trace_lines = [line for line in trace_lines if "fatal" in line.lower()]

    assert fatal_trace_lines, "The source trace contains no fatal entry"
    assert has_processed and has_fatal, (
        "timeline.log must contain both metric progress and traced fatal entries"
    )

    metric_counts = collections.Counter(metric_lines)
    fatal_counts = collections.Counter(fatal_trace_lines)
    seen_processed = set()
    seen_fatal = []

    for line in lines:
        if metric_counts[line] > 0:
            metric_counts[line] -= 1
            match = re.search(r"\bprocessed\s+(\d+)\b", line)
            if match:
                seen_processed.add(int(match.group(1)))
        elif fatal_counts[line] > 0:
            fatal_counts[line] -= 1
            seen_fatal.append(line)
        else:
            pytest.fail(f"Timeline entry is not present in metrics.log or a fatal worker.strace line: {line!r}")

    assert {1, 2, 3, 4, 5}.issubset(seen_processed), (
        "timeline.log does not contain the five worker progress events"
    )
    assert collections.Counter(seen_fatal) == collections.Counter(fatal_trace_lines), (
        "timeline.log does not contain all fatal entries from worker.strace"
    )

    times = [timestamp(line) for line in lines]
    assert times == sorted(times), "timeline.log entries are not chronologically sorted"


def test_worker_script_modified():
    assert os.path.isfile(WORKER_SCRIPT), f"File {WORKER_SCRIPT} does not exist."
    with open(WORKER_SCRIPT, "r") as f:
        content = f.read()
    assert os.access(WORKER_SCRIPT, os.X_OK), f"File {WORKER_SCRIPT} is not executable."
    assert re.search(r"\b(?:g?awk)\b", content), (
        "worker.sh must compute the stable variance directly in awk"
    )
    assert not re.search(
        r"\$?sum_x2\s*-\s*\(\s*\$?sum_x\s*\*\s*\$?sum_x", content
    ), "The buggy sum(x^2) - sum(x)^2 variance expression is still present"


def kill_old_servers():
    me = os.getpid()
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == me:
            continue
        try:
            with open(f"/proc/{name}/cmdline", "rb") as f:
                cmd = f.read().replace(b"\0", b" ").decode(errors="ignore")
            if SERVER_SCRIPT in cmd or ("nc -l" in cmd and "9090" in cmd):
                os.kill(int(name), signal.SIGKILL)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    time.sleep(0.15)


def run_worker_case(values):
    kill_old_servers()
    server = subprocess.Popen(
        [SERVER_SCRIPT], cwd=PIPELINE_DIR,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    trace_fd, trace_path = tempfile.mkstemp(prefix="verify-worker-", suffix=".strace")
    os.close(trace_fd)
    try:
        time.sleep(0.35)
        with open(DATA_FILE, "w") as f:
            f.write("\n".join(format(value, ".12f") for value in values) + "\n")

        completed = subprocess.run(
            ["strace", "-f", "-tt", "-o", trace_path, WORKER_SCRIPT],
            cwd=PIPELINE_DIR, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=20,
        )
        assert completed.returncode == 0, (
            f"Modified worker failed when executed: {completed.stderr}"
        )
        got = read_float_result()
        expected = statistics.pstdev(values)
        assert round(got, 3) == round(expected, 3) and abs(got - expected) < 0.00055, (
            f"Worker produced {got}; expected population standard deviation {expected}"
        )

        time.sleep(0.25)
        metrics = read_lines(METRICS_FILE) if os.path.isfile(METRICS_FILE) else []
        progress = {
            int(match.group(1))
            for line in metrics
            for match in [re.search(r"\bprocessed\s+(\d+)\b", line)]
            if match
        }
        assert set(range(1, len(values) + 1)).issubset(progress), (
            "Executed worker did not send all progress events to metrics_server.sh"
        )

        trace = "\n".join(read_lines(trace_path))
        assert "execve(" in trace and "worker.sh" in trace
        assert "connect(" in trace and re.search(r"(?:htons\()?9090", trace), (
            "Executed worker trace does not show a connection to port 9090"
        )
    finally:
        try:
            os.killpg(server.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            server.wait(timeout=2)
        except subprocess.TimeoutExpired:
            pass
        try:
            os.unlink(trace_path)
        except FileNotFoundError:
            pass
        kill_old_servers()


def test_worker_executes_stable_algorithm_and_sends_metrics():
    backups = {}
    for path in (DATA_FILE, RESULT_FILE, METRICS_FILE):
        if os.path.exists(path):
            with open(path, "rb") as f:
                backups[path] = f.read()
        else:
            backups[path] = None

    try:
        run_worker_case([
            1000000000.010,
            1000000000.020,
            1000000000.030,
            1000000000.040,
            1000000000.050,
        ])
        run_worker_case([
            100000000.0,
            100000000.1,
            100000000.4,
            100000000.9,
            100000001.6,
        ])
    finally:
        for path, content in backups.items():
            if content is None:
                try:
                    os.unlink(path)
                except FileNotFoundError:
                    pass
            else:
                with open(path, "wb") as f:
                    f.write(content)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
