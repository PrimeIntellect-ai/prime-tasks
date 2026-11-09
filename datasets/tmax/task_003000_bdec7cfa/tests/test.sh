#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import socket
import sqlite3
from collections import Counter

import pytest


def test_index_dropped():
    db_path = "/home/user/pipeline.db"
    assert os.path.isfile(db_path), f"Database file {db_path} is missing."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Check that idx_stale has been dropped
    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_stale';")
    result = cursor.fetchone()

    conn.close()

    assert result is None, "The corrupted index 'idx_stale' was not dropped from the database."


def _query_server(node_id: str) -> str:
    host = "127.0.0.1"
    port = 8888

    try:
        with socket.create_connection((host, port), timeout=5) as sock:
            sock.sendall(f"{node_id}\n".encode("utf-8"))
            response = sock.recv(1024).decode("utf-8")
            return response
    except Exception as e:
        pytest.fail(f"Failed to connect to or read from TCP server at {host}:{port}: {e}")


def _listener_processes():
    socket_inodes = set()
    for net_file in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(net_file, encoding="ascii") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9:
                        port = int(fields[1].rsplit(":", 1)[1], 16)
                        state = fields[3]
                        if port == 8888 and state == "0A":
                            socket_inodes.add(fields[9])
        except FileNotFoundError:
            pass

    owners = []
    for pid in (p for p in os.listdir("/proc") if p.isdigit()):
        fd_dir = f"/proc/{pid}/fd"
        try:
            links = [os.readlink(os.path.join(fd_dir, fd)) for fd in os.listdir(fd_dir)]
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if not any(link.startswith("socket:[") and link[8:-1] in socket_inodes for link in links):
            continue
        try:
            executable = os.path.basename(os.readlink(f"/proc/{pid}/exe"))
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                command = f.read().replace(b"\0", b" ").decode("utf-8", "replace")
            owners.append((pid, executable, command))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return owners


def test_server_uses_bash_cli_tooling():
    owners = _listener_processes()
    assert owners, "No process is listening on TCP port 8888."

    allowed = {"bash", "nc", "nc.openbsd", "netcat", "socat"}
    for pid, executable, command in owners:
        assert executable in allowed, (
            f"Listener PID {pid} uses {executable!r}, not Bash/nc/socat tooling."
        )
        lowered = command.lower()
        assert "python" not in lowered and "node" not in lowered, (
            f"Listener PID {pid} delegates to a forbidden Python or Node.js server."
        )


def test_tcp_server_alpha():
    response = _query_server("Alpha")
    assert response == "IN:1,OUT:2\n", f"Expected 'IN:1,OUT:2\\n' for Node 'Alpha', got {repr(response)}"


def test_tcp_server_delta():
    response = _query_server("Delta")
    assert response == "IN:2,OUT:0\n", f"Expected 'IN:2,OUT:0\\n' for Node 'Delta', got {repr(response)}"


def test_tcp_server_beta():
    response = _query_server("Beta")
    assert response == "IN:1,OUT:1\n", f"Expected 'IN:1,OUT:1\\n' for Node 'Beta', got {repr(response)}"


def test_tcp_server_unknown():
    response = _query_server("Unknown")
    assert response == "IN:0,OUT:0\n", f"Expected 'IN:0,OUT:0\\n' for Node 'Unknown', got {repr(response)}"


def test_tcp_server_all_database_nodes_and_fresh_unknowns():
    conn = sqlite3.connect("/home/user/pipeline.db")
    try:
        rows = conn.execute(
            "SELECT upstream_id, downstream_id FROM routing_edges"
        ).fetchall()
    finally:
        conn.close()

    assert rows, "The routing edge data is missing."
    in_degree = Counter(dst for _, dst in rows)
    out_degree = Counter(src for src, _ in rows)
    nodes = {value for edge in rows for value in edge}

    for node in sorted(nodes):
        expected = f"IN:{in_degree[node]},OUT:{out_degree[node]}\n"
        response = _query_server(node)
        assert response == expected, (
            f"Expected {expected!r} for database node {node!r}, got {response!r}"
        )

    for _ in range(4):
        unknown = "VerifierUnknown_" + secrets.token_hex(16)
        assert unknown not in nodes
        response = _query_server(unknown)
        assert response == "IN:0,OUT:0\n", (
            f"Expected zero degrees for fresh unknown node {unknown!r}, got {response!r}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
