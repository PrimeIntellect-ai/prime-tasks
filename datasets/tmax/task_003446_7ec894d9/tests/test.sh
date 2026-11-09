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
import importlib.metadata
import importlib.util
import os
import pathlib
import subprocess
import sys
import tempfile
import time

import pytest
import requests

try:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
except ImportError:
    pytest.fail("cryptography package is not installed. It is required for AES-GCM.")

SERVICE_URL = "http://127.0.0.1:8000/audit_file"
HASHER_PATH = pathlib.Path("/app/vendored/py-auditor-1.2.0/py_auditor/hasher.py")
SERVER_PATH = pathlib.Path("/home/user/server.py")
ORIGINAL_HASHER = b"import hashlib\ndef get_file_hash(filepath):\n    with open(filepath, 'rb') as f:\n        return hashlib.md5(f.read()).hexdigest()\n"


def expected_encryption(digest):
    with open("/app/aes_key.bin", "rb") as key_f:
        key = key_f.read()
    assert len(key) == 32, "AES key must be exactly 32 bytes"
    ciphertext = AESGCM(key).encrypt(b"\x00" * 12, digest.encode("utf-8"), None)
    return base64.b64encode(ciphertext).decode("utf-8")


def post_audit(path):
    try:
        return requests.post(SERVICE_URL, json={"path": path}, timeout=5)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to HTTP service: {exc}")


def test_vendored_hasher_was_fixed_and_uses_sha256():
    assert HASHER_PATH.is_file(), f"Missing vendored hasher at {HASHER_PATH}"
    assert HASHER_PATH.read_bytes() != ORIGINAL_HASHER, "Vendored hasher.py was not modified"

    spec = importlib.util.spec_from_file_location("auditor_vendored_hasher_test", HASHER_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    for content in (os.urandom(37), os.urandom(4099)):
        with tempfile.NamedTemporaryFile(delete=False) as f:
            f.write(content)
            path = f.name
        try:
            assert module.get_file_hash(path) == hashlib.sha256(content).hexdigest()
        finally:
            os.remove(path)


def test_py_auditor_package_is_installed_and_correct():
    dist = importlib.metadata.distribution("py-auditor")
    assert dist.version == "1.2.0", f"Unexpected installed py-auditor version: {dist.version}"

    import py_auditor.hasher as installed_hasher

    content = os.urandom(173)
    with tempfile.NamedTemporaryFile(delete=False) as f:
        f.write(content)
        path = f.name
    try:
        assert installed_hasher.get_file_hash(path) == hashlib.sha256(content).hexdigest()
    finally:
        os.remove(path)


def test_ssh_access_pubkey_only():
    """Test SSH access on port 2222 using the auditor's key, and verify password auth is disabled."""
    cmd_success = [
        "ssh", "-o", "StrictHostKeyChecking=no",
        "-o", "PasswordAuthentication=no",
        "-o", "BatchMode=yes",
        "-i", "/app/auditor_id_rsa",
        "-p", "2222", "user@127.0.0.1", "echo", "success"
    ]
    res_success = subprocess.run(cmd_success, capture_output=True, text=True)
    assert res_success.returncode == 0, f"SSH public key authentication failed. stderr: {res_success.stderr}"
    assert "success" in res_success.stdout, "SSH command did not execute successfully."

    cmd_fail = [
        "ssh", "-o", "StrictHostKeyChecking=no",
        "-o", "PreferredAuthentications=password",
        "-o", "PubkeyAuthentication=no",
        "-o", "BatchMode=yes",
        "-p", "2222", "user@127.0.0.1", "echo", "success"
    ]
    res_fail = subprocess.run(cmd_fail, capture_output=True, text=True)
    assert res_fail.returncode != 0, "SSH password authentication should be disabled, but connection succeeded."


def test_http_audit_file_403_invalid_permissions():
    """Test that the HTTP service returns 403 for files without 0600 permissions."""
    with tempfile.NamedTemporaryFile(delete=False) as f:
        f.write(b"test data")
        temp_path = f.name

    try:
        os.chmod(temp_path, 0o644)
        resp = post_audit(temp_path)
        assert resp.status_code == 403, f"Expected HTTP 403 for invalid permissions, got {resp.status_code}. Response: {resp.text}"
        try:
            json_data = resp.json()
        except ValueError:
            pytest.fail(f"Response is not valid JSON: {resp.text}")
        assert json_data.get("error") == "Invalid permissions", f"Expected error message 'Invalid permissions', got: {json_data}"
    finally:
        os.remove(temp_path)


def assert_valid_encrypted_response(content):
    with tempfile.NamedTemporaryFile(delete=False) as f:
        f.write(content)
        temp_path = f.name

    try:
        os.chmod(temp_path, 0o600)
        expected_digest = hashlib.sha256(content).hexdigest()
        expected_b64 = expected_encryption(expected_digest)
        resp = post_audit(temp_path)
        assert resp.status_code == 200, f"Expected HTTP 200, got {resp.status_code}. Response: {resp.text}"
        try:
            json_data = resp.json()
        except ValueError:
            pytest.fail(f"Response is not valid JSON: {resp.text}")
        assert "encrypted_hash" in json_data, f"Response missing 'encrypted_hash' key: {json_data}"
        assert json_data["encrypted_hash"] == expected_b64, (
            f"Encrypted hash mismatch.\nExpected: {expected_b64}\n"
            f"Got:      {json_data['encrypted_hash']}\n"
            "(Check if SHA-256 is used, AES-GCM IV is all zeros, and tag is appended before base64)"
        )
    finally:
        os.remove(temp_path)


def test_http_audit_file_200_valid_encryption():
    """Retain the original known-content correctness assertion."""
    assert_valid_encrypted_response(b"super secret auditor data")


def test_http_audit_file_dynamic_contents():
    """Exercise unpredictable contents so a fixed ciphertext response cannot pass."""
    for size in (0, 31, 257, 5003):
        assert_valid_encrypted_response(os.urandom(size))


def listener_pids_on_8000():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = pathlib.Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].split(":")[-1].upper() == "1F40" and fields[3] == "0A":
                inodes.add(fields[9])

    pids = set()
    for proc in pathlib.Path("/proc").glob("[0-9]*"):
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(proc.name))
        except OSError:
            continue
    return pids


