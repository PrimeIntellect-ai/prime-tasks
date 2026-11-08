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
import os
import re
import secrets
import sqlite3
import subprocess

import pytest
import requests

BASE_URL = "http://127.0.0.1:9090/api/v1/route-to-root"
PASSPHRASE = "epsilon protocol active"
HEADERS = {"Authorization": f"Bearer {PASSPHRASE}"}
DB_PATH = "/app/routing.sqlite"


def expected_path_for(target):
    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        expected = []
        current = target
        while current is not None:
            cursor.execute("SELECT parent_id FROM network_topology WHERE id = ?", (current,))
            row = cursor.fetchone()
            if not row:
                break
            expected.append(current)
            current = row[0]
        return expected
    finally:
        conn.close()


def test_service_is_go_process():
    """Verify that the process listening on the required port is a Go executable."""
    listener_inodes = set()
    with open("/proc/net/tcp", "r", encoding="utf-8") as f:
        next(f)
        for line in f:
            fields = line.split()
            if fields[1] == "0100007F:2382" and fields[3] == "0A":
                listener_inodes.add(fields[9])

    assert listener_inodes, "No process is listening on 127.0.0.1:9090"

    listener_pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    link = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if link.startswith("socket:[") and link[8:-1] in listener_inodes:
                    listener_pids.add(entry)
        except OSError:
            continue

    assert listener_pids, "Could not identify the process listening on port 9090"

    go_listener = False
    details = []
    for pid in listener_pids:
        try:
            result = subprocess.run(
                ["go", "version", "-m", f"/proc/{pid}/exe"],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=5,
            )
            details.append(result.stdout)
            if result.returncode == 0 and re.search(r"\bgo1\.\d+", result.stdout):
                go_listener = True
        except (OSError, subprocess.SubprocessError) as exc:
            details.append(str(exc))

    assert go_listener, "The service listening on port 9090 is not a Go executable: " + " | ".join(details)


def test_service_unauthorized():
    """Test that the service rejects unauthorized requests."""
    try:
        response = requests.post(
            BASE_URL,
            headers={"Authorization": "Bearer wrong token"},
            json={"target_node": 5},
            timeout=2
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the Go service at {BASE_URL}. Is it running? Error: {e}")

    assert response.status_code == 401, f"Expected 401 Unauthorized for bad token, got {response.status_code}"


def test_service_missing_auth():
    """Test that the service rejects requests with no auth header."""
    try:
        response = requests.post(
            BASE_URL,
            json={"target_node": 5},
            timeout=2
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the Go service at {BASE_URL}. Is it running? Error: {e}")

    assert response.status_code == 401, f"Expected 401 Unauthorized for missing token, got {response.status_code}"


def test_service_valid_route():
    """Test that the service returns the correct route for a valid node."""
    try:
        response = requests.post(
            BASE_URL,
            headers=HEADERS,
            json={"target_node": 5},
            timeout=2
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the Go service at {BASE_URL}. Is it running? Error: {e}")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"

    data = response.json()
    assert "path" in data, f"Response JSON missing 'path' key: {data}"

    assert os.path.isfile(DB_PATH), "Database file missing."
    expected_path = expected_path_for(5)
    assert data["path"] == expected_path, f"Expected path {expected_path}, got {data['path']}"


def test_service_dynamic_database_route():
    """Insert an unpredictable hierarchy and require the service to query SQLite for it."""
    assert os.path.isfile(DB_PATH), "Database file missing."
    conn = sqlite3.connect(DB_PATH, timeout=5)
    inserted = []
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT id FROM network_topology")
        existing = [row[0] for row in cursor.fetchall()]
        assert existing, "Database has no topology nodes"
        anchor = secrets.choice(existing)

        while len(inserted) < 3:
            candidate = secrets.randbelow(1_000_000_000) + 1_000_000_000
            cursor.execute("SELECT 1 FROM network_topology WHERE id = ?", (candidate,))
            if cursor.fetchone() is None and candidate not in inserted:
                inserted.append(candidate)

        cursor.execute(
            "INSERT INTO network_topology (id, parent_id, node_name) VALUES (?, ?, ?)",
            (inserted[0], anchor, f"verify-{inserted[0]}")
        )
        cursor.execute(
            "INSERT INTO network_topology (id, parent_id, node_name) VALUES (?, ?, ?)",
            (inserted[1], inserted[0], f"verify-{inserted[1]}")
        )
        cursor.execute(
            "INSERT INTO network_topology (id, parent_id, node_name) VALUES (?, ?, ?)",
            (inserted[2], inserted[1], f"verify-{inserted[2]}")
        )
        conn.commit()

        expected = expected_path_for(inserted[2])
        response = requests.post(
            BASE_URL,
            headers=HEADERS,
            json={"target_node": inserted[2]},
            timeout=2
        )
        assert response.status_code == 200, f"Expected 200 for dynamically inserted node, got {response.status_code}: {response.text}"
        data = response.json()
        assert "path" in data, f"Response JSON missing 'path' key: {data}"
        assert data["path"] == expected, f"Expected dynamic path {expected}, got {data['path']}"
    finally:
        if inserted:
            conn.execute(
                f"DELETE FROM network_topology WHERE id IN ({','.join('?' for _ in inserted)})",
                inserted
            )
            conn.commit()
        conn.close()


def test_service_not_found():
    """Test that the service returns 404 for a non-existent node."""
    try:
        response = requests.post(
            BASE_URL,
            headers=HEADERS,
            json={"target_node": 999999},
            timeout=2
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the Go service at {BASE_URL}. Is it running? Error: {e}")

    assert response.status_code == 404, f"Expected 404 Not Found for non-existent node, got {response.status_code}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
