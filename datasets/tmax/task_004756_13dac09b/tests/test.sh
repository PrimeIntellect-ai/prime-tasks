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
import base64
import hashlib
import json
import os
import secrets
import time

import pytest
import requests
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

URL = "https://127.0.0.1:9090/auth"
SEC_LOG = "/home/user/security_logs.txt"
AUDIT_LOG = "/home/user/privesc_audit.log"


def b64url(obj):
    raw = json.dumps(obj, separators=(",", ":"), sort_keys=False).encode("utf-8")
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def make_token(header, payload):
    return f"{b64url(header)}.{b64url(payload)}."


def read_bytes(path):
    if not os.path.exists(path):
        return b""
    with open(path, "rb") as f:
        return f.read()


def post_token(token):
    try:
        response = requests.post(
            URL,
            headers={"Authorization": f"Bearer {token}"},
            verify=False,
            timeout=5,
        )
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the honeypot service at {URL}: {exc}")

    assert response.status_code == 200, (
        f"Expected HTTP 200 OK, got {response.status_code}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response, got: {response.text}")
    assert data.get("status") == "logged", (
        f"Expected response {{'status': 'logged'}}, got {data}"
    )


def listener_effective_uids():
    """Return effective UIDs of processes owning the 127.0.0.1:9090 listener."""
    listener_inodes = set()
    target_port = 9090

    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                rows = f.readlines()[1:]
        except OSError:
            continue

        for row in rows:
            fields = row.split()
            if len(fields) < 10 or fields[3] != "0A":
                continue
            try:
                port = int(fields[1].rsplit(":", 1)[1], 16)
            except (ValueError, IndexError):
                continue
            if port == target_port:
                listener_inodes.add(fields[9])

    assert listener_inodes, "No listening socket found on port 9090"

    effective_uids = set()
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        owns_listener = False
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in listener_inodes:
                    owns_listener = True
                    break
        except OSError:
            continue

        if owns_listener:
            try:
                with open(f"/proc/{pid}/status", "r") as f:
                    for line in f:
                        if line.startswith("Uid:"):
                            effective_uids.add(int(line.split()[2]))
                            break
            except (OSError, ValueError, IndexError):
                continue

    assert effective_uids, "Could not determine the effective UID of the server process"
    return effective_uids


def wait_for_append(path, original, expected_line, timeout=2.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        current = read_bytes(path)
        if current.startswith(original):
            appended = current[len(original):].decode("utf-8", errors="replace")
            if expected_line in appended.splitlines():
                return current
        time.sleep(0.05)
    current = read_bytes(path)
    assert current.startswith(original), f"{path} was replaced or truncated instead of appended"
    appended = current[len(original):].decode("utf-8", errors="replace")
    assert expected_line in appended.splitlines(), (
        f"Exact expected appended line not found in {path}: {expected_line!r}. "
        f"New contents were: {appended!r}"
    )
    return current


def test_certificates_exist():
    cert_path = "/home/user/certs/cert.pem"
    key_path = "/home/user/certs/key.pem"
    assert os.path.exists(cert_path), f"Certificate not found at {cert_path}"
    assert os.path.exists(key_path), f"Private key not found at {key_path}"
    assert os.path.isfile(cert_path) and os.path.getsize(cert_path) > 0, "Certificate is not a nonempty file"
    assert os.path.isfile(key_path) and os.path.getsize(key_path) > 0, "Private key is not a nonempty file"


def test_honeypot_service_behavior_and_logging():
    effective_uids = listener_effective_uids()
    expected_audit = (
        "CRITICAL: running as root"
        if 0 in effective_uids
        else "SAFE: running as unprivileged user"
    )

    # Negative cases must still receive the engagement response, but must not log
    # an evasion alert or privilege result.
    negative_tokens = [
        make_token(
            {"alg": "none", "trace": secrets.token_hex(9)},
            {"role": "user", "nonce": secrets.token_urlsafe(12)},
        ),
        make_token(
            {"alg": "HS256", "trace": secrets.token_hex(9)},
            {"role": "admin", "nonce": secrets.token_urlsafe(12)},
        ),
    ]

    for token in negative_tokens:
        sec_before = read_bytes(SEC_LOG)
        audit_before = read_bytes(AUDIT_LOG)
        post_token(token)
        time.sleep(0.25)
        assert read_bytes(SEC_LOG) == sec_before, (
            "A non-matching JWT incorrectly changed the security log"
        )
        assert read_bytes(AUDIT_LOG) == audit_before, (
            "A non-matching JWT incorrectly changed the privilege audit log"
        )

    # Exercise independently generated tokens and mixed-case alg values. The
    # expected hashes are derived from the exact raw tokens sent at test time.
    positive_tokens = [
        make_token(
            {"typ": "JWT", "alg": "NoNe", "trace": secrets.token_hex(10)},
            {"nonce": secrets.token_urlsafe(14), "role": "admin", "user": "redteam"},
        ),
        make_token(
            {"alg": "NONE", "kid": secrets.token_hex(7)},
            {"user": secrets.token_urlsafe(8), "role": "admin", "seq": secrets.randbelow(1000000)},
        ),
    ]

    for token in positive_tokens:
        sec_before = read_bytes(SEC_LOG)
        audit_before = read_bytes(AUDIT_LOG)

        post_token(token)

        expected_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
        expected_security = (
            f"ALERT: Evasion attempt detected | Hash: {expected_hash} | "
            "Escaping to role: admin"
        )
        wait_for_append(SEC_LOG, sec_before, expected_security)
        wait_for_append(AUDIT_LOG, audit_before, expected_audit)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
