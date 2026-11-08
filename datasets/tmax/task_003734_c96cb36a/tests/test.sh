#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import json
import os
import re
import secrets
import subprocess
from collections import Counter

import pytest
import requests

REDIS_LIST = "pipeline_metrics"
ARCHIVE_PATH = "/home/user/data/metrics_archive.jsonl"


def redis(*args):
    return subprocess.run(["redis-cli", *args], capture_output=True, text=True)


def redis_items():
    result = redis("LRANGE", REDIS_LIST, "0", "-1")
    assert result.returncode == 0, f"redis-cli failed: {result.stderr}"
    return [line for line in result.stdout.splitlines() if line]


def canonical_counter(items):
    return Counter(json.dumps(item, sort_keys=True, separators=(",", ":")) for item in items)


def listening_process_on_9000():
    socket_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if int(local.rsplit(":", 1)[1], 16) == 9000 and state == "0A":
                        socket_inodes.add(fields[9])
        except FileNotFoundError:
            pass

    assert socket_inodes, "No process is listening on TCP port 9000."
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in socket_inodes:
                    return int(pid)
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    pytest.fail("Could not associate the port 9000 listening socket with a process.")


def test_cpp_server_artifact():
    sources = []
    for root in ("/app", "/home/user"):
        for directory, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {"cpp-httplib", ".git", "__pycache__"}]
            for name in files:
                if name.endswith((".cpp", ".cc", ".cxx", ".C")):
                    path = os.path.join(directory, name)
                    try:
                        text = open(path, encoding="utf-8", errors="ignore").read()
                    except OSError:
                        continue
                    if "httplib" in text and "ingest" in text and ("std::regex" in text or "<regex>" in text):
                        sources.append(path)
    assert sources, "Expected C++ server source using cpp-httplib and C++ regular expressions."

    pid = listening_process_on_9000()
    exe = os.path.realpath(f"/proc/{pid}/exe")
    assert os.path.isfile(exe), "The port 9000 server has no executable artifact."
    with open(exe, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The port 9000 server is not a compiled executable."

    linked = subprocess.run(["ldd", exe], capture_output=True, text=True)
    linkage = linked.stdout + linked.stderr
    if "libstdc++" not in linkage:
        with open(exe, "rb") as f:
            binary = f.read()
        assert b"GLIBCXX_" in binary or b"__cxa" in binary, "The listening server does not appear to be a C++ executable."


def test_flush_metrics_script():
    path = "/home/user/flush_metrics.sh"
    assert os.path.isfile(path), f"Expected script {path} to exist."
    assert os.access(path, os.X_OK), f"Expected {path} to be executable."


def test_crontab_configured():
    result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to read crontab."
    assert "* * * * * /home/user/flush_metrics.sh" in result.stdout, "Crontab does not contain the expected cron expression."


def test_pipeline_end_to_end():
    # Preserve the original fixed end-to-end assertions.
    redis("DEL", REDIS_LIST)
    if os.path.exists(ARCHIVE_PATH):
        os.remove(ARCHIVE_PATH)

    csv_payload = (
        'machine_id,timestamp,sensor_dump\n'
        'm1,2023-01-01T10:00:00Z,"System OK\n'
        'Temp: 45C\n'
        'Load: 12%\n'
        'Fan: 1200RPM"\n'
        'm2,2023-01-01T10:01:00Z,"Temp: 50C\n'
        'Load: 80%"\n'
    )

    try:
        response = requests.post("http://127.0.0.1:8080/ingest", data=csv_payload, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to Nginx on port 8080 or server error: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"
    assert "5" in response.text, f"Expected response to contain '5' (the number of metrics extracted), got: {response.text}"

    redis_output = redis_items()
    assert len(redis_output) == 5, f"Expected 5 metrics in Redis list 'pipeline_metrics', found {len(redis_output)}."

    metrics = []
    for line in redis_output:
        try:
            metrics.append(json.loads(line))
        except json.JSONDecodeError:
            pytest.fail(f"Invalid JSON in Redis: {line}")

    metrics_str = json.dumps(metrics)
    assert "Temp" in metrics_str
    assert "Load" in metrics_str
    assert "Fan" in metrics_str
    assert "45" in metrics_str
    assert "1200" in metrics_str

    flush_res = subprocess.run(["/home/user/flush_metrics.sh"], capture_output=True, text=True)
    assert flush_res.returncode == 0, f"flush_metrics.sh failed to run: {flush_res.stderr}"

    redis_res_after = redis("LLEN", REDIS_LIST)
    assert redis_res_after.stdout.strip() == "0", "Expected Redis list 'pipeline_metrics' to be empty after flushing."

    assert os.path.isfile(ARCHIVE_PATH), f"Expected archive file {ARCHIVE_PATH} to exist after flushing."
    with open(ARCHIVE_PATH) as f:
        archived_lines = [line.strip() for line in f if line.strip()]
    assert len(archived_lines) >= 5, f"Expected at least 5 metrics in archive file, found {len(archived_lines)}."


def test_randomized_csv_malicious_payload_and_exact_flush():
    redis("DEL", REDIS_LIST)
    if os.path.exists(ARCHIVE_PATH):
        os.remove(ARCHIVE_PATH)

    # A malicious payload with no valid metric must neither execute text nor emit data.
    marker = f"/tmp/pipeline_verifier_{secrets.token_hex(8)}"
    malicious_dump = (
        f'comma, quote " and newline\n$(touch {marker})\n'
        'Temp: 91X\nLoad: nope%\nFan: 1234RPN\n'
        '"; redis-cli RPUSH pipeline_metrics forged; #'
    )
    out = io.StringIO()
    writer = csv.writer(out, lineterminator="\n")
    writer.writerow(["machine_id", "timestamp", "sensor_dump"])
    writer.writerow(["host-malicious", "2026-09-11T11:59:00Z", malicious_dump])
    response = requests.post("http://127.0.0.1:8080/ingest", data=out.getvalue(), timeout=5)
    assert response.status_code == 200
    assert re.search(r"(?<!\d)0(?!\d)", response.text), f"Response did not report zero metrics: {response.text}"
    assert redis("LLEN", REDIS_LIST).stdout.strip() == "0"
    assert not os.path.exists(marker), "Sensor text was executed as a shell command."

    nonce = secrets.token_hex(6)
    metric_count = 4 + secrets.randbelow(5)
    names = ["Temp", "Load", "Fan"]
    suffixes = {"Temp": "C", "Load": "%", "Fan": "RPM"}
    expected = []
    rows = []

    # The first record contains embedded newlines, a comma, an escaped quote,
    # shell-looking text, and all three metric kinds.
    first_lines = ['status, says "normal"', f'$(touch {marker})']
    for index, name in enumerate(names):
        value = str(10000 + secrets.randbelow(80000) + index)
        first_lines.append(f"{name}: {value}{suffixes[name]}")
        expected.append({
            "machine_id": f"dyn-{nonce}-0",
            "timestamp": "2026-09-11T12:00:00Z",
            "metric": name,
            "value": value,
        })
    rows.append([f"dyn-{nonce}-0", "2026-09-11T12:00:00Z", "\n".join(first_lines)])

    for index in range(3, metric_count):
        name = names[index % 3]
        value = str(10000 + secrets.randbelow(80000) + index)
        machine = f"dyn-{nonce}-{index}"
        timestamp = f"2026-09-11T12:00:{index:02d}Z"
        dump = f"noise, with commas\nand an escaped \"quote\"\n{name}: {value}{suffixes[name]}\nTemp: 777X"
        rows.append([machine, timestamp, dump])
        expected.append({"machine_id": machine, "timestamp": timestamp, "metric": name, "value": value})

    out = io.StringIO()
    writer = csv.writer(out, lineterminator="\n")
    writer.writerow(["machine_id", "timestamp", "sensor_dump"])
    writer.writerows(rows)

    response = requests.post("http://127.0.0.1:8080/ingest", data=out.getvalue(), timeout=5)
    assert response.status_code == 200, response.text
    assert re.search(rf"(?<!\d){metric_count}(?!\d)", response.text), \
        f"Response did not report {metric_count} metrics: {response.text}"

    raw_items = redis_items()
    assert len(raw_items) == metric_count
    try:
        actual = [json.loads(item) for item in raw_items]
    except json.JSONDecodeError as error:
        pytest.fail(f"Redis contained invalid JSON: {error}")
    assert canonical_counter(actual) == canonical_counter(expected), \
        f"Redis metrics differ from the submitted CSV. Actual: {actual}"
    assert not os.path.exists(marker), "Sensor text was executed as a shell command."

    flush = subprocess.run(["/home/user/flush_metrics.sh"], capture_output=True, text=True)
    assert flush.returncode == 0, flush.stderr
    assert redis("LLEN", REDIS_LIST).stdout.strip() == "0"
    assert os.path.isfile(ARCHIVE_PATH)
    with open(ARCHIVE_PATH) as f:
        archived = [json.loads(line) for line in f if line.strip()]
    assert canonical_counter(archived) == canonical_counter(expected), \
        "The flush script did not archive the exact Redis JSON objects."

    # Confirm that flushing appends rather than replacing existing archive data.
    extra = {"machine_id": f"append-{nonce}", "timestamp": "2026-09-11T13:00:00Z", "metric": "Temp", "value": "31415"}
    pushed = redis("RPUSH", REDIS_LIST, json.dumps(extra, separators=(",", ":")))
    assert pushed.returncode == 0
    flush = subprocess.run(["/home/user/flush_metrics.sh"], capture_output=True, text=True)
    assert flush.returncode == 0, flush.stderr
    with open(ARCHIVE_PATH) as f:
        archived_after = [json.loads(line) for line in f if line.strip()]
    assert canonical_counter(archived_after) == canonical_counter(expected + [extra])
    assert redis("LLEN", REDIS_LIST).stdout.strip() == "0"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
