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
import sqlite3
import uuid

import pytest
import requests

URL = "http://127.0.0.1:9000/chain"
AUTH = {"X-Compliance-Auth": "auditor_key"}
SOURCE_ACCOUNT = "10001"


def fetch_chain():
    try:
        response = requests.get(URL, headers=AUTH, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the HTTP service at {URL}: {e}")

    assert response.status_code == 200, (
        f"Expected HTTP 200 OK with auth header, got {response.status_code}"
    )
    assert response.headers.get("Content-Type", "").split(";", 1)[0].strip().lower() == "application/json", (
        f"Expected application/json, got {response.headers.get('Content-Type')!r}"
    )
    try:
        return response.json()
    except ValueError:
        pytest.fail("Response is not valid JSON")


def expected_chain(conn, source):
    edges = {}
    for src, dst in conn.execute("SELECT from_acct, to_acct FROM transfers"):
        edges.setdefault(src, set()).add(dst)

    reached = set()
    pending = list(edges.get(source, ()))
    while pending:
        account = pending.pop()
        if account in reached:
            continue
        reached.add(account)
        pending.extend(edges.get(account, ()))
    return sorted(reached)


def listener_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                rows = f.readlines()[1:]
        except OSError:
            continue
        for row in rows:
            fields = row.split()
            if len(fields) > 9 and fields[1].rsplit(":", 1)[1].upper() == wanted and fields[3] == "0A":
                inodes.add(fields[9])

    result = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                if os.readlink(f"{fd_dir}/{fd}") in {f"socket:[{inode}]" for inode in inodes}:
                    result.append(int(entry))
                    break
        except OSError:
            pass
    return result


def service_material(pid):
    chunks = []
    try:
        raw_cmdline = open(f"/proc/{pid}/cmdline", "rb").read()
        chunks.append(raw_cmdline.replace(b"\0", b" "))
        args = [x.decode(errors="ignore") for x in raw_cmdline.split(b"\0") if x]
    except OSError:
        args = []

    try:
        cwd = os.readlink(f"/proc/{pid}/cwd")
    except OSError:
        cwd = None

    candidates = set()
    for arg in args:
        path = arg if os.path.isabs(arg) else os.path.join(cwd, arg) if cwd else None
        if path and os.path.isfile(path):
            candidates.add(os.path.realpath(path))

    # Module-based servers often name only a module in argv, so inspect small
    # source/configuration files in the listener's working tree as well.
    if cwd and cwd != "/" and os.path.isdir(cwd):
        for root, dirs, files in os.walk(cwd):
            rel_depth = os.path.relpath(root, cwd).count(os.sep)
            if rel_depth >= 3:
                dirs[:] = []
            dirs[:] = [d for d in dirs if d not in {".git", "__pycache__", "node_modules"}]
            for name in files:
                path = os.path.realpath(os.path.join(root, name))
                if path == "/tmp/test_final_state.py" or path.startswith("/tests/"):
                    continue
                try:
                    if os.path.getsize(path) <= 2_000_000:
                        candidates.add(path)
                except OSError:
                    pass
            if len(candidates) > 300:
                break

    for path in candidates:
        if path.endswith((".db", ".wav", ".pyc")):
            continue
        try:
            chunks.append(open(path, "rb").read(2_000_000))
        except OSError:
            pass
    return b"\n".join(chunks)


def test_database_index():
    """Verify that an index was created on the transfers table."""
    conn = sqlite3.connect('/app/finance.db')
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='transfers'")
    indexes = cursor.fetchall()

    assert len(indexes) > 0, "No index was created on the 'transfers' table. An index strategy was required."

    useful = []
    for (name,) in indexes:
        columns = [row[2] for row in conn.execute(f"PRAGMA index_info({name!r})")]
        if columns and columns[0] == "from_acct":
            useful.append(name)
    assert useful, "An index exists, but none is useful for expanding edges by transfers.from_acct"

    plan = conn.execute("""
        EXPLAIN QUERY PLAN
        WITH RECURSIVE chain(acct) AS (
            SELECT to_acct FROM transfers WHERE from_acct = ?
            UNION
            SELECT t.to_acct
            FROM transfers AS t JOIN chain AS c ON t.from_acct = c.acct
        )
        SELECT acct FROM chain
    """, (SOURCE_ACCOUNT,)).fetchall()
    conn.close()

    plan_text = " ".join(str(row[3]) for row in plan)
    assert any(name in plan_text for name in useful), (
        f"The recursive traversal plan does not use a from_acct index: {plan_text}"
    )


def test_http_service_unauthorized():
    """Verify the service returns 403 when the auth header is missing."""
    try:
        response = requests.get(URL, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the HTTP service at {URL}: {e}")

    assert response.status_code == 403, f"Expected HTTP 403 Forbidden without auth header, got {response.status_code}"
    wrong = requests.get(URL, headers={"X-Compliance-Auth": "wrong_key"}, timeout=5)
    assert wrong.status_code == 403, f"Expected HTTP 403 with an invalid auth header, got {wrong.status_code}"


def test_http_service_authorized():
    """Verify the service returns the correct JSON array when authorized."""
    data = fetch_chain()
    expected_accounts = ["10002", "10003", "10004", "10005", "10006"]
    assert isinstance(data, list), "Expected a JSON array"
    assert data == expected_accounts, f"Expected account list {expected_accounts}, got {data}"


def test_service_contains_recursive_query():
    """Verify the listening service has an actual recursive transfers query."""
    pids = listener_pids(9000)
    assert pids, "Could not identify a process listening on port 9000"
    material = b"\n".join(service_material(pid) for pid in pids)
    assert re.search(rb"\bWITH\s+RECURSIVE\b", material, re.IGNORECASE), (
        "The service implementation does not contain a WITH RECURSIVE query"
    )
    assert re.search(rb"\btransfers\b", material, re.IGNORECASE), (
        "The recursive query does not reference the transfers table"
    )
    assert re.search(rb"\bfrom_acct\b", material, re.IGNORECASE), (
        "The recursive query does not expand transfers by from_acct"
    )


def test_http_service_uses_database_recursively():
    """Exercise the service on verifier-generated multi-hop graph data."""
    token = uuid.uuid4().hex
    first = "8" + str(int(token[:10], 16)).zfill(13)
    second = "8" + str(int(token[10:20], 16)).zfill(13)
    third = "8" + str(int(token[20:30], 16)).zfill(13)
    isolated = "9" + str(int(token[2:12], 16)).zfill(13)
    unreachable = "9" + str(int(token[12:22], 16)).zfill(13)
    tx_prefix = "verifier_" + token

    conn = sqlite3.connect('/app/finance.db', timeout=10)
    try:
        rows = [
            (tx_prefix + "_1", SOURCE_ACCOUNT, first, 1.0, "2026-01-01"),
            (tx_prefix + "_2", first, second, 1.0, "2026-01-01"),
            (tx_prefix + "_3", second, third, 1.0, "2026-01-01"),
            (tx_prefix + "_4", isolated, unreachable, 1.0, "2026-01-01"),
        ]
        conn.executemany("INSERT INTO transfers VALUES (?, ?, ?, ?, ?)", rows)
        conn.commit()

        expected = expected_chain(conn, SOURCE_ACCOUNT)
        data = fetch_chain()
        assert isinstance(data, list), "Expected a JSON array"
        assert data == expected, f"Expected database-derived account list {expected}, got {data}"
        assert first in data and second in data and third in data, "Multi-hop inserted accounts were not traversed"
        assert unreachable not in data, "An account disconnected from the source was incorrectly returned"
    finally:
        try:
            conn.execute("DELETE FROM transfers WHERE tx_id LIKE ?", (tx_prefix + "%",))
            conn.commit()
        finally:
            conn.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
