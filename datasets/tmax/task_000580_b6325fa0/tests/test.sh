#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import socket
import subprocess
import tempfile
import threading
import time

import cv2
import numpy as np
import pytest


def generate_video(path, frame_count, width=640, height=480):
    writer = cv2.VideoWriter(path, cv2.VideoWriter_fourcc(*"mp4v"), 30, (width, height))
    assert writer.isOpened(), f"Could not create test video at {path}"

    for _ in range(frame_count):
        frame = np.empty((height, width, 3), dtype=np.uint8)
        frame[:] = (35, 30, 25)
        choice = secrets.randbelow(5)
        if choice == 0:
            frame[:50, :50] = (0, 0, 255)       # qualifying red
        elif choice == 1:
            frame[:50, :50] = (0, 220, 0)       # green distractor
        elif choice == 2:
            frame[:50, :50] = (220, 0, 0)       # blue distractor
        elif choice == 3:
            frame[:50, :50] = (20, 20, 130)     # red below threshold
        else:
            noise = np.random.default_rng(secrets.randbits(64)).integers(
                0, 45, size=(50, 50, 3), dtype=np.uint8
            )
            frame[:50, :50] = noise
        writer.write(frame)
    writer.release()


def oracle_count(path):
    cap = cv2.VideoCapture(path)
    assert cap.isOpened(), f"Could not open generated video {path}"
    count = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        means = frame[:50, :50].mean(axis=(0, 1))
        blue, green, red = means
        if red > 150 and green < 50 and blue < 50:
            count += 1
    cap.release()
    return count


def run_analyzer(script, video, timeout=5.0):
    proc = subprocess.run(
        ["python3", script, video], capture_output=True, text=True, timeout=timeout
    )
    assert proc.returncode == 0, (
        f"analyze.py exited with {proc.returncode}. stderr: {proc.stderr}"
    )
    output = proc.stdout.strip()
    assert re.fullmatch(r"[+-]?\d+", output), (
        f"analyze.py did not print a single integer. Output: {proc.stdout!r}"
    )
    return int(output)


def test_proxy_running():
    """Verify the recorded socat process and exercise the requested forwarding."""
    pid_file = "/home/user/proxy.pid"
    assert os.path.exists(pid_file), f"Proxy PID file missing at {pid_file}"

    with open(pid_file, "r") as f:
        pid = f.read().strip()

    assert pid.isdigit(), f"PID file does not contain a valid integer: '{pid}'"

    try:
        output = subprocess.check_output(["ps", "-p", pid, "-o", "comm="], text=True).strip()
        assert "socat" in output, f"Process {pid} is not socat, it is '{output}'"
    except subprocess.CalledProcessError:
        pytest.fail(f"Process with PID {pid} is not running")

    with open(f"/proc/{pid}/cmdline", "rb") as f:
        cmdline = f.read().replace(b"\0", b" ").decode(errors="replace")
    assert "8080" in cmdline and "5000" in cmdline and "LISTEN" in cmdline.upper(), (
        f"Recorded socat process is not configured for 8080 -> 5000: {cmdline}"
    )

    received = []
    errors = []
    ready = threading.Event()
    token = secrets.token_bytes(32)

    def backend():
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
                server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                server.bind(("127.0.0.1", 5000))
                server.listen(1)
                server.settimeout(4)
                ready.set()
                conn, _ = server.accept()
                with conn:
                    conn.settimeout(4)
                    data = conn.recv(4096)
                    received.append(data)
                    conn.sendall(b"proxy-ok:" + data)
        except Exception as exc:
            errors.append(exc)
            ready.set()

    thread = threading.Thread(target=backend, daemon=True)
    thread.start()
    assert ready.wait(2), "Backend server did not start"
    assert not errors, f"Could not listen on service port 5000: {errors}"

    with socket.create_connection(("127.0.0.1", 8080), timeout=4) as client:
        client.sendall(token)
        response = client.recv(4096)

    thread.join(5)
    assert not thread.is_alive(), "Forwarded connection never reached port 5000"
    assert not errors, f"Proxy forwarding failed: {errors}"
    assert received == [token], "Data sent to port 8080 did not arrive at port 5000"
    assert response == b"proxy-ok:" + token, "Return traffic was not forwarded through the proxy"


def test_logrotate_config():
    """Verify the logrotate configuration contains the required directives."""
    conf_file = "/home/user/logrotate.conf"
    assert os.path.exists(conf_file), f"logrotate config missing at {conf_file}"

    with open(conf_file, "r") as f:
        content = f.read()

    assert "rotate 5" in content, "logrotate.conf missing 'rotate 5'"
    assert "daily" in content, "logrotate.conf missing 'daily'"
    assert "compress" in content, "logrotate.conf missing 'compress'"
    assert "missingok" in content, "logrotate.conf missing 'missingok'"
    assert "/home/user/logs/telemetry.log" in content, "logrotate.conf does not reference the correct log file path"

    check = subprocess.run(
        ["logrotate", "--debug", conf_file], capture_output=True, text=True
    )
    assert check.returncode == 0, f"logrotate rejected the configuration: {check.stderr}"


