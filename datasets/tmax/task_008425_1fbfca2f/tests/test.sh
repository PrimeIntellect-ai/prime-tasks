#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import glob
import json
import os
import re
import signal
import sqlite3
import subprocess
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

import pytest

SERVICE_DIR = "/home/user/service"
SERVER_PATH = os.path.join(SERVICE_DIR, "server")
DB_PATH = os.path.join(SERVICE_DIR, "db.sqlite3")
PYTHON_PATH = "/home/user/venv/bin/python"


def request(method, path, payload=None, timeout=5):
    data = None
    headers = {}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(
        "http://127.0.0.1:8080" + path,
        data=data,
        headers=headers,
        method=method,
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return response.status, response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8")


def kill_port_8080_listeners():
    socket_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].endswith(":1F90") and fields[3] == "0A":
                        socket_inodes.add(fields[9])
        except OSError:
            pass

    victims = set()
    for proc_dir in glob.glob("/proc/[0-9]*"):
        try:
            pid = int(proc_dir.rsplit("/", 1)[1])
            if pid == os.getpid():
                continue
            for fd in glob.glob(proc_dir + "/fd/*"):
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in socket_inodes:
                    victims.add(pid)
                    break
        except (OSError, ValueError):
            continue

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    if victims:
        time.sleep(0.5)


