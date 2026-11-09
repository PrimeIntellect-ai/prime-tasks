#!/bin/bash
set +e
mkdir -p /logs/verifier
reward=0
server_pid=""

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import subprocess
import time
from decimal import Decimal
from pathlib import Path

import pytest
import requests


def get_ground_truth():
    cmd = [
        "ffprobe",
        "-v", "error",
        "-select_streams", "v:0",
        "-show_packets",
        "-of", "json",
        "/app/data_video.mp4",
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    data = json.loads(result.stdout)

    packets = data.get("packets", [])
    total_processed = len(packets)

    seen = set()
    deduped = []
    for p in packets:
        size = int(p.get("size", 0))
        flags = p.get("flags", "")
        pts_time = p.get("pts_time", "")
        key = (size, flags)
        if key not in seen:
            seen.add(key)
            deduped.append({"size": size, "pts_time": pts_time})

    # Step 4 requires anomaly detection on the deduplicated packets in PTS order,
    # not ffprobe's packet/decode order.
    deduped.sort(key=lambda p: Decimal(p["pts_time"]))

    anomalies = []
    for i in range(1, len(deduped)):
        prev_size = deduped[i - 1]["size"]
        curr_size = deduped[i]["size"]
        if curr_size > 3 * prev_size:
            anomalies.append(deduped[i]["pts_time"])

    return {
        "total_processed": total_processed,
        "total_deduplicated": len(deduped),
        "total_anomalies": len(anomalies),
        "anomalies": anomalies,
    }


def test_required_go_streaming_and_sanitization_source():
    path = Path("/home/user/analyzer.go")
    assert path.is_file(), "Missing required /home/user/analyzer.go"
    source = path.read_text(encoding="utf-8")
    compact = "".join(source.split())
    lower = source.lower()

    assert "packagemain" in compact, "analyzer.go must be a Go main package"
    assert "ffprobe" in lower and "show_packets" in lower, "Go program must invoke ffprobe packet extraction"
    assert "tags" in lower, "Go program must process packet tags"

    streaming_reader = any(marker in compact for marker in (
        "json.NewDecoder(", "bufio.NewScanner(", "csv.NewReader(",
    ))
    streaming_pipe = "StdoutPipe(" in compact or "io.Pipe(" in compact or "os.Pipe(" in compact
    assert streaming_reader and streaming_pipe, "ffprobe output must be consumed through a streaming reader and pipe"

    assert "regexp." in source, "Tag sanitization must use Go's regexp package"
    assert "regexp.Compile(" in compact or "regexp.MustCompile(" in compact, "A Go sanitization regex must be compiled"
    assert "ReplaceAllString(" in compact or "ReplaceAll(" in compact, "The sanitization regex must be applied"
    assert chr(92) + "u" in source, "Sanitization must handle escaped unicode sequences"
    assert any(token in source for token in ("ASCII", "ascii", "7F", "7f", "127", "x80", "u007F")), \
        "Sanitization regex must account for non-ASCII characters"


@pytest.fixture(scope="module")
def wait_for_service():
    url = "http://127.0.0.1:8080/api/stats"
    for _ in range(30):
        try:
            resp = requests.get(url, timeout=1)
            if resp.status_code == 200:
                return
        except requests.exceptions.RequestException:
            pass
        time.sleep(1)
    pytest.fail("Service at 127.0.0.1:8080 did not become ready in time.")


def test_api_stats(wait_for_service):
    truth = get_ground_truth()
    resp = requests.get("http://127.0.0.1:8080/api/stats", timeout=5)
    assert resp.status_code == 200, f"Expected status 200, got {resp.status_code}"
    try:
        data = resp.json()
    except ValueError:
        pytest.fail("Response from /api/stats is not valid JSON")

    assert "total_processed" in data, "Missing total_processed in /api/stats"
    assert "total_deduplicated" in data, "Missing total_deduplicated in /api/stats"
    assert "total_anomalies" in data, "Missing total_anomalies in /api/stats"
    assert data["total_processed"] == truth["total_processed"], f"Expected total_processed={truth['total_processed']}, got {data['total_processed']}"
    assert data["total_deduplicated"] == truth["total_deduplicated"], f"Expected total_deduplicated={truth['total_deduplicated']}, got {data['total_deduplicated']}"
    assert data["total_anomalies"] == truth["total_anomalies"], f"Expected total_anomalies={truth['total_anomalies']}, got {data['total_anomalies']}"


def test_api_anomalies(wait_for_service):
    truth = get_ground_truth()
    resp = requests.get("http://127.0.0.1:8080/api/anomalies", timeout=5)
    assert resp.status_code == 200, f"Expected status 200, got {resp.status_code}"
    try:
        data = resp.json()
    except ValueError:
        pytest.fail("Response from /api/anomalies is not valid JSON")

    assert isinstance(data, list), "Response from /api/anomalies should be a list"
    assert data == truth["anomalies"], f"Anomalies mismatch. Expected {truth['anomalies']}, got {data}"
TEST_EOF

# Stop any pre-existing listener so the verifier executes the submitted Go artifact itself.
python3 << 'KILL_EOF'
import os
import signal

inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table) as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) >= 10 and fields[1].endswith(":1F90") and fields[3] == "0A":
                    inodes.add(fields[9])
    except OSError:
        pass

for name in os.listdir("/proc"):
    if not name.isdigit():
        continue
    fd_dir = f"/proc/{name}/fd"
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                try:
                    os.kill(int(name), signal.SIGKILL)
                except (ProcessLookupError, PermissionError):
                    pass
                break
    except OSError:
        pass
KILL_EOF

if go build -o /tmp/analyzer_verified /home/user/analyzer.go >/tmp/analyzer_build.log 2>&1; then
    /tmp/analyzer_verified >/tmp/analyzer_server.log 2>&1 &
    server_pid=$!
    if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
        reward=1
    fi
fi

if [ -n "$server_pid" ]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
fi

echo "$reward" > /logs/verifier/reward.txt
exit 0
