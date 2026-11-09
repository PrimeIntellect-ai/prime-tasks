#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import re
import socket
import subprocess
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer


def run_filter(script_path, video_path):
    return subprocess.run(
        ["python3", script_path, video_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )


def derive_first_red_frame(video_path):
    probe = subprocess.run(
        [
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_entries", "stream=width,height",
            "-of", "csv=p=0:s=x", video_path,
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    width, height = map(int, probe.stdout.strip().split("x"))
    assert width >= 10 and height >= 10
    frame_size = width * height * 3

    proc = subprocess.Popen(
        ["ffmpeg", "-v", "error", "-i", video_path,
         "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    frame_number = 0
    try:
        while True:
            chunks = []
            remaining = frame_size
            while remaining:
                chunk = proc.stdout.read(remaining)
                if not chunk:
                    break
                chunks.append(chunk)
                remaining -= len(chunk)
            if remaining:
                break
            frame = b"".join(chunks)
            red_row = b"\xff\x00\x00" * 10
            if all(frame[(y * width) * 3:(y * width) * 3 + 30] == red_row for y in range(10)):
                return frame_number
            frame_number += 1
    finally:
        if proc.poll() is None:
            proc.kill()
        proc.communicate()
    return None


def test_incident_report():
    report_path = "/home/user/incident_report.txt"
    assert os.path.isfile(report_path), f"File {report_path} is missing."

    with open(report_path, "r") as f:
        content = f.read().strip()

    # Preserve the original assertion and independently derive the answer by
    # decoding the supplied incident video.
    assert content == "142", f"Expected incident report to contain '142', but found '{content}'."
    expected = derive_first_red_frame("/app/incident_record.mp4")
    assert expected is not None, "No red artifact was found in the incident recording."
    assert re.fullmatch(r"\d+", content), "Incident report must contain only an integer."
    assert int(content) == expected, f"Expected first artifact frame {expected}, found {content}."


def _http_request(source_ip, marker_expected=False):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(5)
    try:
        sock.bind((source_ip, 0))
        sock.connect(("127.0.0.1", 8080))
        sock.sendall(b"GET /verification-check HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        data = bytearray()
        while True:
            chunk = sock.recv(65536)
            if not chunk:
                break
            data.extend(chunk)
        return bytes(data)
    finally:
        sock.close()


def test_nginx_proxy_config():
    config_path = "/home/user/proxy.conf"
    assert os.path.isfile(config_path), f"File {config_path} is missing."

    with open(config_path, "r") as f:
        content = f.read()

    # Preserve the original directive assertions.
    assert re.search(r"listen\s+8080\b", content), "Nginx config does not listen on port 8080."
    assert re.search(r"proxy_pass\s+http://127\.0\.0\.1:8081/?\s*;", content), "Nginx config does not proxy to http://127.0.0.1:8081."
    assert re.search(r"allow\s+127\.0\.0\.1\s*;", content), "Nginx config missing 'allow 127.0.0.1;' directive."
    assert re.search(r"deny\s+all\s*;", content), "Nginx config missing 'deny all;' directive."

    syntax = subprocess.run(
        ["nginx", "-T", "-c", config_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert syntax.returncode == 0, f"Nginx rejected proxy.conf:\n{syntax.stderr}"
    active_text = syntax.stdout + "\n" + syntax.stderr
    uncommented = "\n".join(line.split("#", 1)[0] for line in active_text.splitlines())
    assert re.search(r"(?m)^\s*user\s+user\s*;", uncommented), \
        "The active Nginx configuration must run workers as the unprivileged user."

    marker = ("backend-" + uuid.uuid4().hex).encode()

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(marker)

        def log_message(self, fmt, *args):
            pass

    class ReusableHTTPServer(HTTPServer):
        allow_reuse_address = True

    backend = ReusableHTTPServer(("127.0.0.1", 8081), Handler)
    backend_thread = threading.Thread(target=backend.serve_forever, daemon=True)
    backend_thread.start()
    nginx_proc = None
    try:
        nginx_proc = subprocess.Popen(
            ["nginx", "-c", config_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        time.sleep(0.8)
        if nginx_proc.poll() not in (None, 0):
            out, err = nginx_proc.communicate(timeout=2)
            raise AssertionError(f"Nginx failed to start:\n{out.decode(errors='replace')}\n{err.decode(errors='replace')}")

        allowed = _http_request("127.0.0.1")
        status_line = allowed.split(b"\r\n", 1)[0]
        assert re.match(br"HTTP/\d\.\d 200\b", status_line), \
            f"A localhost request was not accepted: {status_line!r}"
        assert marker in allowed, "Traffic was not actually forwarded to 127.0.0.1:8081."

        denied = _http_request("127.0.0.2")
        denied_status = denied.split(b"\r\n", 1)[0]
        assert re.match(br"HTTP/\d\.\d 403\b", denied_status), \
            f"A non-allowed source did not receive 403 Forbidden: {denied_status!r}"
        assert marker not in denied, "Denied traffic was forwarded to the backend."
    finally:
        subprocess.run(
            ["nginx", "-c", config_path, "-s", "quit"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=5,
            check=False,
        )
        if nginx_proc is not None and nginx_proc.poll() is None:
            nginx_proc.terminate()
            try:
                nginx_proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                nginx_proc.kill()
                nginx_proc.wait()
        backend.shutdown()
        backend.server_close()
        backend_thread.join(timeout=2)


def test_adversarial_corpus():
    script_path = "/home/user/filter_video.py"
    assert os.path.isfile(script_path), f"Script {script_path} is missing."

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"
    clean_videos = glob.glob(os.path.join(clean_dir, "*.mp4"))
    evil_videos = glob.glob(os.path.join(evil_dir, "*.mp4"))
    assert len(clean_videos) > 0, "No clean videos found in corpus."
    assert len(evil_videos) > 0, "No evil videos found in corpus."

    failed_clean = []
    failed_evil = []
    for video in clean_videos:
        if run_filter(script_path, video).returncode != 0:
            failed_clean.append(os.path.basename(video))
    for video in evil_videos:
        if run_filter(script_path, video).returncode != 1:
            failed_evil.append(os.path.basename(video))

    error_msgs = []
    if failed_clean:
        error_msgs.append(f"{len(failed_clean)} of {len(clean_videos)} clean videos modified/rejected: {', '.join(failed_clean)}")
    if failed_evil:
        error_msgs.append(f"{len(failed_evil)} of {len(evil_videos)} evil videos bypassed: {', '.join(failed_evil)}")
    assert not error_msgs, " | ".join(error_msgs)


def _write_dynamic_video(path, width, height, frame_count, evil_frame, clean_variant):
    frames = bytearray(os.urandom(width * height * 3 * frame_count))
    for n in range(frame_count):
        # Make the top-left area deterministic so random input cannot
        # accidentally form the artifact.
        for y in range(10):
            for x in range(10):
                off = (n * width * height + y * width + x) * 3
                frames[off:off + 3] = b"\x10\x20\x30"

        if evil_frame is not None and n == evil_frame:
            for y in range(10):
                for x in range(10):
                    off = (n * width * height + y * width + x) * 3
                    frames[off:off + 3] = b"\xff\x00\x00"
        elif evil_frame is None:
            if clean_variant == 0:  # Almost red, but not pure red.
                for y in range(10):
                    for x in range(10):
                        off = (n * width * height + y * width + x) * 3
                        frames[off:off + 3] = b"\xfe\x00\x00"
            elif clean_variant == 1:  # Only 9 columns are red.
                for y in range(10):
                    for x in range(9):
                        off = (n * width * height + y * width + x) * 3
                        frames[off:off + 3] = b"\xff\x00\x00"
            elif clean_variant == 2:  # Only 9 rows are red.
                for y in range(9):
                    for x in range(10):
                        off = (n * width * height + y * width + x) * 3
                        frames[off:off + 3] = b"\xff\x00\x00"

    encoded = subprocess.run(
        [
            "ffmpeg", "-v", "error", "-y",
            "-f", "rawvideo", "-pix_fmt", "rgb24",
            "-s", f"{width}x{height}", "-r", "17", "-i", "pipe:0",
            "-c:v", "libx264rgb", "-crf", "0", "-preset", "ultrafast",
            "-pix_fmt", "rgb24", path,
        ],
        input=bytes(frames),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert encoded.returncode == 0, encoded.stderr.decode(errors="replace")


def test_filter_on_runtime_generated_unlabelled_videos(tmp_path):
    script_path = "/home/user/filter_video.py"
    assert os.path.isfile(script_path), f"Script {script_path} is missing."

    dimensions = [(64, 48), (80, 60), (96, 72), (70, 54)]
    frame_counts = [7, 11, 13, 9]
    evil_positions = [0, 5, 12, 8]
    cases = []

    # Names and contents are generated only after the agent has finished, and
    # clean/evil files share the same unlabelled directory.
    for i, ((width, height), count) in enumerate(zip(dimensions, frame_counts)):
        clean_path = str(tmp_path / (uuid.uuid4().hex + ".mp4"))
        evil_path = str(tmp_path / (uuid.uuid4().hex + ".mp4"))
        _write_dynamic_video(clean_path, width, height, count, None, i)
        _write_dynamic_video(evil_path, width, height, count, evil_positions[i], i)
        cases.append((clean_path, 0))
        cases.append((evil_path, 1))

    random.SystemRandom().shuffle(cases)
    failures = []
    for path, expected in cases:
        result = run_filter(script_path, path)
        if result.returncode != expected:
            failures.append(
                f"{os.path.basename(path)}: expected exit {expected}, got {result.returncode}; "
                f"stderr={result.stderr.decode(errors='replace')!r}"
            )
    assert not failures, "Runtime-generated video checks failed: " + " | ".join(failures)

    missing = str(tmp_path / (uuid.uuid4().hex + ".mp4"))
    corrupt = str(tmp_path / (uuid.uuid4().hex + ".mp4"))
    with open(corrupt, "wb") as f:
        f.write(os.urandom(257))
    assert run_filter(script_path, missing).returncode != 0, "Missing input must be rejected."
    assert run_filter(script_path, corrupt).returncode != 0, "Corrupt MP4 input must be rejected."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
