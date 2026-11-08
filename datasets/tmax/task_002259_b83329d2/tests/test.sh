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
set +e
mkdir -p /logs/verifier
status=0

cat << 'TEST_EOF' > /tmp/test_initial_state.py
import os
import socket
import requests
import pytest

API_URL = "http://127.0.0.1:8080"
STORAGE_URL = "http://127.0.0.1:9000"


def test_env_file_updated():
    env_path = "/app/recovery_api/.env"
    assert os.path.isfile(env_path), f"Expected .env file is missing: {env_path}"
    with open(env_path, "r") as f:
        content = f.read()
    normalized_content = content.replace("'", "").replace('"', "")
    assert "STORAGE_URL=http://127.0.0.1:9000" in normalized_content


def test_storage_backend_running():
    try:
        requests.get(f"{STORAGE_URL}/", timeout=3)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Could not connect to the Python storage backend on port 9000: {e}")


def test_rust_recovery_binary_is_the_listener():
    port_hex = f"{8080:04X}"
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                if fields[1].split(":")[-1].upper() == port_hex and fields[3] == "0A":
                    inodes.add(fields[9])
    assert inodes, "No process is listening on TCP port 8080"

    listener_pids = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    listener_pids.append(name)
                    break
        except OSError:
            continue

    assert listener_pids, "Could not identify the process listening on port 8080"
    valid = False
    details = []
    for pid in listener_pids:
        try:
            exe = os.path.realpath(f"/proc/{pid}/exe")
            with open(f"/proc/{pid}/exe", "rb") as f:
                magic = f.read(4)
            details.append(exe)
            if (magic == b"\x7fELF" and os.path.basename(exe) == "recovery_api"
                    and exe.startswith("/app/recovery_api/target/")):
                valid = True
        except OSError:
            pass
    assert valid, f"Port 8080 must be served by the compiled Rust recovery_api binary; listeners: {details}"


