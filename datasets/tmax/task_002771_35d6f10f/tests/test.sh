#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import http.client
import os
import secrets
import signal
import subprocess
import time
from pathlib import Path

import pytest

HOST = "127.0.0.1"
PORT = 8080
ROOT = Path("/app/bash-admin-server")
START = ROOT / "start.sh"


def listener_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local = fields[1]
            state = fields[3]
            if int(local.rsplit(":", 1)[1], 16) == port and state == "0A":
                result.add(fields[9])
    return result


def pids_for_inodes(inodes):
    owners = set()
    if not inodes:
        return owners
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    owners.add(int(proc.name))
        except OSError:
            pass
    return owners


def stop_existing_listener():
    pids = pids_for_inodes(listener_inodes(PORT))
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while listener_inodes(PORT) and time.time() < deadline:
        time.sleep(0.05)
    for pid in pids_for_inodes(listener_inodes(PORT)):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def request(path, timeout=5):
    conn = http.client.HTTPConnection(HOST, PORT, timeout=timeout)
    try:
        conn.request("GET", path)
        response = conn.getresponse()
        body = response.read().decode("utf-8", "replace")
        return response.status, dict(response.getheaders()), body
    finally:
        conn.close()


@pytest.fixture(scope="session", autouse=True)
def launch_from_patched_start_script():
    assert START.is_file(), f"{START} does not exist"
    assert os.access(START, os.X_OK), f"{START} is not executable"
    for endpoint in (ROOT / "cgi-bin/login.sh", ROOT / "cgi-bin/diag.sh"):
        assert endpoint.is_file(), f"{endpoint} does not exist"
        assert os.access(endpoint, os.X_OK), f"{endpoint} is not executable"
        assert endpoint.read_bytes().splitlines()[0] in (b"#!/bin/bash", b"#!/usr/bin/env bash"), \
            f"{endpoint} is not a Bash script"

    stop_existing_listener()
    subprocess.Popen(
        [str(START)],
        cwd=str(ROOT),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    deadline = time.time() + 5
    while time.time() < deadline:
        try:
            status, _, _ = request("/cgi-bin/login.sh?next=/startup-check", timeout=0.3)
            if status == 302:
                break
        except OSError:
            pass
        time.sleep(0.1)
    else:
        pytest.fail("patched start.sh did not bring the service online on 127.0.0.1:8080")

    entries = []
    try:
        entries = Path("/proc/net/tcp").read_text().splitlines()[1:]
    except OSError:
        pass
    assert any(
        line.split()[1] == "0100007F:1F90" and line.split()[3] == "0A"
        for line in entries
    ), "service is not bound specifically to IPv4 127.0.0.1:8080"

    owners = pids_for_inodes(listener_inodes(PORT))
    owner_commands = []
    for pid in owners:
        try:
            owner_commands.append(Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\0", b" ").decode("utf-8", "replace"))
        except OSError:
            pass
    assert any("socat" in command for command in owner_commands), \
        f"the port 8080 listener was not started with socat: {owner_commands}"

    yield


def test_generate_key_script():
    script_path = "/home/user/generate_key.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist"
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable"

    private_path = "/home/user/admin_key"
    public_path = "/home/user/admin_key.pub"
    for path in (private_path, public_path):
        if os.path.lexists(path):
            os.remove(path)

    result = subprocess.run([script_path], capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, f"generate_key.sh failed: {result.stderr}"
    assert os.path.isfile(private_path), "Private key was not generated"
    assert os.path.isfile(public_path), "Public key was not generated"

    public_text = Path(public_path).read_text().strip()
    fields = public_text.split()
    assert len(fields) == 3, "public key must have exactly a key type, key data, and comment"
    assert fields[0] == "ssh-ed25519", f"expected an ED25519 public key, got {fields[0]}"
    assert fields[2] == "CORP_SEC_2024_AUTH", "the public key comment is not the exact corporate identifier"

    check = subprocess.run(
        ["ssh-keygen", "-lf", public_path], capture_output=True, text=True, timeout=5
    )
    assert check.returncode == 0, f"ssh-keygen rejected the public key: {check.stderr}"
    assert "ED25519" in check.stdout, f"ssh-keygen did not identify an ED25519 key: {check.stdout}"

    derived = subprocess.run(
        ["ssh-keygen", "-y", "-P", "", "-f", private_path],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert derived.returncode == 0, f"private key is invalid or password-protected: {derived.stderr}"
    assert derived.stdout.strip().split()[:2] == fields[:2], "public key does not match the generated private key"


def test_login_redirect_valid_random_paths():
    paths = ["/dashboard"] + [f"/{secrets.token_hex(8)}/{secrets.token_hex(5)}" for _ in range(4)]
    for target in paths:
        status, headers, body = request(f"/cgi-bin/login.sh?noise=x&next={target}&tail=y")
        assert status == 302, f"Expected 302 for {target}, got {status}. Response: {body}"
        assert headers.get("Location") == target, f"Expected Location {target}, got {headers.get('Location')}"


def test_login_redirect_invalid_values():
    nonce = secrets.token_hex(10)
    invalid = [
        f"http://{nonce}.invalid/path",
        f"https://{nonce}.invalid/path",
        f"//{nonce}.invalid/path",
        f"relative-{nonce}",
        "",
    ]
    for target in invalid:
        status, headers, body = request(f"/cgi-bin/login.sh?next={target}")
        assert status == 302, f"Expected 302 for invalid redirect {target!r}, got {status}. Response: {body}"
        assert headers.get("Location") == "/index.sh", \
            f"Expected /index.sh for invalid redirect {target!r}, got {headers.get('Location')}"


def test_diag_valid_random_ipv4_addresses():
    addresses = ["127.0.0.1"] + [f"127.{secrets.randbelow(256)}.{secrets.randbelow(256)}.{secrets.randbelow(254) + 1}" for _ in range(3)]
    for ip in addresses:
        status, _, body = request(f"/cgi-bin/diag.sh?ip={ip}")
        assert status == 200, f"Expected 200 for valid IPv4 {ip}, got {status}. Response: {body}"
        assert ip in body and ("ping" in body.lower() or "bytes from" in body.lower()), \
            f"Expected ping output for {ip}. Response: {body}"


def test_diag_rejects_random_malformed_and_out_of_range_ipv4():
    n = secrets.randbelow(200) + 300
    invalid = [
        f"{n}.0.0.1",
        f"127.0.{n}.1",
        f"127.0.0.1;id-{secrets.token_hex(6)}",
        f"127.0.0.{secrets.token_hex(3)}",
        "127.0.1",
        "127.0.0.1.2",
        "-1.0.0.1",
        "",
    ]
    for ip in invalid:
        status, _, body = request(f"/cgi-bin/diag.sh?ip={ip}")
        assert status == 400, f"Expected 400 for invalid IPv4 {ip!r}, got {status}. Response: {body}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
