#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import signal
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

SCRIPT = "/home/user/run_pipeline.sh"
PROJECT = "/home/user/video_processor"
BINARY = "/home/user/video_processor/target/release/video_processor"
FEC_DIR = "/home/user/fec_lib"
RESULTS = "/tmp/validator_results.json"


def run_checked(cmd, cwd=None, timeout=180):
    result = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    assert result.returncode == 0, (
        f"Command failed: {' '.join(cmd)}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def build_expected_results():
    source = r'''
#include <stdint.h>
#include <stddef.h>
uint32_t expected_fec(const uint8_t *buffer, size_t length) {
    uint32_t checksum = 0;
    for (size_t i = 0; i < length; i++)
        checksum ^= (buffer[i] << (i % 8));
    return checksum;
}
'''
    temp_dir = tempfile.mkdtemp(prefix="fec_verifier_")
    c_path = os.path.join(temp_dir, "expected.c")
    so_path = os.path.join(temp_dir, "expected.so")
    with open(c_path, "w") as f:
        f.write(source)
    run_checked(["gcc", "-shared", "-fPIC", "-O2", "-o", so_path, c_path])

    lib = ctypes.CDLL(so_path)
    lib.expected_fec.argtypes = [ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t]
    lib.expected_fec.restype = ctypes.c_uint32

    frame_size = 640 * 360 * 3
    ffmpeg = subprocess.Popen(
        ["ffmpeg", "-v", "error", "-i", "/app/video.mp4", "-f", "rawvideo",
         "-pix_fmt", "rgb24", "-"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    expected = {}
    try:
        while True:
            data = bytearray()
            while len(data) < frame_size:
                chunk = ffmpeg.stdout.read(frame_size - len(data))
                if not chunk:
                    break
                data.extend(chunk)
            if not data:
                break
            assert len(data) == frame_size, "ffmpeg produced a partial final frame"
            array = (ctypes.c_uint8 * frame_size).from_buffer(data)
            expected[len(expected)] = int(lib.expected_fec(array, frame_size))
    finally:
        if ffmpeg.stdout:
            ffmpeg.stdout.close()
    stderr = ffmpeg.stderr.read().decode(errors="replace")
    rc = ffmpeg.wait(timeout=20)
    assert rc == 0, f"Independent ffmpeg extraction failed: {stderr}"
    assert len(expected) == 150, f"Fixture unexpectedly contained {len(expected)} frames"
    return expected


class ValidationHandler(BaseHTTPRequestHandler):
    received = {}
    batch_calls = 0
    submit_calls = 0
    last_batch_time = 0.0
    lock = threading.Lock()

    def log_message(self, *args):
        pass

    def send_json(self, status, value):
        body = json.dumps(value).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        try:
            length = int(self.headers.get("Content-Length", "0"))
            data = json.loads(self.rfile.read(length))
        except Exception:
            self.send_json(400, {"error": "invalid json"})
            return

        with type(self).lock:
            if self.path == "/submit":
                type(self).submit_calls += 1
                self.send_json(400, {"error": "individual submission disabled by verifier"})
                return

            if self.path != "/batch":
                self.send_json(404, {"error": "not found"})
                return

            type(self).batch_calls += 1
            now = time.monotonic()
            if now - type(self).last_batch_time < 0.2:
                self.send_json(429, {"error": "Rate limit exceeded"})
                return

            batches = data.get("batches") if isinstance(data, dict) else None
            if not isinstance(batches, list):
                self.send_json(400, {"error": "batches must be an array"})
                return

            parsed = []
            try:
                for item in batches:
                    if not isinstance(item, dict):
                        raise ValueError()
                    frame = item["frame"]
                    checksum = item["checksum"]
                    if isinstance(frame, bool) or isinstance(checksum, bool):
                        raise ValueError()
                    if not isinstance(frame, int) or not isinstance(checksum, int):
                        raise ValueError()
                    parsed.append((frame, checksum))
            except Exception:
                self.send_json(400, {"error": "invalid frame object"})
                return

            type(self).last_batch_time = now
            for frame, checksum in parsed:
                type(self).received[frame] = checksum
            with open(RESULTS, "w") as f:
                json.dump(type(self).received, f)
            self.send_json(200, {"status": "ok"})


def reset_service_state():
    with ValidationHandler.lock:
        ValidationHandler.received = {}
        ValidationHandler.batch_calls = 0
        ValidationHandler.submit_calls = 0
        ValidationHandler.last_batch_time = 0.0
    with open(RESULTS, "w") as f:
        json.dump({}, f)


def assert_submission(expected):
    with ValidationHandler.lock:
        received = dict(ValidationHandler.received)
        batch_calls = ValidationHandler.batch_calls
        submit_calls = ValidationHandler.submit_calls
    assert batch_calls >= 1, "The pipeline did not use the /batch endpoint"
    assert submit_calls == 0, "The pipeline attempted to use the rate-limited /submit endpoint"
    assert set(received) == set(range(150)), (
        f"Expected exactly frame IDs 0..149, received {len(received)} IDs"
    )
    assert received == expected, "One or more submitted FEC checksums were incorrect"


def test_pipeline_execution_and_metric():
    assert os.path.isfile(SCRIPT), f"Wrapper script not found: {SCRIPT}"

    # Rebuild through the submitted Makefile and build.rs so stale artifacts cannot hide fixes.
    run_checked(["make", "-B", "-C", FEC_DIR])
    assert os.path.isfile(os.path.join(FEC_DIR, "libfec.so"))
    elf = run_checked(["readelf", "-h", os.path.join(FEC_DIR, "libfec.so")]).stdout
    assert "DYN (Shared object file)" in elf, "libfec.so is not a shared library"

    os.utime(os.path.join(PROJECT, "build.rs"), None)
    run_checked(["cargo", "build", "--release"], cwd=PROJECT)
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), (
        f"Compiled release executable not found: {BINARY}"
    )
    dynamic = run_checked(["readelf", "-d", BINARY]).stdout
    assert "libfec.so" in dynamic, "Release binary is not dynamically linked to the legacy FEC library"

    expected = build_expected_results()

    # Stop the image's validator and replace it with a verifier-owned in-memory service.
    subprocess.run(["pkill", "-f", "/home/user/validator_service.py"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.2)
    server = HTTPServer(("127.0.0.1", 8080), ValidationHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = FEC_DIR + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")

    try:
        # Execute the demanded compiled artifact itself and verify its behavior.
        reset_service_state()
        start = time.monotonic()
        direct = subprocess.run([BINARY], capture_output=True, text=True, env=env, timeout=10)
        direct_runtime = time.monotonic() - start
        assert direct.returncode == 0, (
            f"Release binary returned {direct.returncode}. Stderr: {direct.stderr}\nStdout: {direct.stdout}"
        )
        assert direct_runtime <= 3.0, f"Release binary took {direct_runtime:.3f}s; limit is 3.0s"
        assert_submission(expected)

        # Preserve the original wrapper execution and runtime assertions.
        reset_service_state()
        start = time.monotonic()
        res = subprocess.run(["bash", SCRIPT], capture_output=True, text=True, env=env, timeout=10)
        runtime_seconds = time.monotonic() - start
        assert res.returncode == 0, (
            f"Pipeline returned non-zero exit code {res.returncode}. Stderr: {res.stderr}\nStdout: {res.stdout}"
        )
        assert os.path.exists(RESULTS), f"Results file not found: {RESULTS}"
        try:
            with open(RESULTS) as f:
                results = json.load(f)
        except Exception as e:
            pytest.fail(f"Could not read validator results: {e}")
        assert len(results) >= 10, (
            f"Processed too few frames: {len(results)}. Expected at least 10 frames to be submitted."
        )
        normalized = {int(k): int(v) for k, v in results.items()}
        assert normalized == expected, "Validator results do not contain all 150 correct frames"
        assert_submission(expected)
        assert runtime_seconds <= 3.0, (
            f"Execution time {runtime_seconds:.3f}s exceeded the threshold of 3.0s."
        )
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