def test_recover_endpoint():
    try:
        response = requests.post(
            f"{API_URL}/recover", json={"evidence_id": "log_01"}, timeout=5
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Could not connect to the Rust recovery API on port 8080: {e}")
    assert response.status_code == 200, response.text
    assert "EVIDENCE_FOUND_SYSTEM_COMPROMISED" in response.text


def test_export_path_traversal_mitigation():
    try:
        response = requests.post(
            f"{API_URL}/export",
            json={"filename": "../evil.sh", "data": "test"},
            timeout=5,
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Could not connect to the Rust recovery API on port 8080: {e}")
    assert response.status_code in (400, 403), response.text


def test_export_safe_file():
    try:
        response = requests.post(
            f"{API_URL}/export",
            json={"filename": "evidence.txt", "data": "test_safe_export_data"},
            timeout=5,
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Could not connect to the Rust recovery API on port 8080: {e}")
    assert response.status_code == 200, response.text
    export_path = "/app/recovery_api/exports/evidence.txt"
    assert os.path.isfile(export_path)
    with open(export_path, "r") as f:
        content = f.read()
    assert content == "test_safe_export_data"
TEST_EOF

python3 -m pytest /tmp/test_initial_state.py -x --tb=short
if [ $? -ne 0 ]; then status=1; fi

# Replace the known backend with a verifier-controlled backend. Its evidence IDs,
# plaintexts, nonces, and checksums are generated only after the agent has finished.
fuser -k 9000/tcp >/dev/null 2>&1 || true
cat << 'BACKEND_EOF' > /tmp/verifier_backend.py
import hashlib
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlparse
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

KEY = bytes.fromhex("a591a6d40bf420404a011733cfb7b190d62c65bf0bcda32b57b277d9ad9f146e")
cases = {}
for _ in range(3):
    evidence_id = "hidden_" + os.urandom(10).hex()
    plaintext = b"FORENSIC_DYNAMIC_" + os.urandom(36).hex().encode()
    cases[evidence_id] = plaintext
bad_id = "bad_checksum_" + os.urandom(10).hex()
bad_plaintext = b"CHECKSUM_MUST_BE_VERIFIED_" + os.urandom(24).hex().encode()
cases[bad_id] = bad_plaintext

with open("/tmp/verifier_backend_cases.json", "w") as f:
    json.dump({"cases": {k: v.decode() for k, v in cases.items()}, "bad_id": bad_id}, f)

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = unquote(urlparse(self.path).path)
        prefix = "/evidence/"
        if not path.startswith(prefix) or path[len(prefix):] not in cases:
            self.send_response(404)
            self.end_headers()
            return
        evidence_id = path[len(prefix):]
        plaintext = cases[evidence_id]
        nonce = os.urandom(12)
        body = nonce + AESGCM(KEY).encrypt(nonce, plaintext, None)
        checksum = hashlib.sha256(plaintext).hexdigest()
        if evidence_id == bad_id:
            checksum = hashlib.sha256(b"deliberately incorrect").hexdigest()
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Checksum", checksum)
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass

class Server(ThreadingHTTPServer):
    allow_reuse_address = True

Server(("127.0.0.1", 9000), Handler).serve_forever()
BACKEND_EOF
python3 /tmp/verifier_backend.py >/tmp/verifier_backend.log 2>&1 &
backend_pid=$!

for i in $(seq 1 50); do
    [ -s /tmp/verifier_backend_cases.json ] && curl -s --max-time 1 http://127.0.0.1:9000/not-found >/dev/null && break
    sleep 0.1
done

cat << 'TEST_EOF' > /tmp/test_dynamic_state.py
import json
import os
import secrets
import requests

API_URL = "http://127.0.0.1:8080"
EXPORT_DIR = "/app/recovery_api/exports"

with open("/tmp/verifier_backend_cases.json") as f:
    CONFIG = json.load(f)


def test_dynamic_backend_retrieval_key_extraction_and_decryption():
    for evidence_id, plaintext in CONFIG["cases"].items():
        if evidence_id == CONFIG["bad_id"]:
            continue
        response = requests.post(
            f"{API_URL}/recover", json={"evidence_id": evidence_id}, timeout=8
        )
        assert response.status_code == 200, (
            f"Recovery failed for verifier-generated evidence {evidence_id}: "
            f"{response.status_code} {response.text}"
        )
        assert plaintext in response.text, (
            "The API did not return the verifier-generated decrypted evidence"
        )


def test_decrypted_evidence_checksum_mismatch_returns_500():
    evidence_id = CONFIG["bad_id"]
    response = requests.post(
        f"{API_URL}/recover", json={"evidence_id": evidence_id}, timeout=8
    )
    assert response.status_code == 500, (
        f"A wrong X-Checksum must produce HTTP 500, got {response.status_code}: {response.text}"
    )


def test_all_required_filename_rejections():
    token = secrets.token_hex(8)
    outside = f"/tmp/verifier_export_{token}"
    attempts = [
        (f"../verifier_export_{token}", outside),
        (f"subdir/file_{token}", os.path.join(EXPORT_DIR, "subdir", f"file_{token}")),
        (f"notes..{token}.txt", os.path.join(EXPORT_DIR, f"notes..{token}.txt")),
        (outside, outside),
    ]
    for filename, forbidden_path in attempts:
        try:
            os.remove(forbidden_path)
        except (FileNotFoundError, IsADirectoryError):
            pass
        response = requests.post(
            f"{API_URL}/export",
            json={"filename": filename, "data": "must_not_be_written"},
            timeout=5,
        )
        assert response.status_code in (400, 403), (
            f"Filename {filename!r} was not rejected: {response.status_code} {response.text}"
        )
        assert not os.path.isfile(forbidden_path), f"Unsafe export wrote {forbidden_path}"


def test_random_safe_export_stays_in_export_directory():
    filename = f"evidence_{secrets.token_hex(12)}.txt"
    data = "SAFE_DYNAMIC_" + secrets.token_hex(40)
    expected = os.path.join(EXPORT_DIR, filename)
    response = requests.post(
        f"{API_URL}/export", json={"filename": filename, "data": data}, timeout=5
    )
    assert response.status_code == 200, response.text
    assert os.path.isfile(expected)
    with open(expected) as f:
        assert f.read() == data
TEST_EOF

python3 -m pytest /tmp/test_dynamic_state.py -x --tb=short
if [ $? -ne 0 ]; then status=1; fi

kill "$backend_pid" >/dev/null 2>&1 || true
wait "$backend_pid" >/dev/null 2>&1 || true

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
