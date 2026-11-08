#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import signal
import socket
import sqlite3
import subprocess
import time

import pytest

HOST = "127.0.0.1"
PORT = 9000
SERVER_SOURCE = "/home/user/server.c"
VERIFIED_BINARY = "/tmp/verified_server"
_server_process = None


def can_connect():
    try:
        with socket.create_connection((HOST, PORT), timeout=0.5):
            return True
    except OSError:
        return False


def listener_pids():
    inodes = set()
    target = "0100007F:2328"  # 127.0.0.1:9000 in /proc/net/tcp format
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[1].upper() == target and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    link = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if link.startswith("socket:[") and link[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except OSError:
            continue
    return pids


@pytest.fixture(scope="session", autouse=True)
def build_and_run_submitted_server():
    global _server_process

    assert os.path.isfile(SERVER_SOURCE), f"Missing required C source: {SERVER_SOURCE}"
    assert os.path.getsize(SERVER_SOURCE) > 0, f"C source is empty: {SERVER_SOURCE}"
    assert can_connect(), f"No server was left running at {HOST}:{PORT}"

    result = subprocess.run(
        ["gcc", SERVER_SOURCE, "-o", VERIFIED_BINARY, "-lsqlite3"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"server.c did not compile:\n{result.stderr}"

    pids = listener_pids()
    assert pids, "Could not identify the process listening on port 9000"
    for pid in pids:
        os.kill(pid, signal.SIGTERM)

    deadline = time.time() + 3
    while time.time() < deadline and can_connect():
        time.sleep(0.05)
    if can_connect():
        for pid in listener_pids():
            os.kill(pid, signal.SIGKILL)
        time.sleep(0.2)
    assert not can_connect(), "The original listener could not be stopped for source verification"

    _server_process = subprocess.Popen(
        [VERIFIED_BINARY],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    deadline = time.time() + 5
    while time.time() < deadline:
        if _server_process.poll() is not None:
            pytest.fail(f"Compiled server exited with status {_server_process.returncode}")
        if can_connect():
            break
        time.sleep(0.05)
    else:
        pytest.fail(f"Compiled server did not listen at {HOST}:{PORT}")

    yield


def index_columns(conn, index_name):
    escaped = index_name.replace('"', '""')
    rows = conn.execute(f'PRAGMA index_info("{escaped}")').fetchall()
    return [row[2] for row in sorted(rows, key=lambda row: row[0])]


def test_database_indexes():
    """Verify that useful traversal indexes were created on paper_authors."""
    db_path = "/app/dataset.db"
    assert os.path.isfile(db_path), f"Database file missing: {db_path}"

    conn = sqlite3.connect(db_path)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name, tbl_name FROM sqlite_master WHERE type='index' AND tbl_name='paper_authors'")
        indexes = cursor.fetchall()
        assert len(indexes) > 0, "No indexes found on the 'paper_authors' table. The agent must create optimal indexes."

        index_list = conn.execute("PRAGMA index_list('paper_authors')").fetchall()
        leading_columns = set()
        for row in index_list:
            name = row[1]
            partial = bool(row[4]) if len(row) > 4 else False
            columns = index_columns(conn, name)
            if not partial and columns:
                leading_columns.add(columns[0])

        assert "author_id" in leading_columns, (
            "paper_authors needs a non-partial index beginning with author_id "
            "to find an author's papers efficiently"
        )
        assert "paper_id" in leading_columns, (
            "paper_authors needs a non-partial index beginning with paper_id "
            "to find all authors on each paper efficiently"
        )
    finally:
        conn.close()


def read_response(sock):
    response = bytearray()
    while True:
        chunk = sock.recv(1)
        if not chunk:
            pytest.fail("Server closed the connection before sending a complete response")
        response.extend(chunk)
        if chunk == b"\n":
            return response.decode("utf-8")
        if len(response) > 100000:
            pytest.fail("Server response was unreasonably large or lacked a newline")


def check_requests(requests_and_expected):
    try:
        sock = socket.create_connection((HOST, PORT), timeout=5.0)
        sock.settimeout(5.0)
    except Exception as exc:
        pytest.fail(f"Failed to connect to TCP server at {HOST}:{PORT}: {exc}")

    try:
        for author_id, expected in requests_and_expected:
            request = f"GET_COAUTHORS {author_id}\n"
            sock.sendall(request.encode("utf-8"))
            actual = read_response(sock)
            assert actual == expected, (
                f"Expected {expected!r} for request {request.strip()!r}, got {actual!r}"
            )
    finally:
        sock.close()


def test_tcp_server_responses():
    """Verify fixed examples and unpredictable database-backed graph traversals."""
    fixed = [
        (2, "1,3,4\n"),
        (1, "2,3\n"),
        (5, "\n"),
        (99, "\n"),
    ]
    check_requests(fixed)

    conn = sqlite3.connect("/app/dataset.db")
    try:
        used_authors = {row[0] for row in conn.execute("SELECT id FROM authors")}
        used_papers = {row[0] for row in conn.execute("SELECT DISTINCT paper_id FROM paper_authors")}

        random_authors = []
        while len(random_authors) < 6:
            value = 100000 + secrets.randbelow(900000000)
            if value not in used_authors and value not in random_authors:
                random_authors.append(value)

        random_papers = []
        while len(random_papers) < 5:
            value = 100000 + secrets.randbelow(900000000)
            if value not in used_papers and value not in random_papers:
                random_papers.append(value)

        for author_id in random_authors:
            conn.execute("INSERT INTO authors(id, name) VALUES (?, ?)",
                         (author_id, f"generated-{author_id}"))

        a, b, c, d, e, f = random_authors
        p0, p1, p2, p3, p4 = random_papers
        edges = [
            (p0, a), (p0, b), (p0, c),
            (p1, a), (p1, d),
            (p2, b), (p2, e),
            (p3, f),
            (p4, c), (p4, d), (p4, e),
        ]
        conn.executemany("INSERT INTO paper_authors(paper_id, author_id) VALUES (?, ?)", edges)
        conn.commit()

        absent = 100000 + secrets.randbelow(900000000)
        while absent in used_authors or absent in random_authors:
            absent = 100000 + secrets.randbelow(900000000)

        requested = random_authors + [absent]
        secrets.SystemRandom().shuffle(requested)
        dynamic = []
        for author_id in requested:
            rows = conn.execute(
                """
                SELECT DISTINCT other.author_id
                FROM paper_authors AS own
                JOIN paper_authors AS other ON other.paper_id = own.paper_id
                WHERE own.author_id = ? AND other.author_id <> ?
                ORDER BY other.author_id ASC
                """,
                (author_id, author_id),
            ).fetchall()
            expected = ",".join(str(row[0]) for row in rows) + "\n"
            dynamic.append((author_id, expected))
    finally:
        conn.close()

    check_requests(dynamic)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
