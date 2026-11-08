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
import hashlib
import json
import os
import re
import secrets
import socket
import ssl
from pathlib import Path

import pytest
import requests
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

URL = "https://127.0.0.1:8443/analyze"
EXPECTED_COOKIE_VAL = "4fc8197dc364f3a093ed037d7a7ff20993f4e24eb2edaa0dd2da24255cf08b00"
VALID_ELF = b"\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00" + b"A" * 64
INVALID_ELF = b"DEADBEEF" + b"B" * 64
PROJECT = Path("/home/user/c2_honeypot")
CERT = Path("/home/user/cert.pem")
KEY = Path("/home/user/key.pem")
LOG = Path("/home/user/server.log")


def post(body, cookie=None, raw_cookie=None):
    headers = {}
    cookies = None
    if raw_cookie is not None:
        headers["Cookie"] = raw_cookie
    elif cookie is not None:
        cookies = {"session": cookie}
    return requests.post(URL, headers=headers, cookies=cookies, data=body,
                         verify=False, timeout=5)


def listening_inodes():
    found = []
    for table, ipv6 in (("/proc/net/tcp", False), ("/proc/net/tcp6", True)):
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                address, port_hex = fields[1].split(":")
                if int(port_hex, 16) == 8443 and fields[3] == "0A":
                    found.append((address, ipv6, fields[9]))
    return found


def process_executables_for_inodes(inodes):
    wanted = {f"socket:[{inode}]" for inode in inodes}
    executables = set()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            owns_socket = any(os.readlink(fd) in wanted for fd in (proc / "fd").iterdir())
            if owns_socket:
                executables.add(Path(os.path.realpath(proc / "exe")))
        except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
            continue
    return executables


def test_required_rust_release_artifacts_and_startup():
    assert PROJECT.is_dir(), f"Missing Rust project: {PROJECT}"
    manifest = PROJECT / "Cargo.toml"
    assert manifest.is_file() and manifest.stat().st_size > 0, "Missing Cargo.toml"

    metadata_raw = os.popen(
        f"cd {PROJECT} && cargo metadata --no-deps --format-version 1 2>/dev/null"
    ).read()
    assert metadata_raw, "Cargo project metadata could not be read"
    metadata = json.loads(metadata_raw)
    bin_targets = {
        target["name"]
        for package in metadata.get("packages", [])
        for target in package.get("targets", [])
        if "bin" in target.get("kind", []) and target.get("src_path", "").endswith(".rs")
    }
    assert bin_targets, "The project has no Rust binary target"
    assert any(PROJECT.rglob("*.rs")), "No Rust source files were found"

    listeners = listening_inodes()
    assert listeners, "Nothing is listening on TCP port 8443"
    assert all(not ipv6 and address == "0100007F" for address, ipv6, _ in listeners), \
        "Port 8443 must listen exactly on IPv4 127.0.0.1, not a wildcard or IPv6 address"

    executables = process_executables_for_inodes(inode for _, _, inode in listeners)
    assert executables, "Could not identify the process listening on port 8443"
    release_dir = (PROJECT / "target" / "release").resolve()
    valid_release_bins = []
    for executable in executables:
        try:
            executable.relative_to(release_dir)
        except ValueError:
            continue
        if executable.parent == release_dir and executable.name in bin_targets:
            valid_release_bins.append(executable)
    assert valid_release_bins, \
        f"The listener is not a Cargo release binary from {release_dir}; found {executables}"
    for executable in valid_release_bins:
        assert executable.is_file() and os.access(executable, os.X_OK)
        assert executable.read_bytes()[:4] == b"\x7fELF", "Release artifact is not an ELF executable"

    assert CERT.is_file() and CERT.stat().st_size > 0, "Missing cert.pem"
    assert KEY.is_file() and KEY.stat().st_size > 0, "Missing key.pem"
    cert_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    cert_context.load_cert_chain(str(CERT), str(KEY))

    pem_text = CERT.read_text(errors="strict")
    pem_match = re.search(
        r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", pem_text, re.S
    )
    assert pem_match, "cert.pem does not contain a PEM certificate"
    expected_der = ssl.PEM_cert_to_DER_cert(pem_match.group(0))
    client_context = ssl._create_unverified_context()
    with socket.create_connection(("127.0.0.1", 8443), timeout=5) as sock:
        with client_context.wrap_socket(sock, server_hostname="127.0.0.1") as tls_sock:
            served_der = tls_sock.getpeercert(binary_form=True)
    assert served_der == expected_der, "The server is not using /home/user/cert.pem"

    assert LOG.is_file() and LOG.stat().st_size > 0, "Missing or empty server.log"
    log_text = LOG.read_text(errors="replace")
    assert re.search(r"(?i)(start|listen|running|8443)", log_text), \
        "server.log does not confirm server startup"


