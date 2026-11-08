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
import glob
import json
import os
import secrets
import shutil
import socket
import stat
import subprocess
import time

import cv2
import numpy as np
import pytest
import requests

VIDEO = "/app/anomaly_feed.mp4"
FRAMES = "/home/user/extracted_frames"
SOCKET = "/home/user/backend.sock"
API = "http://127.0.0.1:8080/api/anomaly"
AUTH = {"Authorization": "Bearer syseng-secure-2024"}


def analyze_video(path):
    cap = cv2.VideoCapture(path)
    assert cap.isOpened(), f"Could not open video: {path}"
    frames = []
    scores = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frames.append(frame)
        b, g, r = frame.mean(axis=(0, 1))
        scores.append(float(r - max(g, b)))
    cap.release()
    assert frames, f"No frames decoded from {path}"
    anomaly = int(np.argmax(scores))
    b, g, r = frames[anomaly].mean(axis=(0, 1))
    assert r > 200 and g < 80 and b < 80, "Fixture has no clearly solid-red frame"
    return frames, anomaly


def nginx_get(path, headers=None, timeout=20):
    return requests.get("http://127.0.0.1:8080" + path, headers=headers, timeout=timeout)


def direct_backend_anomaly():
    result = subprocess.run(
        ["curl", "-sS", "--max-time", "20", "--unix-socket", SOCKET,
         "-w", "\\n%{http_code}", "http://localhost/api/anomaly"],
        text=True, capture_output=True, timeout=25
    )
    assert result.returncode == 0, f"Direct Unix-socket request failed: {result.stderr}"
    body, status = result.stdout.rsplit("\n", 1)
    assert status == "200", f"Backend returned HTTP {status} through Unix socket"
    try:
        data = json.loads(body)
    except ValueError:
        pytest.fail(f"Backend did not return JSON through Unix socket: {body!r}")
    assert isinstance(data.get("anomaly_frame"), int), data
    return data["anomaly_frame"]


def test_directories_and_symlinks():
    extracted_frames_dir = "/home/user/extracted_frames"
    web_root_dir = "/home/user/web_root"
    media_symlink = "/home/user/web_root/media"

    assert os.path.isdir(extracted_frames_dir), f"Directory not found: {extracted_frames_dir}"
    assert os.path.isdir(web_root_dir), f"Directory not found: {web_root_dir}"
    assert os.path.islink(media_symlink), f"Symlink not found: {media_symlink}"
    assert os.readlink(media_symlink).rstrip('/') == extracted_frames_dir.rstrip('/'), \
        f"Symlink {media_symlink} does not point to {extracted_frames_dir}"


def test_nginx_and_unix_socket_are_real_services():
    assert os.path.isfile("/home/user/nginx.conf"), "Missing /home/user/nginx.conf"
    config = open("/home/user/nginx.conf", encoding="utf-8").read()
    assert "/home/user/backend.sock" in config
    assert "127.0.0.1:8080" in config or "127.0.0.1 8080" in config
    assert "/home/user/nginx_temp/" in config, "Nginx paths were not moved under nginx_temp"
    assert "syseng-secure-2024" in config

    mode = os.stat(SOCKET).st_mode
    assert stat.S_ISSOCK(mode), f"{SOCKET} is not a Unix socket"
    assert os.stat(SOCKET).st_uid != 0, "Backend socket is owned by root"

    # Identify the process that actually owns the listening TCP socket.
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        if not os.path.exists(table):
            continue
        for line in open(table).read().splitlines()[1:]:
            fields = line.split()
            if fields[3] == "0A" and int(fields[1].split(":")[-1], 16) == 8080:
                inodes.add(fields[9])
    assert inodes, "Nothing is listening on TCP port 8080"

    owners = []
    for procdir in glob.glob("/proc/[0-9]*"):
        pid = os.path.basename(procdir)
        try:
            links = [os.readlink(fd) for fd in glob.glob(procdir + "/fd/*")]
            if any(link.startswith("socket:[") and link[8:-1] in inodes for link in links):
                cmd = open(procdir + "/cmdline", "rb").read().replace(b"\0", b" ").decode(errors="replace")
                uid = int(open(procdir + "/status").read().split("Uid:", 1)[1].split()[0])
                owners.append((cmd, uid))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    assert owners, "Could not identify the process listening on port 8080"
    assert any("nginx" in cmd.lower() for cmd, _ in owners), f"Port 8080 is not owned by Nginx: {owners}"
    assert all(uid != 0 for _, uid in owners), f"Nginx listener is running as root: {owners}"

    # The backend must itself answer through the required Unix socket.
    assert isinstance(direct_backend_anomaly(), int)


