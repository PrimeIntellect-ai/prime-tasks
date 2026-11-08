#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import signal
import socket
import stat
import subprocess
import time
from datetime import datetime, timedelta

import pytest

SCRIPT = "/home/user/serve_cleaned.sh"
RAW_FILE = "/home/user/raw_syslogs.txt"
HOST = "127.0.0.1"
PORT = 8333


def parse_date(date_str):
    formats = [
        "%b %d %H:%M:%S %Y",
        "%Y/%m/%d %H:%M:%S",
        "%Y-%m-%d %H:%M:%S",
        "%d %b %Y %H:%M:%S",
    ]
    for fmt in formats:
        try:
            return datetime.strptime(date_str, fmt)
        except ValueError:
            pass
    raise ValueError(f"Could not parse date: {date_str}")


def get_anonymized_email(email):
    result = subprocess.run(
        ["/app/anonymizer", email],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def listening_inodes():
    result = set()
    wanted_port = f"{PORT:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[1].rsplit(":", 1)[-1].upper() == wanted_port and fields[3] == "0A":
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def kill_existing_listener():
    deadline = time.time() + 3
    while time.time() < deadline:
        inodes = listening_inodes()
        if not inodes:
            return
        victims = set()
        for pid in os.listdir("/proc"):
            if not pid.isdigit() or int(pid) == os.getpid():
                continue
            fd_dir = f"/proc/{pid}/fd"
            try:
                for fd in os.listdir(fd_dir):
                    try:
                        target = os.readlink(f"{fd_dir}/{fd}")
                    except OSError:
                        continue
                    if target.startswith("socket:[") and target[8:-1] in inodes:
                        victims.add(int(pid))
                        break
            except OSError:
                continue
        for pid in victims:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        time.sleep(0.1)
    assert not listening_inodes(), "Could not stop the pre-existing service on port 8333"


def wait_for_listener(process):
    deadline = time.time() + 10
    while time.time() < deadline:
        if listening_inodes():
            return
        if process.poll() is not None:
            pytest.fail(f"{SCRIPT} exited before starting the service (status {process.returncode})")
        time.sleep(0.1)
    pytest.fail(f"{SCRIPT} did not start a listener on {HOST}:{PORT}")


def write_challenge_logs():
    emails = [
        "alice@example.com",
        "bob@example.com",
        "charlie@example.com",
        "diana@example.com",
        "eve@example.com",
    ]
    formats = [
        "%b %d %H:%M:%S %Y",
        "%Y/%m/%d %H:%M:%S",
        "%d %b %Y %H:%M:%S",
    ]
    rng = random.SystemRandom()
    offsets = rng.sample(range(0, 300 * 24 * 60 * 60), 45)
    rows = []
    for i, offset in enumerate(offsets):
        dt = datetime(2022, 1, 1) + timedelta(seconds=offset)
        email = emails[i % len(emails)]
        payload = json.dumps(
            {"action": rng.choice(["login", "logout", "view", "upload"]),
             "token": secrets.token_hex(8), "record": i},
            separators=(",", ":"),
        )
        rows.append(
            f"[{dt.strftime(formats[i % len(formats)])}] "
            f"source_ip=192.168.{rng.randrange(0, 256)}.{rng.randrange(1, 256)} "
            f"user={email} payload={payload}\n"
        )
    rng.shuffle(rows)
    with open(RAW_FILE, "w") as f:
        f.writelines(rows)


def fetch(anon_email):
    try:
        s = socket.create_connection((HOST, PORT), timeout=5)
    except Exception as e:
        pytest.fail(f"Could not connect to service on {HOST}:{PORT}: {e}")

    with s:
        s.settimeout(5)
        s.sendall(f"FETCH {anon_email}\n".encode("utf-8"))
        response_data = b""
        try:
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                response_data += chunk
        except socket.timeout:
            pytest.fail(f"Service did not finish its response for {anon_email}")

    response_text = response_data.decode("utf-8").strip()
    return [line.strip() for line in response_text.split("\n") if line.strip()]


def test_service_responses():
    assert os.path.lexists(SCRIPT), f"Required script missing: {SCRIPT}"
    assert not os.path.islink(SCRIPT), f"Required script must be a regular file: {SCRIPT}"
    mode = os.stat(SCRIPT).st_mode
    assert stat.S_ISREG(mode), f"Required script is not a regular file: {SCRIPT}"
    assert os.path.getsize(SCRIPT) > 0, f"Required script is empty: {SCRIPT}"

    syntax = subprocess.run(["bash", "-n", SCRIPT], capture_output=True, text=True)
    assert syntax.returncode == 0, f"Invalid Bash script: {syntax.stderr}"

    # Replace the agent-writable input with a fresh conforming challenge, then
    # execute the submitted processing/service artifact against that input.
    write_challenge_logs()
    assert os.path.exists(RAW_FILE), f"Raw logs file missing: {RAW_FILE}"

    pattern = re.compile(r"^\[(.*?)\]\s+source_ip=\S+\s+user=(\S+)\s+payload=(.*)$")
    data_by_email = {}
    parsed_count = 0
    with open(RAW_FILE) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            match = pattern.match(line)
            assert match, f"Generated challenge line was not parseable: {line}"
            timestamp_str, email, payload = match.groups()
            dt = parse_date(timestamp_str)
            iso_ts = dt.strftime("%Y-%m-%dT%H:%M:%SZ")
            data_by_email.setdefault(email, []).append((dt, iso_ts, payload))
            parsed_count += 1

    assert parsed_count == 45
    assert len(data_by_email) == 5

    kill_existing_listener()
    process = subprocess.Popen(
        ["bash", SCRIPT],
        cwd="/home/user",
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    wait_for_listener(process)

    # Preserve the original exact per-email service assertions, now using
    # records fixed by the verifier before the submitted script is executed.
    for email, records in data_by_email.items():
        anon_email = get_anonymized_email(email)
        records.sort(key=lambda x: x[0])
        expected_lines = [
            f"{iso_ts} | {anon_email} | {payload}"
            for dt, iso_ts, payload in records
        ]
        actual_lines = fetch(anon_email)

        assert len(actual_lines) == len(expected_lines), \
            f"Expected {len(expected_lines)} lines for {anon_email}, got {len(actual_lines)}"
        for i, (expected, actual) in enumerate(zip(expected_lines, actual_lines)):
            assert actual == expected, \
                f"Mismatch at line {i+1} for {anon_email}.\nExpected: {expected}\nActual: {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
