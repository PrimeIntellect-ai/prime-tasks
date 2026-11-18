#!/bin/bash
set -e
mkdir -p /logs/verifier
PASS=0
ORACLE_MOVED=0

cleanup() {
    if [ "$ORACLE_MOVED" = "1" ] && [ -e /app/score_oracle.verifier-real ]; then
        rm -f /app/score_oracle
        mv /app/score_oracle.verifier-real /app/score_oracle
    fi
    echo "$PASS" > /logs/verifier/reward.txt
}
trap cleanup EXIT

rm -rf /tmp/oracle_capture
mkdir -p /tmp/oracle_capture
chmod 777 /tmp/oracle_capture

mv /app/score_oracle /app/score_oracle.verifier-real
ORACLE_MOVED=1
cat > /app/score_oracle <<'WRAPPER_EOF'
#!/bin/bash
set -e
call_dir=$(mktemp -d /tmp/oracle_capture/call.XXXXXX)
printf '%s' "$2" > "$call_dir/node_id"
cp -- "$1" "$call_dir/input.csv"
exec /app/score_oracle.verifier-real "$@"
WRAPPER_EOF
chmod 755 /app/score_oracle

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import os
import socket
import sqlite3
import subprocess
import tempfile
import time

import pytest

EXPECTED_NODES = {
    ("A", "User"), ("B", "User"), ("C", "User"),
    ("D", "User"), ("E", "User"),
}
EXPECTED_EDGES = {
    ("A", "B", 10.0), ("B", "C", 5.0), ("A", "D", 8.0),
    ("D", "C", 12.0), ("C", "E", 20.0), ("B", "E", 15.0),
}
EXPECTED_TWO_HOP = {
    ("A", "C", 8.0), ("A", "E", 10.0),
    ("B", "E", 5.0), ("D", "E", 12.0),
}


def relation_columns(conn, name):
    return [row[1] for row in conn.execute(f'PRAGMA table_info("{name}")')]


def find_database():
    paths = set()
    for pattern in ("/home/user/**/*.db", "/home/user/**/*.sqlite", "/home/user/**/*.sqlite3"):
        paths.update(glob.glob(pattern, recursive=True))

    for path in sorted(paths):
        try:
            conn = sqlite3.connect(path, timeout=2)
            objects = conn.execute(
                "SELECT name, type FROM sqlite_master WHERE type IN ('table','view')"
            ).fetchall()
            names = {name: kind for name, kind in objects}
            if "two_hop" not in names:
                conn.close()
                continue
            if relation_columns(conn, "two_hop") != ["source", "target", "weight"]:
                conn.close()
                continue

            node_relation = None
            edge_relation = None
            for name, _ in objects:
                cols = relation_columns(conn, name)
                try:
                    if cols == ["node_id", "type"]:
                        rows = set(conn.execute(
                            f'SELECT node_id, type FROM "{name}"'
                        ).fetchall())
                        if rows == EXPECTED_NODES:
                            node_relation = name
                    elif cols == ["source", "target", "weight"] and name != "two_hop":
                        rows = {
                            (str(s), str(t), float(w))
                            for s, t, w in conn.execute(
                                f'SELECT source, target, weight FROM "{name}"'
                            )
                        }
                        if rows == EXPECTED_EDGES:
                            edge_relation = name
                except sqlite3.DatabaseError:
                    pass

            projected = {
                (str(s), str(t), float(w))
                for s, t, w in conn.execute(
                    'SELECT source, target, weight FROM "two_hop"'
                )
            }
            if node_relation and edge_relation and projected == EXPECTED_TWO_HOP:
                kind = names["two_hop"]
                conn.close()
                return path, kind, node_relation, edge_relation
            conn.close()
        except sqlite3.DatabaseError:
            pass
    pytest.fail("No SQLite database contains the loaded nodes/edges and the required two_hop projection")


