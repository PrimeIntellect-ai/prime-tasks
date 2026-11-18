#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import gzip
import http.server
import json
import math
import os
import secrets
import shutil
import signal
import stat
import subprocess
import threading
import time
from pathlib import Path

import pytest
import requests

API_URL = "http://127.0.0.1:8080"
PARSER = Path("/home/user/parser.go")
ARCHIVES = Path("/home/user/data/archives")
TRUTH = Path("/app/services/truth_log.json")
BINARY = Path("/tmp/submitted_parser")

state_lock = threading.Lock()
allowed = collections.Counter()
received = collections.Counter()
invalid = []


def record_key(obj):
    if not isinstance(obj, dict) or set(obj) != {"sensor_id", "value", "timestamp"}:
        raise ValueError("payload must contain exactly sensor_id, value, and timestamp")
    sid = obj["sensor_id"]
    value = obj["value"]
    timestamp = obj["timestamp"]
    if not isinstance(sid, str) or not isinstance(timestamp, str):
        raise ValueError("sensor_id and timestamp must be strings")
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError("value must be numeric")
    value = float(value)
    if not math.isfinite(value) or value < 0.0:
        raise ValueError("value must be a finite nonnegative number")
    return sid, value, timestamp


class ValidationHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send_json(self, status, obj):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path != "/metrics":
            self.send_json(404, {"error": "not found"})
            return
        with state_lock:
            count = sum(received.values())
        self.send_json(200, {"received_valid_count": count})

    def do_POST(self):
        if self.path != "/submit":
            self.send_json(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > 1024 * 1024:
                raise ValueError("invalid body length")
            obj = json.loads(self.rfile.read(length).decode("utf-8"))
            key = record_key(obj)
            with state_lock:
                if allowed[key] == 0:
                    invalid.append(("unexpected", obj))
                elif received[key] >= allowed[key]:
                    invalid.append(("duplicate", obj))
                else:
                    received[key] += 1
            self.send_json(200, {"status": "ok"})
        except Exception as exc:
            with state_lock:
                invalid.append(("malformed", str(exc)))
            self.send_json(400, {"status": "error"})


class ReusableHTTPServer(http.server.ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True


def kill_port_8080():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[3] == "0A":
                try:
                    port = int(fields[1].rsplit(":", 1)[1], 16)
                except ValueError:
                    continue
                if port == 8080:
                    inodes.add(fields[9])

    victims = set()
    for proc in Path("/proc").glob("[0-9]*"):
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(proc.name))
        except (OSError, ValueError):
            continue

    victims.discard(os.getpid())
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.4)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def configure_expected(records):
    expected = collections.Counter()
    for obj in records:
        if float(obj["value"]) >= 0.0:
            expected[record_key(obj)] += 1
    with state_lock:
        allowed.clear()
        allowed.update(expected)
        received.clear()
        invalid.clear()
    return expected


def run_parser(expected, label):
    configure_expected(expected)
    start = time.monotonic()
    try:
        result = subprocess.run(
            [str(BINARY)],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5.0,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"parser exceeded the required runtime of less than 5 seconds during {label}")
    elapsed = time.monotonic() - start
    assert elapsed < 5.0, f"parser runtime was {elapsed:.3f}s during {label}, not less than 5 seconds"
    assert result.returncode == 0, (
        f"parser exited with status {result.returncode} during {label}. "
        f"stderr: {result.stderr[-2000:]}"
    )

    metrics = requests.get(API_URL + "/metrics", timeout=5)
    assert metrics.status_code == 200
    count = metrics.json().get("received_valid_count", 0)
    expected_count = sum(configure_count for configure_count in collections.Counter(
        record_key(obj) for obj in expected if float(obj["value"]) >= 0.0
    ).values())

    with state_lock:
        bad = list(invalid)
    assert not bad, f"parser submitted malformed, unexpected, or duplicate records during {label}: {bad[:5]}"
    assert expected_count > 0
    recall = count / expected_count
    assert recall >= 0.98, (
        f"Recovery Recall {recall:.4f} is below 0.98 during {label}: "
        f"received {count} correctly parsed unique records, expected {expected_count}."
    )


