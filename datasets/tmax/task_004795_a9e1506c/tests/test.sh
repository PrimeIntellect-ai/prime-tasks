#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import signal
import socket
import sqlite3
import subprocess
import tempfile
import time
import pytest

HOST = "127.0.0.1"
PORT = 9090
DB_PATH = "/home/user/anonymized.db"
SERVICE_PATH = "/home/user/data_service"


def mask_string(s: str) -> str:
    return "".join(f"{b ^ 0x42:02x}" for b in s.encode("utf-8")[::-1])


def listening_pid():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[3] != "0A":
                        continue
                    address, port_hex = fields[1].rsplit(":", 1)
                    if int(port_hex, 16) != PORT:
                        continue
                    if table.endswith("tcp") and address != "0100007F":
                        continue
                    inodes.add(fields[9])
        except FileNotFoundError:
            pass

    for proc in glob.glob("/proc/[0-9]*"):
        pid = int(proc.rsplit("/", 1)[1])
        for fd in glob.glob(proc + "/fd/*"):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                return pid
    return None


def wait_for_listener(timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        pid = listening_pid()
        if pid is not None:
            return pid
        time.sleep(0.05)
    return None


def compile_cpp_service(output_path):
    sources = []
    for extension in ("*.cpp", "*.cc", "*.cxx", "*.C"):
        sources.extend(glob.glob("/home/user/**/" + extension, recursive=True))
    sources = sorted(set(os.path.realpath(p) for p in sources if os.path.isfile(p)))
    assert sources, "No C++ source file was retained under /home/user"

    preferred = sorted(
        sources,
        key=lambda p: (os.path.basename(p).lower() not in
                       ("data_service.cpp", "data_service.cc", "server.cpp", "main.cpp"), p),
    )
    attempts = [[p] for p in preferred]
    if len(sources) > 1:
        attempts.append(sources)

    errors = []
    for source_set in attempts:
        try:
            subprocess.run(
                ["g++", "-O3", "-o", output_path, *source_set,
                 "-lsqlite3", "-pthread"],
                cwd=os.path.dirname(source_set[0]),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=45,
                check=True,
            )
            return
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
            errors.append(str(exc))
    pytest.fail("C++ sources could not be compiled with g++ -O3: " + errors[-1])


def send_batch(lines, timeout=15):
    payload = "BULK_LOAD\n" + "\n".join(lines) + "\nEOF\n"
    try:
        with socket.create_connection((HOST, PORT), timeout=5) as sock:
            sock.settimeout(timeout)
            sock.sendall(payload.encode("utf-8"))
            response = bytearray()
            while not response.endswith(b"\n"):
                part = sock.recv(4096)
                assert part, "Service closed the connection without a complete response"
                response.extend(part)
                assert len(response) <= 1024, "Service returned an oversized response"
            return bytes(response).decode("utf-8")
    except ConnectionRefusedError:
        pytest.fail(f"Connection refused to {HOST}:{PORT}. Is the service running?")
    except socket.timeout:
        pytest.fail(f"Connection timed out when communicating with {HOST}:{PORT}.")


def assert_rows(expected):
    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        for row_id, expected_row in expected.items():
            cursor.execute(
                "SELECT id, name, email, ssn FROM users WHERE id = ?;", (row_id,)
            )
            rows = cursor.fetchall()
            assert rows == [expected_row], f"Incorrect database row for id {row_id}: {rows!r}"
    finally:
        conn.close()


def test_tcp_service_and_database():
    assert os.path.isfile(SERVICE_PATH), f"Binary not found at {SERVICE_PATH}"
    assert os.access(SERVICE_PATH, os.X_OK), f"Binary is not executable: {SERVICE_PATH}"
    with open(SERVICE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "data_service must be a compiled ELF executable"

    assert os.path.exists(DB_PATH), f"Database file not found at {DB_PATH}"
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("PRAGMA table_info(users);")
    columns = {row[1]: row[2].upper() for row in cursor.fetchall()}
    assert "id" in columns, "Column 'id' missing from users table"
    assert "name" in columns, "Column 'name' missing from users table"
    assert "email" in columns, "Column 'email' missing from users table"
    assert "ssn" in columns, "Column 'ssn' missing from users table"
    conn.close()

    old_pid = wait_for_listener(2)
    assert old_pid is not None, "No service is listening on port 9090"
    assert os.path.realpath(f"/proc/{old_pid}/exe") == SERVICE_PATH, \
        "The listener on port 9090 is not /home/user/data_service"

    fd, rebuilt = tempfile.mkstemp(prefix="data_service_o3_", dir="/home/user")
    os.close(fd)
    os.unlink(rebuilt)
    compile_cpp_service(rebuilt)

    os.kill(old_pid, signal.SIGTERM)
    deadline = time.time() + 3
    while time.time() < deadline and listening_pid() is not None:
        time.sleep(0.05)
    if listening_pid() is not None:
        os.kill(old_pid, signal.SIGKILL)
        time.sleep(0.2)

    os.chmod(rebuilt, 0o755)
    os.replace(rebuilt, SERVICE_PATH)
    proc = subprocess.Popen(
        [SERVICE_PATH], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    new_pid = wait_for_listener(8)
    assert new_pid is not None, "The g++ -O3 rebuilt C++ service did not listen on port 9090"
    assert os.path.realpath(f"/proc/{new_pid}/exe") == SERVICE_PATH, \
        "The rebuilt C++ executable is not the process listening on port 9090"

    fixed = [
        "100,Charlie,charlie@test.com,123-45-6789",
        "101,Dave,dave@example.net,987-65-4321",
    ]
    conn = sqlite3.connect(DB_PATH)
    conn.execute("DELETE FROM users WHERE id IN (100, 101)")
    conn.commit()
    conn.close()

    assert send_batch(fixed) == "SUCCESS 2\n"
    assert_rows({
        100: (100, "Charlie", mask_string("charlie@test.com"), mask_string("123-45-6789")),
        101: (101, "Dave", mask_string("dave@example.net"), mask_string("987-65-4321")),
    })

    token = secrets.token_hex(12)
    base_id = secrets.randbelow(500_000_000) + 1_000_000_000
    bulk_lines = []
    bulk_expected = {}
    for i in range(2048):
        row_id = base_id + i
        name = f"User_{token}_{i}"
        email = f"person.{token}.{i}@example-{i % 37}.test"
        ssn = f"{(i * 173 + 101) % 1000:03d}-{(i * 29 + 7) % 100:02d}-{(i * 7919 + 11) % 10000:04d}"
        bulk_lines.append(f"{row_id},{name},{email},{ssn}")
        bulk_expected[row_id] = (row_id, name, mask_string(email), mask_string(ssn))

    conn = sqlite3.connect(DB_PATH)
    conn.executemany("DELETE FROM users WHERE id = ?", ((i,) for i in bulk_expected))
    conn.commit()
    conn.close()

    assert send_batch(bulk_lines, timeout=25) == "SUCCESS 2048\n"
    assert_rows(bulk_expected)

    # A fresh connection after the large load must still work.
    final_id = base_id + 5000
    final_name = "Reconnect_" + token
    final_email = f"again.{token}@example.org"
    final_ssn = "314-15-9265"
    conn = sqlite3.connect(DB_PATH)
    conn.execute("DELETE FROM users WHERE id = ?", (final_id,))
    conn.commit()
    conn.close()

    assert send_batch([f"{final_id},{final_name},{final_email},{final_ssn}"]) == "SUCCESS 1\n"
    assert_rows({
        final_id: (final_id, final_name, mask_string(final_email), mask_string(final_ssn))
    })
    assert proc.poll() is None or listening_pid() is not None
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
