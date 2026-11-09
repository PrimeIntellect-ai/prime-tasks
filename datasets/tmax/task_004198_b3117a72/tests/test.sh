#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import pathlib
import random
import re
import signal
import subprocess
import time

import pytest
import requests


def test_cleaned_detections_csv():
    path = "/home/user/cleaned_detections.csv"
    assert os.path.isfile(path), f"Missing required file: {path}"

    with open(path, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "Cleaned CSV is empty"
    header = rows[0]
    expected_header = ["frame_id", "object_id", "x", "y", "w", "h", "area"]
    assert header == expected_header, f"Expected header {expected_header}, got {header}"

    data_rows = rows[1:]
    assert len(data_rows) == 3, f"Expected 3 data rows, got {len(data_rows)}"
    assert data_rows[0] == ["1", "101", "10", "10", "50", "50", "2500"], "Row 1 mismatch"
    assert data_rows[1] == ["3", "102", "5", "5", "10", "10", "100"], "Row 2 mismatch"
    assert data_rows[2] == ["12", "101", "15", "15", "50", "60", "3000"], "Row 3 mismatch"


def _video_properties(path):
    out = subprocess.check_output([
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "stream=width,height:format=duration",
        "-of", "json", path
    ], text=True)
    info = json.loads(out)
    stream = info["streams"][0]
    return int(stream["width"]), int(stream["height"]), float(info["format"]["duration"])


def test_experiments_log():
    path = "/home/user/experiments.log"
    assert os.path.isfile(path), f"Missing required file: {path}"
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    # Retain the original assertion.
    assert "Total Frames: 10" in content, f"Expected 'Total Frames: 10' in {path}, got:\n{content}"

    width, height, duration = _video_properties("/app/traffic.mp4")
    expected_count = int(math.ceil(duration - 1e-6))
    logged = [int(v) for v in re.findall(r"Total Frames:\s*(\d+)", content)]
    assert expected_count in logged, f"No log entry reports the derived frame count {expected_count}"

    image_exts = {".jpg", ".jpeg", ".png", ".bmp", ".webp", ".ppm"}
    candidates = []
    for root in ("/home/user", "/app", "/tmp"):
        for p in pathlib.Path(root).rglob("*"):
            if p.is_file() and p.suffix.lower() in image_exts and "/tmp/pytest" not in str(p):
                candidates.append(str(p))

    valid_hashes = set()
    valid_files = []
    for candidate in candidates:
        try:
            probe = subprocess.run([
                "ffprobe", "-v", "error", "-select_streams", "v:0",
                "-show_entries", "stream=width,height", "-of", "csv=p=0",
                candidate
            ], capture_output=True, text=True, timeout=4)
            if probe.returncode != 0 or probe.stdout.strip() != f"{width},{height}":
                continue
            decoded = subprocess.run([
                "ffmpeg", "-v", "error", "-i", candidate,
                "-frames:v", "1", "-f", "md5", "-"
            ], capture_output=True, text=True, timeout=5)
            assert decoded.returncode == 0
            digest = decoded.stdout.strip()
            if digest:
                valid_files.append(candidate)
                valid_hashes.add(digest)
        except (OSError, subprocess.SubprocessError, AssertionError):
            continue

    assert len(valid_files) >= expected_count, (
        f"Expected at least {expected_count} extracted, decodable {width}x{height} frames; "
        f"found {len(valid_files)}"
    )
    assert len(valid_hashes) >= expected_count, "Extracted frames are not distinct video frames"


def test_api_area_endpoint():
    url = "http://127.0.0.1:8080/area"
    resp1 = requests.get(url, params={"object_id": "101"}, timeout=5)
    assert resp1.status_code == 200, f"Expected 200 OK, got {resp1.status_code}"
    assert resp1.text.strip() == "5500", f"Expected '5500', got '{resp1.text}'"

    resp2 = requests.get(url, params={"object_id": "102"}, timeout=5)
    assert resp2.status_code == 200, f"Expected 200 OK, got {resp2.status_code}"
    assert resp2.text.strip() == "100", f"Expected '100', got '{resp2.text}'"


def test_api_secure_stats_endpoint():
    url = "http://127.0.0.1:8080/secure_stats"
    resp_no_auth = requests.get(url, timeout=5)
    assert resp_no_auth.status_code == 401, f"Expected 401 Unauthorized, got {resp_no_auth.status_code}"

    headers = {"Authorization": "Bearer ds_token_2024"}
    resp_auth = requests.get(url, headers=headers, timeout=5)
    assert resp_auth.status_code == 200, f"Expected 200 OK, got {resp_auth.status_code}"
    try:
        data = resp_auth.json()
    except ValueError:
        pytest.fail(f"Expected JSON response, got '{resp_auth.text}'")
    assert data == {"status": "ok"}, f"Expected {{'status': 'ok'}}, got {data}"


def _listener_processes(port):
    inodes = set()
    port_hex = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table, encoding="ascii").read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if fields[1].split(":")[-1].upper() == port_hex and fields[3] == "0A":
                inodes.add(fields[9])
    result = []
    for proc in pathlib.Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                target = os.readlink(fd)
                m = re.fullmatch(r"socket:\[(\d+)\]", target)
                if m and m.group(1) in inodes:
                    result.append(int(proc.name))
                    break
        except OSError:
            pass
    return result


