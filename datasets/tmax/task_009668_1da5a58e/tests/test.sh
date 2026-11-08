#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'INTEGRATION_EOF' > /tmp/verify_integration.py
import json
import os
import pwd
import signal
import socket
import sqlite3
import subprocess
import time

WORK = "/home/user/telemetry_system"
SERVER = os.path.join(WORK, "server.py")
DB = os.path.join(WORK, "db.sqlite3")
CONF = os.path.join(WORK, "nginx.conf")
E2E = os.path.join(WORK, "run_e2e.js")
RESULT = os.path.join(WORK, "e2e_result.log")
USER = pwd.getpwnam("user")
ENV = os.environ.copy()
ENV["NODE_PATH"] = os.path.join(WORK, "node_modules") + (":" + ENV["NODE_PATH"] if ENV.get("NODE_PATH") else "")


def child_setup():
    os.setsid()
    os.initgroups(USER.pw_name, USER.pw_gid)
    os.setgid(USER.pw_gid)
    os.setuid(USER.pw_uid)


def listening_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        local_port = int(fields[1].rsplit(":", 1)[1], 16)
                        if local_port == port:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    found = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    found.add(int(name))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return found


def wait_listener(port, timeout=12):
    end = time.time() + timeout
    while time.time() < end:
        pids = listening_pids(port)
        if pids:
            return pids
        time.sleep(0.1)
    raise AssertionError(f"No process began listening on port {port}")


def wait_no_listener(port, timeout=5):
    end = time.time() + timeout
    while time.time() < end:
        if not listening_pids(port):
            return
        time.sleep(0.1)
    raise AssertionError(f"Port {port} remained occupied")


