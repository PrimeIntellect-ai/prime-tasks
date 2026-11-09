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
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import signal
import socket
import stat
import subprocess
import time
from collections import defaultdict, deque

import barcode
import cv2
import numpy as np
import pytest
import requests
from barcode.writer import ImageWriter
from pyzbar.pyzbar import decode

SCRIPT = "/home/user/serve_api.py"
VIDEO = "/app/experiment_run.mp4"
URL = "http://127.0.0.1:8555/analyze"


def post(node, timeout=5):
    response = requests.post(URL, json={"node": node}, timeout=timeout)
    assert response.status_code == 200, (
        f"Expected status code 200 for {node}, got {response.status_code}: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert "direct_interactions" in data, "Missing 'direct_interactions' in response"
    assert "strongest_path_to_hub" in data, "Missing 'strongest_path_to_hub' in response"
    assert "rolling_avg_strength" in data, "Missing 'rolling_avg_strength' in response"
    return data


def decode_video(path, require_zero_blank=True):
    cap = cv2.VideoCapture(path)
    assert cap.isOpened(), f"Could not open {path}"
    fps = cap.get(cv2.CAP_PROP_FPS)
    count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    assert fps > 0 and count >= 2, "Video has no usable timed frames"

    if require_zero_blank:
        cap.set(cv2.CAP_PROP_POS_MSEC, 0)
        ok, frame = cap.read()
        assert ok, "Could not read timestamp 00:00:00"
        assert not decode(frame), "The first edge must be at 00:00:01, not 00:00:00"

    duration = count / fps
    edges = []
    for second in range(1, int(duration)):
        cap.set(cv2.CAP_PROP_POS_MSEC, second * 1000)
        ok, frame = cap.read()
        assert ok, f"Could not read frame at second {second}"
        values = decode(frame)
        assert len(values) == 1, f"Expected one barcode at second {second}, found {len(values)}"
        text = values[0].data.decode("utf-8")
        parts = text.split("-")
        assert len(parts) == 3 and parts[2].isdigit(), f"Malformed edge barcode: {text}"
        edges.append((parts[0], parts[1], int(parts[2])))
    cap.release()
    assert edges, "No edge barcodes were decoded"
    return edges


def expected_for(edges, node):
    direct = [
        {"target": target, "strength": strength}
        for source, target, strength in edges
        if source == node
    ]
    direct.sort(key=lambda item: (-item["strength"], item["target"]))

    involving = [strength for source, target, strength in edges if source == node or target == node]
    expected_avg = sum(involving) / len(involving) if involving else 0.0

    graph = defaultdict(list)
    nodes = {"ProtHub"}
    for source, target, strength in edges:
        graph[source].append((target, strength))
        nodes.update((source, target))

    if node == "ProtHub":
        path = "ProtHub"
    else:
        candidates = []
        queue = deque([(node, [node], 0)])
        best_hops = None
        while queue:
            current, route, total = queue.popleft()
            hops = len(route) - 1
            if best_hops is not None and hops >= best_hops:
                continue
            for target, strength in graph[current]:
                if target in route:
                    continue
                new_route = route + [target]
                new_total = total + strength
                if target == "ProtHub":
                    best_hops = len(new_route) - 1
                    candidates.append((new_route, new_total))
                else:
                    queue.append((target, new_route, new_total))
        assert candidates, f"Test graph unexpectedly has no path from {node} to ProtHub"
        min_hops = min(len(route) - 1 for route, _ in candidates)
        candidates = [item for item in candidates if len(item[0]) - 1 == min_hops]
        route, _ = max(candidates, key=lambda item: (item[1], " -> ".join(item[0])))
        path = " -> ".join(route)

    return direct, path, expected_avg


def assert_graph_responses(edges):
    nodes = sorted({value for source, target, _ in edges for value in (source, target)})
    for node in nodes:
        expected_direct, expected_path, expected_avg = expected_for(edges, node)
        data = post(node)
        assert data["direct_interactions"] == expected_direct, (
            f"Wrong direct interactions for {node}: {data['direct_interactions']}"
        )
        assert data["strongest_path_to_hub"] == expected_path, (
            f"Wrong strongest path for {node}: {data['strongest_path_to_hub']}"
        )
        assert isinstance(data["rolling_avg_strength"], (int, float)) and not isinstance(
            data["rolling_avg_strength"], bool
        )
        assert abs(data["rolling_avg_strength"] - expected_avg) < 1e-5, (
            f"Wrong rolling average for {node}: {data['rolling_avg_strength']}"
        )


def listener_pids(port=8555):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as handle:
                next(handle)
                for line in handle:
                    fields = line.split()
                    if fields[3] == "0A" and int(fields[1].rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass
    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    link = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if link.startswith("socket:[") and link[8:-1] in inodes:
                    pids.add(int(name))
        except OSError:
            pass
    return pids


def stop_server():
    pids = listener_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listener_pids():
        time.sleep(0.1)
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def write_video(path, edges):
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    out = cv2.VideoWriter(path, fourcc, 1.0, (640, 480))
    assert out.isOpened(), "Could not create challenge video"
    out.write(np.full((480, 640, 3), 255, dtype=np.uint8))
    temp_base = "/tmp/verifier_barcode"
    try:
        for source, target, strength in edges:
            code128 = barcode.Code128(f"{source}-{target}-{strength}", writer=ImageWriter())
            code128.save(temp_base)
            image = cv2.imread(temp_base + ".png")
            assert image is not None
            out.write(cv2.resize(image, (640, 480)))
    finally:
        out.release()
        try:
            os.unlink(temp_base + ".png")
        except FileNotFoundError:
            pass


def start_artifact(probe_node):
    log = open("/tmp/serve_api_verifier.log", "w")
    env = os.environ.copy()
    env["HOME"] = "/home/user"
    process = subprocess.Popen(
        ["python3", SCRIPT], cwd="/home/user", env=env,
        stdout=log, stderr=subprocess.STDOUT, start_new_session=True
    )
    deadline = time.time() + 30
    last_error = None
    while time.time() < deadline:
        if process.poll() is not None:
            break
        try:
            response = requests.post(URL, json={"node": probe_node}, timeout=1)
            if response.status_code == 200:
                return process
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(0.25)
    log.flush()
    try:
        details = open("/tmp/serve_api_verifier.log").read()
    except OSError:
        details = str(last_error)
    pytest.fail(f"{SCRIPT} did not start a working server:\n{details}")


def test_complete_artifact_and_api():
    assert os.path.exists(SCRIPT), f"Missing required artifact {SCRIPT}"
    mode = os.stat(SCRIPT).st_mode
    assert stat.S_ISREG(mode), f"{SCRIPT} is not a regular file"
    assert os.path.getsize(SCRIPT) > 0, f"{SCRIPT} is empty"
    subprocess.run(["python3", "-m", "py_compile", SCRIPT], check=True)

    source = open(SCRIPT, encoding="utf-8").read()
    lowered = source.lower()
    assert "/app/experiment_run.mp4" in source, "The script does not process the supplied video"
    assert "sqlite" in lowered, "The script does not use SQLite"
    assert re.search(r"\bwith\s+recursive\b", source, re.I), "No recursive SQLite query found"
    assert re.search(r"\bover\b", source, re.I), "No SQL window function found"
    assert re.search(r"pyzbar|barcode_barcodedetector|zbar", source, re.I), (
        "No Code 128 decoding implementation found"
    )

    # Preserve the original endpoint assertions exactly.
    data = post("ProtA")
    expected_direct = [
        {"target": "ProtD", "strength": 90},
        {"target": "ProtB", "strength": 50},
        {"target": "ProtZ", "strength": 5},
    ]
    assert data["direct_interactions"] == expected_direct
    assert data["strongest_path_to_hub"] == "ProtA -> ProtD -> ProtHub"
    assert abs(data["rolling_avg_strength"] - 41.25) < 1e-5

    original_edges = decode_video(VIDEO)
    assert_graph_responses(original_edges)

    # Replace the input with a fresh, valid experiment so fixed responses or a
    # pre-populated database cannot pass. Expected answers are derived here.
    token = secrets.token_hex(2)
    a, b, c, d = [f"P{token}{suffix}" for suffix in "ABCD"]
    x, y, z = [f"P{token}{suffix}" for suffix in "XYZ"]
    strengths = [10 + secrets.randbelow(90) for _ in range(10)]
    challenge = [
        (a, b, strengths[0]), (b, c, strengths[1]),
        (a, d, strengths[2]), (c, "ProtHub", strengths[3]),
        (d, "ProtHub", strengths[4]), (x, y, strengths[5]),
        (y, a, strengths[6]), (b, "ProtHub", strengths[7]),
        (z, "ProtHub", strengths[8]), (a, z, strengths[9]),
    ]

    backup = "/tmp/original_experiment_run.mp4"
    subprocess.run(["cp", VIDEO, backup], check=True)
    try:
        stop_server()
        for db in ("/home/user/graph.db", "/home/user/graph.db-shm", "/home/user/graph.db-wal"):
            try:
                os.unlink(db)
            except FileNotFoundError:
                pass
        write_video(VIDEO, challenge)
        assert decode_video(VIDEO) == challenge
        start_artifact(a)
        assert_graph_responses(challenge)
    finally:
        subprocess.run(["cp", backup, VIDEO], check=True)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