def xml_record(sid, value, timestamp, encoding):
    text = (
        f"<Reading>\n<SensorID>{sid}</SensorID>\n<Value>{value:.2f}</Value>\n"
        f"<Timestamp>{timestamp}</Timestamp>\n</Reading>\n"
    )
    return text.encode(encoding)


def make_fixture(directory):
    token = secrets.token_hex(12)
    expected = []
    groups = []
    for group in range(4):
        raw = bytearray()
        encoding = "latin-1" if group == 1 else "utf-8"
        for i in range(110):
            value = -3.25 if i % 17 == 0 else round(group * 100 + i / 10 + 0.25, 2)
            sid = f"café-{token}-{group}-{i}" if encoding == "latin-1" else f"秘密-{token}-{group}-{i}"
            ts = f"2042-05-{group + 1:02d}T03:{i % 60:02d}:{i % 57:02d}Z"
            raw.extend(xml_record(sid, value, ts, encoding))
            expected.append({"sensor_id": sid, "value": value, "timestamp": ts})
        groups.append(bytes(raw))

    (directory / "valid_utf8.gz").write_bytes(gzip.compress(groups[0]))
    (directory / "valid_latin1.gz").write_bytes(gzip.compress(groups[1]))
    truncated = gzip.compress(groups[2])
    (directory / "incomplete_trailer.gz").write_bytes(truncated[:-4])
    (directory / "trailing_garbage.gz").write_bytes(gzip.compress(groups[3]) + b"NOT-A-GZIP-MEMBER\x00\xff")
    return expected


def test_01_api_reachable_and_metrics_exist():
    try:
        resp = requests.get(API_URL + "/metrics", timeout=5)
        assert resp.status_code == 200, f"API returned status {resp.status_code} instead of 200"
        assert "received_valid_count" in resp.json(), "metrics JSON is missing received_valid_count"
    except requests.RequestException as exc:
        pytest.fail(f"API is not reachable on port 8080; fix start_all.sh and leave it running: {exc}")


def test_02_parser_recovery_correctness_and_runtime():
    assert PARSER.exists(), f"required Go source {PARSER} does not exist"
    assert not PARSER.is_symlink(), f"{PARSER} must be a real Go source file, not a symlink"
    assert stat.S_ISREG(PARSER.stat().st_mode), f"{PARSER} is not a regular file"

    build = subprocess.run(
        ["go", "build", "-o", str(BINARY), str(PARSER)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert build.returncode == 0, f"parser.go does not compile: {build.stderr[-3000:]}"

    assert TRUTH.exists(), f"truth log {TRUTH} is missing"
    try:
        truth = json.loads(TRUTH.read_text())
    except json.JSONDecodeError as exc:
        pytest.fail(f"failed to parse {TRUTH}: {exc}")
    assert isinstance(truth, list)
    assert sum(1 for obj in truth if obj.get("value", -1.0) >= 0.0) > 0, "truth log has no valid records"

    kill_port_8080()
    server = ReusableHTTPServer(("127.0.0.1", 8080), ValidationHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    backup = Path(f"/home/user/data/archives.verifier-backup-{secrets.token_hex(8)}")
    try:
        assert ARCHIVES.is_dir(), f"archive directory {ARCHIVES} is missing"
        ARCHIVES.rename(backup)
        ARCHIVES.mkdir(parents=True)
        fixture_expected = make_fixture(ARCHIVES)
        run_parser(fixture_expected, "independently generated mixed-encoding/corrupt-gzip fixtures")

        shutil.rmtree(ARCHIVES)
        backup.rename(ARCHIVES)
        run_parser(truth, "generated sensor archives")
    finally:
        server.shutdown()
        server.server_close()
        if backup.exists():
            if ARCHIVES.exists():
                shutil.rmtree(ARCHIVES)
            backup.rename(ARCHIVES)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