def query_service(node_id):
    before = set(glob.glob("/tmp/oracle_capture/call.*"))
    try:
        with socket.create_connection(("localhost", 9000), timeout=5) as sock:
            sock.settimeout(5)
            sock.sendall((node_id + "\n").encode("utf-8"))
            chunks = []
            while True:
                data = sock.recv(1024)
                if not data:
                    break
                chunks.append(data)
    except ConnectionRefusedError:
        pytest.fail("TCP service is not running on localhost:9000 or refused the connection")
    except socket.timeout:
        pytest.fail("TCP service on localhost:9000 timed out or did not close the connection")

    raw = b"".join(chunks)
    assert raw.endswith(b"\n"), "TCP response was not followed by a newline"

    deadline = time.time() + 2
    new_calls = set()
    while time.time() < deadline:
        new_calls = set(glob.glob("/tmp/oracle_capture/call.*")) - before
        if new_calls:
            break
        time.sleep(0.02)
    assert len(new_calls) == 1, "Each request must invoke /app/score_oracle exactly once"

    call_dir = new_calls.pop()
    with open(os.path.join(call_dir, "node_id"), encoding="utf-8") as f:
        invoked_node = f.read()
    assert invoked_node == node_id, "The service passed the wrong node_id to the oracle"

    rows = []
    with open(os.path.join(call_dir, "input.csv"), newline="", encoding="utf-8") as f:
        for row in csv.reader(f):
            assert len(row) == 3, "Oracle input must be headerless source,target,weight CSV"
            rows.append((row[0], row[1], float(row[2])))
    return raw.decode("utf-8").strip(), rows


def assert_request(node_id, expected_response, expected_rows):
    response, rows = query_service(node_id)
    assert response == expected_response
    assert set(rows) == set(expected_rows)
    assert len(rows) == len(expected_rows)


def oracle_result(node_id, rows):
    fd, path = tempfile.mkstemp(prefix="expected-", suffix=".csv")
    try:
        with os.fdopen(fd, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerows(rows)
        return subprocess.check_output(
            ["/app/score_oracle.verifier-real", path, node_id], text=True
        ).strip()
    finally:
        os.unlink(path)


def test_00_sqlite_projection_exists_and_is_correct():
    find_database()


def test_tcp_service_node_a():
    # A->C has maximum bottleneck 8; A->E has bottleneck 10.
    assert_request("A", "27.00", [("A", "C", 8.0), ("A", "E", 10.0)])


def test_tcp_service_node_b():
    assert_request("B", "7.50", [("B", "E", 5.0)])


def test_tcp_service_node_d():
    assert_request("D", "18.00", [("D", "E", 12.0)])


def test_tcp_service_node_c():
    assert_request("C", "0.00", [])


def test_service_queries_live_sqlite_data_and_handles_input_safely():
    path, kind, _, edge_relation = find_database()
    conn = sqlite3.connect(path, timeout=5)
    try:
        if kind == "table":
            conn.execute(
                'INSERT INTO "two_hop" (source, target, weight) VALUES (?, ?, ?)',
                ("Q", "R", 13.25),
            )
            cleanup_sql = 'DELETE FROM "two_hop" WHERE source = ? AND target = ?'
            cleanup_args = ("Q", "R")
        else:
            conn.executemany(
                f'INSERT INTO "{edge_relation}" (source, target, weight) VALUES (?, ?, ?)',
                [("Q", "X", 13.25), ("X", "R", 20.0)],
            )
            cleanup_sql = f'DELETE FROM "{edge_relation}" WHERE source IN (?, ?)'
            cleanup_args = ("Q", "X")
        conn.commit()

        dynamic_rows = [
            (str(s), str(t), float(w))
            for s, t, w in conn.execute(
                'SELECT source, target, weight FROM "two_hop" WHERE source = ?', ("Q",)
            )
        ]
        assert dynamic_rows == [("Q", "R", 13.25)]
        expected = oracle_result("Q", dynamic_rows)
        assert_request("Q", expected, dynamic_rows)

        injected = "Q' OR 1=1 --"
        expected_empty = oracle_result(injected, [])
        assert_request(injected, expected_empty, [])
    finally:
        try:
            if 'cleanup_sql' in locals():
                conn.execute(cleanup_sql, cleanup_args)
                conn.commit()
        finally:
            conn.close()
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
PASS=1
