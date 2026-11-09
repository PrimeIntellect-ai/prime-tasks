#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import io
import json
import os
import random
import stat
import subprocess
import time
import urllib.request

import pytest
import redis

EXECUTABLE = "/home/user/csv_tracker"
SOURCE = "/home/user/csv_tracker.c"
PIPE = "/tmp/config_stream.pipe"


def levenshtein(a, b):
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(current[-1] + 1,
                               previous[j] + 1,
                               previous[j - 1] + (ca != cb)))
        previous = current
    return previous[-1]


def rejected(old, new):
    return any(c in old or c in new for c in "`$|<>") or levenshtein(old, new) > 50


def expected_rows(wide_rows):
    result = []
    for row in wide_rows:
        assert len(row) == 6, f"invalid test/corpus input row: {row!r}"
        ident, timestamp, old_a, new_a, old_b, new_b = row
        for name, old, new in (("config_A", old_a, new_a),
                               ("config_B", old_b, new_b)):
            if not rejected(old, new):
                result.append([ident, timestamp, name, old, new,
                               str(levenshtein(old, new))])
    return result


def encode_csv(rows):
    out = io.StringIO(newline="")
    writer = csv.writer(out, lineterminator="\r\n")
    writer.writerows(rows)
    return out.getvalue()


def parse_csv(text):
    reader = csv.reader(io.StringIO(text, newline=""), strict=True)
    rows = list(reader)
    assert all(row for row in rows), "output contains blank CSV records"
    assert all(len(row) == 6 for row in rows), f"output rows must have 6 columns: {rows!r}"
    return rows


def run_tracker(rows):
    proc = subprocess.run(
        [EXECUTABLE], input=encode_csv(rows), text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=8
    )
    assert proc.returncode == 0, f"csv_tracker exited {proc.returncode}: {proc.stderr}"
    return parse_csv(proc.stdout)


def read_corpus(path):
    with open(path, "r", newline="", encoding="utf-8") as f:
        return [row for row in csv.reader(f, strict=True) if row]


def test_csv_tracker_executable_and_is_compiled_c_artifact():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} not found. Did you compile the C program?"
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable."
    assert os.path.isfile(SOURCE), f"C source {SOURCE} is missing"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "csv_tracker must be a compiled native executable"


def test_provided_corpora_exactly():
    clean_files = glob.glob("/app/corpora/clean/*.csv")
    evil_files = glob.glob("/app/corpora/evil/*.csv")
    assert clean_files, "No clean corpus files found"
    assert evil_files, "No evil corpus files found"

    for path in clean_files:
        rows = read_corpus(path)
        actual = run_tracker(rows)
        expected = expected_rows(rows)
        assert len(actual) == len(rows) * 2, \
            f"{os.path.basename(path)} did not preserve and reshape every clean record"
        assert actual == expected, f"incorrect output for clean corpus {path}: {actual!r}"

    # Filtering is per reshaped record: a safe config_B record in a wide row
    # survives even when config_A is malicious.
    for path in evil_files:
        rows = read_corpus(path)
        assert run_tracker(rows) == expected_rows(rows), \
            f"incorrect record-level filtering for evil corpus {path}"


def test_exact_reshaping_csv_quoting_distances_and_filtering():
    rows = [
        ["id,1", "1700000000", "line one\nline two", "line one\nline 2", "a\"b", "a\"bc"],
        ["empty", "1700000001", "", "x" * 50, "", "y" * 51],
        ["shell", "1700000002", "safe", "bad|command", "left", "right"],
        ["chars", "1700000003", "has`tick", "safe", "safe,old", "safe,old\nnew"],
        ["angle", "1700000004", "safe", "bad<value", "ok", "ok2"],
        ["dollar", "1700000005", "$HOME", "safe", "quote \" old", "quote \" new"],
    ]

    rng = random.Random(93017)
    alphabet = "abc XYZ,\"\n"
    for i in range(18):
        old_a = "".join(rng.choice(alphabet) for _ in range(rng.randrange(0, 35)))
        new_a = old_a
        if new_a:
            p = rng.randrange(len(new_a))
            new_a = new_a[:p] + rng.choice("abcXYZ") + new_a[p + 1:]
        else:
            new_a = "a"
        old_b = "".join(rng.choice(alphabet) for _ in range(rng.randrange(1, 28)))
        new_b = old_b + rng.choice("abc")
        rows.append([f"random-{i}", str(1800000000 + i), old_a, new_a, old_b, new_b])

    assert run_tracker(rows) == expected_rows(rows)


def tracker_process_running():
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            exe = os.path.realpath(f"/proc/{pid}/exe")
            cmd = open(f"/proc/{pid}/cmdline", "rb").read().replace(b"\0", b" ")
            if exe == os.path.realpath(EXECUTABLE) or EXECUTABLE.encode() in cmd:
                return True
        except (OSError, PermissionError):
            pass
    return False


def fifo_has_consumer_process():
    target = os.path.realpath(PIPE)
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.path.realpath(os.path.join(fd_dir, fd)) == target:
                        return True
                except OSError:
                    pass
        except (OSError, PermissionError):
            pass
    return False


def wait_http(url, timeout=8):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=1) as response:
                return response.status, response.read()
        except Exception as exc:
            last = exc
            time.sleep(0.2)
    raise AssertionError(f"service at {url} is not available: {last}")


def redis_blob(client):
    chunks = []
    for key in client.scan_iter(match="*"):
        chunks.append(key)
        value = client.dump(key)
        if value:
            chunks.append(value)
    return b"\n".join(chunks)


def test_running_api_pipe_tracker_and_redis_integration():
    assert os.path.exists(PIPE), f"named pipe {PIPE} is missing"
    assert stat.S_ISFIFO(os.stat(PIPE).st_mode), f"{PIPE} is not a FIFO"
    assert tracker_process_running(), "no running csv_tracker consumer process found"
    assert fifo_has_consumer_process(), "no running service has the configuration FIFO open"

    status, body = wait_http("http://127.0.0.1:5000/health")
    assert status == 200 and body == b"OK", "Flask health endpoint is not healthy"

    client = redis.Redis(host="127.0.0.1", port=6379, socket_timeout=2)
    assert client.ping(), "Redis is not running"
    client.flushdb()

    unique = str(time.time_ns())
    payload = {
        "id": "integration-" + unique,
        "timestamp": "1900000000",
        "old_config_A": "old-A-" + unique,
        "new_config_A": "new-A-" + unique + "\nsecond,line",
        "old_config_B": "old-B-" + unique + " with \"quote\"",
        "new_config_B": "new-B-" + unique,
    }
    request = urllib.request.Request(
        "http://127.0.0.1:5000/webhook",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=5) as response:
        assert 200 <= response.status < 300, f"webhook returned {response.status}"

    required = [
        payload["id"], payload["old_config_A"], payload["new_config_A"],
        payload["old_config_B"], payload["new_config_B"], "config_A", "config_B"
    ]
    deadline = time.time() + 8
    blob = b""
    while time.time() < deadline:
        blob = redis_blob(client)
        if all(token.encode("utf-8") in blob for token in required):
            break
        time.sleep(0.2)
    missing = [token for token in required if token.encode("utf-8") not in blob]
    assert not missing, \
        f"webhook/FIFO/tracker pipeline did not write complete reshaped records to Redis; missing {missing!r}"
PYTEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