def test_git_hook_and_log():
    """Push a new commit and verify checkout plus analyzer execution by the hook."""
    log_file = "/home/user/logs/telemetry.log"
    assert os.path.exists(log_file), f"Log file missing at {log_file}"

    with open(log_file, "r") as f:
        content = f.read()
    assert "45" in content, f"telemetry.log does not contain the expected output '45'. Content: {content}"

    hook_file = "/home/user/telemetry.git/hooks/post-receive"
    assert os.path.exists(hook_file), f"post-receive hook missing at {hook_file}"
    assert os.access(hook_file, os.X_OK), "post-receive hook is not executable"

    original_video = "/app/telemetry.mp4"
    backup = f"/tmp/telemetry-backup-{secrets.token_hex(8)}.mp4"
    replacement = f"/tmp/telemetry-hook-{secrets.token_hex(8)}.mp4"
    clone_dir = tempfile.mkdtemp(prefix="verify-push-", dir="/home/user")
    marker_name = f"verifier-marker-{secrets.token_hex(12)}.txt"
    marker_value = secrets.token_hex(24)

    try:
        shutil.copy2(original_video, backup)
        generate_video(replacement, 180 + secrets.randbelow(80))
        expected = oracle_count(replacement)
        os.replace(replacement, original_video)

        before_size = os.path.getsize(log_file)
        subprocess.run(
            ["git", "clone", "/home/user/telemetry.git", clone_dir],
            check=True, capture_output=True, text=True, timeout=20
        )
        subprocess.run(["git", "-C", clone_dir, "config", "user.email", "verifier@example.invalid"], check=True)
        subprocess.run(["git", "-C", clone_dir, "config", "user.name", "Verifier"], check=True)
        with open(os.path.join(clone_dir, marker_name), "w") as f:
            f.write(marker_value)
        subprocess.run(["git", "-C", clone_dir, "add", marker_name], check=True)
        subprocess.run(
            ["git", "-C", clone_dir, "commit", "-m", "Verifier deployment exercise"],
            check=True, capture_output=True, text=True
        )
        push = subprocess.run(
            ["git", "-C", clone_dir, "push", "origin", "HEAD:master"],
            capture_output=True, text=True, timeout=20
        )
        assert push.returncode == 0, f"Push to master failed: {push.stdout}\n{push.stderr}"

        deployed_marker = os.path.join("/home/user/deploy", marker_name)
        assert os.path.exists(deployed_marker), "post-receive hook did not check out the pushed master commit"
        with open(deployed_marker) as f:
            assert f.read() == marker_value, "Deployment directory does not contain the latest pushed content"

        with open(log_file, "rb") as f:
            f.seek(before_size)
            appended = f.read().decode(errors="replace")
        logged_integers = [int(x) for x in re.findall(r"(?m)^\s*([+-]?\d+)\s*$", appended)]
        assert expected in logged_integers, (
            f"Hook did not append analyzer output {expected} for the current /app/telemetry.mp4. "
            f"Appended log content: {appended!r}"
        )

        deployed_script = "/home/user/deploy/analyze.py"
        remote_script = subprocess.check_output(
            ["git", "--git-dir=/home/user/telemetry.git", "show", "master:analyze.py"]
        )
        with open(deployed_script, "rb") as f:
            assert f.read() == remote_script, "deploy/analyze.py is not the version from the pushed master branch"
    finally:
        if os.path.exists(backup):
            os.replace(backup, original_video)
        if os.path.exists(replacement):
            os.unlink(replacement)
        shutil.rmtree(clone_dir, ignore_errors=True)


def test_analyze_script_metric():
    """Verify correctness and performance on the supplied video."""
    script_path = "/home/user/deploy/analyze.py"
    assert os.path.exists(script_path), f"analyze.py missing at {script_path}"

    video_path = "/app/telemetry.mp4"
    assert os.path.exists(video_path), f"Video fixture missing at {video_path}"

    start_time = time.time()
    try:
        count = run_analyzer(script_path, video_path, timeout=5.0)
    except subprocess.TimeoutExpired:
        pytest.fail("analyze.py took longer than 5.0 seconds to execute, well above the 1.5s threshold")
    duration = time.time() - start_time

    assert count == 45, f"FAILED: Expected 45 red frames, got {count}"
    assert duration <= 1.5, f"Execution time {duration:.3f}s exceeded the 1.5s threshold"


def test_analyze_script_on_derived_inputs():
    """Reject fixed answers by checking independently derived randomized videos."""
    script_path = "/home/user/deploy/analyze.py"
    results = []

    for index, frames in enumerate((121 + secrets.randbelow(40), 205 + secrets.randbelow(45))):
        path = f"/tmp/analyzer-random-{secrets.token_hex(12)}-{index}.mp4"
        try:
            generate_video(path, frames)
            expected = oracle_count(path)
            actual = run_analyzer(script_path, path)
            assert actual == expected, (
                f"analyze.py returned {actual} for a randomized video; independently derived count was {expected}"
            )
            results.append(expected)
        finally:
            if os.path.exists(path):
                os.unlink(path)

    assert results != [45, 45], "Randomized behavioral tests unexpectedly failed to vary the fixture"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