@pytest.fixture(scope="session", autouse=True)
def prepared_service():
    assert os.path.isfile(PYTHON_PATH), f"Virtual environment Python not found at {PYTHON_PATH}"
    assert os.access(PYTHON_PATH, os.X_OK), f"Virtual environment Python is not executable"

    import_check = subprocess.run(
        [PYTHON_PATH, "-c", "import requests"], capture_output=True, text=True, timeout=15
    )
    assert import_check.returncode == 0, import_check.stderr

    migrate_path = "/home/user/migrate.py"
    exploit_path = "/home/user/exploit.py"
    assert os.path.isfile(migrate_path), f"Migration script not found at {migrate_path}"
    assert os.path.isfile(exploit_path), f"Exploit script not found at {exploit_path}"

    kill_port_8080_listeners()
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)

    migration = subprocess.run(
        [PYTHON_PATH, migrate_path],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert migration.returncode == 0, f"Migration script failed: {migration.stderr}"
    assert os.path.isfile(DB_PATH), "Migration did not create db.sqlite3"

    build = subprocess.run(
        ["go", "build", "-o", SERVER_PATH, "."],
        cwd=SERVICE_DIR,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert build.returncode == 0, f"Go service does not compile: {build.stderr}"
    assert os.path.isfile(SERVER_PATH), f"Expected executable not found at {SERVER_PATH}"
    assert os.access(SERVER_PATH, os.X_OK), f"File at {SERVER_PATH} is not executable"

    go_binary = subprocess.run(
        ["go", "version", "-m", SERVER_PATH], capture_output=True, text=True, timeout=15
    )
    assert go_binary.returncode == 0, f"server is not a Go executable: {go_binary.stderr}"
    assert "example.com/service" in go_binary.stdout, "server was not built from the service Go module"

    proc = subprocess.Popen(
        [SERVER_PATH],
        cwd=SERVICE_DIR,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        ready = False
        for _ in range(50):
            if proc.poll() is not None:
                break
            try:
                status, _ = request("GET", "/balance?username=verifier_readiness", timeout=1)
                if status == 200:
                    ready = True
                    break
            except Exception:
                time.sleep(0.1)
        assert ready, f"Compiled server did not listen on port 8080; stderr: {proc.stderr.read() if proc.poll() is not None else ''}"
        assert proc.poll() is None, "Compiled server exited unexpectedly"

        exploit = subprocess.run(
            [PYTHON_PATH, exploit_path],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=45,
        )
        assert exploit.returncode == 0, f"Exploit script failed: {exploit.stderr}"
        assert proc.poll() is None, "Server exited while the exploit was running"

        yield
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)


def test_server_compiled():
    server_path = "/home/user/service/server"
    assert os.path.isfile(server_path), f"Expected executable not found at {server_path}"
    assert os.access(server_path, os.X_OK), f"File at {server_path} is not executable"


def test_database_schema():
    db_path = "/home/user/service/db.sqlite3"
    assert os.path.isfile(db_path), f"Database file not found at {db_path}"

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='users';")
    table = cursor.fetchone()
    assert table is not None, "Table 'users' does not exist in the database."

    cursor.execute("PRAGMA table_info(users);")
    columns = {row[1]: row[2].upper() for row in cursor.fetchall()}
    expected_columns = ["id", "username", "balance", "coupon_redeemed"]
    for col in expected_columns:
        assert col in columns, f"Column '{col}' missing from 'users' table"
    conn.close()


def test_report_balance():
    report_path = "/home/user/report.txt"
    assert os.path.isfile(report_path), f"Report file not found at {report_path}"

    with open(report_path, "r") as f:
        raw_content = f.read()
    assert re.fullmatch(r"[0-9]+\n?", raw_content), f"{report_path} must contain only the integer balance"
    content = raw_content.strip()
    try:
        balance = int(content)
    except ValueError:
        pytest.fail(f"Content of {report_path} is not a valid integer: '{content}'")

    assert balance > 50, f"Expected balance to be strictly greater than 50 (race condition exploited), but got {balance}"

    status, body = request("GET", "/balance?username=qa_tester")
    assert status == 200, "The running service did not return qa_tester's balance"
    assert re.fullmatch(r"-?[0-9]+", body.strip()), f"Invalid balance response: {body!r}"
    api_balance = int(body.strip())

    conn = sqlite3.connect(DB_PATH)
    row = conn.execute("SELECT balance FROM users WHERE username = ?", ("qa_tester",)).fetchone()
    conn.close()
    assert row is not None, "exploit.py did not create qa_tester in the migrated database"
    assert balance == api_balance == int(row[0]), (
        f"Report ({balance}), API ({api_balance}), and database ({row[0]}) balances do not agree"
    )


def test_service_endpoints_and_race_independently():
    username = "verifier_" + uuid.uuid4().hex
    status, _ = request("POST", "/register", {"username": username})
    assert status == 200, f"POST /register returned HTTP {status}"

    status, body = request("GET", "/balance?username=" + urllib.parse.quote(username))
    assert status == 200 and body.strip() == "0", f"New user did not have a zero balance: {status}, {body!r}"

    status, _ = request("POST", "/redeem", {"username": username, "code": "NOT_A_COUPON"})
    assert status == 400, f"POST /redeem accepted an invalid coupon with HTTP {status}"

    workers = 20
    barrier = threading.Barrier(workers)

    def redeem_once():
        barrier.wait(timeout=10)
        return request("POST", "/redeem", {"username": username, "code": "WELCOME50"}, timeout=15)[0]

    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
        statuses = list(executor.map(lambda _: redeem_once(), range(workers)))

    assert all(status in (200, 400) for status in statuses), f"Unexpected redeem responses: {statuses}"
    status, body = request("GET", "/balance?username=" + urllib.parse.quote(username))
    assert status == 200 and re.fullmatch(r"-?[0-9]+", body.strip()), f"Invalid /balance response: {status}, {body!r}"
    balance = int(body.strip())
    assert balance > 50, f"20 simultaneous redemptions did not expose the TOCTOU race; balance was {balance}"
    assert balance % 50 == 0 and balance <= 1000, f"Unexpected coupon balance {balance}"

    conn = sqlite3.connect(DB_PATH)
    row = conn.execute("SELECT balance, coupon_redeemed FROM users WHERE username = ?", (username,)).fetchone()
    conn.close()
    assert row is not None, "Registered user was not stored in the SQLite database"
    assert int(row[0]) == balance and bool(row[1]), "API result does not match the persisted coupon state"


def test_venv_and_requests():
    python_path = "/home/user/venv/bin/python"
    assert os.path.isfile(python_path), f"Virtual environment Python not found at {python_path}"
    assert os.access(python_path, os.X_OK), f"Virtual environment Python is not executable"
    result = subprocess.run(
        [python_path, "-c", "import requests"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Failed to import 'requests' in the virtual environment. Error: {result.stderr}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