def stop_http_listener():
    pids = listener_pids_on_8000()
    for pid in pids:
        try:
            os.kill(pid, 15)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listener_pids_on_8000():
        time.sleep(0.05)
    for pid in listener_pids_on_8000():
        try:
            os.kill(pid, 9)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids_on_8000():
        time.sleep(0.05)


def test_server_artifact_imports_and_calls_py_auditor_get_file_hash(tmp_path):
    """Run server.py with an instrumented py_auditor package and prove the service calls it."""
    assert SERVER_PATH.is_file(), f"Missing server artifact at {SERVER_PATH}"

    probe_root = tmp_path / "probe"
    package = probe_root / "py_auditor"
    package.mkdir(parents=True)
    marker = tmp_path / "calls.txt"
    sentinel = "a" * 64
    (package / "__init__.py").write_text("from .hasher import get_file_hash\n")
    (package / "hasher.py").write_text(
        "import os\n"
        "def get_file_hash(filepath):\n"
        "    with open(os.environ['AUDITOR_HASH_MARKER'], 'a') as f:\n"
        "        f.write(filepath + '\\n')\n"
        "    return os.environ['AUDITOR_HASH_SENTINEL']\n"
    )

    stop_http_listener()
    assert not listener_pids_on_8000(), "Could not stop the existing HTTP listener for server.py execution test"

    env = os.environ.copy()
    env["PYTHONPATH"] = str(probe_root) + os.pathsep + env.get("PYTHONPATH", "")
    env["AUDITOR_HASH_MARKER"] = str(marker)
    env["AUDITOR_HASH_SENTINEL"] = sentinel
    proc = subprocess.Popen(
        [sys.executable, str(SERVER_PATH)],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    try:
        deadline = time.time() + 8
        while time.time() < deadline:
            if proc.poll() is not None:
                stdout, stderr = proc.communicate()
                pytest.fail(f"/home/user/server.py exited before serving requests. stdout: {stdout} stderr: {stderr}")
            try:
                requests.post(SERVICE_URL, json={"path": "/nonexistent"}, timeout=0.25)
                break
            except requests.RequestException:
                time.sleep(0.1)
        else:
            pytest.fail("/home/user/server.py did not listen on 127.0.0.1:8000")

        content = os.urandom(211)
        with tempfile.NamedTemporaryFile(delete=False) as f:
            f.write(content)
            requested_path = f.name
        try:
            os.chmod(requested_path, 0o600)
            resp = post_audit(requested_path)
            assert resp.status_code == 200, f"Instrumented server request failed: {resp.status_code} {resp.text}"
            data = resp.json()
            assert data.get("encrypted_hash") == expected_encryption(sentinel), (
                "The service did not encrypt the value returned by py_auditor.get_file_hash"
            )
            assert marker.is_file(), "py_auditor.get_file_hash was not called by the service"
            assert requested_path in marker.read_text().splitlines(), "get_file_hash was not called with the requested path"
        finally:
            os.remove(requested_path)
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
        stop_http_listener()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
