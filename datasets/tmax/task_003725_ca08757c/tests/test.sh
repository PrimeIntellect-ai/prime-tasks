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
import atexit
import json
import os
import random
import re
import shutil
import subprocess
import tempfile
import time

import requests

SERVICE = "/home/user/service"
FILTER = os.path.join(SERVICE, "filter")
SOURCE = os.path.join(SERVICE, "filter.c")
MESSAGE = "/app/data/message.wav"
MARKER = "/tmp/filter-invocation.json"
REAL_FILTER = os.path.join(SERVICE, ".filter.verifier-real")
CHALLENGE_WAV = "/tmp/verifier-challenge.wav"

_saved_message = tempfile.mktemp(prefix="message-backup-", suffix=".wav")
shutil.copy2(MESSAGE, _saved_message)


def restore_state():
    try:
        if os.path.exists(REAL_FILTER):
            os.replace(REAL_FILTER, FILTER)
    except Exception:
        pass
    try:
        if os.path.exists(_saved_message):
            shutil.copy2(_saved_message, MESSAGE)
            os.unlink(_saved_message)
    except Exception:
        pass


atexit.register(restore_state)


def run(cmd, **kwargs):
    kwargs.setdefault("cwd", SERVICE)
    kwargs.setdefault("timeout", 30)
    kwargs.setdefault("check", True)
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, **kwargs)


def assert_valid_audio(path):
    assert os.path.isfile(path), f"Filter did not create output audio: {path}"
    assert os.path.getsize(path) > 44, f"Output audio is empty or truncated: {path}"
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-f", "null", "-"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, f"Output is not valid decodable audio: {result.stderr.decode(errors='replace')}"


def test_filter_executable_exists():
    """Verify the filter is built from the supplied C source and produces valid audio."""
    assert os.path.isfile(FILTER), f"The executable {FILTER} is missing. Did you run make?"
    assert os.access(FILTER, os.X_OK), f"The file {FILTER} is not executable."
    assert os.path.isfile(SOURCE), f"The C source {SOURCE} is missing."

    # The C source itself must compile, independently of any pre-existing artifact.
    source_binary = "/tmp/filter-built-directly-from-source"
    run(["gcc", "-O2", SOURCE, "-o", source_binary, "-lm"])
    assert open(source_binary, "rb").read(4) == b"\x7fELF", "filter.c did not compile to a native executable"

    # Removing the submitted executable ensures `make` really recreates it.
    os.unlink(FILTER)
    run(["make", "-B"])
    assert os.path.isfile(FILTER), "Running make did not produce filter"
    assert os.access(FILTER, os.X_OK), "The filter produced by make is not executable"
    assert open(FILTER, "rb").read(4) == b"\x7fELF", "The filter produced by make is not a native executable"

    probe_input = "/tmp/filter-probe-input.wav"
    subprocess.run(["espeak", "-w", probe_input, "filter validation audio"], check=True, timeout=30)
    for binary, output in ((FILTER, "/tmp/filter-make-output.wav"),
                           (source_binary, "/tmp/filter-source-output.wav")):
        if os.path.exists(output):
            os.unlink(output)
        run([binary, probe_input, output])
        assert_valid_audio(output)

    # Preserve the verified native binary and instrument the requested path. The
    # wrapper records arguments and substitutes unpredictable output audio, proving
    # that the server invokes filter and transcribes its output rather than its input.
    os.replace(FILTER, REAL_FILTER)
    wrapper = '''#!/usr/bin/env python3
import json, os, shutil, subprocess, sys
args = sys.argv[1:]
with open("/tmp/filter-invocation.json", "w") as f:
    json.dump(args, f)
if len(args) < 2:
    sys.exit(2)
result = subprocess.run(["/home/user/service/.filter.verifier-real"] + args)
if result.returncode != 0:
    sys.exit(result.returncode)
shutil.copyfile("/tmp/verifier-challenge.wav", args[1])
'''
    with open(FILTER, "w") as f:
        f.write(wrapper)
    os.chmod(FILTER, 0o755)


def test_server_log_exists():
    """Verify that the server log file was created."""
    log_path = "/home/user/server.log"
    assert os.path.isfile(log_path), f"The server log file {log_path} is missing."


def test_server_transcribe_endpoint():
    """Verify the endpoint runs the filter and transcribes dynamically chosen output audio."""
    colors = ["red", "blue", "green", "black"]
    subjects = ["tiger", "robot", "rabbit", "sailor"]
    places = ["garden", "station", "river", "market"]
    color = random.SystemRandom().choice(colors)
    subject = random.SystemRandom().choice(subjects)
    place = random.SystemRandom().choice(places)
    expected_phrase = f"the {color} {subject} walks to the {place}"

    # The endpoint input says something different. Only filter's output contains the
    # challenge phrase, so transcribing the original input cannot satisfy the test.
    subprocess.run(
        ["espeak", "-w", MESSAGE, "this is the decoy input audio"],
        check=True,
        timeout=30,
    )
    subprocess.run(["espeak", "-w", CHALLENGE_WAV, expected_phrase], check=True, timeout=30)
    if os.path.exists(MARKER):
        os.unlink(MARKER)

    url = "http://127.0.0.1:8888/api/v1/transcribe"
    max_retries = 3
    response = None
    for i in range(max_retries):
        try:
            response = requests.get(url, timeout=30)
            break
        except requests.exceptions.RequestException as e:
            if i == max_retries - 1:
                assert False, f"Failed to connect to the server at {url}: {e}"
            time.sleep(1)

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        assert False, f"Response is not valid JSON. Response text: {response.text}"

    assert "version" in data, "Response JSON is missing the 'version' key"
    assert data["version"] == "v2", f"Expected version 'v2', got '{data['version']}'"
    assert "data" in data, "Response JSON is missing the 'data' key"
    assert isinstance(data["data"], dict), "Response 'data' must be a JSON object"
    assert "status" in data["data"], "Response JSON is missing the 'data.status' key"
    assert data["data"]["status"] == "success", f"Expected status 'success', got '{data['data']['status']}'"
    assert "transcript" in data["data"], "Response JSON is missing the 'data.transcript' key"

    transcript = data["data"]["transcript"]
    assert isinstance(transcript, str), "The transcript must be a string"
    assert transcript == transcript.lower(), f"Transcript must be lowercase, got {transcript!r}"
    normalized = re.sub(r"[^a-z]+", " ", transcript).strip().split()
    for token in (color, subject, place):
        assert token in normalized, (
            f"Expected transcription of dynamic filter output {expected_phrase!r}, got {transcript!r}"
        )
    assert len(normalized) <= len(expected_phrase.split()) + 3, "Transcript contains unrelated or hardcoded word lists"
    assert "decoy" not in normalized, "Server transcribed the input instead of the filter output"

    assert os.path.isfile(MARKER), "The endpoint did not execute /home/user/service/filter"
    with open(MARKER) as f:
        args = json.load(f)
    assert len(args) >= 2, f"Filter was not called with input and output paths: {args!r}"
    assert os.path.realpath(args[0]) == os.path.realpath(MESSAGE), (
        f"Filter input must be {MESSAGE}, got {args[0]!r}"
    )
    assert os.path.realpath(args[1]) != os.path.realpath(MESSAGE), "Filter output must be a separate temporary file"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
