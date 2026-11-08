#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import json
import os
import random
import shutil
import signal
import socket
import struct
import subprocess
import time
import traceback
import uuid
from pathlib import Path

HOST = "127.0.0.1"
PORT = 9001
PROJECT = Path("/home/user/ci_analyzer")
VIDEO = Path("/app/ci_test_recording.mp4")
BACKUP = Path("/tmp/ci_test_recording.original.mp4")


def stop_listener():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[3] == "0A":
                try:
                    port = int(fields[1].rsplit(":", 1)[1], 16)
                except ValueError:
                    continue
                if port == PORT:
                    inodes.add(fields[9])

    pids = set()
    for proc in Path("/proc").glob("[0-9]*"):
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(proc.name))
                    break
        except OSError:
            pass

    for sig in (signal.SIGTERM, signal.SIGKILL):
        for pid in list(pids):
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        time.sleep(0.5)


def wait_for_server(proc, timeout=30):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc.poll() is not None:
            raise AssertionError(f"Rust service exited early with status {proc.returncode}")
        try:
            with socket.create_connection((HOST, PORT), timeout=0.5):
                return
        except OSError:
            time.sleep(0.2)
    raise AssertionError(f"Could not connect to {HOST}:{PORT}. Is the Rust service running?")


def build_rust_binary():
    assert PROJECT.is_dir(), f"Missing Rust project directory: {PROJECT}"
    assert (PROJECT / "Cargo.toml").is_file(), "Missing Cargo.toml"
    rust_sources = list((PROJECT / "src").rglob("*.rs")) if (PROJECT / "src").is_dir() else []
    assert rust_sources and any(p.stat().st_size > 0 for p in rust_sources), "Missing Rust source code"

    env = os.environ.copy()
    env["HOME"] = "/home/user"
    env["CARGO_HOME"] = "/home/user/.cargo"

    metadata = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1"],
        cwd=PROJECT, env=env, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=60
    )
    assert metadata.returncode == 0, f"cargo metadata failed:\n{metadata.stdout}"
    meta = json.loads(metadata.stdout)
    manifest = str((PROJECT / "Cargo.toml").resolve())
    packages = [p for p in meta["packages"] if str(Path(p["manifest_path"]).resolve()) == manifest]
    assert packages, "Cargo metadata does not contain the requested project"
    bins = [t for t in packages[0]["targets"] if "bin" in t.get("kind", [])]
    assert bins, "The Rust project has no binary target"
    bin_name = bins[0]["name"]

    build = subprocess.run(
        ["cargo", "build", "--release", "--offline", "--bin", bin_name],
        cwd=PROJECT, env=env, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=240
    )
    assert build.returncode == 0, f"Rust release build failed:\n{build.stdout}"

    binary = Path(meta["target_directory"]) / "release" / bin_name
    assert binary.is_file() and os.access(binary, os.X_OK), f"Missing executable Rust artifact: {binary}"
    assert binary.read_bytes()[:4] == b"\x7fELF", "Built service is not an ELF executable"
    return binary, env


def start_server(binary, env, log_name):
    stop_listener()
    log = open(f"/tmp/{log_name}.log", "wb")
    proc = subprocess.Popen([str(binary)], cwd=PROJECT, env=env, stdout=log, stderr=subprocess.STDOUT)
    wait_for_server(proc)
    return proc, log


def stop_server(proc, log):
    if proc is not None and proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=3)
    stop_listener()
    if log is not None:
        log.close()


