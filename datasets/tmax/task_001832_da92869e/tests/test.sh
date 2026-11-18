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
import importlib.util
import json
import os
import random
import signal
import socket
import sqlite3
import subprocess
import time

import pytest
import requests

API_URL = "http://localhost:8080/api/stats"
AUTH_URL = API_URL + "?auth=vision2024"
EXPECTED = {
    "status": "success",
    "data": {"northbound": 42, "southbound": 17},
}


def get(url):
    try:
        return requests.get(url, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("API service is not running or not listening on port 8080.")
    except requests.exceptions.Timeout:
        pytest.fail("API request timed out.")


def assert_json_response(response, expected):
    assert response.status_code == 200, (
        f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"API did not return valid JSON. Response: {response.text}")
    assert data == expected, f"API returned incorrect data. Expected {expected}, got {data}"


def test_api_unauthorized():
    response = get(API_URL)
    assert response.status_code == 401, (
        f"Expected 401 Unauthorized, got {response.status_code}. Response: {response.text}"
    )


def test_api_stats_correct():
    assert_json_response(get(AUTH_URL), EXPECTED)


def reference_intersect(p):
    x1, y1, x2, y2, x3, y3, x4, y4 = p
    den = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
    if den == 0:
        return False
    t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / den
    u = -((x1 - x2) * (y1 - y3) - (y1 - y2) * (x1 - x3)) / den
    return 0 <= t <= 1 and 0 <= u <= 1


def load_detector():
    path = "/home/user/vision_engine/detector.py"
    assert os.path.isfile(path), f"Missing required detector: {path}"
    spec = importlib.util.spec_from_file_location("submitted_detector", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_build_detector_and_video_processing():
    build = "/home/user/vision_engine/build.sh"
    assert os.path.isfile(build), f"Missing required build script: {build}"
    result = subprocess.run(
        ["bash", build],
        cwd="/home/user/vision_engine",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
    )
    assert result.returncode == 0, f"build.sh failed:\n{result.stdout}"
    venv_python = "/home/user/vision_engine/venv/bin/python"
    assert os.path.isfile(venv_python), "build.sh did not create a usable virtual environment"
    probe = subprocess.run(
        [venv_python, "-c", "import sqlite3"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    assert probe.returncode == 0, f"Built environment is unusable:\n{probe.stdout}"

    detector = load_detector()
    assert callable(getattr(detector, "intersect", None)), "detector.py lacks intersect()"

    cases = [
        (100, 400, 100, 200, 0, 300, 640, 300),
        (200, 200, 200, 400, 0, 300, 640, 300),
        (0, 0, 2, 2, 0, 2, 2, 0),
        (0, 0, 1, 0, 2, -1, 2, 1),
        (0, 0, 10, 0, 0, 2, 10, 2),
    ]
    rng = random.Random(934751)
    while len(cases) < 105:
        p = tuple(rng.randint(-100, 100) for _ in range(8))
        den = (p[0] - p[2]) * (p[5] - p[7]) - (p[1] - p[3]) * (p[4] - p[6])
        if den != 0:
            cases.append(p)
    for p in cases:
        actual = detector.intersect(*p)
        expected = reference_intersect(p)
        assert actual == expected, f"Incorrect line intersection result for {p}: {actual} != {expected}"

    video = "/app/traffic_cam_04.mp4"
    assert os.path.isfile(video), f"Missing supplied video: {video}"
    run = subprocess.run(
        [venv_python, "/home/user/vision_engine/detector.py"],
        cwd="/home/user/vision_engine",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert run.returncode == 0, f"Video processing failed:\n{run.stdout}"

    db_path = "/home/user/data/traffic.db"
    assert os.path.isfile(db_path), "Video processing did not create traffic.db"
    with sqlite3.connect(db_path) as db:
        rows = dict(db.execute(
            "SELECT direction, COUNT(id) FROM crossings GROUP BY direction"
        ).fetchall())
    assert rows == {"northbound": 42, "southbound": 17}, (
        f"Processed database has incorrect crossing counts: {rows}"
    )


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        local_port = int(fields[1].rsplit(":", 1)[1], 16)
                        if local_port == port:
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
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except OSError:
            continue
    return pids


def stop_port(port):
    for sig in (signal.SIGTERM, signal.SIGKILL):
        pids = listener_pids(port)
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        deadline = time.time() + 4
        while time.time() < deadline and listener_pids(port):
            time.sleep(0.1)
    assert not listener_pids(port), f"Could not stop existing listener on port {port}"


def wait_for_api(timeout=15):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.get(AUTH_URL, timeout=1)
            if response.status_code in (200, 401, 500):
                return response
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(0.2)
    pytest.fail(f"server.js did not start on port 8080: {last_error}")


def test_server_artifact_queries_database_dynamically():
    server = "/home/user/api_service/server.js"
    assert os.path.isfile(server), f"Missing required API implementation: {server}"

    stop_port(8080)
    log = open("/tmp/submitted_server.log", "w")
    subprocess.Popen(
        ["node", server],
        cwd="/home/user/api_service",
        stdout=log,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    wait_for_api()

    unauthorized = get(API_URL)
    assert unauthorized.status_code == 401, (
        f"Expected 401 Unauthorized, got {unauthorized.status_code}. Response: {unauthorized.text}"
    )
    assert_json_response(get(AUTH_URL), EXPECTED)

    rng = random.SystemRandom()
    north = rng.randint(3, 14)
    south = rng.randint(19, 35)
    while (north, south) == (42, 17):
        north = rng.randint(3, 14)
        south = rng.randint(19, 35)

    db_path = "/home/user/data/traffic.db"
    with sqlite3.connect(db_path) as db:
        db.execute("DELETE FROM crossings")
        db.executemany(
            "INSERT INTO crossings (id, direction) VALUES (?, ?)",
            [(f"verify_n_{i}", "northbound") for i in range(north)]
            + [(f"verify_s_{i}", "southbound") for i in range(south)],
        )
        db.commit()

    dynamic_expected = {
        "status": "success",
        "data": {"northbound": north, "southbound": south},
    }
    assert_json_response(get(AUTH_URL), dynamic_expected)

    detector = load_detector()
    detector.process_video("/app/traffic_cam_04.mp4")
    assert_json_response(get(AUTH_URL), EXPECTED)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
