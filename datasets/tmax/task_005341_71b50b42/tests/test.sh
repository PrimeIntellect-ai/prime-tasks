#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pathlib
import secrets
import signal
import sqlite3
import subprocess
import time

import pytest
import requests

URL = "http://127.0.0.1:9090/api/v1/latest-backups"
TOKEN = "DBRE_SECURE_8832"
SCRIPT = pathlib.Path("/home/user/api_server.py")
DB = "/app/backup_inventory.sqlite"


def listener_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    pids = set()
    for entry in os.scandir("/proc"):
        if not entry.name.isdigit():
            continue
        try:
            for fd in os.scandir(f"/proc/{entry.name}/fd"):
                try:
                    target = os.readlink(fd.path)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry.name))
        except OSError:
            pass
    return pids


def restart_submitted_server():
    assert SCRIPT.exists(), f"Missing required server script: {SCRIPT}"
    assert SCRIPT.is_file(), f"Server artifact is not a regular file: {SCRIPT}"
    assert SCRIPT.stat().st_size > 0, f"Server script is empty: {SCRIPT}"

    for _ in range(20):
        pids = listener_pids(9090)
        if not pids:
            break
        for pid in pids:
            if pid != os.getpid():
                try:
                    os.kill(pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
        time.sleep(0.1)
    for pid in listener_pids(9090):
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass

    log = open("/tmp/submitted_api_server.log", "wb")
    subprocess.Popen(
        ["python3", str(SCRIPT)],
        cwd=str(SCRIPT.parent),
        stdout=log,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )

    deadline = time.time() + 10
    last_error = None
    while time.time() < deadline:
        try:
            requests.get(URL, timeout=0.5)
            return
        except requests.RequestException as exc:
            last_error = exc
            time.sleep(0.2)
    pytest.fail(f"Submitted server did not start on 127.0.0.1:9090: {last_error}")


restart_submitted_server()


def test_01_api_unauthorized():
    """Verify that the API rejects requests without a valid token."""
    try:
        response = requests.get(URL, timeout=5)
        assert response.status_code in (401, 403), f"Expected 401/403 without token, got {response.status_code}"
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to API: {e}")

    try:
        headers = {"Authorization": "Bearer WRONG_TOKEN"}
        response = requests.get(URL, headers=headers, timeout=5)
        assert response.status_code in (401, 403), f"Expected 401/403 with wrong token, got {response.status_code}"
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to API: {e}")


def test_02_api_success_and_data():
    """Preserve the original known-data assertion."""
    headers = {"Authorization": f"Bearer {TOKEN}"}
    try:
        response = requests.get(URL, headers=headers, timeout=5)
        assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"

        try:
            data = response.json()
        except ValueError:
            pytest.fail(f"Response is not valid JSON. Response text: {response.text}")

        assert isinstance(data, list), "Expected JSON response to be a list"

        expected_data = [
            {
                "device_name": "Server-A",
                "latest_status": "SUCCESS",
                "timestamp": "2023-10-02 10:00:00"
            },
            {
                "device_name": "Server-B",
                "latest_status": "SUCCESS",
                "timestamp": "2023-10-01 11:00:00"
            }
        ]

        data_sorted = sorted(data, key=lambda x: x.get("device_name", ""))
        expected_sorted = sorted(expected_data, key=lambda x: x["device_name"])
        assert data_sorted == expected_sorted, f"Expected {expected_sorted}, but got {data_sorted}"
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to API: {e}")


def test_03_api_reads_and_aggregates_live_database():
    """Add unpredictable records, then derive the required response directly from SQLite."""
    nonce = secrets.token_hex(8)
    conn = sqlite3.connect(DB, timeout=10)
    try:
        new_devices = [
            (f"hw-{nonce}-a", f"Audit-{nonce}-A"),
            (f"hw-{nonce}-b", f"Audit-{nonce}-B"),
        ]
        conn.executemany("INSERT INTO devices (hw_id, device_name) VALUES (?, ?)", new_devices)
        conn.executemany(
            "INSERT INTO backups (device_ref_hash, status, timestamp) VALUES (?, ?, ?)",
            [
                (new_devices[0][0], f"OLD-{nonce}", "2048-01-01 00:00:00"),
                (new_devices[0][0], f"LATEST-A-{nonce}", "2049-02-03 04:05:06"),
                (new_devices[1][0], f"LATEST-B-{nonce}", "2050-03-04 05:06:07"),
                ("abc", f"REFRESHED-{nonce}", "2051-04-05 06:07:08"),
            ],
        )
        conn.commit()

        rows = conn.execute(
            """
            WITH ranked AS (
                SELECT d.device_name, b.status, b.timestamp,
                       ROW_NUMBER() OVER (
                           PARTITION BY d.hw_id
                           ORDER BY b.timestamp DESC, b.id DESC
                       ) AS rn
                FROM devices AS d
                JOIN backups AS b NOT INDEXED
                  ON b.device_ref_hash = d.hw_id
            )
            SELECT device_name, status, timestamp
            FROM ranked
            WHERE rn = 1
            """
        ).fetchall()
    finally:
        conn.close()

    expected = sorted(
        [
            {"device_name": name, "latest_status": status, "timestamp": timestamp}
            for name, status, timestamp in rows
        ],
        key=lambda item: item["device_name"],
    )

    response = requests.get(URL, headers={"Authorization": f"Bearer {TOKEN}"}, timeout=5)
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")

    assert isinstance(data, list), "Expected JSON response to be a list"
    assert all(isinstance(item, dict) for item in data), "Every list item must be a dictionary"
    assert all(set(item) == {"device_name", "latest_status", "timestamp"} for item in data), \
        "Each result must contain exactly device_name, latest_status, and timestamp"
    actual = sorted(data, key=lambda item: item.get("device_name", ""))
    assert actual == expected, f"Expected live database result {expected}, but got {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