def test_missing_auth():
    """Original Request 1: missing authentication with valid ELF."""
    try:
        response = post(VALID_ELF)
        assert response.status_code == 401, \
            f"Expected HTTP 401 for missing auth, got {response.status_code}. Response: {response.text}"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {URL}: {e}")


def test_valid_auth_invalid_elf():
    """Original Request 2: valid authentication with invalid ELF."""
    try:
        response = post(INVALID_ELF, EXPECTED_COOKIE_VAL)
        assert response.status_code == 400, \
            f"Expected HTTP 400 for invalid ELF, got {response.status_code}. Response: {response.text}"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {URL}: {e}")


def test_valid_auth_valid_elf():
    """Original Request 3: valid authentication with valid ELF."""
    try:
        response = post(VALID_ELF, EXPECTED_COOKIE_VAL)
        assert response.status_code == 200, \
            f"Expected HTTP 200 for valid auth and valid ELF, got {response.status_code}. Response: {response.text}"
        expected_hash = hashlib.sha256(VALID_ELF).hexdigest()
        actual_hash = response.text.strip()
        assert actual_hash == expected_hash, \
            f"Expected response body to be SHA-256 hash '{expected_hash}', but got '{actual_hash}'"
        assert response.content == expected_hash.encode("ascii"), \
            "The response must contain exactly the hexadecimal hash"
        assert response.headers.get("Content-Type", "").lower().startswith("text/plain"), \
            "Successful responses must be plain text"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {URL}: {e}")


def test_randomized_elf_detection_and_sha256():
    sizes = [0, 1, 7, 31, 257, 4096, 131072]
    for size in sizes:
        payload = b"\x7fELF" + secrets.token_bytes(size)
        response = post(payload, raw_cookie=f"other=x; session={EXPECTED_COOKIE_VAL}; final=y")
        expected = hashlib.sha256(payload).hexdigest().encode("ascii")
        assert response.status_code == 200, f"Valid randomized ELF of size {len(payload)} was rejected"
        assert response.content == expected, "Incorrect SHA-256 for a randomized ELF payload"
        assert response.headers.get("Content-Type", "").lower().startswith("text/plain")

    invalid_payloads = [b"", b"\x7f", b"\x7fE", b"\x7fEL"]
    for size in [4, 19, 513, 8193]:
        payload = bytearray(secrets.token_bytes(size))
        if payload[:4] == b"\x7fELF":
            payload[0] ^= 1
        invalid_payloads.append(bytes(payload))
    invalid_payloads.extend([
        b"\x00ELF" + secrets.token_bytes(73),
        b"\x7fELG" + secrets.token_bytes(91),
        secrets.token_bytes(20) + b"\x7fELF" + secrets.token_bytes(20),
    ])
    for payload in invalid_payloads:
        response = post(payload, EXPECTED_COOKIE_VAL)
        assert response.status_code == 400, \
            f"Non-ELF payload {payload[:8].hex()} was not rejected with 400"


def test_randomized_authentication_rejection():
    for _ in range(6):
        payload = b"\x7fELF" + secrets.token_bytes(secrets.randbelow(2048) + 1)
        wrong_cookie = secrets.token_hex(32)
        assert wrong_cookie != EXPECTED_COOKIE_VAL
        response = post(payload, wrong_cookie)
        assert response.status_code == 401, "A random invalid session cookie was accepted"

    payload = b"\x7fELF" + secrets.token_bytes(64)
    assert post(payload, raw_cookie=f"session={EXPECTED_COOKIE_VAL}x").status_code == 401
    assert post(payload, raw_cookie=f"xsession={EXPECTED_COOKIE_VAL}").status_code == 401
    assert post(secrets.token_bytes(50), raw_cookie="other=value").status_code == 401
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
