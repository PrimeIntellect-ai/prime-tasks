#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import json
import os
import shutil
import socket
import subprocess
import time

import pytest

APP = "/home/user/app"
VIDEO = "/app/ui_test.mp4"


def recv_exact(s, n):
    out = b""
    while len(out) < n:
        chunk = s.recv(n - len(out))
        if not chunk:
            raise AssertionError("Connection closed while receiving WebSocket frame")
        out += chunk
    return out


def get_websocket_data(host, port, path):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(15.0)
    try:
        s.connect((host, port))
        key = base64.b64encode(os.urandom(16)).decode()
        req = (
            f"GET {path} HTTP/1.1\r\nHost: {host}:{port}\r\n"
            "Upgrade: websocket\r\nConnection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
        )
        s.sendall(req.encode())
        resp = b""
        while b"\r\n\r\n" not in resp:
            resp += recv_exact(s, 1)
        assert b"101 Switching Protocols" in resp, f"WebSocket handshake failed: {resp[:200]}"

        head = recv_exact(s, 2)
        assert (head[0] & 0x0f) == 1, "Server did not send a WebSocket text message"
        length = head[1] & 0x7f
        if length == 126:
            length = int.from_bytes(recv_exact(s, 2), "big")
        elif length == 127:
            length = int.from_bytes(recv_exact(s, 8), "big")
        if head[1] & 0x80:
            mask = recv_exact(s, 4)
            payload = bytes(v ^ mask[i % 4] for i, v in enumerate(recv_exact(s, length)))
        else:
            payload = recv_exact(s, length)
        return payload.decode()
    finally:
        s.close()


def expected_from_video():
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
         "stream=width,height", "-of", "json", VIDEO],
        check=True, capture_output=True, text=True)
    stream = json.loads(probe.stdout)["streams"][0]
    width, height = int(stream["width"]), int(stream["height"])
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", VIDEO, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        check=True, capture_output=True).stdout
    frame_size = width * height * 3
    assert frame_size and len(raw) % frame_size == 0

    def color_state(r, g, b):
        if r > 150 and g > 150 and b > 150: return 0
        if b > 150 and r < 100 and g < 100: return 1
        if g > 150 and r < 100 and b < 100: return 2
        return -1

    states = []
    offset = ((height // 2) * width + width // 2) * 3
    for pos in range(0, len(raw), frame_size):
        r, g, b = raw[pos + offset:pos + offset + 3]
        states.append(color_state(r, g, b))
    return states


def parse_prediction(message, total_frames):
    data = json.loads(message)
    assert isinstance(data, list), "WebSocket JSON must be an array"
    pred = [-1] * total_frames
    for event in data:
        assert isinstance(event, dict), f"Invalid event: {event!r}"
        for key in ("state", "start_frame", "end_frame"):
            assert key in event, f"Invalid JSON object format, missing {key}: {event}"
            assert type(event[key]) is int, f"{key} must be an integer"
        state, start, end = event["state"], event["start_frame"], event["end_frame"]
        assert state in (0, 1, 2), f"Invalid state {state}"
        assert 0 <= start <= end < total_frames, f"Invalid frame range {start}..{end}"
        for i in range(start, end + 1):
            pred[i] = state
    return pred


def test_build_native_linkage_and_dynamic_video():
    assert os.path.isfile(os.path.join(APP, "go.mod"))
    assert os.path.isfile(os.path.join(APP, "lib", "color.h"))
    assert os.path.isfile(os.path.join(APP, "lib", "libcolor.so"))

    subprocess.run(["go", "clean", "-cache"], cwd=APP, check=True)
    subprocess.run(["go", "build", "-o", "/tmp/submission-server", "."], cwd=APP, check=True,
                   env={**os.environ, "CGO_ENABLED": "1"})
    dynamic = subprocess.run(["readelf", "-d", "/tmp/submission-server"], check=True,
                             capture_output=True, text=True).stdout
    assert "libcolor.so" in dynamic, "Built server does not dynamically link the required C library"

    backup = "/tmp/ui_test.original.mp4"
    shutil.copy2(VIDEO, backup)
    # Create a fresh, non-fixture sequence after the agent has finished. Its timings
    # are intentionally generated here and expected values are derived from pixels.
    segments = [("0x32C832", 29), ("0xC8C8C8", 17), ("0x3232C8", 41), ("0x32C832", 13)]
    parts = []
    try:
        for i, (color, frames) in enumerate(segments):
            part = f"/tmp/verify_part_{i}.mkv"
            subprocess.run([
                "ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i",
                f"color=c={color}:s=100x100:r=24", "-frames:v", str(frames),
                "-c:v", "ffv1", part], check=True)
            parts.append(part)
        with open("/tmp/verify_concat.txt", "w") as f:
            for part in parts:
                f.write(f"file '{part}'\n")
        subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0",
                        "-i", "/tmp/verify_concat.txt", "-c", "copy", VIDEO], check=True)

        expected = expected_from_video()
        env = {**os.environ, "LD_LIBRARY_PATH": os.path.join(APP, "lib") + ":" + os.environ.get("LD_LIBRARY_PATH", "")}
        server = subprocess.Popen(["/tmp/submission-server"], cwd=APP, env=env,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            message = None
            last_error = None
            for _ in range(40):
                if server.poll() is not None:
                    out, err = server.communicate()
                    pytest.fail(f"Built server exited early: {out.decode()} {err.decode()}")
                try:
                    message = get_websocket_data("127.0.0.1", 8080, "/ws")
                    break
                except Exception as exc:
                    last_error = exc
                    time.sleep(0.25)
            assert message is not None, f"Could not connect to built server: {last_error}"
            pred = parse_prediction(message, len(expected))
            accuracy = sum(a == b and a != -1 for a, b in zip(expected, pred)) / len(expected)
            assert accuracy >= 0.95, f"Frame overlap accuracy is {accuracy:.4f}, below 0.95"
        finally:
            server.terminate()
            try:
                server.wait(timeout=3)
            except subprocess.TimeoutExpired:
                server.kill()
    finally:
        shutil.move(backup, VIDEO)
        for part in parts:
            if os.path.exists(part): os.remove(part)

TEST_EOF

# Stop any fixed-response server left by the agent, then test a clean build of the submission.
fuser -k 8080/tcp >/dev/null 2>&1 || true
if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
