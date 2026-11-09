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
import json
import os
import signal
import socket
import sqlite3
import subprocess
import time
import secrets
from pathlib import Path

import pytest
import requests

URL = "http://127.0.0.1:9050/api/audit"
TOKEN = "secret123"
PROJECT = Path("/home/user/audit_service")


def get_expected_data():
    conn = sqlite3.connect("/app/logs.db")
    cursor = conn.cursor()
    query = """
    SELECT u.id, u.email, COUNT(l.id) as failed_attempts
    FROM users u
    JOIN logins l ON u.id = l.user_id
    WHERE l.status = 'FAILED'
      AND json_extract(u.metadata, '$.department') = 'Engineering'
    GROUP BY u.id
    HAVING failed_attempts > 3
    ORDER BY failed_attempts DESC, u.id ASC
    """
    cursor.execute(query)
    rows = cursor.fetchall()
    conn.close()
    return [
        {"user_id": row[0], "email": row[1], "failed_attempts": row[2]}
        for row in rows
    ]


def pids_listening_on(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == wanted and fields[3] == "0A":
                inodes.add(fields[9])

    found = set()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    found.add(int(proc.name))
                    break
        except OSError:
            continue
    return found


def stop_existing_listener(port):
    pids = pids_listening_on(port)
    for pid in pids:
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    deadline = time.time() + 3
    while time.time() < deadline and pids_listening_on(port):
        time.sleep(0.1)
    for pid in pids_listening_on(port):
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def build_rust_binary():
    assert PROJECT.is_dir(), f"Missing Rust project directory: {PROJECT}"
    assert (PROJECT / "Cargo.toml").is_file(), "Missing Cargo.toml"
    rust_sources = list((PROJECT / "src").rglob("*.rs")) if (PROJECT / "src").is_dir() else []
    assert rust_sources, "No Rust source files found under audit_service/src"

    metadata_result = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert metadata_result.returncode == 0, f"cargo metadata failed:\n{metadata_result.stderr}"
    metadata = json.loads(metadata_result.stdout)
    manifest = (PROJECT / "Cargo.toml").resolve()
    packages = [p for p in metadata["packages"] if Path(p["manifest_path"]).resolve() == manifest]
    assert len(packages) == 1, "Could not identify the audit_service Cargo package"
    package = packages[0]
    bin_targets = [t for t in package["targets"] if "bin" in t.get("kind", [])]
    assert bin_targets, "The Rust project has no binary target"

    default_run = package.get("default_run")
    if default_run:
        matching = [t for t in bin_targets if t["name"] == default_run]
        assert len(matching) == 1, "Cargo default-run does not identify a binary target"
        target_name = matching[0]["name"]
    else:
        assert len(bin_targets) == 1, "Multiple binary targets require Cargo default-run"
        target_name = bin_targets[0]["name"]

    build_result = subprocess.run(
        ["cargo", "build", "--bin", target_name, "--message-format=json"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=240,
    )
    assert build_result.returncode == 0, f"cargo build failed:\n{build_result.stderr}"

    executables = []
    for line in build_result.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        target = message.get("target", {})
        if (
            message.get("reason") == "compiler-artifact"
            and target.get("name") == target_name
            and "bin" in target.get("kind", [])
            and message.get("executable")
        ):
            executables.append(Path(message["executable"]))

    assert executables, "Cargo did not produce the requested executable"
    executable = executables[-1].resolve()
    assert executable.is_file() and os.access(executable, os.X_OK), "Built artifact is not executable"
    with executable.open("rb") as f:
        assert f.read(4) == b"\x7fELF", "Built service artifact is not an ELF binary"
    return executable


@pytest.fixture(scope="session", autouse=True)
def run_submitted_rust_artifact():
    executable = build_rust_binary()
    stop_existing_listener(9050)
    process = subprocess.Popen(
        [str(executable)],
        cwd=PROJECT,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    deadline = time.time() + 20
    while time.time() < deadline:
        assert process.poll() is None, "The built Rust service exited before accepting requests"
        try:
            with socket.create_connection(("127.0.0.1", 9050), timeout=0.25):
                break
        except OSError:
            time.sleep(0.15)
    else:
        pytest.fail("The built Rust artifact did not listen on localhost:9050")

    assert process.poll() is None, "The built Rust service is not actively running"
    yield process
    assert process.poll() is None, "The built Rust service stopped during verification"


def test_unauthorized_request():
    try:
        response = requests.get(URL, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {URL}: {e}")
    assert response.status_code == 401, f"Expected 401 Unauthorized without token, got {response.status_code}. Response: {response.text}"

    headers = {"Authorization": "Bearer wrong_token"}
    try:
        response = requests.get(URL, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {URL}: {e}")
    assert response.status_code == 401, f"Expected 401 Unauthorized with wrong token, got {response.status_code}. Response: {response.text}"


def test_authorized_request():
    headers = {"Authorization": f"Bearer {TOKEN}"}
    try:
        response = requests.get(URL, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {URL}: {e}")
    assert response.status_code == 200, f"Expected 200 OK with correct token, got {response.status_code}. Response: {response.text}"
    try:
        actual_data = response.json()
    except ValueError:
        pytest.fail(f"Service did not return valid JSON. Response text: {response.text}")
    expected_data = get_expected_data()
    assert actual_data == expected_data, f"JSON response mismatch.\nExpected: {expected_data}\nActual: {actual_data}"


def test_query_is_executed_against_current_database():
    baseline = get_expected_data()
    conn = sqlite3.connect("/app/logs.db")
    cursor = conn.cursor()

    while True:
        engineering_id = secrets.randbelow(1_000_000_000) + 100_000
        hr_id = engineering_id + 1
        small_id = engineering_id + 2
        cursor.execute("SELECT COUNT(*) FROM users WHERE id IN (?, ?, ?)", (engineering_id, hr_id, small_id))
        if cursor.fetchone()[0] == 0:
            break

    engineering_count = 6 + secrets.randbelow(5)
    engineering_email = f"dynamic-{secrets.token_hex(8)}@example.test"
    try:
        cursor.executemany(
            "INSERT INTO users(id, email, metadata) VALUES (?, ?, ?)",
            [
                (engineering_id, engineering_email, '{"department":"Engineering","dynamic":true}'),
                (hr_id, "dynamic-hr@example.test", '{"department":"HR"}'),
                (small_id, "dynamic-small@example.test", '{"department":"Engineering"}'),
            ],
        )
        cursor.executemany(
            "INSERT INTO logins(user_id, status, timestamp) VALUES (?, ?, '2040-01-01')",
            [(engineering_id, "FAILED")] * engineering_count
            + [(engineering_id, "SUCCESS")] * 4
            + [(hr_id, "FAILED")] * (engineering_count + 5)
            + [(small_id, "FAILED")] * 3,
        )
        conn.commit()

        expected = get_expected_data()
        assert expected != baseline
        assert {
            "user_id": engineering_id,
            "email": engineering_email,
            "failed_attempts": engineering_count,
        } in expected
        assert all(row["user_id"] not in (hr_id, small_id) for row in expected)

        response = requests.get(URL, headers={"Authorization": f"Bearer {TOKEN}"}, timeout=5)
        assert response.status_code == 200, f"Expected 200 after database mutation, got {response.status_code}: {response.text}"
        try:
            actual = response.json()
        except ValueError:
            pytest.fail(f"Service did not return valid JSON after database mutation: {response.text}")
        assert actual == expected, f"Service did not query the current database.\nExpected: {expected}\nActual: {actual}"
    finally:
        cursor.execute("DELETE FROM logins WHERE user_id IN (?, ?, ?)", (engineering_id, hr_id, small_id))
        cursor.execute("DELETE FROM users WHERE id IN (?, ?, ?)", (engineering_id, hr_id, small_id))
        conn.commit()
        conn.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