def kill_port(port):
    for pid in listening_pids(port):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.3)
    for pid in listening_pids(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    wait_no_listener(port)


def stop_process(proc):
    if proc is None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        pass
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def uid_of(pid):
    with open(f"/proc/{pid}/status") as f:
        for line in f:
            if line.startswith("Uid:"):
                return int(line.split()[1])
    raise AssertionError(f"Could not determine uid of process {pid}")


def rss_kb(pid):
    with open(f"/proc/{pid}/status") as f:
        for line in f:
            if line.startswith("VmRSS:"):
                return int(line.split()[1])
    raise AssertionError(f"Could not determine RSS of process {pid}")


def row_count():
    with sqlite3.connect(DB) as conn:
        return conn.execute("SELECT COUNT(*) FROM device_telemetry").fetchone()[0]


def clear_rows():
    with sqlite3.connect(DB) as conn:
        conn.execute("DELETE FROM device_telemetry")
        conn.commit()


def wait_rows(expected, timeout=15):
    end = time.time() + timeout
    while time.time() < end:
        if row_count() == expected:
            return
        time.sleep(0.1)
    raise AssertionError(f"Expected {expected} database rows, found {row_count()}")


assert os.path.isfile(SERVER), "server.py is missing"
assert os.path.isfile(CONF), "nginx.conf is missing"
assert os.path.isfile(E2E), "run_e2e.js is missing"
assert os.path.isfile(DB), "db.sqlite3 is missing"

# Ensure stale agent-started services cannot satisfy the network checks.
kill_port(9000)
kill_port(8080)
clear_rows()
for path in (RESULT, "/tmp/e2e_capture.json"):
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass

server_proc = None
nginx_proc = None
capture_proc = None
try:
    server_log = open("/tmp/verified_server.log", "wb")
    server_proc = subprocess.Popen(
        ["python3", SERVER], cwd=WORK, stdout=server_log,
        stderr=subprocess.STDOUT, preexec_fn=child_setup, env=ENV)
    server_pids = wait_listener(8080)
    assert all(uid_of(pid) == USER.pw_uid for pid in server_pids), "Python server was not run as the non-root user"

    os.makedirs(os.path.join(WORK, "logs"), exist_ok=True)
    os.chown(os.path.join(WORK, "logs"), USER.pw_uid, USER.pw_gid)
    nginx_log = open("/tmp/verified_nginx.log", "wb")
    nginx_proc = subprocess.Popen(
        ["nginx", "-p", WORK + "/", "-c", CONF], cwd=WORK,
        stdout=nginx_log, stderr=subprocess.STDOUT,
        preexec_fn=child_setup, env=ENV)
    nginx_pids = wait_listener(9000)
    assert all(uid_of(pid) == USER.pw_uid for pid in nginx_pids), "Nginx is not running as the non-root user"

    # Exercise the submitted server through the submitted Nginx /ws route.
    client_js = r'''const WebSocket = require("ws");
const ws = new WebSocket("ws://127.0.0.1:9000/ws");
let sent = 0;
ws.on("open", () => {
  ws.send(JSON.stringify({sensor:"probe", value:1}), sendLarge);
});
function sendLarge(err) {
  if (err) throw err;
  if (sent === 80) { ws.close(); return; }
  sent++;
  ws.send(JSON.stringify({sensor:"memory-probe", blob:"x".repeat(512*1024)}), sendLarge);
}
ws.on("close", () => process.exit(0));
ws.on("error", e => { console.error(e); process.exit(2); });
setTimeout(() => process.exit(3), 30000);
'''
    with open("/tmp/verify_ws_client.js", "w") as f:
        f.write(client_js)

    server_pid = next(iter(server_pids))
    baseline_rss = rss_kb(server_pid)
    client = subprocess.run(
        ["node", "/tmp/verify_ws_client.js"], cwd=WORK, env=ENV,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=35)
    assert client.returncode == 0, "WebSocket traffic through Nginx failed: " + client.stdout
    wait_rows(81)
    time.sleep(1)
    growth_kb = rss_kb(server_pid) - baseline_rss
    assert growth_kb < 30 * 1024, f"Server retained incoming messages in memory (RSS grew by {growth_kb} KiB)"

    with sqlite3.connect(DB) as conn:
        missing = conn.execute("SELECT COUNT(*) FROM device_telemetry WHERE received_at IS NULL").fetchone()[0]
        assert missing == 0, "received_at was not populated for inserted telemetry"

    # Replace only the server with a verifier-controlled capture endpoint. This
    # proves run_e2e.js itself connects to /ws and sends exactly five messages,
    # rather than merely fabricating its result log or inserting rows directly.
    kill_port(8080)
    stop_process(server_proc)
    server_proc = None
    clear_rows()

    capture_source = r'''import asyncio, json, sqlite3
from websockets.asyncio.server import serve
DB = "/home/user/telemetry_system/db.sqlite3"
OUT = "/tmp/e2e_capture.json"
done = asyncio.Event()
messages = []
async def handler(ws):
    path = ws.request.path
    assert path == "/ws", path
    try:
        async for message in ws:
            messages.append(message)
            with sqlite3.connect(DB) as conn:
                conn.execute("INSERT INTO device_telemetry(data) VALUES (?)", (message,))
                conn.commit()
    finally:
        with open(OUT, "w") as f:
            json.dump({"path": path, "messages": messages}, f)
        done.set()
async def main():
    async with serve(handler, "127.0.0.1", 8080):
        await done.wait()
asyncio.run(main())
'''
    with open("/tmp/e2e_capture_server.py", "w") as f:
        f.write(capture_source)
    os.chmod("/tmp/e2e_capture_server.py", 0o644)
    capture_log = open("/tmp/e2e_capture_server.log", "wb")
    capture_proc = subprocess.Popen(
        ["python3", "/tmp/e2e_capture_server.py"], cwd=WORK,
        stdout=capture_log, stderr=subprocess.STDOUT,
        preexec_fn=child_setup, env=ENV)
    wait_listener(8080)

    run = subprocess.run(
        ["node", E2E], cwd=WORK, env=ENV,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=40)
    assert run.returncode == 0, "run_e2e.js failed: " + run.stdout

    end = time.time() + 5
    while time.time() < end and not os.path.isfile("/tmp/e2e_capture.json"):
        time.sleep(0.1)
    assert os.path.isfile("/tmp/e2e_capture.json"), "run_e2e.js did not complete a WebSocket connection"
    with open("/tmp/e2e_capture.json") as f:
        capture = json.load(f)
    assert capture["path"] == "/ws", "run_e2e.js used the wrong WebSocket endpoint"
    assert len(capture["messages"]) == 5, f"run_e2e.js sent {len(capture['messages'])} messages instead of exactly 5"
    for message in capture["messages"]:
        parsed = json.loads(message)
        assert isinstance(parsed, dict), "Telemetry message was not a JSON object"
    assert row_count() == 5, f"Expected exactly 5 rows after run_e2e.js, found {row_count()}"
    assert os.path.isfile(RESULT), "run_e2e.js did not create e2e_result.log"
    with open(RESULT) as f:
        assert f.read().strip() == "E2E_PASS", "e2e_result.log does not contain exactly E2E_PASS"
finally:
    stop_process(capture_proc)
    stop_process(server_proc)
    kill_port(8080)
    kill_port(9000)
    stop_process(nginx_proc)
INTEGRATION_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3
import py_compile
import pytest

WORKSPACE_DIR = "/home/user/telemetry_system"
SERVER_FILE = os.path.join(WORKSPACE_DIR, "server.py")
DB_FILE = os.path.join(WORKSPACE_DIR, "db.sqlite3")
NGINX_CONF = os.path.join(WORKSPACE_DIR, "nginx.conf")
E2E_SCRIPT = os.path.join(WORKSPACE_DIR, "run_e2e.js")
E2E_RESULT_LOG = os.path.join(WORKSPACE_DIR, "e2e_result.log")

def test_server_syntax_and_memory_leak_fixed():
    assert os.path.isfile(SERVER_FILE), f"File {SERVER_FILE} does not exist."
    try:
        py_compile.compile(SERVER_FILE, doraise=True)
    except py_compile.PyCompileError as e:
        pytest.fail(f"Syntax error in {SERVER_FILE}: {e}")
    with open(SERVER_FILE, "r") as f:
        content = f.read()
    assert "message_history.append" not in content, "Memory leak still present: 'message_history.append' found in server.py."

def test_database_schema_migrated():
    assert os.path.isfile(DB_FILE), f"Database file {DB_FILE} does not exist."
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='device_telemetry';")
    assert cursor.fetchone() is not None, "Table 'device_telemetry' does not exist. Did you rename 'telemetry'?"
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='telemetry';")
    assert cursor.fetchone() is None, "Legacy table 'telemetry' still exists instead of being renamed."
    cursor.execute("PRAGMA table_info(device_telemetry);")
    rows = cursor.fetchall()
    columns = {row[1]: row[2] for row in rows}
    defaults = {row[1]: row[4] for row in rows}
    assert "id" in columns, "Column 'id' missing in 'device_telemetry' table."
    assert "data" in columns, "Column 'data' missing in 'device_telemetry' table."
    assert "received_at" in columns, "Column 'received_at' missing in 'device_telemetry' table."
    assert "DATETIME" in columns["received_at"].upper(), "Column 'received_at' is not of type DATETIME."
    assert defaults["received_at"] and "CURRENT_TIMESTAMP" in defaults["received_at"].upper(), "received_at does not default to CURRENT_TIMESTAMP."
    conn.close()

def test_nginx_configuration():
    assert os.path.isfile(NGINX_CONF), f"Nginx config {NGINX_CONF} does not exist."
    with open(NGINX_CONF, "r") as f:
        content = f.read().lower()
    assert "proxy_set_header upgrade $http_upgrade;" in content or "proxy_set_header upgrade $http_upgrade" in content, "Nginx config missing 'proxy_set_header Upgrade $http_upgrade;'"
    assert "proxy_set_header connection" in content and "upgrade" in content, "Nginx config missing 'proxy_set_header Connection \"upgrade\";'"
    assert "9000" in content, "Nginx config does not seem to listen on port 9000."
    assert "127.0.0.1:8080" in content, "Nginx config does not proxy to 127.0.0.1:8080."
    assert "/ws" in content, "Nginx config does not define the /ws endpoint."

def test_e2e_result_log():
    assert os.path.isfile(E2E_SCRIPT), f"E2E script {E2E_SCRIPT} does not exist."
    assert os.path.isfile(E2E_RESULT_LOG), f"E2E result log {E2E_RESULT_LOG} does not exist. Did the Node.js script run successfully?"
    with open(E2E_RESULT_LOG, "r") as f:
        content = f.read().strip()
    assert "E2E_PASS" in content, f"Expected 'E2E_PASS' in {E2E_RESULT_LOG}, but found '{content}'."
TEST_EOF

if python3 /tmp/verify_integration.py 2>&1 && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