def detect_visual_timestamps(path):
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height,avg_frame_rate", "-of", "json", str(path)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30, check=True
    )
    stream = json.loads(probe.stdout)["streams"][0]
    width, height = int(stream["width"]), int(stream["height"])
    num, den = map(int, stream["avg_frame_rate"].split("/"))
    fps = num / den
    assert abs(fps - 1.0) < 0.001, f"Test video is not 1 fps: {fps}"

    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60, check=True
    ).stdout
    frame_size = width * height * 3
    assert frame_size > 0 and len(raw) % frame_size == 0, "Could not decode complete video frames"

    found = []
    for index in range(len(raw) // frame_size):
        frame = raw[index * frame_size:(index + 1) * frame_size]
        red_pixels = 0
        for pos in range(0, len(frame), 3):
            r, g, b = frame[pos], frame[pos + 1], frame[pos + 2]
            if r >= 220 and g <= 45 and b <= 45:
                red_pixels += 1
        if red_pixels >= 2500:
            timestamp = index / fps
            assert timestamp.is_integer(), f"Non-integral timestamp in 1 fps video: {timestamp}"
            found.append(int(timestamp))
    return found


class WebSocketClient:
    def __init__(self, authorization):
        self.sock = socket.create_connection((HOST, PORT), timeout=8)
        self.sock.settimeout(8)
        self.buffer = b""
        key = base64.b64encode(os.urandom(16)).decode()
        headers = [
            "GET / HTTP/1.1",
            f"Host: {HOST}:{PORT}",
            "Upgrade: websocket",
            "Connection: Upgrade",
            f"Sec-WebSocket-Key: {key}",
            "Sec-WebSocket-Version: 13",
        ]
        if authorization is not None:
            headers.append(f"Authorization: {authorization}")
        request = "\r\n".join(headers) + "\r\n\r\n"
        self.sock.sendall(request.encode())

        data = b""
        while b"\r\n\r\n" not in data:
            chunk = self.sock.recv(4096)
            assert chunk, "Connection closed before HTTP upgrade response"
            data += chunk
        head, self.buffer = data.split(b"\r\n\r\n", 1)
        lines = head.decode("latin1").split("\r\n")
        self.status_line = lines[0]
        self.headers = {}
        for line in lines[1:]:
            if ":" in line:
                name, value = line.split(":", 1)
                self.headers[name.strip().lower()] = value.strip()
        self.key = key

    def validate_upgrade(self):
        assert " 101 " in self.status_line, f"Expected 101 Switching Protocols, got: {self.status_line}"
        expected = base64.b64encode(hashlib.sha1((self.key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
        assert self.headers.get("sec-websocket-accept") == expected, "Invalid WebSocket upgrade response"

    def _take(self, count):
        while len(self.buffer) < count:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise AssertionError("WebSocket closed without a close frame")
            self.buffer += chunk
        out, self.buffer = self.buffer[:count], self.buffer[count:]
        return out

    def send_frame(self, opcode, payload=b""):
        first = 0x80 | opcode
        length = len(payload)
        frame = bytearray([first])
        if length < 126:
            frame.append(0x80 | length)
        elif length < 65536:
            frame.append(0x80 | 126)
            frame.extend(struct.pack("!H", length))
        else:
            frame.append(0x80 | 127)
            frame.extend(struct.pack("!Q", length))
        mask = os.urandom(4)
        frame.extend(mask)
        frame.extend(byte ^ mask[i % 4] for i, byte in enumerate(payload))
        self.sock.sendall(frame)

    def read_frame(self):
        first, second = self._take(2)
        fin = bool(first & 0x80)
        opcode = first & 0x0F
        assert not (second & 0x80), "Server frames must not be masked"
        length = second & 0x7F
        if length == 126:
            length = struct.unpack("!H", self._take(2))[0]
        elif length == 127:
            length = struct.unpack("!Q", self._take(8))[0]
        return fin, opcode, self._take(length)

    def send_json_and_receive(self, events):
        self.send_frame(1, json.dumps(events).encode())
        while True:
            fin, opcode, payload = self.read_frame()
            if opcode == 9:
                self.send_frame(10, payload)
                continue
            assert opcode == 1 and fin, f"Expected one complete text frame, got opcode={opcode}, fin={fin}"
            try:
                result = json.loads(payload.decode("utf-8"))
            except Exception as exc:
                raise AssertionError(f"Response was not valid UTF-8 JSON: {payload!r}") from exc
            break

        while True:
            fin, opcode, payload = self.read_frame()
            if opcode == 9:
                self.send_frame(10, payload)
                continue
            assert opcode == 8 and fin, f"Expected graceful WebSocket close frame, got opcode={opcode}"
            assert len(payload) != 1, "Malformed WebSocket close payload"
            self.send_frame(8, payload)
            self.sock.close()
            return result


def assert_rejected(authorization):
    client = WebSocketClient(authorization)
    try:
        assert " 401 " in client.status_line, f"Expected 401 Unauthorized, got: {client.status_line}"
    finally:
        client.sock.close()


def expected_merge(events, visual_times):
    visual = [
        {"timestamp_sec": sec, "event_msg": "Visual Error Detected", "source": "ui_test"}
        for sec in visual_times
    ]
    return sorted(events + visual, key=lambda event: event["timestamp_sec"])


def run_case(events, visual_times):
    client = WebSocketClient("Bearer secret-ci-token")
    client.validate_upgrade()
    actual = client.send_json_and_receive(events)
    expected = expected_merge(events, visual_times)
    assert actual == expected, f"Response JSON does not match expected output.\nExpected: {expected}\nGot: {actual}"


def make_dynamic_video(path, red_times):
    expression = "+".join(f"eq(n\\,{sec})" for sec in red_times)
    vf = f"drawbox=x=137:y=91:w=80:h=80:color=0xFF0000:t=fill:enable='{expression}'"
    subprocess.run(
        ["ffmpeg", "-v", "error", "-f", "lavfi", "-i",
         "color=c=black:s=640x480:r=1:d=12", "-vf", vf,
         "-c:v", "libx264", "-pix_fmt", "yuv420p", "-r", "1", "-y", str(path)],
        timeout=60, check=True
    )


def main():
    assert VIDEO.is_file(), f"Missing required video: {VIDEO}"
    shutil.copy2(VIDEO, BACKUP)
    binary, env = build_rust_binary()
    proc = log = None
    try:
        # Preserve the original authentication and exact transformation checks.
        original_visuals = detect_visual_timestamps(VIDEO)
        assert original_visuals == [4, 15, 27], f"Unexpected original fixture timestamps: {original_visuals}"
        proc, log = start_server(binary, env, "ci_analyzer_original")
        assert_rejected(None)
        assert_rejected("Bearer wrong-token")

        original_payload = [
            {"timestamp_sec": 4, "event_msg": "Click checkout", "source": "puppeteer"},
            {"timestamp_sec": 26, "event_msg": "Database lock", "source": "db"}
        ]
        original_expected = [
            {"timestamp_sec": 4, "event_msg": "Click checkout", "source": "puppeteer"},
            {"timestamp_sec": 4, "event_msg": "Visual Error Detected", "source": "ui_test"},
            {"timestamp_sec": 15, "event_msg": "Visual Error Detected", "source": "ui_test"},
            {"timestamp_sec": 26, "event_msg": "Database lock", "source": "db"},
            {"timestamp_sec": 27, "event_msg": "Visual Error Detected", "source": "ui_test"}
        ]
        client = WebSocketClient("Bearer secret-ci-token")
        client.validate_upgrade()
        original_actual = client.send_json_and_receive(original_payload)
        assert original_actual == original_expected, f"Response JSON does not match expected output.\nExpected: {original_expected}\nGot: {original_actual}"
        stop_server(proc, log)
        proc = log = None

        # Replace the recording only at verification time so hardcoded timestamps cannot pass.
        red_times = sorted(random.SystemRandom().sample(range(1, 11), 3))
        make_dynamic_video(VIDEO, red_times)
        derived_visuals = detect_visual_timestamps(VIDEO)
        assert derived_visuals == red_times, f"Dynamic video generation/detection mismatch: {derived_visuals} vs {red_times}"

        proc, log = start_server(binary, env, "ci_analyzer_dynamic")
        assert_rejected(None)
        assert_rejected("Bearer secret-ci-token-extra")

        marker = uuid.uuid4().hex
        collision = red_times[1]
        run_case([
            {"timestamp_sec": 11, "event_msg": "late-" + marker, "source": "runner"},
            {"timestamp_sec": collision, "event_msg": "tie-" + marker, "source": "backend"},
            {"timestamp_sec": 0, "event_msg": "early-" + marker, "source": "browser"}
        ], derived_visuals)
        run_case([
            {"timestamp_sec": 9, "event_msg": "z-" + marker, "source": "db"},
            {"timestamp_sec": 2, "event_msg": "a-" + marker, "source": "network"}
        ], derived_visuals)
        run_case([], derived_visuals)
    finally:
        stop_server(proc, log)
        if BACKUP.exists():
            shutil.copy2(BACKUP, VIDEO)
            BACKUP.unlink()


if __name__ == "__main__":
    try:
        main()
    except Exception:
        traceback.print_exc()
        raise
PY_EOF

python3 /tmp/test_final_state.py
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
