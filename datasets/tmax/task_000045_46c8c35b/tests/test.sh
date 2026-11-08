#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import hmac
import os
import re
import signal
import socket
import subprocess
import time

import pytest

SCRIPT = "/home/user/webhook.sh"
PORT = 8080


def get_suid_hash():
    suspicious_dir = "/home/user/suspicious"
    for name in os.listdir(suspicious_dir):
        path = os.path.join(suspicious_dir, name)
        if os.path.isfile(path) and (os.stat(path).st_mode & 0o4000):
            with open(path, "rb") as f_in:
                return hashlib.sha256(f_in.read()).hexdigest()
    return None


def get_attacker_ip():
    with open("/home/user/access.log", "r", encoding="utf-8") as f:
        for line in f:
            if "X-Exploit-Payload" in line:
                return line.split()[0]
    return None


def get_c2_secret():
    try:
        out = subprocess.check_output(
            ["ffmpeg", "-i", "/app/evidence.mp4", "-f", "srt", "-"],
            stderr=subprocess.DEVNULL,
        ).decode(errors="ignore")
        for line in out.splitlines():
            if "C2_SECRET:" in line:
                return line.split("C2_SECRET:", 1)[1].strip()
    except Exception:
        pass
    return None


def socket_inodes_for_port(states=None):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r", encoding="ascii") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) < 10:
                        continue
                    local = fields[1]
                    state = fields[3]
                    if states is not None and state not in states:
                        continue
                    try:
                        local_port = int(local.rsplit(":", 1)[1], 16)
                    except (ValueError, IndexError):
                        continue
                    if local_port == PORT:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass
    return inodes


def pids_for_inodes(inodes):
    pids = set()
    if not inodes:
        return pids
    wanted = {f"socket:[{inode}]" for inode in inodes}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(os.path.join(fd_dir, fd)) in wanted:
                        pids.add(int(entry))
                        break
                except OSError:
                    continue
        except OSError:
            continue
    return pids


def listener_pids():
    return pids_for_inodes(socket_inodes_for_port(states={"0A"}))


def kill_existing_listener():
    own_group = os.getpgrp()
    for _ in range(20):
        pids = listener_pids()
        if not pids:
            return
        for pid in pids:
            try:
                group = os.getpgid(pid)
                if group != own_group:
                    os.killpg(group, signal.SIGTERM)
                else:
                    os.kill(pid, signal.SIGTERM)
            except (ProcessLookupError, PermissionError):
                pass
        time.sleep(0.1)
    for pid in listener_pids():
        try:
            group = os.getpgid(pid)
            if group != own_group:
                os.killpg(group, signal.SIGKILL)
            else:
                os.kill(pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
    time.sleep(0.2)
    assert not listener_pids(), "Could not stop the pre-existing service on port 8080"


def assert_no_forbidden_server_runtime():
    pids = pids_for_inodes(socket_inodes_for_port())
    for pid in pids:
        try:
            exe = os.path.basename(os.readlink(f"/proc/{pid}/exe")).lower()
        except OSError:
            continue
        assert not re.match(r"^(python(?:[0-9.]*)?|node(?:js)?|go)$", exe), (
            f"Webhook socket is handled by prohibited runtime {exe!r} (pid {pid})"
        )


@pytest.fixture(scope="module")
def truth_data():
    suid_hash = get_suid_hash()
    ip = get_attacker_ip()
    secret = get_c2_secret()

    assert suid_hash is not None, "Could not find SUID binary to compute hash"
    assert ip is not None, "Could not find attacker IP in access.log"
    assert secret is not None, "Could not extract C2_SECRET from video"

    expected_hmac = hmac.new(secret.encode(), ip.encode(), hashlib.sha256).hexdigest()
    return {"hash": suid_hash, "hmac": expected_hmac}


@pytest.fixture(scope="module", autouse=True)
def webhook_server():
    assert os.path.lexists(SCRIPT), f"Missing required script {SCRIPT}"
    assert not os.path.islink(SCRIPT), f"{SCRIPT} must be a Bash script, not a symlink"
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is not a regular file"

    with open(SCRIPT, "rb") as f:
        first_line = f.readline().rstrip(b"\r\n")
    bash_shebang = rb"#![ \t]*(?:/usr/bin/env[ \t]+(?:-S[ \t]+)?bash|/(?:usr/)?bin/bash)(?:[ \t]+.*)?"
    assert re.fullmatch(bash_shebang, first_line), (
        f"{SCRIPT} must have a Bash shebang"
    )

    syntax = subprocess.run(
        ["/bin/bash", "-n", SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert syntax.returncode == 0, f"Invalid Bash syntax in {SCRIPT}: {syntax.stderr}"

    kill_existing_listener()
    proc = None
    try:
        proc = subprocess.Popen(
            ["/bin/bash", SCRIPT],
            cwd="/home/user",
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )

        deadline = time.time() + 6.0
        while time.time() < deadline and not listener_pids():
            time.sleep(0.1)
        assert listener_pids(), f"Executing {SCRIPT} did not start a listener on 127.0.0.1:8080"
        assert_no_forbidden_server_runtime()
        yield
    finally:
        if proc is not None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        kill_existing_listener()


def send_raw_http_request(auth_header=None):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(3.0)
    try:
        s.connect(("127.0.0.1", PORT))
        time.sleep(0.05)
        assert_no_forbidden_server_runtime()

        req = b"GET /audit HTTP/1.1\r\nHost: 127.0.0.1\r\n"
        if auth_header is not None:
            req += b"X-Incident-Auth: " + auth_header.encode("ascii") + b"\r\n"
        req += b"\r\n"
        s.sendall(req)

        response = b""
        while True:
            try:
                chunk = s.recv(4096)
            except socket.timeout:
                break
            if not chunk:
                break
            response += chunk
            assert len(response) <= 4096, "Webhook returned an unexpectedly large response"
        return response
    finally:
        s.close()


def test_webhook_valid_token(truth_data):
    response = send_raw_http_request(auth_header=truth_data["hmac"])
    assert response, "Received empty response from webhook for valid request"
    assert b"200 OK" in response, f"Expected 200 OK for valid token, got: {response[:100]!r}"
    assert truth_data["hash"].encode() in response, (
        f"Expected SUID hash {truth_data['hash']} in response, got: {response!r}"
    )
    expected = b"HTTP/1.1 200 OK\r\n\r\n" + truth_data["hash"].encode("ascii")
    assert response == expected, f"Valid-token response was not exact: {response!r}"


def test_webhook_invalid_token(truth_data):
    altered = ("0" if truth_data["hmac"][0] != "0" else "1") + truth_data["hmac"][1:]
    for token in ("deadbeef1234567890abcdef", altered):
        response = send_raw_http_request(auth_header=token)
        assert response, "Received empty response from webhook for invalid token"
        assert b"403 Forbidden" in response, (
            f"Expected 403 Forbidden for invalid token, got: {response[:100]!r}"
        )
        assert response == b"HTTP/1.1 403 Forbidden\r\n\r\n", (
            f"Invalid-token response was not exact: {response!r}"
        )


def test_webhook_missing_token():
    response = send_raw_http_request(auth_header=None)
    assert response, "Received empty response from webhook for missing token"
    assert b"403 Forbidden" in response, (
        f"Expected 403 Forbidden for missing token, got: {response[:100]!r}"
    )
    assert response == b"HTTP/1.1 403 Forbidden\r\n\r\n", (
        f"Missing-token response was not exact: {response!r}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
