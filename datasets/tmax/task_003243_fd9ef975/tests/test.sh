#!/bin/bash
set +e
mkdir -p /logs/verifier
score=0

check_source() {
    test -f /app/server.go &&
    test -s /app/server.go &&
    grep -Eq 'package[[:space:]]+main' /app/server.go &&
    grep -q 'database/sql' /app/server.go &&
    grep -Eqi 'sqlite3|sqlite' /app/server.go
}

check_original_response() {
python3 <<'PY'
import json
import urllib.request

url = "http://127.0.0.1:8080/api/v1/corrupted_sizes"
expected = [
    {"hostname": "prod-db-01", "total_corrupted_bytes": 8000},
    {"hostname": "prod-db-02", "total_corrupted_bytes": 7000},
]
try:
    with urllib.request.urlopen(url, timeout=5) as response:
        assert response.status == 200, f"expected HTTP 200, got {response.status}"
        data = json.loads(response.read().decode())
except Exception as exc:
    raise AssertionError(f"failed to query {url}: {exc}")
assert data == expected, f"expected {expected!r}, got {data!r}"
PY
}

stop_port_8080() {
python3 <<'PY'
import glob
import os
import signal
import time

PORT = "1F90"

def socket_inodes():
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if fields[1].rsplit(":", 1)[-1].upper() == PORT and fields[3] == "0A":
                found.add(fields[9])
    return found

def owners(inodes):
    result = set()
    for proc in glob.glob("/proc/[0-9]*"):
        try:
            pid = int(proc.rsplit("/", 1)[-1])
            for fd in glob.glob(proc + "/fd/*"):
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    result.add(pid)
                    break
        except (OSError, ValueError):
            pass
    return result

for sig in (signal.SIGTERM, signal.SIGKILL):
    for pid in owners(socket_inodes()):
        if pid not in (1, os.getpid(), os.getppid()):
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
    for _ in range(20):
        if not socket_inodes():
            raise SystemExit(0)
        time.sleep(0.1)
raise SystemExit(1 if socket_inodes() else 0)
PY
}

wait_for_server() {
    for _ in $(seq 1 60); do
        python3 - <<'PY' >/dev/null 2>&1
import urllib.request
with urllib.request.urlopen("http://127.0.0.1:8080/api/v1/corrupted_sizes", timeout=1) as r:
    assert r.status == 200
PY
        if [ $? -eq 0 ]; then
            return 0
        fi
        sleep 0.5
    done
    return 1
}

check_exact_listener() {
python3 <<'PY'
listeners = []
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        lines = open(table).read().splitlines()[1:]
    except OSError:
        continue
    for line in lines:
        fields = line.split()
        address, port = fields[1].rsplit(":", 1)
        if port.upper() == "1F90" and fields[3] == "0A":
            listeners.append((table, address.upper()))
assert listeners == [("/proc/net/tcp", "0100007F")], \
    f"port 8080 must listen exactly on IPv4 127.0.0.1; found {listeners!r}"
PY
}

check_dynamic_behavior_and_routes() {
python3 <<'PY'
import json
import secrets
import sqlite3
import urllib.error
import urllib.request

DB = "/app/backup_meta.db"
URL = "http://127.0.0.1:8080/api/v1/corrupted_sizes"
ids = ("BK-3091", "BK-4422", "BK-8819")
token = secrets.token_hex(5)
host1 = "audit-a-" + token
host2 = "audit-z-" + token
sizes = [secrets.randbelow(900000) + 100001 for _ in ids]

with sqlite3.connect(DB) as db:
    db.execute("UPDATE servers SET hostname=? WHERE server_id=1", (host1,))
    db.execute("UPDATE servers SET hostname=? WHERE server_id=2", (host2,))
    for backup_id, size in zip(ids, sizes):
        db.execute("UPDATE backups SET size_bytes=? WHERE backup_id=?", (size, backup_id))
    db.execute("UPDATE backups SET size_bytes=? WHERE backup_id='BK-9999'", (987654321,))
    db.execute(
        "INSERT OR REPLACE INTO backups(backup_id,server_id,size_bytes,timestamp) VALUES(?,?,?,?)",
        ("BK-1234", 1, 876543210, "2026-01-01"),
    )
    next_node = db.execute("SELECT COALESCE(MAX(node_id),0)+1 FROM storage_nodes").fetchone()[0]
    for backup_id in ids:
        for suffix in range(3):
            db.execute(
                "INSERT INTO storage_nodes(node_id,backup_id,location) VALUES(?,?,?)",
                (next_node, backup_id, f"audit-{suffix}"),
            )
            next_node += 1
    db.execute(
        "INSERT INTO storage_nodes(node_id,backup_id,location) VALUES(?,?,?)",
        (next_node, "BK-1234", "audit-decoy"),
    )
    db.commit()
    rows = db.execute(
        "SELECT s.hostname, SUM(b.size_bytes) "
        "FROM servers s JOIN backups b ON s.server_id=b.server_id "
        "WHERE b.backup_id IN (?,?,?) "
        "GROUP BY s.hostname ORDER BY s.hostname",
        ids,
    ).fetchall()

expected = [
    {"hostname": hostname, "total_corrupted_bytes": total}
    for hostname, total in rows
]

with urllib.request.urlopen(URL, timeout=5) as response:
    assert response.status == 200, response.status
    assert response.headers.get_content_type() == "application/json", response.headers
    actual = json.loads(response.read().decode())
assert actual == expected, f"expected dynamically derived response {expected!r}, got {actual!r}"

for method in ("POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"):
    request = urllib.request.Request(URL, method=method)
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            status = response.status
    except urllib.error.HTTPError as exc:
        status = exc.code
    assert 400 <= status < 500, f"{method} must not be supported; got HTTP {status}"

for path in ("/", "/favicon.ico", "/api/v1/corrupted_sizes/", "/api/v1/corrupted_size", "/api/v1/other_" + token):
    request = urllib.request.Request("http://127.0.0.1:8080" + path, method="GET")
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            status = response.status
    except urllib.error.HTTPError as exc:
        status = exc.code
    assert status == 404, f"unexpected endpoint {path!r} returned HTTP {status}"
PY
}

if check_source && check_original_response; then
    if stop_port_8080; then
        cd /app
        go run /app/server.go >/tmp/verifier_server.log 2>&1 &
        server_pid=$!
        cd - >/dev/null
        if wait_for_server && check_exact_listener && check_dynamic_behavior_and_routes; then
            score=1
        else
            cat /tmp/verifier_server.log 2>/dev/null || true
        fi
    fi
fi

echo "$score" > /logs/verifier/reward.txt
exit 0
