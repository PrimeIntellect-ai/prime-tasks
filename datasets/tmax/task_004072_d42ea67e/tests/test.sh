#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import signal
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid

import pytest

SANITIZER = "/home/user/sanitizer"
SOURCE = "/home/user/sanitizer.c"
WATCHDOG = "/home/user/watchdog.sh"
DAEMON = "/app/backend/telemetry_daemon"


def compute_black_frames():
    video = "/app/incident_record.mp4"
    assert os.path.isfile(video), f"Incident video missing: {video}"
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height", "-of", "json", video],
        capture_output=True, check=True, timeout=15,
    )
    stream = json.loads(probe.stdout)["streams"][0]
    width, height = int(stream["width"]), int(stream["height"])
    decoded = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", video, "-vf", "fps=1",
         "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        capture_output=True, check=True, timeout=30,
    ).stdout
    frame_size = width * height * 3
    assert frame_size > 0 and len(decoded) % frame_size == 0, "Could not decode complete video frames"
    frames = [decoded[i:i + frame_size] for i in range(0, len(decoded), frame_size)]
    assert frames, "No frames were extracted from the incident video"
    return sum(1 for frame in frames if max(frame) <= 8)


def test_black_frame_count():
    path = "/home/user/black_frame_count.txt"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "5", f"Expected black frame count to be '5', got '{content}'."
    recomputed = compute_black_frames()
    assert content == str(recomputed), f"Recorded count {content} does not match video-derived count {recomputed}"


def run_sanitizer(path, payload):
    return subprocess.run([path], input=payload, capture_output=True, timeout=5)


def assert_clean(path, payload):
    result = run_sanitizer(path, payload)
    assert result.returncode == 0, f"Sanitizer rejected clean payload: {payload!r}"
    assert result.stdout == payload, "Sanitizer did not preserve a clean payload exactly"


def assert_evil(path, payload):
    result = run_sanitizer(path, payload)
    assert result.returncode != 0, f"Sanitizer accepted evil payload: {payload[:100]!r}"
    assert result.stdout == b"", "Sanitizer emitted output for an evil payload"


