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
import glob
import hashlib
import json
import os
import secrets
import subprocess
import time

import pytest
import requests
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC

EVIDENCE_PATH = "/home/user/evidence.enc"
DECRYPTED_PATH = "/home/user/decrypted_evidence.json"


def extract_running_salts():
    # Invoking ps also triggers the environment's fallback that starts the worker.
    subprocess.run(["/bin/ps", "-ef"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.2)

    salts = []
    for cmdline_path in glob.glob("/proc/[0-9]*/cmdline"):
        try:
            raw = open(cmdline_path, "rb").read()
        except (OSError, PermissionError):
            continue
        argv = [part.decode("utf-8", "replace") for part in raw.split(b"\0") if part]
        if "/home/user/rogue_worker.py" not in argv:
            continue
        try:
            index = argv.index("--salt")
            salt = argv[index + 1]
        except (ValueError, IndexError):
            continue
        if salt not in salts:
            salts.append(salt)
    assert salts, "Could not extract --salt from a running /home/user/rogue_worker.py process"
    return salts


def decrypt_with_salt(encrypted, salt_text):
    assert len(encrypted) > 16 and (len(encrypted) - 16) % 16 == 0, \
        "Encrypted evidence is not valid IV-prefixed AES-CBC data"

    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=32,
        salt=salt_text.encode("ascii"),
        iterations=100000,
    )
    key = kdf.derive(b"black mesa")
    decryptor = Cipher(algorithms.AES(key), modes.CBC(encrypted[:16])).decryptor()
    padded = decryptor.update(encrypted[16:]) + decryptor.finalize()

    pad_len = padded[-1]
    if pad_len < 1 or pad_len > 16 or padded[-pad_len:] != bytes([pad_len]) * pad_len:
        raise ValueError("invalid PKCS#7 padding")
    return json.loads(padded[:-pad_len].decode("utf-8"))


@pytest.fixture(scope="session")
def expected_evidence():
    assert os.path.isfile(EVIDENCE_PATH), f"Encrypted evidence is missing at {EVIDENCE_PATH}"
    with open(EVIDENCE_PATH, "rb") as f:
        encrypted = f.read()

    failures = []
    for salt in extract_running_salts():
        try:
            data = decrypt_with_salt(encrypted, salt)
        except Exception as exc:
            failures.append(f"{salt}: {exc}")
            continue
        if isinstance(data, dict) and "auth_token" in data and "listen_port" in data:
            return data

    pytest.fail("Could not decrypt evidence using salt from the rogue process: " + "; ".join(failures))


def test_decrypted_evidence_exists_and_correct(expected_evidence):
    evidence_path = DECRYPTED_PATH
    assert os.path.exists(evidence_path), f"Decrypted evidence file is missing at {evidence_path}"
    assert os.path.isfile(evidence_path), f"Path {evidence_path} is not a file"

    with open(evidence_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {evidence_path} does not contain valid JSON")

    assert "auth_token" in data, "Decrypted JSON missing 'auth_token'"
    assert "listen_port" in data, "Decrypted JSON missing 'listen_port'"
    assert data["auth_token"] == expected_evidence["auth_token"], "Incorrect auth_token in decrypted JSON"
    assert data["listen_port"] == expected_evidence["listen_port"], "Incorrect listen_port in decrypted JSON"


def callback_url(expected_evidence):
    return f"http://127.0.0.1:{expected_evidence['listen_port']}/callback"


def test_callback_server_no_auth(expected_evidence):
    url = callback_url(expected_evidence)
    try:
        response = requests.post(url, data=b"test", timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {url}: {e}")
    assert response.status_code == 401, \
        f"Expected HTTP 401 without Authorization header, got {response.status_code}"


def test_callback_server_wrong_auth(expected_evidence):
    url = callback_url(expected_evidence)
    wrong_token = secrets.token_hex(24)
    while wrong_token == str(expected_evidence["auth_token"]):
        wrong_token = secrets.token_hex(24)
    headers = {"Authorization": f"Bearer {wrong_token}"}
    try:
        response = requests.post(url, data=b"test", headers=headers, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {url}: {e}")
    assert response.status_code == 401, \
        f"Expected HTTP 401 with wrong Authorization header, got {response.status_code}"


def test_callback_server_correct_auth_and_hashing(expected_evidence):
    url = callback_url(expected_evidence)
    headers = {"Authorization": f"Bearer {expected_evidence['auth_token']}"}
    payloads = [
        secrets.token_bytes(1),
        secrets.token_bytes(37),
        secrets.token_bytes(1024),
    ]

    for payload in payloads:
        expected_hash = hashlib.sha256(payload).hexdigest()
        try:
            response = requests.post(url, data=payload, headers=headers, timeout=2)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to connect to the server at {url}: {e}")

        assert response.status_code == 200, \
            f"Expected HTTP 200 with correct Authorization header, got {response.status_code}. Response: {response.text}"
        try:
            resp_json = response.json()
        except ValueError:
            pytest.fail(f"Expected JSON response, got: {response.text}")

        assert resp_json.get("status") == "received", \
            f"Expected status 'received', got {resp_json.get('status')}"
        assert resp_json.get("sha256") == expected_hash, \
            f"Expected sha256 '{expected_hash}', got {resp_json.get('sha256')}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