def _capture_server():
    pids = _listener_processes(8080)
    assert pids, "No process is listening on port 8080"
    pid = pids[0]
    raw_argv = open(f"/proc/{pid}/cmdline", "rb").read().split(b"\0")
    argv = [v.decode(errors="surrogateescape") for v in raw_argv if v]
    cwd = os.readlink(f"/proc/{pid}/cwd")
    env = os.environ.copy()
    try:
        for item in open(f"/proc/{pid}/environ", "rb").read().split(b"\0"):
            if b"=" in item:
                k, v = item.split(b"=", 1)
                env[k.decode(errors="ignore")] = v.decode(errors="surrogateescape")
    except OSError:
        pass
    return argv, cwd, env


def _restart_server(server):
    argv, cwd, env = server
    assert argv, "Could not determine server command"
    for pid in _listener_processes(8080):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while _listener_processes(8080) and time.time() < deadline:
        time.sleep(0.1)
    for pid in _listener_processes(8080):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    subprocess.Popen(argv, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)
    deadline = time.time() + 8
    while time.time() < deadline:
        try:
            requests.get("http://127.0.0.1:8080/secure_stats", timeout=0.5)
            return
        except requests.RequestException:
            time.sleep(0.2)
    pytest.fail("Server did not restart on port 8080")


def test_real_cleaning_script_and_general_area_api():
    server = _capture_server()
    source = "/app/detections.csv"
    output = "/home/user/cleaned_detections.csv"
    nonce = random.SystemRandom().randint(20000, 90000)
    oid = nonce
    other = nonce + 1
    fixture = (
        "frame_id,object_id,x,y,w,h\n"
        f"{nonce + 10}.0,{oid}.0,7,8,13,17\n"
        f"{nonce + 11}.0,NaN,1,2,3,4\n"
        f"NA,{oid}.0,1,2,3,4\n"
        f"{nonce + 12}.0,{oid}.0,9,10,19,23\n"
        f"{nonce + 13}.0,,1,2,3,4\n"
        f"{nonce + 14}.0,{other}.0,2,3,29,31\n"
    )
    expected = [
        [str(nonce + 10), str(oid), "7", "8", "13", "17", str(13 * 17)],
        [str(nonce + 12), str(oid), "9", "10", "19", "23", str(19 * 23)],
        [str(nonce + 14), str(other), "2", "3", "29", "31", str(29 * 31)],
    ]

    scripts = []
    for root in (pathlib.Path("/home/user"), pathlib.Path("/app")):
        for p in root.rglob("*"):
            if not p.is_file() or p == pathlib.Path(source):
                continue
            try:
                text = p.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError):
                continue
            if ("detections.csv" in text and "cleaned_detections.csv" in text
                    and re.search(r"\b(?:g?awk|sed|cut|tr|paste|join)\b", text)):
                scripts.append((p, text))
    assert scripts, "No Bash/Unix cleaning pipeline script was found"

    matched = None
    for script, text in scripts:
        pathlib.Path(source).write_text(fixture, encoding="utf-8")
        try:
            os.remove(output)
        except FileNotFoundError:
            pass
        run = subprocess.run(["/bin/bash", str(script)], cwd=str(script.parent),
                             capture_output=True, text=True, timeout=15)
        if run.returncode != 0 or not os.path.isfile(output):
            continue
        try:
            with open(output, newline="", encoding="utf-8") as f:
                rows = list(csv.reader(f))
        except Exception:
            continue
        if rows == [["frame_id", "object_id", "x", "y", "w", "h", "area"]] + expected:
            matched = script
            break
    assert matched is not None, "No submitted Bash/Unix cleaning script correctly handled a runtime-generated dataset"

    expected_sum = 13 * 17 + 19 * 23
    url = "http://127.0.0.1:8080/area"
    try:
        response = requests.get(url, params={"object_id": str(oid)}, timeout=3)
    except requests.RequestException:
        response = None
    if response is None or response.status_code != 200 or response.text.strip() != str(expected_sum):
        _restart_server(server)
        response = requests.get(url, params={"object_id": str(oid)}, timeout=5)
    assert response.status_code == 200, f"Expected 200 OK for generated object ID, got {response.status_code}"
    assert response.text.strip() == str(expected_sum), (
        f"Expected generated aggregate {expected_sum}, got {response.text!r}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
