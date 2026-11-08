#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import struct
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import uuid
import pytest


def make_wav(audio_format=1, riff_id=b"RIFF", wave_id=b"WAVE", riff_size_delta=0, payload=None):
    if payload is None:
        payload = os.urandom(24)
    fmt_body = struct.pack("<HHIIHH", audio_format, 1, 8000, 16000, 2, 16)
    body = wave_id + b"fmt " + struct.pack("<I", len(fmt_body)) + fmt_body
    body += b"data" + struct.pack("<I", len(payload)) + payload
    return riff_id + struct.pack("<I", len(body) + riff_size_delta) + body


def run_filter(path):
    return subprocess.run(
        ["/home/user/filter", path], capture_output=True, timeout=3
    ).returncode


def test_node_code_txt():
    """Verify that the node code was extracted correctly."""
    path = "/home/user/node_code.txt"
    assert os.path.isfile(path), f"File not found: {path}"
    with open(path, "r") as f:
        content = f.read().strip().upper()
    assert content == "EPSILON-ECHO-9", f"Expected 'EPSILON-ECHO-9', got '{content}'"


def test_filter_binary_adversarial_corpus():
    """Verify the filter binary correctly classifies clean and evil corpora."""
    binary_path = "/home/user/filter"
    assert os.path.isfile(binary_path), f"Binary not found: {binary_path}"
    assert os.access(binary_path, os.X_OK), f"Binary is not executable: {binary_path}"

    clean_dir = "/app/corpora/clean/"
    evil_dir = "/app/corpora/evil/"

    clean_failed = []
    for filename in os.listdir(clean_dir):
        filepath = os.path.join(clean_dir, filename)
        if os.path.isfile(filepath):
            result = subprocess.run([binary_path, filepath], capture_output=True)
            if result.returncode != 0:
                clean_failed.append(filename)

    evil_failed = []
    for filename in os.listdir(evil_dir):
        filepath = os.path.join(evil_dir, filename)
        if os.path.isfile(filepath):
            result = subprocess.run([binary_path, filepath], capture_output=True)
            if result.returncode != 1:
                evil_failed.append(filename)

    error_messages = []
    if clean_failed:
        error_messages.append(f"{len(clean_failed)} clean files modified/rejected: {', '.join(clean_failed)}")
    if evil_failed:
        error_messages.append(f"{len(evil_failed)} evil files bypassed/accepted: {', '.join(evil_failed)}")

    assert not error_messages, "Adversarial corpus verification failed: " + "; ".join(error_messages)


def test_filter_generated_wavs():
    """Exercise the compiled C artifact on fresh paths and verifier-derived WAV variants."""
    source_path = "/home/user/filter.c"
    binary_path = "/home/user/filter"
    assert os.path.isfile(source_path), f"C source not found: {source_path}"
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "filter must be a compiled executable"

    payload = os.urandom(31)
    cases = [
        (make_wav(payload=payload), 0),
        (make_wav(riff_id=b"NOPE", payload=payload), 1),
        (make_wav(wave_id=b"BADD", payload=payload), 1),
        (make_wav(audio_format=2, payload=payload), 1),
        (make_wav(riff_size_delta=1, payload=payload), 1),
        (make_wav(riff_size_delta=-1, payload=payload), 1),
    ]
    random.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="wav-validation-") as td:
        for data, expected in cases:
            path = os.path.join(td, uuid.uuid4().hex + ".wav")
            with open(path, "wb") as f:
                f.write(data)
            actual = run_filter(path)
            assert actual == expected, (
                f"fresh WAV validation returned {actual}, expected {expected}"
            )


def test_pipeline_and_dirs():
    """Verify pipeline script and required directories exist."""
    script_path = "/home/user/pipeline.sh"
    assert os.path.isfile(script_path), f"Script not found: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"

    for d in ["/home/user/incoming", "/home/user/approved", "/home/user/rejected"]:
        assert os.path.isdir(d), f"Directory not found: {d}"


