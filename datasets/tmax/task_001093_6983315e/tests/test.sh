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
import fcntl
import http.client
import os
import secrets
import select
import socket
import tarfile

import pytest
import requests

CONF_PATH = "/home/user/system.conf"
ARCHIVE_PATH = "/home/user/config_archive.tar.gz"
EXPECTED = {
    "max_worker_threads": "1024",
    "cache_retention_days": "30",
    "log_level": "warn",
    "database_url": "postgres://localhost:5432",
}


def parse_config(content):
    result = {}
    for lineno, raw_line in enumerate(content.splitlines(), 1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        assert "=" in line, f"Malformed configuration line {lineno}: {raw_line!r}"
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        assert key, f"Empty configuration key on line {lineno}"
        assert key not in result, f"Duplicate configuration key: {key}"
        result[key] = value
    return result


def test_system_conf_updated():
    """Verify that /home/user/system.conf exists and has the updated values."""
    assert os.path.isfile(CONF_PATH), f"Missing updated config file at {CONF_PATH}"

    with open(CONF_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "max_worker_threads=1024" in content, "max_worker_threads not updated correctly in system.conf"
    assert "cache_retention_days=30" in content, "cache_retention_days not updated correctly in system.conf"
    assert "log_level=warn" in content, "log_level not updated correctly in system.conf"
    assert "database_url=postgres://localhost:5432" in content, "database_url missing or altered in system.conf"

    parsed = parse_config(content)
    assert parsed == EXPECTED, f"Unexpected parsed system.conf contents: {parsed!r}"


def test_archive_updated():
    """Verify that the configuration archive exists and contains the updated system.conf."""
    assert os.path.isfile(ARCHIVE_PATH), f"Missing config archive at {ARCHIVE_PATH}"

    with tarfile.open(ARCHIVE_PATH, "r:gz") as tar:
        members = tar.getnames()
        assert "system.conf" in members, "Archive does not contain 'system.conf'"

        member = tar.getmember("system.conf")
        assert member.isfile(), "Archived system.conf is not a regular file"
        f = tar.extractfile(member)
        assert f is not None, "Could not extract 'system.conf' from archive"
        content = f.read().decode("utf-8")

        # Preserve the original assertions.
        assert "max_worker_threads=1024" in content, "max_worker_threads not updated correctly in archived system.conf"
        assert "cache_retention_days=30" in content, "cache_retention_days not updated correctly in archived system.conf"
        assert "log_level=warn" in content, "log_level not updated correctly in archived system.conf"
        assert "database_url=postgres://localhost:5432" in content, "database_url missing or altered in archived system.conf"

        parsed = parse_config(content)
        assert parsed == EXPECTED, f"Unexpected parsed archived configuration: {parsed!r}"

    with open(CONF_PATH, "r", encoding="utf-8") as f:
        live_parsed = parse_config(f.read())
    assert parsed == live_parsed, "Archived system.conf does not match the final live configuration"


def test_http_server_port_9000():
    """Verify HTTP server on port 9000 serves the correct configuration values."""
    try:
        r1 = requests.get("http://localhost:9000/get?key=max_worker_threads", timeout=2)
        assert r1.status_code == 200, f"Expected HTTP 200, got {r1.status_code}"
        assert r1.text.strip() == "1024", f"Expected '1024', got '{r1.text}'"

        r2 = requests.get("http://localhost:9000/get?key=cache_retention_days", timeout=2)
        assert r2.status_code == 200, f"Expected HTTP 200, got {r2.status_code}"
        assert r2.text.strip() == "30", f"Expected '30', got '{r2.text}'"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"HTTP request to port 9000 failed: {e}")


def query_tcp(key):
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(2.0)
        s.connect(("localhost", 9001))
        s.sendall(f"{key}\n".encode("utf-8"))
        response = s.recv(1024).decode("utf-8")
        s.close()
        return response
    except Exception as e:
        pytest.fail(f"TCP request to port 9001 failed for key '{key}': {e}")


def test_tcp_server_port_9001():
    """Verify raw TCP server on port 9001 serves the correct configuration values."""
    resp1 = query_tcp("log_level")
    assert resp1.strip() == "warn", f"Expected 'warn', got '{resp1.strip()}'"

    resp2 = query_tcp("database_url")
    assert resp2.strip() == "postgres://localhost:5432", f"Expected 'postgres://localhost:5432', got '{resp2.strip()}'"


def acquire_both_locks(file_obj):
    # Hold both common Linux advisory-lock families so implementations using
    # either flock() or POSIX fcntl/lockf locks are exercised.
    fcntl.flock(file_obj.fileno(), fcntl.LOCK_EX)
    fcntl.lockf(file_obj.fileno(), fcntl.LOCK_EX)


def release_both_locks(file_obj):
    fcntl.lockf(file_obj.fileno(), fcntl.LOCK_UN)
    fcntl.flock(file_obj.fileno(), fcntl.LOCK_UN)


def restore_config(original):
    with open(CONF_PATH, "r+b") as f:
        acquire_both_locks(f)
        try:
            f.seek(0)
            f.write(original)
            f.truncate()
            f.flush()
            os.fsync(f.fileno())
        finally:
            release_both_locks(f)


def test_http_reads_arbitrary_keys_with_file_locking():
    """Add an unpredictable key and ensure HTTP reads it only after the file lock is released."""
    with open(CONF_PATH, "rb") as f:
        original = f.read()
    key = "http_dynamic_" + secrets.token_hex(8)
    value = "value_" + secrets.token_hex(16)
    sock = None

    try:
        with open(CONF_PATH, "r+b") as f:
            acquire_both_locks(f)
            try:
                f.seek(0, os.SEEK_END)
                if original and not original.endswith(b"\n"):
                    f.write(b"\n")
                f.write(f"{key}={value}\n".encode("utf-8"))
                f.flush()
                os.fsync(f.fileno())

                sock = socket.create_connection(("localhost", 9000), timeout=2)
                sock.settimeout(3)
                request = (
                    f"GET /get?key={key} HTTP/1.1\r\n"
                    "Host: localhost\r\n"
                    "Connection: close\r\n\r\n"
                )
                sock.sendall(request.encode("ascii"))
                readable, _, _ = select.select([sock], [], [], 0.6)
                assert not readable, "HTTP server answered while system.conf was exclusively locked"
            finally:
                release_both_locks(f)

        response = http.client.HTTPResponse(sock)
        response.begin()
        body = response.read().decode("utf-8")
        assert response.status == 200, f"Expected HTTP 200 for dynamic key, got {response.status}"
        assert body.strip() == value, f"HTTP server did not read dynamic key from system.conf: {body!r}"
    finally:
        if sock is not None:
            sock.close()
        restore_config(original)


def test_tcp_reads_arbitrary_keys_with_file_locking_and_closes():
    """Add an unpredictable key and ensure TCP locks, reads it, and closes the connection."""
    with open(CONF_PATH, "rb") as f:
        original = f.read()
    key = "tcp_dynamic_" + secrets.token_hex(8)
    value = "value_" + secrets.token_hex(16)
    sock = None

    try:
        with open(CONF_PATH, "r+b") as f:
            acquire_both_locks(f)
            try:
                f.seek(0, os.SEEK_END)
                if original and not original.endswith(b"\n"):
                    f.write(b"\n")
                f.write(f"{key}={value}\n".encode("utf-8"))
                f.flush()
                os.fsync(f.fileno())

                sock = socket.create_connection(("localhost", 9001), timeout=2)
                sock.settimeout(3)
                sock.sendall(f"{key}\n".encode("utf-8"))
                readable, _, _ = select.select([sock], [], [], 0.6)
                assert not readable, "TCP server answered while system.conf was exclusively locked"
            finally:
                release_both_locks(f)

        chunks = []
        while True:
            chunk = sock.recv(1024)
            if not chunk:
                break
            chunks.append(chunk)
        response = b"".join(chunks).decode("utf-8")
        assert response == value + "\n", f"TCP server did not return the dynamic value and newline: {response!r}"
    finally:
        if sock is not None:
            sock.close()
        restore_config(original)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
