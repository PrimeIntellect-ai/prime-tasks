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
set +e
mkdir -p /logs/verifier

RAW_COPY=$(mktemp /tmp/raw_datasets.XXXXXX.csv)
RAW_HIDDEN=/home/user/raw_datasets.csv.verifier-hidden
SERVICE_PID=""

cleanup() {
    if [ -n "$SERVICE_PID" ]; then
        kill "$SERVICE_PID" 2>/dev/null || true
        wait "$SERVICE_PID" 2>/dev/null || true
    fi
    if [ -f "$RAW_HIDDEN" ]; then
        mv -f "$RAW_HIDDEN" /home/user/raw_datasets.csv
    fi
    rm -f "$RAW_COPY"
}
trap cleanup EXIT

if [ -f /home/user/raw_datasets.csv ]; then
    cp /home/user/raw_datasets.csv "$RAW_COPY"
    mv /home/user/raw_datasets.csv "$RAW_HIDDEN"
fi
export RAW_COPY

# Stop any service currently owning port 8080 so the submitted artifact itself
# must be launched by this verifier.
python3 - <<'PY' 2>/dev/null
import os, signal, time
inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                if int(fields[1].split(':')[-1], 16) == 8080 and fields[3] == '0A':
                    inodes.add(fields[9])
    except OSError:
        pass
for pid in os.listdir('/proc'):
    if not pid.isdigit() or int(pid) == os.getpid():
        continue
    try:
        for fd in os.listdir('/proc/' + pid + '/fd'):
            try:
                target = os.readlink('/proc/' + pid + '/fd/' + fd)
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                os.kill(int(pid), signal.SIGTERM)
                break
    except OSError:
        pass
time.sleep(0.5)
PY

if [ -x /home/user/graph_service ]; then
    (cd /home/user && exec /home/user/graph_service) >/tmp/graph_service.verifier.log 2>&1 &
    SERVICE_PID=$!
fi

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import datetime
import json
import math
import os
import struct
import subprocess
import time
from collections import Counter
from concurrent.futures import ThreadPoolExecutor

import pytest
import requests

URL = "http://127.0.0.1:8080/shortest-path"


def load_raw():
    path = os.environ["RAW_COPY"]
    assert os.path.isfile(path) and os.path.getsize(path) > 0, "Raw dataset fixture is missing"
    with open(path, newline="") as f:
        return list(csv.DictReader(f))


def test_graph_service_code_exists():
    path = "/home/user/graph_service.cpp"
    assert os.path.isfile(path), f"Missing C++ source code at {path}"


def test_graph_service_binary_exists():
    path = "/home/user/graph_service"
    assert os.path.isfile(path), f"Missing graph service binary at {path}"
    assert os.access(path, os.X_OK), f"Graph service binary at {path} is not executable"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "graph_service is not a compiled ELF executable"


def test_graph_bin_exists_and_valid():
    path = "/home/user/graph.bin"
    assert os.path.isfile(path), f"Missing graph.bin at {path}"
    raw = open(path, "rb").read()
    assert len(raw) >= 12 and raw[:4] == b"GRPH", "Invalid graph header"

    n = struct.unpack_from("<i", raw, 4)[0]
    expected_rows = load_raw()
    expected_names = {r["source"] for r in expected_rows} | {r["target"] for r in expected_rows}
    assert n == len(expected_names), f"Expected {len(expected_names)} graph nodes, got {n}"

    offset = 8
    assert offset + n * 32 + 4 <= len(raw), "Truncated node array"
    nodes = []
    for _ in range(n):
        name_bytes, timestamp, padding = struct.unpack_from("<16sqq", raw, offset)
        offset += 32
        name = name_bytes.split(b"\0", 1)[0].decode("utf-8")
        assert name, "Graph contains an unnamed node"
        nodes.append((name, timestamp))
    assert len({name for name, _ in nodes}) == n, "Graph contains duplicate node names"
    assert {name for name, _ in nodes} == expected_names, "graph.bin nodes do not match raw_datasets.csv"

    e = struct.unpack_from("<i", raw, offset)[0]
    offset += 4
    assert e == len(expected_rows), f"Expected {len(expected_rows)} graph edges, got {e}"
    assert offset + e * 12 <= len(raw), "Truncated edge array"
    actual_edges = []
    for _ in range(e):
        src, dst, weight = struct.unpack_from("<iif", raw, offset)
        offset += 12
        assert 0 <= src < n and 0 <= dst < n, "Edge contains an invalid node index"
        assert math.isfinite(weight), "Edge contains a non-finite weight"
        actual_edges.append((nodes[src][0], nodes[dst][0], round(float(weight), 5)))
    expected_edges = Counter((r["source"], r["target"], round(float(r["weight"]), 5)) for r in expected_rows)
    assert Counter(actual_edges) == expected_edges, "graph.bin edges or weights do not match raw_datasets.csv"

    expected_dates = {}
    for row in expected_rows:
        expected_dates[row["source"]] = row["source_date"]
        expected_dates[row["target"]] = row["target_date"]
    actual_times = dict(nodes)
    encodings = []
    for scale in (1, 1000):
        encodings.append({name: int(datetime.datetime.strptime(date, "%Y-%m-%d").replace(tzinfo=datetime.timezone.utc).timestamp()) * scale
                          for name, date in expected_dates.items()})
    encodings.append({name: int(date.replace("-", "")) for name, date in expected_dates.items()})
    encodings.append({name: (datetime.date.fromisoformat(date) - datetime.date(1970, 1, 1)).days
                      for name, date in expected_dates.items()})
    assert any(actual_times == encoding for encoding in encodings), "Node timestamps do not encode the CSV creation dates"

    oracle_path = "/app/legacy_graph_oracle"
    try:
        result = subprocess.run([oracle_path], capture_output=True, text=True, timeout=5)
        assert result.returncode == 0, f"Legacy oracle validation failed with exit code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"
    except subprocess.TimeoutExpired:
        pytest.fail("Legacy oracle validation timed out.")
    except Exception as exc:
        pytest.fail(f"Failed to run legacy oracle: {exc}")