def test_api_anomaly_unauthorized():
    try:
        response = requests.get(API, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to Nginx on 127.0.0.1:8080: {e}")
    assert response.status_code == 403, \
        f"Expected HTTP 403 Forbidden without auth, got {response.status_code}"

    for value in ("syseng-secure-2024", "Bearer wrong", "bearer syseng-secure-2024"):
        response = requests.get(API, headers={"Authorization": value}, timeout=5)
        assert response.status_code == 403, f"Invalid Authorization value {value!r} was accepted"


def test_api_anomaly_authorized_and_derived_from_fixture():
    _, expected = analyze_video(VIDEO)
    assert expected == 142, f"Unexpected supplied fixture anomaly frame: {expected}"
    try:
        response = requests.get(API, headers=AUTH, timeout=20)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to Nginx on 127.0.0.1:8080: {e}")
    assert response.status_code == 200, f"Expected HTTP 200 OK with auth, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response, got: {response.text}")
    assert "anomaly_frame" in data, "Response JSON missing 'anomaly_frame' key"
    assert data["anomaly_frame"] == expected, \
        f"Expected anomaly_frame to be {expected}, got {data['anomaly_frame']}"


def test_all_frames_were_extracted_and_match_video():
    video_frames, anomaly = analyze_video(VIDEO)
    expected_paths = [os.path.join(FRAMES, f"frame_{i:04d}.jpg") for i in range(len(video_frames))]
    missing = [p for p in expected_paths if not os.path.isfile(p)]
    assert not missing, f"Missing extracted frames, first few: {missing[:5]}"

    for i, (path, source) in enumerate(zip(expected_paths, video_frames)):
        raw = open(path, "rb").read()
        assert raw.startswith(b"\xff\xd8"), f"Extracted frame is not JPEG: {path}"
        decoded = cv2.imdecode(np.frombuffer(raw, dtype=np.uint8), cv2.IMREAD_COLOR)
        assert decoded is not None, f"Invalid JPEG data: {path}"
        assert decoded.shape == source.shape, f"Wrong dimensions for {path}"
        mae = float(np.mean(np.abs(decoded.astype(np.int16) - source.astype(np.int16))))
        assert mae < 25.0, f"{path} does not correspond to video frame {i} (MAE {mae:.2f})"

    anomaly_image = cv2.imread(expected_paths[anomaly])
    b, g, r = anomaly_image.mean(axis=(0, 1))
    assert r > 200 and g < 80 and b < 80, "Extracted anomaly frame is not solid red"


def test_static_frame_serving():
    url = "http://127.0.0.1:8080/static/frame_0142.jpg"
    try:
        response = requests.get(url, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to Nginx on 127.0.0.1:8080: {e}")
    assert response.status_code == 200, f"Expected HTTP 200 OK for {url}, got {response.status_code}"
    assert response.headers.get("Content-Type", "").startswith("image/jpeg"), \
        "Expected Content-Type to be image/jpeg"
    assert response.content.startswith(b'\xff\xd8'), "Served file is not a valid JPEG image"
    assert response.content == open(f"{FRAMES}/frame_0142.jpg", "rb").read(), \
        "Nginx did not serve the extracted frame"

    total = len(analyze_video(VIDEO)[0])
    indices = {0, total - 1, secrets.randbelow(total), secrets.randbelow(total)}
    for i in indices:
        response = nginx_get(f"/static/frame_{i:04d}.jpg")
        assert response.status_code == 200, f"Static frame {i} returned {response.status_code}"
        assert response.content == open(f"{FRAMES}/frame_{i:04d}.jpg", "rb").read(), \
            f"Static response for frame {i} differs from extracted file"


def make_dynamic_fixture(path, anomaly, frame_count=8):
    vf = f"drawbox=x=0:y=0:w=iw:h=ih:color=red:t=fill:enable=eq(n\\,{anomaly})"
    result = subprocess.run([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-f", "lavfi", "-i", f"color=c=blue:s=160x120:r=8:d={frame_count / 8}",
        "-vf", vf, "-frames:v", str(frame_count), "-c:v", "libx264",
        "-pix_fmt", "yuv420p", path
    ], capture_output=True, text=True, timeout=20)
    assert result.returncode == 0, f"Could not generate verifier fixture: {result.stderr}"
    _, derived = analyze_video(path)
    assert derived == anomaly


def test_backend_actually_analyzes_current_video():
    backup = VIDEO + ".verifier-backup"
    assert not os.path.exists(backup), f"Unexpected backup path exists: {backup}"
    os.replace(VIDEO, backup)
    try:
        first = 1 + secrets.randbelow(3)
        second = 4 + secrets.randbelow(3)
        for expected in (first, second):
            tmp = VIDEO + ".new.mp4"
            make_dynamic_fixture(tmp, expected)
            os.replace(tmp, VIDEO)
            time.sleep(0.15)

            direct = direct_backend_anomaly()
            assert direct == expected, \
                f"Unix-socket backend returned {direct} for a video whose anomaly is {expected}"

            response = requests.get(API, headers=AUTH, timeout=20)
            assert response.status_code == 200
            data = response.json()
            assert data.get("anomaly_frame") == expected, \
                f"Proxied API returned {data} for a video whose anomaly is {expected}"
    finally:
        for path in (VIDEO, VIDEO + ".new.mp4"):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
        os.replace(backup, VIDEO)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
