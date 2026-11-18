#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import signal
import subprocess
import time

import pytest
import requests

WIDTH = 320
HEIGHT = 240
FRAME_SIZE = WIDTH * HEIGHT * 3


def listening_pids(port=8080):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[3] == "0A" and fields[1].split(":")[-1].upper() == wanted:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    result = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    result.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return result


def wait_for_server(timeout=5):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.get("http://127.0.0.1:8080/data", timeout=0.5)
            if response.status_code == 200:
                return
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(0.1)
    pytest.fail(f"Server did not become ready: {last_error}")


def replace_symlink(link, target):
    temporary = link + ".verifier-swap"
    try:
        os.unlink(temporary)
    except FileNotFoundError:
        pass
    os.symlink(target, temporary)
    os.replace(temporary, link)


def test_project_data_extracted():
    path = "/home/user/assets/project_data.txt"
    assert os.path.exists(path), f"File missing: {path}"
    assert os.path.isfile(path), f"Not a file: {path}"
    with open(path, "r") as f:
        content = f.read()
    assert content == "LEGACY_PROJECT_IDENTIFIER_9942", f"Incorrect content in {path}"


def test_thumb_raw_exists():
    path = "/home/user/assets/thumb_raw.jpg"
    assert os.path.exists(path), f"File missing: {path}"
    assert os.path.isfile(path), f"Not a file: {path}"
    assert os.path.getsize(path) > 0, f"File is empty: {path}"

    with open(path, "rb") as f:
        encoded = f.read()
    assert encoded.startswith(b"\xff\xd8") and encoded.endswith(b"\xff\xd9"), "Thumbnail is not a JPEG file"

    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-count_frames", "-select_streams", "v:0",
         "-show_entries", "stream=codec_name,width,height,nb_read_frames", "-of", "json", path],
        check=True, capture_output=True, text=True,
    )
    streams = json.loads(probe.stdout).get("streams", [])
    assert len(streams) == 1, "Thumbnail must contain exactly one image stream"
    stream = streams[0]
    assert stream.get("codec_name") == "mjpeg", "Thumbnail is not JPEG-encoded"
    assert (stream.get("width"), stream.get("height")) == (WIDTH, HEIGHT), "Thumbnail has incorrect dimensions"
    assert stream.get("nb_read_frames") == "1", "Thumbnail must contain exactly one frame"

    decoded = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-frames:v", "1", "-pix_fmt", "rgb24", "-f", "rawvideo", "-"],
        check=True, capture_output=True,
    ).stdout
    assert len(decoded) == FRAME_SIZE, "Could not decode exactly one full thumbnail frame"

    with open("/tmp/demo.rgb", "rb") as f:
        video = f.read()
    assert len(video) % FRAME_SIZE == 0
    frames = [video[i:i + FRAME_SIZE] for i in range(0, len(video), FRAME_SIZE)]
    assert len(frames) > 30, "Reference video is unexpectedly short"

    errors = []
    for frame in frames:
        errors.append(sum(abs(a - b) for a, b in zip(decoded, frame)) / FRAME_SIZE)
    best_index = min(range(len(errors)), key=errors.__getitem__)
    assert best_index == 30, f"Thumbnail is closest to video frame {best_index / 10:.1f}s, not 3.0s"
    assert errors[30] < 10.0, f"Thumbnail does not accurately represent the frame at 3.0s (MAE {errors[30]:.2f})"


def test_symlink_exists():
    symlink_path = "/home/user/public/thumb.jpg"
    target_path = "/home/user/assets/thumb_raw.jpg"
    assert os.path.exists(symlink_path), f"Symlink missing: {symlink_path}"
    assert os.path.islink(symlink_path), f"Not a symlink: {symlink_path}"
    assert os.readlink(symlink_path) == target_path, f"Symlink points to wrong target: {os.readlink(symlink_path)}"


def test_server_data_endpoint():
    try:
        response = requests.get("http://127.0.0.1:8080/data", timeout=2)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to Go server at /data: {e}")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
    assert response.text == "LEGACY_PROJECT_IDENTIFIER_9942", f"Incorrect response body: {response.text}"


def test_server_video_thumb_endpoint():
    try:
        response = requests.get("http://127.0.0.1:8080/video-thumb", timeout=2)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to Go server at /video-thumb: {e}")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
    assert "image/jpeg" in response.headers.get("Content-Type", ""), f"Expected Content-Type image/jpeg, got {response.headers.get('Content-Type')}"

    thumb_path = "/home/user/assets/thumb_raw.jpg"
    assert os.path.exists(thumb_path), "Raw thumb image missing"
    with open(thumb_path, "rb") as f:
        expected_bytes = f.read()

    assert response.content == expected_bytes, "Response content does not match the actual thumb_raw.jpg file"


def test_running_listener_is_go_and_submitted_program_is_dynamic():
    pids = listening_pids()
    assert pids, "No process is listening on port 8080"
    assert any(
        subprocess.run(["go", "version", "-m", f"/proc/{pid}/exe"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
        for pid in pids
    ), "The process listening on port 8080 is not a Go executable"

    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while listening_pids() and time.time() < deadline:
        time.sleep(0.05)
    for pid in listening_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    subprocess.Popen(
        ["/tmp/submission_server"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    wait_for_server()

    data_path = "/home/user/assets/project_data.txt"
    link_path = "/home/user/public/thumb.jpg"
    original_data = open(data_path, "rb").read()
    original_target = os.readlink(link_path)
    token = f"VERIFIER_DYNAMIC_{secrets.token_hex(16)}".encode()

    try:
        with open(data_path, "wb") as f:
            f.write(token)
        response = requests.get("http://127.0.0.1:8080/data", timeout=2)
        assert response.status_code == 200
        assert response.content == token, "/data does not serve the actual project_data.txt contents"

        replace_symlink(link_path, "/tmp/alternate.jpg")
        with open("/tmp/alternate.jpg", "rb") as f:
            alternate = f.read()
        response = requests.get("http://127.0.0.1:8080/video-thumb", timeout=2)
        assert response.status_code == 200
        assert "image/jpeg" in response.headers.get("Content-Type", "")
        assert response.content == alternate, "/video-thumb does not resolve and serve the public symlink"
    finally:
        with open(data_path, "wb") as f:
            f.write(original_data)
        replace_symlink(link_path, original_target)

    response = requests.get("http://127.0.0.1:8080/data", timeout=2)
    assert response.content == original_data
    response = requests.get("http://127.0.0.1:8080/video-thumb", timeout=2)
    with open("/home/user/assets/thumb_raw.jpg", "rb") as f:
        assert response.content == f.read()
TEST_EOF

result=0
if test -f /home/user/server.go \
   && go build -o /tmp/submission_server /home/user/server.go \
   && ffmpeg -y -v error -i /app/demo.mp4 -pix_fmt rgb24 -f rawvideo /tmp/demo.rgb \
   && ffmpeg -y -v error -ss 00:00:04 -i /app/demo.mp4 -frames:v 1 /tmp/alternate.jpg \
   && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    result=1
fi

echo "$result" > /logs/verifier/reward.txt
