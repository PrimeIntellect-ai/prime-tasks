#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import json
import os
import re
import signal
import socket
import subprocess
import time
import uuid
import wave
from pathlib import Path

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
EXPECTED_TRANSCRIPT = "the primary sensor malfunctioned due to wildlife interference"


def normalize_text(text):
    text = text.lower()
    text = re.sub(r'[^\w\s]', '', text)
    return re.sub(r'\s+', ' ', text).strip()


def get_json(path, timeout=5):
    try:
        response = requests.get(f"{BASE_URL}{path}", timeout=timeout)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to {BASE_URL}{path}: {e}")
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    try:
        return response.json()
    except ValueError:
        pytest.fail(f"Response from {path} is not valid JSON. Response text: {response.text}")


def listener_pid(port=8080):
    wanted_inode = None
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local = fields[1]
            state = fields[3]
            if int(local.rsplit(':', 1)[1], 16) == port and state == "0A":
                wanted_inode = fields[9]
                break
        if wanted_inode:
            break
    assert wanted_inode is not None, f"No process is listening on port {port}"

    target = f"socket:[{wanted_inode}]"
    for proc in Path("/proc").glob("[0-9]*"):
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    if os.readlink(fd) == target:
                        return int(proc.name)
                except OSError:
                    pass
        except OSError:
            pass
    pytest.fail(f"Could not identify the process listening on port {port}")


def capture_server(pid):
    proc = Path(f"/proc/{pid}")
    argv = [x.decode(errors="surrogateescape") for x in (proc / "cmdline").read_bytes().split(b"\0") if x]
    assert argv, "Listening server has an empty command line"
    executable = os.readlink(proc / "exe")
    assert "python" in executable.lower(), f"Server is not a Python process: {executable}"
    cwd = os.readlink(proc / "cwd")
    env = {}
    for item in (proc / "environ").read_bytes().split(b"\0"):
        if b"=" in item:
            key, value = item.split(b"=", 1)
            env[key.decode(errors="surrogateescape")] = value.decode(errors="surrogateescape")
    return argv, cwd, env


def restart_server(pid, argv, cwd, env):
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    deadline = time.time() + 5
    while time.time() < deadline and Path(f"/proc/{pid}").exists():
        time.sleep(0.1)
    if Path(f"/proc/{pid}").exists():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    subprocess.Popen(
        argv,
        cwd=cwd,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    deadline = time.time() + 120
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.get(f"{BASE_URL}/anomalies", timeout=2)
            if response.status_code == 200:
                return
        except requests.RequestException as e:
            last_error = e
        time.sleep(0.5)
    pytest.fail(f"Restarted server did not become ready: {last_error}")


def derive_anomalies():
    timestamps = []
    for path in Path("/app/dataset/logs").rglob("*.log.gz"):
        with gzip.open(path, "rt") as stream:
            content = stream.read()
        for record in re.findall(r"---BEGIN RECORD---\s*(.*?)\s*---END RECORD---", content, re.S):
            timestamp = re.search(r"^Timestamp:\s*(.+?)\s*$", record, re.M)
            flag = re.search(r"^AnomalyFlag:\s*(TRUE|FALSE)\s*$", record, re.M)
            if timestamp and flag and flag.group(1) == "TRUE":
                timestamps.append(timestamp.group(1))
    return sorted(timestamps)


def test_anomalies_endpoint():
    data = get_json("/anomalies")
    expected_anomalies = [
        "2024-01-05T08:30:00Z",
        "2024-01-15T09:11:00Z"
    ]
    assert isinstance(data, list), f"Expected JSON array, got {type(data)}"
    assert data == expected_anomalies, f"Anomalies mismatch. Expected {expected_anomalies}, got {data}"


def test_transcript_endpoint():
    data = get_json("/transcript")
    assert isinstance(data, dict), f"Expected JSON object, got {type(data)}"
    assert "transcript" in data, "Key 'transcript' missing from JSON response."
    actual_transcript = data["transcript"]
    assert isinstance(actual_transcript, str), "Transcript value must be a string."

    norm_actual = normalize_text(actual_transcript)
    norm_expected = normalize_text(EXPECTED_TRANSCRIPT)
    actual_words = norm_actual.split()
    expected_words = norm_expected.split()
    matched_words = [word for word in expected_words if word in actual_words]
    match_ratio = len(matched_words) / len(expected_words)
    assert match_ratio >= 0.8, (
        f"Transcript does not match closely enough. "
        f"Expected: '{EXPECTED_TRANSCRIPT}', Actual: '{actual_transcript}'"
    )


def test_zz_server_reprocesses_source_artifacts():
    pid = listener_pid()
    argv, cwd, env = capture_server(pid)

    token = uuid.uuid4().hex
    second = int(token[:2], 16) % 60
    challenge_timestamp = f"2035-07-19T12:34:{second:02d}Z"
    challenge_dir = Path("/app/dataset/logs/verifier_challenge")
    challenge_dir.mkdir(parents=True, exist_ok=True)
    challenge_path = challenge_dir / f"{token}.log.gz"
    record = f"""---BEGIN RECORD---
Timestamp: {challenge_timestamp}
SensorID: VERIFY-{token}
Reading: 777.7
AnomalyFlag: TRUE
---END RECORD---
"""
    with gzip.open(challenge_path, "wt") as stream:
        stream.write(record)

    # Replace the note with valid silent WAV audio. A real transcription pass should
    # no longer return the words from the original spoken field note.
    with wave.open("/app/field_audio.wav", "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(16000)
        wav.writeframes(b"\x00\x00" * 32000)

    expected_anomalies = derive_anomalies()
    assert challenge_timestamp in expected_anomalies
    restart_server(pid, argv, cwd, env)

    anomaly_data = get_json("/anomalies")
    assert isinstance(anomaly_data, list), f"Expected JSON array, got {type(anomaly_data)}"
    assert anomaly_data == expected_anomalies, (
        f"Server did not parse the changed recursive gzip dataset. "
        f"Expected {expected_anomalies}, got {anomaly_data}"
    )

    transcript_data = get_json("/transcript")
    assert isinstance(transcript_data, dict), f"Expected JSON object, got {type(transcript_data)}"
    assert "transcript" in transcript_data, "Key 'transcript' missing from JSON response."
    changed_transcript = transcript_data["transcript"]
    assert isinstance(changed_transcript, str), "Transcript value must be a string."
    original_words = normalize_text(EXPECTED_TRANSCRIPT).split()
    changed_words = normalize_text(changed_transcript).split()
    retained = sum(word in changed_words for word in original_words) / len(original_words)
    assert retained < 0.3, (
        "Transcript remained the hardcoded original phrase after the WAV was replaced "
        f"with silence: {changed_transcript!r}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
