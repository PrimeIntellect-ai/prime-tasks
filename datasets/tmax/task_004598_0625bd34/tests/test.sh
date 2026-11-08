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
import os
import random
import signal
import subprocess
import time
from pathlib import Path

import cv2
import numpy as np
import pytest
import qrcode
import requests
from rdflib import Graph, Namespace

URL = "http://127.0.0.1:9090/unauthorized"
ORG = Namespace("http://example.org/org#")


def request_json():
    response = None
    for i in range(5):
        try:
            response = requests.get(URL, timeout=2)
            break
        except requests.exceptions.RequestException:
            if i < 4:
                time.sleep(1)
            else:
                pytest.fail(
                    f"Failed to connect to the server at {URL}. Ensure the server is running on 0.0.0.0:9090."
                )

    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. "
        f"Response body: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response body is not valid JSON. Response body: {response.text}")
    assert isinstance(data, list), f"Expected a JSON array, got {type(data).__name__}"
    return data


def listening_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[3] == "0A":
                local_port = int(fields[1].rsplit(":", 1)[1], 16)
                if local_port == port:
                    inodes.add(fields[9])

    result = []
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                target = os.readlink(fd)
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    result.append(int(proc.name))
                    break
        except (OSError, PermissionError):
            pass
    return sorted(set(result))


def snapshot_server_process():
    pids = listening_pids(9090)
    assert pids, "No process is listening on TCP port 9090"
    pid = pids[0]
    try:
        raw_argv = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
        argv = [x.decode("utf-8", "surrogateescape") for x in raw_argv if x]
        cwd = os.readlink(f"/proc/{pid}/cwd")
        executable = os.readlink(f"/proc/{pid}/exe")
        env = {}
        for item in Path(f"/proc/{pid}/environ").read_bytes().split(b"\0"):
            if b"=" in item:
                key, value = item.split(b"=", 1)
                env[key.decode("utf-8", "surrogateescape")] = value.decode(
                    "utf-8", "surrogateescape"
                )
    except OSError as exc:
        pytest.fail(f"Could not inspect the running server process: {exc}")
    assert argv, "The server process has no restartable command line"
    env.pop("LISTEN_PID", None)
    env.pop("LISTEN_FDS", None)
    return argv, cwd, executable, env


def stop_server():
    pids = listening_pids(9090)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listening_pids(9090):
        time.sleep(0.1)
    for pid in listening_pids(9090):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listening_pids(9090):
        time.sleep(0.1)
    assert not listening_pids(9090), "Could not stop the original server"


def make_random_fixtures():
    rng = random.SystemRandom()
    ids = set()
    while len(ids) < 8:
        ids.add(f"EMP{rng.randrange(100000, 1000000)}")
    admin, transitive, unauthorized_user, unauthorized_missing, unauthorized_cycle, manager, user_boss, cycle_peer = list(ids)

    ttl = f'''@prefix org: <http://example.org/org#> .
org:{admin} org:hasRole org:Admin .
org:{transitive} org:reportsTo org:{manager} .
org:{manager} org:reportsTo org:{admin} .
org:{unauthorized_user} org:reportsTo org:{user_boss} .
org:{user_boss} org:hasRole org:User .
org:{unauthorized_cycle} org:reportsTo org:{cycle_peer} .
org:{cycle_peer} org:reportsTo org:{unauthorized_cycle} .
'''
    graph_tmp = Path("/app/.verifier_org_graph.ttl")
    graph_tmp.write_text(ttl)
    os.replace(graph_tmp, "/app/org_graph.ttl")

    entries = [admin, unauthorized_user, transitive, unauthorized_missing, unauthorized_cycle, unauthorized_user]
    width, height, fps = 640, 480, 15
    video_tmp = "/app/.verifier_entry_log.mp4"
    writer = cv2.VideoWriter(video_tmp, cv2.VideoWriter_fourcc(*"mp4v"), fps, (width, height))
    assert writer.isOpened(), "Verifier could not create the randomized video fixture"
    for employee_id in entries:
        qr = qrcode.QRCode(version=None, box_size=10, border=4)
        qr.add_data(employee_id)
        qr.make(fit=True)
        qr_image = np.array(qr.make_image(fill_color="black", back_color="white").convert("RGB"))
        frame = np.full((height, width, 3), 255, dtype=np.uint8)
        qr_h, qr_w, _ = qr_image.shape
        y = (height - qr_h) // 2
        x = (width - qr_w) // 2
        frame[y:y + qr_h, x:x + qr_w] = qr_image
        for _ in range(fps):
            writer.write(frame)
    writer.release()
    os.replace(video_tmp, "/app/entry_log.mp4")
    return set(entries)


def decode_video(path):
    capture = cv2.VideoCapture(path)
    assert capture.isOpened(), "Could not open randomized entry video"
    detector = cv2.QRCodeDetector()
    decoded = set()
    while True:
        ok, frame = capture.read()
        if not ok:
            break
        value, _, _ = detector.detectAndDecode(frame)
        if value:
            decoded.add(value)
    capture.release()
    return decoded


def derive_expected(employee_ids, graph_path):
    graph = Graph()
    graph.parse(graph_path, format="turtle")

    def authorized(employee_id):
        start = ORG[employee_id]
        stack = [start]
        visited = set()
        while stack:
            person = stack.pop()
            if person in visited:
                continue
            visited.add(person)
            if (person, ORG.hasRole, ORG.Admin) in graph:
                return True
            stack.extend(graph.objects(person, ORG.reportsTo))
        return False

    return sorted(employee_id for employee_id in employee_ids if not authorized(employee_id))


def test_unauthorized_endpoint():
    # Preserve the original endpoint and fixed-fixture assertions.
    data = request_json()
    expected_data = ["EMP007", "EMP042"]
    assert sorted(data) == expected_data, f"Expected {expected_data}, got {data}"

    argv, cwd, executable, env = snapshot_server_process()
    intended_entries = make_random_fixtures()
    decoded_entries = decode_video("/app/entry_log.mp4")
    assert decoded_entries == intended_entries, (
        f"Verifier QR generation/decoding mismatch: expected {intended_entries}, decoded {decoded_entries}"
    )
    expected_randomized = derive_expected(decoded_entries, "/app/org_graph.ttl")

    stop_server()
    try:
        subprocess.Popen(
            argv,
            executable=executable,
            cwd=cwd,
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError as exc:
        pytest.fail(f"Could not restart the submitted server command: {exc}")

    randomized_data = request_json()
    assert all(isinstance(item, str) for item in randomized_data), "Every array element must be a string"
    assert randomized_data == sorted(randomized_data), "The response array must be sorted alphabetically"
    assert randomized_data == expected_randomized, (
        f"Expected {expected_randomized} for randomized video and graph inputs, got {randomized_data}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
