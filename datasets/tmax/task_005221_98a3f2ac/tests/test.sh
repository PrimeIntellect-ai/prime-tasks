#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shlex
import shutil
import socket
import subprocess
import tempfile
import time

import cv2
import numpy as np
import pytest
import requests

HOME = "/home/user"
FEED = "/app/feed.mp4"
MANAGE = f"{HOME}/manage.sh"
DEPLOY = f"{HOME}/deploy.sh"


def is_port_open(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        return sock.connect_ex(("127.0.0.1", port)) == 0


def get_json(path):
    try:
        response = requests.get(f"http://127.0.0.1:8080{path}", timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to {path} endpoint: {exc}")
    assert response.status_code == 200, (
        f"Expected status code 200 from {path}, got {response.status_code}"
    )
    try:
        return response.json()
    except ValueError:
        pytest.fail(f"Response from {path} is not valid JSON")


def expected_black_frames(path):
    capture = cv2.VideoCapture(path)
    assert capture.isOpened(), f"Could not open generated video {path}"
    result = []
    index = 0
    while True:
        ok, frame = capture.read()
        if not ok:
            break
        if float(frame.mean()) == 0.0:
            result.append(index)
        index += 1
    capture.release()
    assert index > 0, "Generated test video contained no frames"
    return result


def create_random_feed(destination):
    frame_count = 11
    intended = sorted(secrets.SystemRandom().sample(range(frame_count), 3))
    with tempfile.TemporaryDirectory(prefix="verifier_frames_") as directory:
        for index in range(frame_count):
            value = 0 if index in intended else 255
            frame = np.full((96, 128, 3), value, dtype=np.uint8)
            path = os.path.join(directory, f"frame_{index:03d}.png")
            assert cv2.imwrite(path, frame), f"Failed to write {path}"
        subprocess.run(
            [
                "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                "-framerate", "1", "-i", os.path.join(directory, "frame_%03d.png"),
                "-c:v", "libx264", "-pix_fmt", "yuv420p", "-r", "1",
                destination,
            ],
            check=True,
        )
    decoded = expected_black_frames(destination)
    assert decoded == intended, (
        f"Test video did not decode as constructed: intended {intended}, got {decoded}"
    )
    return decoded


def wait_for_port(open_state, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if is_port_open(8080) == open_state:
            return True
        time.sleep(0.1)
    return is_port_open(8080) == open_state


def test_scripts_exist():
    scripts = [
        "/home/user/monitor.py",
        "/home/user/manage.sh",
        "/home/user/deploy.sh",
    ]
    for script in scripts:
        assert os.path.exists(script), f"Script {script} does not exist"
        assert os.access(script, os.X_OK) or script.endswith(".py"), (
            f"Script {script} is not executable"
        )


def test_health_endpoint():
    data = get_json("/health")
    assert data.get("status") == "ok", f"Expected {{'status': 'ok'}}, got {data}"


def test_alerts_endpoint():
    data = get_json("/alerts")
    assert "black_frames" in data, "Response JSON missing 'black_frames' key"
    frames = data["black_frames"]
    assert isinstance(frames, list), "'black_frames' should be a list"
    assert sorted(frames) == [3, 8], f"Expected black frames [3, 8], got {frames}"


def test_manage_sh_lifecycle():
    status_proc = subprocess.run([MANAGE, "status"], capture_output=True)
    assert status_proc.returncode == 0, (
        f"manage.sh status returned non-zero exit code: {status_proc.returncode}"
    )

    stop_proc = subprocess.run([MANAGE, "stop"], capture_output=True)
    assert stop_proc.returncode == 0, (
        f"manage.sh stop returned non-zero exit code: {stop_proc.returncode}"
    )
    time.sleep(1)
    assert not is_port_open(8080), "Port 8080 is still bound after running manage.sh stop"


def test_deploy_restarts_service_and_analyzes_changed_feed():
    token = f"{os.getpid()}_{secrets.token_hex(4)}"
    feed_backup = f"/tmp/feed_backup_{token}.mp4"
    generated_feed = f"/tmp/generated_feed_{token}.mp4"
    manage_backup = f"/tmp/manage_backup_{token}.sh"
    trace_file = f"/tmp/manage_trace_{token}.txt"
    delayed_pid_file = f"/tmp/manage_delayed_{token}.pid"

    shutil.copy2(FEED, feed_backup)
    expected = create_random_feed(generated_feed)
    assert expected != [3, 8]
    os.replace(generated_feed, FEED)
    os.chmod(FEED, 0o777)

    shutil.move(MANAGE, manage_backup)
    wrapper = f'''#!/bin/bash
set -e
printf '%s\\n' "$1" >> {shlex.quote(trace_file)}
if [ "$1" = "start" ]; then
    nohup bash -c 'sleep 2; exec "$1" start' _ {shlex.quote(manage_backup)} \
        >/tmp/verifier_delayed_start.log 2>&1 &
    echo $! > {shlex.quote(delayed_pid_file)}
    exit 0
fi
exec {shlex.quote(manage_backup)} "$@"
'''
    with open(MANAGE, "w", encoding="utf-8") as handle:
        handle.write(wrapper)
    os.chmod(MANAGE, 0o755)

    try:
        started = time.monotonic()
        deploy_proc = subprocess.run(
            [DEPLOY],
            cwd=HOME,
            capture_output=True,
            text=True,
            timeout=40,
        )
        elapsed = time.monotonic() - started
        assert deploy_proc.returncode == 0, (
            f"deploy.sh failed with {deploy_proc.returncode}:\n"
            f"stdout:\n{deploy_proc.stdout}\nstderr:\n{deploy_proc.stderr}"
        )

        with open(trace_file, encoding="utf-8") as handle:
            commands = [line.strip() for line in handle if line.strip()]
        assert "stop" in commands, "deploy.sh did not invoke manage.sh stop"
        assert "start" in commands, "deploy.sh did not invoke manage.sh start"
        assert commands.index("stop") < commands.index("start"), (
            f"deploy.sh did not call stop before start: {commands}"
        )

        # The wrapper returns from start immediately but makes the service become
        # ready two seconds later. A successful deploy must therefore have waited
        # and polled for health rather than merely launching and exiting.
        assert elapsed >= 1.5, (
            f"deploy.sh returned after {elapsed:.2f}s without waiting for delayed health"
        )
        assert is_port_open(8080), "Service was not ready when deploy.sh reported success"

        health = get_json("/health")
        assert health.get("status") == "ok", (
            f"Expected {{'status': 'ok'}} after deployment, got {health}"
        )

        alerts = get_json("/alerts")
        assert "black_frames" in alerts, "Response JSON missing 'black_frames' key"
        frames = alerts["black_frames"]
        assert isinstance(frames, list), "'black_frames' should be a list"
        assert sorted(frames) == expected, (
            f"Expected dynamically derived black frames {expected}, got {frames}"
        )

        status_proc = subprocess.run([MANAGE, "status"], capture_output=True)
        assert status_proc.returncode == 0, (
            f"manage.sh status failed after deployment: {status_proc.returncode}"
        )
    finally:
        if os.path.exists(delayed_pid_file):
            try:
                with open(delayed_pid_file, encoding="utf-8") as handle:
                    delayed_pid = int(handle.read().strip())
                try:
                    os.kill(delayed_pid, 15)
                except ProcessLookupError:
                    pass
            except (OSError, ValueError):
                pass

        if os.path.exists(MANAGE):
            subprocess.run([MANAGE, "stop"], capture_output=True)
            try:
                os.remove(MANAGE)
            except FileNotFoundError:
                pass
        if os.path.exists(manage_backup):
            shutil.move(manage_backup, MANAGE)
        if os.path.exists(feed_backup):
            shutil.copy2(feed_backup, FEED)
            os.chmod(FEED, 0o777)

        # Restore the original feed and leave the submitted service running.
        subprocess.run([MANAGE, "stop"], capture_output=True)
        subprocess.run([MANAGE, "start"], capture_output=True)
        wait_for_port(True, timeout=5)

        for path in (feed_backup, generated_feed, trace_file, delayed_pid_file):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