def test_pipeline_moves_fresh_files():
    """Run the pipeline and verify fresh WAVs are routed using their validity."""
    incoming = "/home/user/incoming"
    approved = "/home/user/approved"
    rejected = "/home/user/rejected"
    token = uuid.uuid4().hex
    clean_name = token + "a.wav"
    evil_name = token + "b.wav"

    cases = [
        (clean_name, make_wav(payload=os.urandom(19)), approved),
        (evil_name, make_wav(audio_format=2, payload=os.urandom(19)), rejected),
    ]
    random.shuffle(cases)

    for name, data, destination in cases:
        for directory in (incoming, approved, rejected):
            try:
                os.unlink(os.path.join(directory, name))
            except FileNotFoundError:
                pass
        temporary = os.path.join("/tmp", uuid.uuid4().hex)
        with open(temporary, "wb") as f:
            f.write(data)
        os.replace(temporary, os.path.join(incoming, name))

    result = subprocess.run(["/home/user/pipeline.sh"], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"pipeline failed: {result.stderr}"

    for name, data, destination in cases:
        expected = os.path.join(destination, name)
        assert os.path.isfile(expected), f"pipeline did not move {name} to {destination}"
        assert not os.path.exists(os.path.join(incoming, name)), f"pipeline left {name} in incoming"
        with open(expected, "rb") as f:
            assert f.read() == data, f"pipeline altered {name}"


def test_cron_job():
    """Verify the cron job is set up correctly."""
    result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to run crontab -l"

    cron_lines = result.stdout.strip().split('\n')
    expected_job = "* * * * * /home/user/pipeline.sh"

    found = any(expected_job in line for line in cron_lines if not line.strip().startswith('#'))
    assert found, f"Cron job '{expected_job}' not found in crontab"


def nginx_listener_processes(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                lines = f.readlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[3] == "0A":
                local_port = int(fields[1].rsplit(":", 1)[1], 16)
                if local_port == port:
                    inodes.add(fields[9])

    owners = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            fds = os.listdir(fd_dir)
        except OSError:
            continue
        owns_socket = False
        for fd in fds:
            try:
                target = os.readlink(os.path.join(fd_dir, fd))
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                owns_socket = True
                break
        if not owns_socket:
            continue
        try:
            with open(f"/proc/{pid}/comm", "r") as f:
                comm = f.read().strip()
            with open(f"/proc/{pid}/status", "r") as f:
                status = f.read().splitlines()
            uid_line = next(line for line in status if line.startswith("Uid:"))
            effective_uid = int(uid_line.split()[2])
            owners.append((comm, effective_uid))
        except (OSError, StopIteration, ValueError):
            continue
    return owners


def test_nginx_config_and_running():
    """Verify Nginx configuration and that it is serving approved files on port 8080."""
    conf_path = "/home/user/nginx.conf"
    assert os.path.isfile(conf_path), f"Nginx config not found: {conf_path}"

    with open(conf_path, "r") as f:
        conf_content = f.read()

    assert "root /home/user/approved" in conf_content or "root /home/user/approved/" in conf_content, \
        "Nginx config does not define root as /home/user/approved/"
    assert "/home/user/nginx_logs/" in conf_content, "Nginx config does not use nginx_logs"
    assert "/home/user/nginx_temp/" in conf_content, "Nginx config does not use nginx_temp"
    assert os.path.isdir("/home/user/nginx_logs"), "Nginx log directory is missing"
    assert os.path.isdir("/home/user/nginx_temp"), "Nginx temporary directory is missing"

    try:
        req = urllib.request.Request("http://127.0.0.1:8080/")
        with urllib.request.urlopen(req, timeout=2) as response:
            status = response.getcode()
            assert status in [200, 403], f"Unexpected status code {status}"
    except urllib.error.HTTPError as e:
        assert e.code in [200, 403], f"Unexpected HTTP error code {e.code}"
    except Exception as e:
        pytest.fail(f"Failed to connect to Nginx on port 8080: {e}")

    name = uuid.uuid4().hex + ".wav"
    body = os.urandom(97)
    served_path = os.path.join("/home/user/approved", name)
    with open(served_path, "wb") as f:
        f.write(body)
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:8080/{name}", timeout=3) as response:
            assert response.getcode() == 200
            assert response.read() == body, "port 8080 did not serve the approved file"
            assert "nginx" in response.headers.get("Server", "").lower(), "HTTP service is not Nginx"
    finally:
        try:
            os.unlink(served_path)
        except FileNotFoundError:
            pass

    owners = nginx_listener_processes(8080)
    assert owners, "No process owns the listening socket on port 8080"
    assert all(comm == "nginx" for comm, uid in owners), f"Port 8080 is not owned by Nginx: {owners}"
    assert all(uid != 0 for comm, uid in owners), f"Nginx on port 8080 is running as root: {owners}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
