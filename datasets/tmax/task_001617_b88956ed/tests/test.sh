#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import signal
import subprocess
import time
from pathlib import Path

import pytest
import requests

URL = "http://127.0.0.1:8080/api/artifact"
IMAGE = Path("/app/artifact_info.png")


def request_artifact(retries=10):
    last_error = None
    for _ in range(retries):
        try:
            return requests.get(URL, timeout=2)
        except requests.exceptions.RequestException as exc:
            last_error = exc
            time.sleep(0.5)
    pytest.fail(f"Failed to connect to the server at {URL}: {last_error}")


def listener_pid():
    socket_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[1].split(":")[-1].upper() == "1F90" and fields[3] == "0A":
                socket_inodes.add(fields[9])

    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                target = os.readlink(fd)
                if target.startswith("socket:[") and target[8:-1] in socket_inodes:
                    return int(proc.name)
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return None


def capture_server_command(pid):
    raw = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
    argv = [item.decode(errors="surrogateescape") for item in raw if item]
    assert argv, "Could not determine the running server command"
    cwd = os.readlink(f"/proc/{pid}/cwd")
    env = os.environ.copy()
    try:
        entries = Path(f"/proc/{pid}/environ").read_bytes().split(b"\0")
        env = {}
        for entry in entries:
            if b"=" in entry:
                key, value = entry.split(b"=", 1)
                env[key.decode(errors="surrogateescape")] = value.decode(errors="surrogateescape")
    except OSError:
        pass
    return argv, cwd, env


def stop_listener():
    pid = listener_pid()
    if pid is None:
        return
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    for _ in range(20):
        if listener_pid() is None:
            return
        time.sleep(0.1)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    time.sleep(0.2)


def render_image(version, matrix):
    draw = (
        f"text 20,40 'BUILD_VERSION: {version}' "
        f"text 20,80 'COEFFICIENTS:' "
        f"text 20,120 '{matrix[0][0]} {matrix[0][1]}' "
        f"text 20,160 '{matrix[1][0]} {matrix[1][1]}'"
    )
    subprocess.run([
        "convert", "-size", "560x200", "xc:white",
        "-font", "DejaVu-Sans", "-pointsize", "24", "-fill", "black",
        "-draw", draw, str(IMAGE)
    ], check=True)


def semver_greater_than_baseline(version):
    core, sep, prerelease = version.partition("-")
    major, minor, patch = (int(x) for x in core.split("."))
    if (major, minor, patch) != (2, 0, 0):
        return (major, minor, patch) > (2, 0, 0)
    return False  # 2.0.0 itself and its prereleases are not strictly greater.


def assert_payload(response, version, determinant):
    assert response is not None, "Response should not be None."
    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")
    assert "version" in data, "The JSON response must contain a 'version' key."
    assert "determinant" in data, "The JSON response must contain a 'determinant' key."
    assert data["version"] == version, f"Expected version {version!r}, got {data['version']!r}"
    assert data["determinant"] == determinant, (
        f"Expected determinant {determinant}, got {data['determinant']}"
    )


def test_api_artifact_endpoint_and_dynamic_processing():
    # Preserve the original verifier's assertions against the supplied artifact.
    response = request_artifact()
    assert_payload(response, "2.1.4", 29)

    pid = listener_pid()
    assert pid is not None, "No process was found listening on 127.0.0.1:8080"
    argv, cwd, env = capture_server_command(pid)
    original_image = IMAGE.read_bytes()

    rng = random.SystemRandom()
    cases = [
        (f"2.0.{rng.randint(1, 9)}", [[rng.randint(1, 9) for _ in range(2)] for _ in range(2)]),
        (f"1.9.{rng.randint(1, 9)}", [[rng.randint(1, 9) for _ in range(2)] for _ in range(2)]),
        ("2.0.0-rc.1", [[rng.randint(1, 9) for _ in range(2)] for _ in range(2)]),
    ]

    child = None
    try:
        stop_listener()
        for version, matrix in cases:
            render_image(version, matrix)
            raw_det = matrix[0][0] * matrix[1][1] - matrix[0][1] * matrix[1][0]
            expected = raw_det if semver_greater_than_baseline(version) else 0

            child = subprocess.Popen(
                argv, cwd=cwd, env=env,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            response = request_artifact()
            assert_payload(response, version, expected)
            stop_listener()
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    child.kill()
            child = None
    finally:
        stop_listener()
        if child is not None and child.poll() is None:
            child.kill()
        IMAGE.write_bytes(original_image)
        # Leave the requested server running with the original artifact.
        subprocess.Popen(
            argv, cwd=cwd, env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
