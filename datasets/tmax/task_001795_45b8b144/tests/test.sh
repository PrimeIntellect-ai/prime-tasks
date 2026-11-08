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
from pathlib import Path
import secrets
import signal
import subprocess
import time

import pytest
import requests
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

PROJECT = Path("/app/rotation_service")
URL = "http://127.0.0.1:8080/rotate"
LEGACY_KEY = "WntrBse_xk"


def listening_socket_inodes(port):
    entries = []
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            address, port_hex = fields[1].split(":")
            if int(port_hex, 16) == port and fields[3] == "0A":
                entries.append((table, address, fields[9]))
    return entries


def pids_for_socket_inodes(inodes):
    wanted = {f"socket:[{inode}]" for inode in inodes}
    found = set()
    for proc_entry in Path("/proc").iterdir():
        if not proc_entry.name.isdigit():
            continue
        fd_dir = proc_entry / "fd"
        try:
            for fd in fd_dir.iterdir():
                try:
                    if os.readlink(fd) in wanted:
                        found.add(int(proc_entry.name))
                        break
                except OSError:
                    pass
        except OSError:
            pass
    return found


def stop_existing_listener():
    entries = listening_socket_inodes(8080)
    pids = pids_for_socket_inodes([entry[2] for entry in entries])
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while listening_socket_inodes(8080) and time.time() < deadline:
        time.sleep(0.05)
    if listening_socket_inodes(8080):
        for pid in pids:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        time.sleep(0.2)


def recovered_credentials():
    encrypted = Path("/app/db_backup.enc").read_bytes()
    key = hashlib.sha256(LEGACY_KEY.encode()).digest()
    return AESGCM(key).decrypt(b"0" * 12, encrypted, None)


@pytest.fixture(scope="session", autouse=True)
def build_and_start_submitted_rust_service():
    assert PROJECT.is_dir(), "/app/rotation_service does not exist"
    manifest = PROJECT / "Cargo.toml"
    assert manifest.is_file(), "Rust project is missing Cargo.toml"

    metadata_result = subprocess.run(
        ["cargo", "metadata", "--format-version", "1", "--no-deps", "--manifest-path", str(manifest)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert metadata_result.returncode == 0, f"Invalid Cargo project: {metadata_result.stderr}"
    metadata = json.loads(metadata_result.stdout)

    project_root = PROJECT.resolve()
    bin_targets = []
    for package in metadata.get("packages", []):
        for target in package.get("targets", []):
            if "bin" not in target.get("kind", []):
                continue
            source = Path(target["src_path"]).resolve()
            assert source.suffix == ".rs", f"Binary target is not Rust source: {source}"
            assert source == project_root or project_root in source.parents, \
                f"Rust binary source is outside /app/rotation_service: {source}"
            bin_targets.append(target)
    assert bin_targets, "Cargo project has no Rust binary target"
    assert len(bin_targets) == 1, "Expected exactly one Rust service binary target"

    build_result = subprocess.run(
        ["cargo", "build", "--manifest-path", str(manifest)],
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert build_result.returncode == 0, f"Rust service failed to compile: {build_result.stderr}"

    executable = Path(metadata["target_directory"]) / "debug" / bin_targets[0]["name"]
    assert executable.is_file(), f"Compiled Rust service binary is missing: {executable}"
    assert os.access(executable, os.X_OK), f"Compiled service is not executable: {executable}"

    stop_existing_listener()
    process = subprocess.Popen(
        [str(executable)],
        cwd=str(PROJECT),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    deadline = time.time() + 10
    while time.time() < deadline:
        assert process.poll() is None, "Compiled Rust service exited before binding to port 8080"
        if listening_socket_inodes(8080):
            break
        time.sleep(0.1)
    else:
        pytest.fail("Compiled Rust service did not listen on port 8080")

    listeners = listening_socket_inodes(8080)
    assert listeners, "No listener found on port 8080"
    assert all(table == "/proc/net/tcp" and address == "0100007F" for table, address, _ in listeners), \
        f"Service must listen exactly on IPv4 127.0.0.1:8080; found {listeners}"

    listener_pids = pids_for_socket_inodes([entry[2] for entry in listeners])
    assert process.pid in listener_pids, "Port 8080 is not owned by the compiled Rust service"


def test_recovered_key_file():
    """Verify that the recovered key is written correctly."""
    path = "/app/recovered_key.txt"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "WntrBse_xk", f"Recovered key is incorrect. Got: {content}"


def test_audit_file():
    """Verify that the audit file contains only the correct CWE identifier."""
    path = "/app/audit.txt"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    assert "CWE-214" in content.upper(), f"Audit file does not contain CWE-214. Got: {content}"
    assert content == "CWE-214", f"Audit file must contain only CWE-214. Got: {content!r}"


def test_service_unauthorized():
    """Verify that the service returns 401 for missing or invalid tokens."""
    payload = {"new_key": "test_key"}

    try:
        resp = requests.post(URL, json=payload, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {URL}: {e}")
    assert resp.status_code == 401, f"Expected 401 for missing token, got {resp.status_code}"

    headers = {"Authorization": "Bearer WntrBse_xx"}
    resp = requests.post(URL, json=payload, headers=headers, timeout=2)
    assert resp.status_code == 401, f"Expected 401 for invalid token, got {resp.status_code}"


def rotate_and_decrypt(new_key):
    headers = {"Authorization": f"Bearer {LEGACY_KEY}"}
    try:
        resp = requests.post(URL, json={"new_key": new_key}, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {URL}: {e}")

    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}. Response: {resp.text}"
    try:
        data = resp.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {resp.text}")
    assert "encrypted_credentials" in data, "Response JSON missing 'encrypted_credentials' key."

    b64_ct = data["encrypted_credentials"]
    assert isinstance(b64_ct, str), "encrypted_credentials must be a base64 string"
    try:
        ct_bytes = base64.b64decode(b64_ct, validate=True)
    except Exception:
        pytest.fail(f"encrypted_credentials is not valid base64: {b64_ct}")

    expected_plaintext = recovered_credentials()
    expected_length = len(expected_plaintext) + 16
    assert expected_length == 69
    assert len(ct_bytes) == expected_length, f"Expected ciphertext length {expected_length}, got {len(ct_bytes)}"

    new_aes_key = hashlib.sha256(new_key.encode()).digest()
    try:
        plaintext = AESGCM(new_aes_key).decrypt(b"1" * 12, ct_bytes, None)
    except Exception as exc:
        pytest.fail(f"Ciphertext cannot be authenticated/decrypted with the submitted new_key: {exc}")
    assert plaintext == expected_plaintext, "Rotated ciphertext does not contain the recovered database credentials"
    return ct_bytes


def test_service_rotate_success():
    """Verify rotation cryptographically for verifier-generated new keys."""
    first_key = "verify-" + secrets.token_urlsafe(24)
    second_key = "verify-" + secrets.token_urlsafe(24)
    first = rotate_and_decrypt(first_key)
    second = rotate_and_decrypt(second_key)
    assert first != second, "Different new keys unexpectedly produced identical ciphertext"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
