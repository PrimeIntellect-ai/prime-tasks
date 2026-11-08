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
import ctypes
import os
import secrets
import shutil
import signal
import socket
import sqlite3
import subprocess
import time

import pytest
import requests


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[3] != "0A":
                        continue
                    if int(fields[1].rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except OSError:
            continue
    return pids


def wait_for_port(port, should_be_open, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        open_now = bool(listener_pids(port))
        if open_now == should_be_open:
            return
        time.sleep(0.1)
    raise AssertionError(
        f"Port {port} did not become {'open' if should_be_open else 'closed'}"
    )


def read_process_launch(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        cmd = [part.decode(errors="surrogateescape") for part in f.read().split(b"\0") if part]
    assert cmd, f"Could not determine command line for server PID {pid}"
    cwd = os.readlink(f"/proc/{pid}/cwd")
    env = {}
    with open(f"/proc/{pid}/environ", "rb") as f:
        for item in f.read().split(b"\0"):
            if b"=" in item:
                key, value = item.split(b"=", 1)
                env[key.decode(errors="surrogateescape")] = value.decode(errors="surrogateescape")
    return cmd, cwd, env


def stop_pids(pids):
    pids = {pid for pid in pids if pid != os.getpid()}
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline:
        remaining = []
        for pid in pids:
            try:
                os.kill(pid, 0)
                remaining.append(pid)
            except ProcessLookupError:
                pass
        if not remaining:
            return
        time.sleep(0.1)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def tcp_request(payload):
    with socket.create_connection(("127.0.0.1", 8081), timeout=5) as s:
        s.sendall(payload)
        s.settimeout(5)
        chunks = []
        while True:
            chunk = s.recv(1024)
            if not chunk:
                break
            chunks.append(chunk)
            if b"\n" in chunk:
                break
        return b"".join(chunks)


def test_legacy_db_state():
    db_path = "/app/legacy.db"
    assert os.path.exists(db_path), f"Database {db_path} does not exist."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='users'")
    assert cursor.fetchone() is not None, "Table 'users' does not exist in the database."

    cursor.execute("SELECT id, name, role FROM users WHERE id=1")
    row = cursor.fetchone()
    assert row is not None, "User with ID 1 does not exist."
    assert row[0] == 1, f"Expected user ID 1, got {row[0]}"
    assert row[1] == "mötley_user", f"Expected user name 'mötley_user', got {row[1]}"
    assert row[2] == "admin", f"Expected user role 'admin', got {row[2]}"
    conn.close()


def test_shared_library_exists_and_is_loadable():
    so_path = "/app/legacy_hash.so"
    assert os.path.exists(so_path), f"Shared library {so_path} was not compiled."
    assert os.path.isfile(so_path), f"Shared library {so_path} is not a regular file."
    with open(so_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Shared library {so_path} is not an ELF binary."

    try:
        lib = ctypes.CDLL(so_path)
        generate_token = lib.generate_token
    except (OSError, AttributeError) as exc:
        pytest.fail(f"Shared library is not loadable with generate_token: {exc}")
    generate_token.argtypes = [ctypes.c_int]
    generate_token.restype = ctypes.c_int
    assert generate_token(1) == 999375


def test_http_service():
    url = "http://127.0.0.1:8080/user/1"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"HTTP request to {url} failed: {e}. Is the server running on port 8080?")

    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    expected_bytes = "1,mötley_user,admin".encode("windows-1252")
    assert response.content == expected_bytes, f"Expected response bytes {expected_bytes}, got {response.content}. Ensure windows-1252 encoding is used."


def test_http_service_queries_database_and_encodes_current_values():
    marker = secrets.token_hex(8)
    changed_name = f"€uro_{marker}"
    changed_role = f"qa_{marker}"
    conn = sqlite3.connect("/app/legacy.db")
    try:
        conn.execute(
            "UPDATE users SET name=?, role=? WHERE id=1",
            (changed_name, changed_role),
        )
        conn.commit()
        response = requests.get("http://127.0.0.1:8080/user/1", timeout=5)
        assert response.status_code == 200
        expected = f"1,{changed_name},{changed_role}".encode("windows-1252")
        assert response.content == expected, (
            "HTTP response did not reflect the current SQLite row with windows-1252 encoding"
        )
    finally:
        conn.execute(
            "UPDATE users SET name='mötley_user', role='admin' WHERE id=1"
        )
        conn.commit()
        conn.close()


def test_tcp_service():
    try:
        data = tcp_request(b"TOKEN 1\n")
    except Exception as e:
        pytest.fail(f"TCP connection or communication to 127.0.0.1:8081 failed: {e}. Is the TCP server running?")

    expected = b"999375\n"
    assert expected in data or data.strip() == b"999375", f"Expected TCP response {expected}, got {data}"


def test_tcp_listener_has_library_loaded():
    pids = listener_pids(8081)
    assert pids, "No process is listening on TCP port 8081"
    loaded_by = []
    for pid in pids:
        try:
            with open(f"/proc/{pid}/maps", errors="replace") as f:
                maps = f.read()
        except OSError:
            continue
        if "/app/legacy_hash.so" in maps:
            loaded_by.append(pid)
    assert loaded_by, (
        "The TCP service process has not loaded /app/legacy_hash.so"
    )


def test_tcp_service_calls_compiled_library():
    tcp_pids = listener_pids(8081)
    assert tcp_pids, "No process is listening on TCP port 8081"
    server_pid = next(iter(tcp_pids))
    cmd, cwd, env = read_process_launch(server_pid)

    all_server_pids = listener_pids(8080) | listener_pids(8081)
    backup = "/app/legacy_hash.so.verifier-backup"
    challenge_source = "/tmp/legacy_hash_challenge.c"
    challenge = secrets.randbelow(1_500_000_000) + 100_000_000
    proc = None

    stop_pids(all_server_pids)
    wait_for_port(8081, False)
    if os.path.exists(backup):
        os.unlink(backup)
    os.replace("/app/legacy_hash.so", backup)

    try:
        with open(challenge_source, "w") as f:
            f.write(
                "int generate_token(int id) { (void)id; return %d; }\n" % challenge
            )
        subprocess.run(
            ["gcc", "-shared", "-fPIC", challenge_source, "-o", "/app/legacy_hash.so"],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        proc = subprocess.Popen(
            cmd,
            cwd=cwd,
            env=env or None,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        wait_for_port(8081, True)
        data = tcp_request(b"TOKEN 1\n")
        assert data.strip() == str(challenge).encode("ascii"), (
            "TCP service did not return the result from the compiled generate_token function"
        )
    finally:
        stop_pids(listener_pids(8080) | listener_pids(8081))
        if proc is not None:
            try:
                proc.wait(timeout=1)
            except subprocess.TimeoutExpired:
                proc.kill()
        if os.path.exists("/app/legacy_hash.so"):
            os.unlink("/app/legacy_hash.so")
        if os.path.exists(backup):
            os.replace(backup, "/app/legacy_hash.so")
        try:
            subprocess.Popen(
                cmd,
                cwd=cwd,
                env=env or None,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except Exception:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
