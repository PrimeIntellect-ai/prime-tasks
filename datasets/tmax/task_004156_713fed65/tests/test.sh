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
import json
import os
import random
import signal
import socket
import subprocess
import tempfile
import time
from pathlib import Path

import pytest
import requests

BIN_PATH = "/home/user/release_bin"
AUDIO_PATH = Path("/app/voicemail.wav")
URL = "http://127.0.0.1:9000/analyze"


def test_release_bin_exists_and_statically_linked():
    """Check that the compiled binary exists at the correct path and is statically linked."""
    assert os.path.isfile(BIN_PATH), f"Compiled binary is missing at {BIN_PATH}"

    result = subprocess.run(["file", BIN_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"Failed to run file command on {BIN_PATH}"
    assert "statically linked" in result.stdout, (
        f"Binary at {BIN_PATH} is not statically linked. File output: {result.stdout}"
    )


def test_http_server_analyze_endpoint():
    """Check that the server was left running and handles the original fixture."""
    try:
        response = requests.get(URL, timeout=30)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the server at {URL}: {exc}")

    assert response.status_code == 200, (
        f"Expected HTTP 200 OK, but got {response.status_code}. Response: {response.text}"
    )

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response body is not valid JSON. Response: {response.text}")

    assert "secret" in data, f"JSON response missing 'secret' key. Response: {data}"
    secret_text = data["secret"].lower()
    for token in ["delta", "tango", "seven"]:
        assert token in secret_text, (
            f"Transcribed text is missing expected token '{token}'. "
            f"Transcribed text: {data['secret']}"
        )


def _listener_pids(port):
    inodes = set()
    target_port = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[1].split(":")[-1] == target_port and fields[3] == "0A":
                inodes.add(fields[9])

    pids = set()
    for proc_dir in Path("/proc").iterdir():
        if not proc_dir.name.isdigit():
            continue
        try:
            for fd in (proc_dir / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(proc_dir.name))
        except OSError:
            continue
    return pids


def _stop_existing_listener():
    for pid in _listener_pids(9000):
        os.kill(pid, signal.SIGKILL)
    deadline = time.time() + 5
    while time.time() < deadline:
        if not _listener_pids(9000):
            return
        time.sleep(0.05)
    pytest.fail("Could not stop the existing listener on port 9000")


def _wait_for_port(proc):
    deadline = time.time() + 10
    while time.time() < deadline:
        assert proc.poll() is None, "release_bin exited before opening port 9000"
        try:
            with socket.create_connection(("127.0.0.1", 9000), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    pytest.fail("release_bin did not listen on 127.0.0.1:9000")


def _replace_audio(spoken_text):
    fd, temp_name = tempfile.mkstemp(prefix="verifier-audio-", suffix=".wav", dir="/app")
    os.close(fd)
    try:
        result = subprocess.run(
            ["espeak", "-w", temp_name, spoken_text],
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, f"espeak failed: {result.stderr}"
        os.chmod(temp_name, 0o644)
        os.replace(temp_name, AUDIO_PATH)
    finally:
        if os.path.exists(temp_name):
            os.unlink(temp_name)


def test_release_binary_transcribes_current_audio_and_enforces_constraint():
    """Run the submitted artifact and exercise fresh valid and invalid audio."""
    original_audio = AUDIO_PATH.read_bytes()
    original_mode = AUDIO_PATH.stat().st_mode & 0o777
    proc = None

    words = [
        "apple", "banana", "garden", "purple", "rabbit", "river",
        "silver", "tiger", "window", "yellow", "Monday", "sunset",
    ]
    rng = random.SystemRandom()
    valid_cases = []
    for _ in range(2):
        markers = rng.sample(words, 3)
        valid_cases.append((True, markers, "The secret code is " + " ".join(markers) + "."))
    invalid_markers = rng.sample(words, 3)
    cases = valid_cases + [
        (False, invalid_markers, "The secret message is " + " ".join(invalid_markers) + ".")
    ]
    rng.shuffle(cases)

    try:
        _stop_existing_listener()
        proc = subprocess.Popen(
            [BIN_PATH],
            cwd="/home/user/audio-server",
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        _wait_for_port(proc)

        for contains_code, markers, spoken_text in cases:
            _replace_audio(spoken_text)
            response = requests.get(URL, timeout=30)

            try:
                data = response.json()
            except ValueError:
                pytest.fail(f"Response body is not valid JSON for audio '{spoken_text}': {response.text}")

            if contains_code:
                assert response.status_code == 200, (
                    f"Expected HTTP 200 for audio containing 'code', got {response.status_code}: "
                    f"{response.text}"
                )
                assert "secret" in data, f"JSON response missing 'secret' key: {data}"
                assert isinstance(data["secret"], str), f"'secret' must be a string: {data}"
                transcript = data["secret"].lower()
                for marker in markers:
                    assert marker.lower() in transcript, (
                        f"Fresh audio token '{marker}' is missing from transcription: {data['secret']}"
                    )
            else:
                assert response.status_code == 400, (
                    f"Expected HTTP 400 for audio without 'code', got {response.status_code}: "
                    f"{response.text}"
                )
                assert data == {"error": "constraint failed"}, (
                    f"Incorrect constraint failure JSON: {data}"
                )

        assert proc.poll() is None, "release_bin exited while serving requests"
    finally:
        restore = AUDIO_PATH.with_name("verifier-restore.wav")
        restore.write_bytes(original_audio)
        os.chmod(restore, original_mode)
        os.replace(restore, AUDIO_PATH)
        if proc is not None and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