def test_sanitizer_executable_and_source():
    assert os.path.isfile(SANITIZER), f"Sanitizer executable {SANITIZER} does not exist."
    assert os.access(SANITIZER, os.X_OK), f"Sanitizer {SANITIZER} is not executable."
    with open(SANITIZER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The installed sanitizer is not a compiled executable"

    assert os.path.isfile(SOURCE), f"C source {SOURCE} does not exist."
    assert os.path.getsize(SOURCE) > 0, f"C source {SOURCE} is empty."
    rebuilt = os.path.join(tempfile.mkdtemp(prefix="sanitizer-build-"), "sanitizer")
    build = subprocess.run(
        ["gcc", SOURCE, "-o", rebuilt], capture_output=True, text=True, timeout=20
    )
    assert build.returncode == 0, f"sanitizer.c does not compile:\n{build.stderr}"

    token = uuid.uuid4().hex
    clean_cases = [
        (json.dumps({"sensor": token, "value": 17.25}) + "\n").encode(),
        ("  {\"outer\":[1,{\"token\":\"%s\"}],\"ok\":true}  \n" % token).encode(),
        json.dumps({"sensor": token, "value": "A" * 1000}, separators=(",", ":")).encode(),
    ]
    evil_cases = [
        json.dumps({"sensor": token, "value": "DROP TABLE telemetry_" + token}).encode(),
        json.dumps({"sensor": token, "value": "A" * 1001}, separators=(",", ":")).encode(),
        ('{"sensor":"%s","value":[1,2,3}' % token).encode(),
        ('{"sensor":"%s","value":1]' % token).encode(),
    ]
    for executable in (SANITIZER, rebuilt):
        for payload in clean_cases:
            assert_clean(executable, payload)
        for payload in evil_cases:
            assert_evil(executable, payload)


def test_adversarial_corpus():
    clean_dir = "/app/corpora/clean/"
    evil_dir = "/app/corpora/evil/"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"
    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    assert evil_files, "No evil corpus files found."
    assert clean_files, "No clean corpus files found."
    for name in evil_files:
        with open(os.path.join(evil_dir, name), "rb") as f:
            assert_evil(SANITIZER, f.read())
    for name in clean_files:
        with open(os.path.join(clean_dir, name), "rb") as f:
            assert_clean(SANITIZER, f.read())


def matching_pids(path):
    result = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                args = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
            if path in args:
                result.append(int(entry))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return result


def stop_matching(path):
    pids = matching_pids(path)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and matching_pids(path):
        time.sleep(0.05)
    for pid in matching_pids(path):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def wait_for_new_daemon(excluded=(), timeout=6):
    deadline = time.time() + timeout
    while time.time() < deadline:
        pids = [p for p in matching_pids(DAEMON) if p not in excluded]
        if pids:
            return pids[0]
        time.sleep(0.1)
    return None


def test_watchdog_supervises_daemon():
    assert os.path.isfile(WATCHDOG), f"Watchdog script {WATCHDOG} does not exist."
    assert os.access(WATCHDOG, os.X_OK), f"Watchdog script {WATCHDOG} is not executable."

    stop_matching(WATCHDOG)
    stop_matching(DAEMON)
    watchdog = subprocess.Popen(
        [WATCHDOG], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, start_new_session=True,
    )
    first = wait_for_new_daemon()
    assert watchdog.poll() is None, "The watchdog exited instead of continuously supervising"
    assert first is not None, "Executing watchdog.sh did not start the telemetry daemon"

    os.kill(first, signal.SIGKILL)
    second = wait_for_new_daemon(excluded={first})
    assert watchdog.poll() is None, "The watchdog exited after the daemon crashed"
    assert second is not None and second != first, "The watchdog did not restart the crashed daemon"


def http_post(payload, timeout=5):
    req = urllib.request.Request("http://localhost:80/telemetry", data=payload, method="POST")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read()
    except urllib.error.URLError:
        return 0, b""


def test_nginx_endpoint_and_sanitizer_integration():
    config_test = subprocess.run(["nginx", "-t"], capture_output=True, text=True, timeout=10)
    assert config_test.returncode == 0, f"Invalid Nginx configuration: {config_test.stderr}"
    assert matching_pids("nginx: master process") or subprocess.run(
        ["pgrep", "-x", "nginx"], capture_output=True
    ).returncode == 0, "Nginx is not running"

    original = b'{"sensor":"temp","value":22.5}'
    status, _ = http_post(original)
    assert status == 200, f"Expected HTTP 200 OK, got {status}"

    token = uuid.uuid4().hex
    generated_clean = json.dumps({"sensor": token, "value": 31.75}).encode()
    status, _ = http_post(generated_clean)
    assert status == 200, f"Nginx rejected a generated valid payload with status {status}"

    backup = SANITIZER + ".verifier-backup-" + token
    os.replace(SANITIZER, backup)
    try:
        with open(SANITIZER, "w") as f:
            f.write("#!/bin/sh\nexit 1\n")
        os.chmod(SANITIZER, 0o755)
        status, _ = http_post(generated_clean)
        assert status != 200, "Nginx returned 200 while the required sanitizer rejected the request"
    finally:
        try:
            os.unlink(SANITIZER)
        except FileNotFoundError:
            pass
        os.replace(backup, SANITIZER)

    evil_payloads = [
        json.dumps({"sensor": token, "value": "DROP TABLE live_" + token}).encode(),
        json.dumps({"sensor": token, "value": "A" * 1001}, separators=(",", ":")).encode(),
        ('{"sensor":"%s","value":42' % token).encode(),
    ]
    daemon_pids = matching_pids(DAEMON)
    assert daemon_pids, "Telemetry daemon is not running before proxy tests"
    daemon_pid = daemon_pids[0]
    for payload in evil_payloads:
        status, _ = http_post(payload)
        assert status != 200, f"Nginx accepted malicious payload with status {status}"
        time.sleep(0.25)
        assert daemon_pid in matching_pids(DAEMON), "A malicious request reached and crashed the backend"

    status, _ = http_post(json.dumps({"sensor": token, "value": 99}).encode())
    assert status == 200, f"Valid request failed after malicious-request tests with status {status}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
