#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import signal
import socket
import subprocess
import time
from pathlib import Path

import pytest

HOST = "127.0.0.1"
PORT = 9090
SOURCE = Path("/home/user/loc_server.c")
BINARY = Path("/tmp/loc_server_verified")
REPO = Path("/home/user/whisper.cpp")


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[3] == "0A":
                try:
                    local_port = int(fields[1].rsplit(":", 1)[1], 16)
                except ValueError:
                    continue
                if local_port == port:
                    inodes.add(fields[9])

    result = set()
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        fd_dir = entry / "fd"
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    result.add(int(entry.name))
        except (OSError, PermissionError):
            continue
    return result


def stop_existing_listener():
    for pid in listener_pids(PORT):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listener_pids(PORT):
        time.sleep(0.05)
    for pid in listener_pids(PORT):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def send_request(message):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(5.0)
            sock.connect((HOST, PORT))
            sock.sendall(message.encode("utf-8"))
            chunks = []
            while True:
                chunk = sock.recv(1024)
                if not chunk:
                    break
                chunks.append(chunk)
            return b"".join(chunks).decode("utf-8")
    except Exception as exc:
        pytest.fail(f"Failed to connect to or receive data from {HOST}:{PORT}: {exc}")


@pytest.fixture(scope="session", autouse=True)
def compiled_submission_server():
    assert SOURCE.is_file(), f"The C source code file is missing: {SOURCE}"
    assert SOURCE.stat().st_size > 0, "The C source code is empty"

    stop_existing_listener()
    result = subprocess.run(
        ["gcc", str(SOURCE), "-O2", "-o", str(BINARY)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, f"loc_server.c did not compile with gcc:\n{result.stderr}"
    assert BINARY.read_bytes()[:4] == b"\x7fELF", "gcc did not produce a native executable"

    proc = subprocess.Popen(
        [str(BINARY)],
        cwd="/home/user",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    deadline = time.time() + 5
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f"The compiled loc_server exited with status {proc.returncode}")
        try:
            with socket.create_connection((HOST, PORT), timeout=0.2):
                break
        except OSError:
            time.sleep(0.05)
    else:
        proc.terminate()
        pytest.fail("The compiled loc_server did not listen on 127.0.0.1:9090")

    yield

    stop_existing_listener()
    if proc.poll() is None:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass


def test_c_source_code_exists():
    assert os.path.isfile("/home/user/loc_server.c"), "The C source code file is missing: /home/user/loc_server.c"


def test_official_whisper_checkout_and_build():
    assert (REPO / ".git").exists(), "whisper.cpp was not cloned as a git repository"
    remote = subprocess.run(
        ["git", "-c", f"safe.directory={REPO}", "-C", str(REPO), "config", "--get", "remote.origin.url"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert remote.returncode == 0, "Could not inspect the whisper.cpp git remote"
    normalized = remote.stdout.strip().lower().removesuffix(".git").rstrip("/")
    assert normalized.endswith("github.com/ggerganov/whisper.cpp"), f"Unexpected whisper.cpp origin: {remote.stdout.strip()}"

    candidates = [
        REPO / "main",
        REPO / "build/bin/main",
        REPO / "build/bin/whisper-cli",
        REPO / "bin/whisper-cli",
    ]
    assert any(p.is_file() and p.read_bytes()[:4] == b"\x7fELF" for p in candidates), \
        "No compiled whisper.cpp CLI executable was found"

    model = REPO / "models/ggml-base.en.bin"
    assert model.is_file(), "The ggml-base.en.bin model is missing"
    assert model.stat().st_size > 100_000_000, "ggml-base.en.bin is not a complete base.en model"


def test_timestamped_transcription_output_exists():
    outputs = []
    for root in (Path("/home/user"), Path("/app")):
        for pattern in ("*.csv", "*.vtt"):
            outputs.extend(root.rglob(pattern))

    valid = []
    for path in outputs:
        try:
            if path.stat().st_size > 5_000_000:
                continue
            text = path.read_text(errors="ignore").lower()
        except OSError:
            continue
        has_timestamps = "-->" in text or (
            "start" in text and "end" in text and any(ch.isdigit() for ch in text)
        )
        phrases = (
            "welcome to the system",
            "please enter your password",
            "login successful",
        )
        if has_timestamps and all(phrase in text for phrase in phrases):
            valid.append(path)
    assert valid, "No CSV or VTT transcription with timestamps and the dialogue content was found"


@pytest.mark.parametrize("bucket, expected_response", [
    ("0\n", "welcome to the system [LOC-EN]\n"),
    ("10\n", "please enter your password [LOC-EN]\n"),
    ("20\n", "login successful [LOC-EN]\n"),
    ("30\n", "EMPTY [LOC-EN]\n"),
])
def test_tcp_server_responses(bucket, expected_response):
    assert send_request(bucket) == expected_response


def test_general_empty_bucket_protocol():
    occupied = {0, 10, 20}
    rng = random.SystemRandom()
    buckets = set()
    while len(buckets) < 12:
        value = rng.randrange(4, 100000) * 10
        if value not in occupied:
            buckets.add(value)
    for bucket in buckets:
        assert send_request(f"{bucket}\n") == "EMPTY [LOC-EN]\n"


def test_server_handles_repeated_connections():
    requests = [
        (20, "login successful [LOC-EN]\n"),
        (0, "welcome to the system [LOC-EN]\n"),
        (10, "please enter your password [LOC-EN]\n"),
        (20, "login successful [LOC-EN]\n"),
    ]
    for bucket, expected in requests:
        assert send_request(f"{bucket}\n") == expected
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
