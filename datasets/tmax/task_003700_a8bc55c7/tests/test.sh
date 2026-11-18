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
import re
import secrets
import subprocess
from pathlib import Path

import pytest
import requests
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

URL = "https://127.0.0.1:8443/"
EXPECTED_SECRET = b"FLAG{f0r3ns1cs_w1n}"
EXPECTED_HASH = hashlib.sha256(EXPECTED_SECRET).hexdigest()


def test_secret_data_extracted_and_verified():
    secret_path = "/home/user/secret_data.txt"
    hash_path = "/home/user/hash.txt"

    assert os.path.exists(secret_path), f"File not found: {secret_path}. Did you extract it from the archive?"
    assert os.path.exists(hash_path), f"File not found: {hash_path}."

    with open(secret_path, "rb") as f:
        secret = f.read()
        actual_hash = hashlib.sha256(secret).hexdigest()

    with open(hash_path, "r") as f:
        expected_hash = f.read().strip()

    # Preserve the original integrity assertion, but do not trust the writable hash file alone.
    assert actual_hash == expected_hash, f"Hash of {secret_path} does not match the expected hash in {hash_path}."
    assert secret == EXPECTED_SECRET, "secret_data.txt does not contain the evidence from the supplied archive."
    assert expected_hash == EXPECTED_HASH, "/home/user/hash.txt was modified from the supplied evidence hash."

    # Independently exercise the documented OCR-derived password search and confirm the archive member.
    ocr = subprocess.run(
        ["tesseract", "/app/evidence.png", "stdout"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
    ).stdout.strip()
    prefix = next((line.strip() for line in ocr.splitlines() if line.strip()), "")
    assert prefix, "OCR did not produce a password prefix from /app/evidence.png."

    extracted = None
    for number in range(100):
        password = f"{prefix}_{number:02d}"
        result = subprocess.run(
            ["unzip", "-qq", "-P", password, "-p", "/home/user/vault.zip", "secret_data.txt"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
        if result.returncode == 0:
            extracted = result.stdout
            break
    assert extracted == secret, "secret_data.txt does not match the password-protected archive member."


def _listener_process():
    wanted_inode = None
    with open("/proc/net/tcp", "r") as f:
        for line in f.readlines()[1:]:
            fields = line.split()
            local_address, state, inode = fields[1], fields[3], fields[9]
            if local_address.upper() == "00000000:20FB" and state == "0A":
                wanted_inode = inode
                break
    assert wanted_inode is not None, "No IPv4 listener is bound to 0.0.0.0:8443."

    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        fd_dir = proc / "fd"
        try:
            for fd in fd_dir.iterdir():
                try:
                    if os.readlink(fd) == f"socket:[{wanted_inode}]":
                        exe = os.path.realpath(proc / "exe")
                        args = (proc / "cmdline").read_bytes().split(b"\0")
                        args = [a.decode("utf-8", "replace") for a in args if a]
                        cwd = os.path.realpath(proc / "cwd")
                        return proc.name, exe, args, cwd
                except (OSError, PermissionError):
                    pass
        except (OSError, PermissionError):
            pass
    pytest.fail("Could not identify the process owning 0.0.0.0:8443.")


def _option_path(args, option, cwd):
    pattern = re.compile(r"(?:^|,)" + re.escape(option) + r"=([^,]+)")
    for arg in args:
        match = pattern.search(arg)
        if match:
            value = match.group(1).strip("'\"")
            return value if os.path.isabs(value) else os.path.join(cwd, value)
    return None


def test_required_socat_tls_and_bash_handler():
    _, exe, args, cwd = _listener_process()
    command = " ".join(args)
    assert os.path.basename(exe) == "socat", f"Port 8443 is owned by {exe}, not socat."
    assert "OPENSSL-LISTEN:8443" in command, "socat is not using OPENSSL-LISTEN on port 8443."
    assert re.search(r"(?:^|,)bind=0\.0\.0\.0(?:,|$)", command), "socat is not explicitly bound to 0.0.0.0."
    assert "EXEC:" in command or "SYSTEM:" in command, "socat is not dispatching requests to a handler."

    cert_path = _option_path(args, "cert", cwd)
    key_path = _option_path(args, "key", cwd)
    assert cert_path and os.path.basename(cert_path) == "cert.pem" and os.path.isfile(cert_path), "socat must use cert.pem."
    assert key_path and os.path.basename(key_path) == "key.pem" and os.path.isfile(key_path), "socat must use key.pem."

    cert_info = subprocess.run(
        ["openssl", "x509", "-in", cert_path, "-noout", "-subject", "-issuer", "-text"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
    ).stdout
    assert re.search(r"(?:CN\s*=\s*localhost|DNS:localhost)", cert_info), "cert.pem is not issued for localhost."

    cert_pub = subprocess.run(
        ["openssl", "x509", "-in", cert_path, "-pubkey", "-noout"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    ).stdout
    key_pub = subprocess.run(
        ["openssl", "pkey", "-in", key_path, "-pubout"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    ).stdout
    assert cert_pub == key_pub, "cert.pem and key.pem do not form a matching key pair."
    subprocess.run(
        ["openssl", "verify", "-CAfile", cert_path, cert_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )

    # Locate the executable handler referenced by the socat command and require a Bash shebang.
    candidates = re.findall(r"(?:/|\./)[A-Za-z0-9_.+/-]+", command)
    bash_handler = False
    for candidate in candidates:
        path = candidate if os.path.isabs(candidate) else os.path.join(cwd, candidate)
        try:
            first_line = Path(path).read_text(errors="replace").splitlines()[0]
        except (OSError, IndexError):
            continue
        if re.match(r"^#!\s*(?:/bin/bash|/usr/bin/bash|/usr/bin/env\s+bash)\b", first_line):
            bash_handler = True
            break
    assert bash_handler, "The socat request handler is not an executable Bash script."


def _segment(value):
    raw = json.dumps(value, separators=(",", ":"), ensure_ascii=True).encode()
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def _token(header, payload):
    return f"{_segment(header)}.{_segment(payload)}."


def _request(token=None):
    headers = {"Authorization": f"Bearer {token}"} if token is not None else {}
    try:
        return requests.get(URL + "?probe=" + secrets.token_hex(6), headers=headers, verify=False, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the HTTPS server at {URL}: {exc}")


def test_https_server_valid_jwt_bypass():
    nonce = secrets.token_hex(18)
    token = _token({"probe": nonce, "alg": "none"}, {"nonce": nonce, "role": "admin"})
    response = _request(token)

    assert response.status_code == 200, f"Expected HTTP 200 OK for a valid 'alg: none' JWT with admin role, but got {response.status_code}."

    with open("/home/user/secret_data.txt", "r") as f:
        expected_data = f.read().strip()

    assert expected_data in response.text, "The server response did not contain the contents of secret_data.txt."
    assert response.content == EXPECTED_SECRET, "The HTTP 200 response body must be exactly secret_data.txt."


def test_https_server_varied_valid_jwt_decoding():
    nonce = secrets.token_urlsafe(20)
    # Different claim order and randomized values ensure a fixed-token responder cannot pass.
    token = _token({"typ": nonce, "alg": "none", "extra": True}, {"role": "admin", "value": nonce})
    response = _request(token)
    assert response.status_code == 200
    assert response.content == EXPECTED_SECRET


def test_https_server_invalid_role_jwt():
    nonce = secrets.token_hex(16)
    token = _token({"alg": "none", "probe": nonce}, {"role": "user", "probe": nonce})
    response = _request(token)
    assert response.status_code == 401, f"Expected HTTP 401 Unauthorized for a JWT with a non-admin role, but got {response.status_code}."


def test_https_server_rejects_wrong_algorithm_and_malformed_tokens():
    nonce = secrets.token_hex(16)
    wrong_alg = _token({"alg": "HS256", "probe": nonce}, {"role": "admin", "probe": nonce})
    assert _request(wrong_alg).status_code == 401

    missing_role = _token({"alg": "none", "probe": nonce}, {"admin": True, "probe": nonce})
    assert _request(missing_role).status_code == 401

    malformed = f"{secrets.token_urlsafe(12)}.{secrets.token_urlsafe(12)}."
    assert _request(malformed).status_code == 401


def test_https_server_missing_jwt():
    response = _request()
    assert response.status_code == 401, f"Expected HTTP 401 Unauthorized when no Authorization header is provided, but got {response.status_code}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