def post(payload, retry=False):
    deadline = time.time() + 5
    while True:
        try:
            return requests.post(URL, json=payload, timeout=5)
        except requests.exceptions.ConnectionError:
            if not retry or time.time() >= deadline:
                pytest.fail(f"Could not connect to the HTTP service at {URL}. Is it running?")
            time.sleep(0.1)
        except requests.exceptions.Timeout:
            pytest.fail(f"Request to {URL} timed out.")


def decode_response(response, limit):
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except (json.JSONDecodeError, requests.exceptions.JSONDecodeError):
        pytest.fail(f"Response is not valid JSON. Response body: {response.text}")
    assert isinstance(data, (dict, list)), f"Unexpected JSON structure: {data}"
    assert isinstance(data, dict), "Response must contain both paginated edges and total path cost"
    assert "cost" in data or "total_cost" in data or "edges" in data, f"Missing expected keys in JSON response: {data}"
    assert "edges" in data, f"Missing edges in JSON response: {data}"
    assert isinstance(data["edges"], list), "Edges should be a list"
    assert len(data["edges"]) <= limit, f"Expected at most {limit} edges due to pagination limit, got {len(data['edges'])}"
    cost_key = "total_cost" if "total_cost" in data else "cost" if "cost" in data else None
    assert cost_key is not None, f"Missing total path cost: {data}"
    assert isinstance(data[cost_key], (int, float)) and not isinstance(data[cost_key], bool), "Path cost must be numeric"
    assert math.isfinite(float(data[cost_key])), "Path cost must be finite"
    return data["edges"], float(data[cost_key])


def normalize_edge(edge):
    if isinstance(edge, dict):
        src = next((edge[k] for k in ("source", "src", "from") if k in edge), None)
        dst = next((edge[k] for k in ("target", "dst", "to") if k in edge), None)
        weight = next((edge[k] for k in ("weight", "cost") if k in edge), None)
    elif isinstance(edge, (list, tuple)) and len(edge) >= 3:
        src, dst, weight = edge[:3]
    else:
        pytest.fail(f"Unrecognized edge representation: {edge}")
    assert isinstance(src, str) and isinstance(dst, str), f"Edge endpoints must be dataset names: {edge}"
    assert isinstance(weight, (int, float)) and not isinstance(weight, bool), f"Edge weight must be numeric: {edge}"
    return src, dst, float(weight)


def assert_path(payload, expected, expected_cost, retry=False):
    edges, cost = decode_response(post(payload, retry=retry), payload["limit"])
    normalized = [normalize_edge(edge) for edge in edges]
    assert len(normalized) == len(expected), f"Wrong number of path edges: {normalized}"
    for actual, wanted in zip(normalized, expected):
        assert actual[:2] == wanted[:2], f"Wrong traversal order: {normalized}"
        assert actual[2] == pytest.approx(wanted[2], rel=1e-5, abs=1e-5)
    assert cost == pytest.approx(expected_cost, rel=1e-5, abs=1e-5)


def test_http_service_shortest_path():
    payload = {"source": "D1", "target": "D99", "min_date": "2021-05-01", "page": 1, "limit": 2}
    assert_path(payload, [("D1", "D2", 1.0), ("D2", "D99", 2.0)], 3.0, retry=True)


def test_shortest_path_pagination_and_alternatives():
    base = {"source": "D1", "target": "D99", "min_date": "2021-05-01", "limit": 1}
    assert_path(dict(base, page=1), [("D1", "D2", 1.0)], 3.0)
    assert_path(dict(base, page=2), [("D2", "D99", 2.0)], 3.0)
    assert_path({"source": "D1", "target": "D3", "min_date": "2021-05-01", "page": 1, "limit": 10},
                [("D1", "D3", 5.0)], 5.0)
    assert_path({"source": "D3", "target": "D99", "min_date": "2021-05-04", "page": 1, "limit": 10},
                [("D3", "D99", 1.0)], 1.0)


def test_min_date_filter_rejects_old_source():
    response = post({"source": "D1", "target": "D99", "min_date": "2021-05-03", "page": 1, "limit": 10})
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}: {response.text}"
    data = response.json()
    assert isinstance(data, dict) and isinstance(data.get("edges"), list), f"Invalid no-path response: {data}"
    assert data["edges"] == [], "Date filtering must not return a path through an excluded source node"


def test_concurrent_requests():
    payloads = [
        {"source": "D1", "target": "D99", "min_date": "2021-05-01", "page": 1, "limit": 2},
        {"source": "D2", "target": "D99", "min_date": "2021-05-03", "page": 1, "limit": 2},
        {"source": "D3", "target": "D99", "min_date": "2021-05-04", "page": 1, "limit": 2},
    ] * 4
    with ThreadPoolExecutor(max_workers=8) as pool:
        responses = list(pool.map(post, payloads))
    assert all(r.status_code == 200 for r in responses), "Concurrent requests did not all succeed"
    expected_costs = [3.0, 2.0, 1.0] * 4
    for response, expected_cost in zip(responses, expected_costs):
        _, cost = decode_response(response, 2)
        assert cost == pytest.approx(expected_cost)
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
STATUS=$?
if [ "$STATUS" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
