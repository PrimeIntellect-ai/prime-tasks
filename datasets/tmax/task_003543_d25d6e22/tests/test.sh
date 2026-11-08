#!/bin/bash
set +e
mkdir -p /logs/verifier

SERVICE_PID=""
cleanup() {
    if [ -n "$SERVICE_PID" ]; then
        kill "$SERVICE_PID" 2>/dev/null || true
        wait "$SERVICE_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import sqlite3

import pytest
import requests

DB_PATH = "/home/user/metadata.db"
BASE_URL = "http://127.0.0.1:8080/chain"


def expected_chain(conn, node_id):
    rows = conn.execute(
        """
        WITH RECURSIVE chain AS (
            SELECT id, parent_id, size, backup_time
              FROM backups WHERE id = ?
            UNION ALL
            SELECT b.id, b.parent_id, b.size, b.backup_time
              FROM backups AS b
              JOIN chain AS c ON b.id = c.parent_id
        )
        SELECT id, parent_id, size, backup_time
          FROM chain
         ORDER BY backup_time
        """,
        (node_id,),
    ).fetchall()

    total = 0
    result = []
    for node_id, parent_id, size, _ in rows:
        total += size
        result.append({
            "id": node_id,
            "parent_id": parent_id,
            "size": size,
            "cumulative_size": total,
        })
    return result


def fetch_chain(node_id):
    url = f"{BASE_URL}?id={node_id}"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the backup service at {url}: {exc}")

    assert response.status_code == 200, (
        f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")

    assert isinstance(data, list), f"Expected a JSON array, got {type(data).__name__}"
    assert len(data) > 0, "Expected a non-empty JSON array representing the backup chain."

    expected_keys = {"id", "parent_id", "size", "cumulative_size"}
    for item in data:
        assert isinstance(item, dict), f"Expected each chain entry to be an object: {item!r}"
        missing_keys = expected_keys - set(item.keys())
        assert not missing_keys, f"JSON object missing expected keys {missing_keys}: {item}"

        assert isinstance(item["id"], int), f"Invalid id in response: {item}"
        assert item["parent_id"] is None or isinstance(item["parent_id"], int), item
        assert isinstance(item["size"], int), f"Invalid size in response: {item}"
        assert isinstance(item["cumulative_size"], int), item

    expected_cumulative = 0
    for item in data:
        expected_cumulative += item["size"]
        assert item["cumulative_size"] == expected_cumulative, (
            f"Cumulative size mismatch for node {item['id']}. "
            f"Expected {expected_cumulative}, got {item['cumulative_size']}"
        )
    return data


def test_database_indices_and_integrity():
    assert os.path.isfile(DB_PATH), f"Database file missing at {DB_PATH}"

    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()

        cursor.execute("PRAGMA integrity_check;")
        result = cursor.fetchone()
        assert result is not None and result[0].lower() == "ok", (
            f"Database integrity check failed: {result}"
        )

        cursor.execute(
            "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_opt';"
        )
        assert cursor.fetchone() is not None, "Index 'idx_opt' was not created."

        cursor.execute("PRAGMA index_info(idx_opt);")
        columns = [row[2] for row in cursor.fetchall()]
        expected_columns = ["id", "parent_id", "size", "backup_time"]
        assert columns == expected_columns, (
            f"Index 'idx_opt' has incorrect columns. "
            f"Expected {expected_columns}, got {columns}"
        )
    finally:
        conn.close()


def test_http_service_matches_database_for_original_chain():
    conn = sqlite3.connect(DB_PATH)
    try:
        expected = expected_chain(conn, 5)
    finally:
        conn.close()

    assert expected, "The requested database chain for id=5 is missing."
    data = fetch_chain(5)
    assert data[-1]["id"] == 5, (
        f"Expected the last node in the chain to have id=5, got {data[-1]['id']}"
    )
    assert data == expected, f"Service response does not match database chain: {data} != {expected}"


def test_http_service_uses_requested_id_and_current_database_values():
    conn = sqlite3.connect(DB_PATH)
    inserted = []
    try:
        while True:
            root = secrets.randbelow(700_000_000) + 100_000_000
            ids = [root, root + 1, root + 2]
            placeholders = ",".join("?" for _ in ids)
            found = conn.execute(
                f"SELECT COUNT(*) FROM backups WHERE id IN ({placeholders})", ids
            ).fetchone()[0]
            if found == 0:
                break

        sizes = [
            secrets.randbelow(9000) + 101,
            secrets.randbelow(9000) + 101,
            secrets.randbelow(9000) + 101,
        ]
        rows = [
            (ids[0], None, sizes[0], "2099-01-01 01:00:00"),
            (ids[1], ids[0], sizes[1], "2099-01-02 02:00:00"),
            (ids[2], ids[1], sizes[2], "2099-01-03 03:00:00"),
        ]
        conn.executemany(
            "INSERT INTO backups(id, parent_id, size, backup_time) VALUES (?, ?, ?, ?)",
            rows,
        )
        conn.commit()
        inserted = ids

        for requested_id in (ids[0], ids[1], ids[2]):
            expected = expected_chain(conn, requested_id)
            actual = fetch_chain(requested_id)
            assert actual[-1]["id"] == requested_id, (
                f"Service ignored requested id {requested_id}: {actual}"
            )
            assert actual == expected, (
                f"Response for id={requested_id} does not match the database. "
                f"Expected {expected}, got {actual}"
            )
    finally:
        if inserted:
            placeholders = ",".join("?" for _ in inserted)
            conn.execute(f"DELETE FROM backups WHERE id IN ({placeholders})", inserted)
            conn.commit()
        conn.close()
TEST_EOF

stop_port_8080() {
python3 << 'PY'
import os
import signal
import time

inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table) as f:
            next(f, None)
            for line in f:
                fields = line.split()
                local = fields[1]
                state = fields[3]
                if int(local.rsplit(":", 1)[1], 16) == 8080 and state == "0A":
                    inodes.add(fields[9])
    except OSError:
        pass

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
                os.kill(int(entry), signal.SIGTERM)
                break
    except OSError:
        continue

time.sleep(0.5)
PY
}

verify() {
    local srcdir="/app/backup_service-1.0"
    local binary="$srcdir/backup_server"

    [ -f "$srcdir/Makefile" ] || return 1
    [ -f "$srcdir/server.c" ] || return 1

    stop_port_8080 || return 1
    rm -f "$binary" || return 1
    make -C "$srcdir" -B backup_server >/tmp/backup-build.log 2>&1 || {
        cat /tmp/backup-build.log
        return 1
    }

    [ -f "$binary" ] && [ -x "$binary" ] || return 1
    python3 - "$binary" << 'PY' || return 1
import sys
with open(sys.argv[1], "rb") as f:
    assert f.read(4) == b"\x7fELF", "backup_server is not a compiled ELF executable"
PY
    ldd "$binary" 2>/dev/null | grep -q 'libsqlite3' || return 1

    "$binary" >/tmp/backup-service.log 2>&1 &
    SERVICE_PID=$!

    python3 - "$SERVICE_PID" "$binary" << 'PY' || return 1
import os
import sys
import time

pid = int(sys.argv[1])
expected_exe = os.path.realpath(sys.argv[2])

def listener_inodes():
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if int(fields[1].rsplit(":", 1)[1], 16) == 8080 and fields[3] == "0A":
                        result.add(fields[9])
        except OSError:
            pass
    return result

for _ in range(50):
    try:
        actual_exe = os.path.realpath(f"/proc/{pid}/exe")
        if actual_exe != expected_exe:
            raise AssertionError(f"Running process is {actual_exe}, not {expected_exe}")
        owned = set()
        for fd in os.listdir(f"/proc/{pid}/fd"):
            try:
                target = os.readlink(f"/proc/{pid}/fd/{fd}")
            except OSError:
                continue
            if target.startswith("socket:["):
                owned.add(target[8:-1])
        if owned & listener_inodes():
            break
    except FileNotFoundError:
        pass
    time.sleep(0.1)
else:
    raise AssertionError("Compiled backup_server did not remain running and own port 8080")
PY

    python3 -m pytest /tmp/test_final_state.py -x --tb=short
}

if verify 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
