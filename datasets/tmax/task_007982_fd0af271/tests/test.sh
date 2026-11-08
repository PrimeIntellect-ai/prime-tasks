#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pwd
import re
import secrets
import shutil
import socket
import sqlite3
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

USER = pwd.getpwnam("user")
NGINX_CONF = "/home/user/nginx.conf"
BACKEND_TOKEN = "backend-" + secrets.token_hex(20)
_backend = None
_nginx_processes = []


def run_as_user(args, **kwargs):
    return subprocess.run(
        ["runuser", "-u", "user", "--", *args],
        **kwargs,
    )


def wait_for_port(port, open_state=True, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        sock = socket.socket()
        sock.settimeout(0.15)
        try:
            connected = sock.connect_ex(("127.0.0.1", port)) == 0
        finally:
            sock.close()
        if connected == open_state:
            return
        time.sleep(0.05)
    state = "open" if open_state else "closed"
    pytest.fail(f"Port {port} did not become {state}.")


def stop_user_nginx():
    if os.path.exists(NGINX_CONF):
        run_as_user(
            ["nginx", "-c", NGINX_CONF, "-s", "stop"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    subprocess.run(
        ["pkill", "-u", str(USER.pw_uid), "-x", "nginx"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    deadline = time.time() + 3
    while time.time() < deadline:
        sock = socket.socket()
        sock.settimeout(0.1)
        try:
            if sock.connect_ex(("127.0.0.1", 8080)) != 0:
                break
        finally:
            sock.close()
        time.sleep(0.05)
    try:
        os.remove("/home/user/nginx.pid")
    except FileNotFoundError:
        pass


def start_submitted_nginx():
    stop_user_nginx()
    proc = subprocess.Popen(
        ["runuser", "-u", "user", "--", "nginx", "-c", NGINX_CONF],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    _nginx_processes.append(proc)
    deadline = time.time() + 5
    while time.time() < deadline:
        sock = socket.socket()
        sock.settimeout(0.15)
        try:
            if sock.connect_ex(("127.0.0.1", 8080)) == 0:
                return
        finally:
            sock.close()
        if proc.poll() not in (None, 0):
            pytest.fail("The submitted nginx configuration could not be started as user.")
        time.sleep(0.05)
    pytest.fail("Submitted Nginx did not bind to port 8080.")


class BackendHandler(BaseHTTPRequestHandler):
    def do_HEAD(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()

    def do_GET(self):
        body = BACKEND_TOKEN.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass


@pytest.fixture(scope="session", autouse=True)
def backend_server():
    global _backend
    try:
        _backend = ThreadingHTTPServer(("127.0.0.1", 9999), BackendHandler)
    except OSError as exc:
        pytest.fail(f"Could not establish verifier backend on required port 9999: {exc}")
    thread = threading.Thread(target=_backend.serve_forever, daemon=True)
    thread.start()
    yield
    _backend.shutdown()
    _backend.server_close()


def test_schema_migration():
    db_path = "/home/user/builds.db"
    assert os.path.exists(db_path), f"Database file {db_path} is missing."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='legacy_builds';")
    assert cursor.fetchone() is None, "Table 'legacy_builds' was not dropped."

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='active_builds';")
    assert cursor.fetchone() is not None, "Table 'active_builds' was not created."

    cursor.execute("SELECT repository, lang, build_cmd FROM active_builds ORDER BY repository;")
    rows = cursor.fetchall()
    expected_rows = [
        ('github.com/org/repo1', 'node', 'npm run build'),
        ('github.com/org/repo2', 'python', 'pip install -r req.txt && pytest')
    ]
    assert len(rows) == len(expected_rows), f"Expected {len(expected_rows)} rows in active_builds, got {len(rows)}."
    for row, expected in zip(rows, expected_rows):
        assert row == expected, f"Row mismatch: expected {expected}, got {row}."
    conn.close()


def test_migration_script_on_fresh_dynamic_database():
    script = "/home/user/migrate.sh"
    db_path = "/home/user/builds.db"
    assert os.path.isfile(script), f"Migration script {script} is missing."
    assert os.access(script, os.X_OK), f"Migration script {script} is not executable."

    token = secrets.token_hex(12)
    records = [
        (17, f"host/{token}/alpha", {"lang": f"lang-{token}-a", "command": f"compile alpha {token}", "timeout": 11}),
        (23, f"host/{token}/repo's-beta", {"lang": f"lang-{token}-b", "command": f"run beta && echo {token}", "timeout": 22}),
        (41, f"host/{token}/gamma", {"lang": f"lang-{token}-c", "command": f"tool --token={token}", "timeout": 33}),
    ]

    backup = tempfile.NamedTemporaryFile(delete=False)
    backup.close()
    shutil.copy2(db_path, backup.name)
    try:
        os.remove(db_path)
        conn = sqlite3.connect(db_path)
        conn.execute("CREATE TABLE legacy_builds(id INTEGER PRIMARY KEY, repository TEXT, build_data TEXT)")
        conn.executemany(
            "INSERT INTO legacy_builds(id, repository, build_data) VALUES (?, ?, ?)",
            [(row_id, repository, json.dumps(data)) for row_id, repository, data in records],
        )
        conn.commit()
        conn.close()
        os.chown(db_path, USER.pw_uid, USER.pw_gid)
        os.chmod(db_path, 0o666)

        result = run_as_user([script], capture_output=True, text=True, timeout=15)
        assert result.returncode == 0, f"migrate.sh failed on a fresh database:\n{result.stderr}"

        conn = sqlite3.connect(db_path)
        tables = {row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        assert "legacy_builds" not in tables, "migrate.sh did not drop legacy_builds."
        assert "active_builds" in tables, "migrate.sh did not create active_builds."
        columns = conn.execute("PRAGMA table_info(active_builds)").fetchall()
        assert [(c[1], c[2].upper(), c[5]) for c in columns] == [
            ("id", "INTEGER", 1),
            ("repository", "TEXT", 0),
            ("lang", "TEXT", 0),
            ("build_cmd", "TEXT", 0),
        ]
        actual = conn.execute(
            "SELECT id, repository, lang, build_cmd FROM active_builds ORDER BY id"
        ).fetchall()
        expected = [
            (row_id, repository, data["lang"], data["command"])
            for row_id, repository, data in records
        ]
        assert actual == expected, f"Dynamic migration result was incorrect: {actual!r}"
        conn.close()
    finally:
        try:
            os.remove(db_path)
        except FileNotFoundError:
            pass
        shutil.copy2(backup.name, db_path)
        os.remove(backup.name)


def invoke_generate_env(data):
    fd, path = tempfile.mkstemp(suffix=".json")
    try:
        with os.fdopen(fd, "w") as handle:
            json.dump(data, handle)
        os.chmod(path, 0o644)
        return run_as_user(
            ["/home/user/generate_env.sh", path],
            capture_output=True,
            text=True,
            timeout=10,
        )
    finally:
        os.remove(path)


def test_generate_env_script():
    script_path = "/home/user/generate_env.sh"
    assert os.path.exists(script_path), f"Script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    test_data = {
        "project": "example",
        "env": {
            "NODE_ENV": "production",
            "PORT": "3000",
            "API_KEY": "secret123"
        }
    }
    result = invoke_generate_env(test_data)
    assert result.returncode == 0, result.stderr
    output = result.stdout.strip()
    expected_output = 'export API_KEY="secret123"\nexport NODE_ENV="production"\nexport PORT="3000"'
    assert output == expected_output, f"Output of generate_env.sh is incorrect.\nExpected:\n{expected_output}\nGot:\n{output}"


def test_generate_env_dynamic_and_empty_inputs():
    token = secrets.token_hex(10)
    env = {
        "ZETA_VALUE": f"zeta {token}",
        "ALPHA_VALUE": f"alpha-{token}",
        "MIDDLE_7": f"middle {token}",
        "BUILD_TOKEN": token,
    }
    result = invoke_generate_env({"project": "dynamic", "env": env})
    assert result.returncode == 0, result.stderr
    expected = "\n".join(f'export {key}="{env[key]}"' for key in sorted(env)) + "\n"
    assert result.stdout == expected, f"Dynamic env transformation was incorrect: {result.stdout!r}"

    for data in ({"project": "missing"}, {"project": "empty", "env": {}}):
        empty_result = invoke_generate_env(data)
        assert empty_result.returncode == 0, empty_result.stderr
        assert empty_result.stdout == "", "Missing or empty env must produce no output."


def test_nginx_configuration_directives():
    assert os.path.isfile(NGINX_CONF), f"Nginx configuration {NGINX_CONF} is missing."
    result = run_as_user(
        ["nginx", "-T", "-c", NGINX_CONF],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"nginx.conf is not valid when tested as user:\n{result.stderr}"
    config = re.sub(r"#.*", "", result.stdout + "\n" + result.stderr)

    assert re.search(r"\bpid\s+/home/user/nginx\.pid\s*;", config)
    assert re.search(r"\berror_log\s+/home/user/error\.log(?:\s+\w+)?\s*;", config)
    assert re.search(r"\baccess_log\s+/home/user/access\.log(?:\s+[^;]+)?\s*;", config)
    assert re.search(r"\blisten\s+(?:127\.0\.0\.1:|0\.0\.0\.0:|\[::\]:)?8080\b[^;]*;", config)
    assert re.search(
        r"limit_req_zone\s+\$(?:binary_remote_addr|remote_addr)\s+zone=build_zone:1m\s+rate=2r/m\s*;",
        config,
    ), "Expected build_zone keyed by client IP, size 1m, with rate 2r/m."

    match = re.search(r"location\s+(?:\^~\s+|=\s+)?/trigger\s*\{([^{}]*)\}", config, re.S)
    assert match, "A /trigger location is missing."
    location = match.group(1)
    assert re.search(r"proxy_pass\s+http://127\.0\.0\.1:9999\s*;", location)
    limit = re.search(r"limit_req\s+([^;]+);", location)
    assert limit, "limit_req is not applied to /trigger."
    terms = limit.group(1).split()
    assert "zone=build_zone" in terms
    assert not any(term == "nodelay" or term.startswith("burst=") for term in terms), \
        "The /trigger limiter must not use burst or nodelay."


def test_nginx_running_and_header():
    start_submitted_nginx()
    req = urllib.request.Request("http://127.0.0.1:8080/trigger", method="HEAD")
    try:
        with urllib.request.urlopen(req, timeout=3) as response:
            headers = response.headers
    except urllib.error.HTTPError as e:
        headers = e.headers
    except urllib.error.URLError as e:
        pytest.fail(f"Could not connect to Nginx on port 8080: {e}")

    proxy_header = headers.get("X-Build-Proxy")
    assert proxy_header == "active", f"Expected X-Build-Proxy: active, got {proxy_header}"

    start_submitted_nginx()
    try:
        urllib.request.urlopen("http://127.0.0.1:8080/not-a-real-path", timeout=3)
        pytest.fail("Unexpected success for nonexistent path.")
    except urllib.error.HTTPError as e:
        assert e.headers.get("X-Build-Proxy") == "active", \
            "X-Build-Proxy must be added to error responses from the port 8080 server."


def test_nginx_rate_limiting():
    start_submitted_nginx()
    url = "http://127.0.0.1:8080/trigger"

    try:
        with urllib.request.urlopen(url, timeout=3) as response:
            body = response.read().decode()
            assert response.status == 200
            assert body == BACKEND_TOKEN, "The first /trigger request was not proxied to port 9999."
            assert response.headers.get("X-Build-Proxy") == "active"
    except urllib.error.HTTPError as e:
        pytest.fail(f"First request should reach the backend, but returned HTTP {e.code}.")
    except urllib.error.URLError as e:
        pytest.fail(f"Unexpected error reaching proxy: {e}")

    try:
        urllib.request.urlopen(url, timeout=3)
        pytest.fail("Second request was not rate limited (expected 503).")
    except urllib.error.HTTPError as e:
        assert e.code == 503, f"Expected HTTP 503 for rate limit, got {e.code}."
        assert e.headers.get("X-Build-Proxy") == "active", \
            "Rate-limit responses must include X-Build-Proxy: active."
    except urllib.error.URLError as e:
        pytest.fail(f"Unexpected error when testing rate limiting: {e}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
