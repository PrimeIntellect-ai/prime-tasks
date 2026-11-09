#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import os
import re
import subprocess
import time
import uuid
from collections import Counter

import pytest
import requests

COMPOSE_FILE = "/app/vendored_usermgmt/docker-compose.yml"
APP_SOURCE = "/app/vendored_usermgmt/api/main.py"
BASE_URL = "http://localhost:8000"


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, capture_output=True, text=True, **kwargs)


def compose(*args):
    return run(["docker", "compose", "-f", COMPOSE_FILE, *args])


def container_id(service):
    cid = compose("ps", "-q", service).stdout.strip()
    assert cid, f"Docker Compose service {service!r} is not running"
    return cid


def inspect_container(cid):
    return json.loads(run(["docker", "inspect", cid]).stdout)[0]


def compose_environment(service):
    raw = compose("config", "--format", "json").stdout
    config = json.loads(raw)
    env = config["services"][service].get("environment", {})
    if isinstance(env, list):
        result = {}
        for item in env:
            key, _, value = item.partition("=")
            result[key] = value
        return result
    return env


def db_query(sql):
    db_cid = container_id("postgres_db")
    db_env = compose_environment("postgres_db")
    user = db_env.get("POSTGRES_USER", "postgres")
    database = db_env.get("POSTGRES_DB", user)
    return run([
        "docker", "exec", db_cid, "psql", "-X", "-U", user, "-d", database,
        "-v", "ON_ERROR_STOP=1", "-Atc", sql,
    ]).stdout


def docker_logs(cid):
    result = subprocess.run(["docker", "logs", cid], capture_output=True, text=True, check=True)
    return result.stdout + result.stderr


def expected_legacy_rows():
    pattern = re.compile(
        r"^\[USER-MIGRATE\] username: (.*?) \| email: (.*?) \| role: (.*?)$"
    )
    rows = []
    with open("/home/user/legacy_users.txt", "r", encoding="utf-8") as f:
        for raw_line in f:
            match = pattern.fullmatch(raw_line.rstrip("\r\n"))
            if match:
                rows.append(list(match.groups()))
    return rows


def monitor_processes():
    found = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/cmdline", "rb") as f:
                argv = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
            if "/home/user/health_monitor.sh" in argv:
                found.append((int(name), argv))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return found


def test_01_compose_configuration_and_intended_api():
    assert os.path.isfile(COMPOSE_FILE), f"Missing {COMPOSE_FILE}"
    config = json.loads(compose("config", "--format", "json").stdout)
    services = config.get("services", {})
    assert "api" in services and "postgres_db" in services, "Compose must define api and postgres_db"

    api = services["api"]
    postgres = services["postgres_db"]
    api_env = compose_environment("api")
    db_env = compose_environment("postgres_db")
    assert api_env.get("DB_HOST") == "postgres_db", "API DB_HOST must address the postgres_db service"
    assert api_env.get("DB_USER") == db_env.get("POSTGRES_USER")
    assert api_env.get("DB_PASSWORD") == db_env.get("POSTGRES_PASSWORD")
    assert api_env.get("DB_NAME") == db_env.get("POSTGRES_DB")

    api_networks = set((api.get("networks") or {}).keys())
    db_networks = set((postgres.get("networks") or {}).keys())
    assert api_networks & db_networks, "API and PostgreSQL must share a Docker network"
    assert api.get("build"), "The api service must build the vendored API"
    assert str(postgres.get("image", "")).startswith("postgres:13"), "postgres_db must use PostgreSQL 13"

    api_cid = container_id("api")
    db_cid = container_id("postgres_db")
    api_inspect = inspect_container(api_cid)
    db_inspect = inspect_container(db_cid)
    assert api_inspect["State"]["Running"] and db_inspect["State"]["Running"]
    assert set(api_inspect["NetworkSettings"]["Networks"]) & set(db_inspect["NetworkSettings"]["Networks"])

    bindings = api_inspect["HostConfig"].get("PortBindings", {}).get("8000/tcp", [])
    assert any(binding.get("HostPort") == "8000" for binding in bindings), "Compose API must publish port 8000"
    command = " ".join((api_inspect["Config"].get("Entrypoint") or []) + (api_inspect["Config"].get("Cmd") or []))
    assert "uvicorn" in command and "main:app" in command, "The running API container must launch the vendored FastAPI app"

    assert os.path.isfile(APP_SOURCE), f"Missing vendored API source at {APP_SOURCE}"
    with open(APP_SOURCE, "rb") as f:
        host_source_bytes = f.read()
    container_source_bytes = subprocess.run(
        ["docker", "exec", api_cid, "cat", "/app/main.py"], check=True, capture_output=True
    ).stdout
    assert container_source_bytes == host_source_bytes, "Running container is not using the vendored API source"

    source = host_source_bytes.decode("utf-8")
    tree = ast.parse(source)
    create_user = next(
        (node for node in tree.body if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == "create_user"),
        None,
    )
    assert create_user is not None, "Vendored create_user implementation is missing"
    create_text = ast.get_source_segment(source, create_user) or ""
    assert "asyncpg.connect" in create_text
    assert "INSERT INTO users" in create_text
    sleep_values = []
    for node in ast.walk(create_user):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "sleep" and node.args:
            try:
                sleep_values.append(float(ast.literal_eval(node.args[0])))
            except Exception:
                pass
    assert any(value >= 0.015 for value in sleep_values), "Vendored API's simulated request latency was removed"


def test_02_api_is_running_and_uses_postgres():
    """Ensure the intended API is healthy and its user endpoints operate on PostgreSQL."""
    try:
        res = requests.get(f"{BASE_URL}/health", timeout=5)
        assert res.status_code == 200, f"API health endpoint returned {res.status_code} instead of 200"
        assert res.json() == {"status": "ok"}
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API on {BASE_URL}/health: {e}")

    marker = "verifier_" + uuid.uuid4().hex
    payload = {"username": marker, "email": marker + "@example.com", "role": "user"}
    post_res = requests.post(f"{BASE_URL}/users", json=payload, timeout=5)
    assert post_res.status_code == 200, f"Vendored POST /users failed: {post_res.text}"
    count = int(db_query(f"SELECT COUNT(*) FROM users WHERE username = '{marker}';").strip())
    assert count == 1, "POST /users did not insert its payload into the Compose PostgreSQL database"

    del_res = requests.delete(f"{BASE_URL}/users", timeout=5)
    del_res.raise_for_status()
    assert int(db_query("SELECT COUNT(*) FROM users;").strip()) == 0, "DELETE /users did not clear PostgreSQL"


def test_03_health_monitor_script():
    """Ensure the monitor is a running shell script that appends fresh, correctly paced health records."""
    script_path = "/home/user/health_monitor.sh"
    log_path = "/home/user/api_health.log"
    assert os.path.isfile(script_path), f"Missing shell script at {script_path}"
    with open(script_path, "r", encoding="utf-8") as f:
        script = f.read()
    assert BASE_URL + "/health" in script, "Monitor does not check the required health endpoint"
    assert log_path in script, "Monitor does not append to the required log"
    assert re.search(r"\bsleep\s+2(?:\s|;|$)", script), "Monitor must check every 2 seconds"
    assert monitor_processes(), "health_monitor.sh is not running in the background"

    assert os.path.isfile(log_path), f"Missing log file at {log_path}. Ensure the script is running in the background."
    with open(log_path, "rb") as f:
        f.seek(0, os.SEEK_END)
        offset = f.tell()
    time.sleep(4.8)
    with open(log_path, "rb") as f:
        f.seek(offset)
        fresh = f.read().decode("utf-8", errors="strict")

    lines = [line for line in fresh.splitlines() if line]
    assert len(lines) >= 2, "The running monitor did not append at least two records within about four seconds"
    parsed = []
    for line in lines:
        match = re.fullmatch(r"\[(OK|FAIL)\] ([0-9]+)", line)
        assert match, f"Invalid health log record format: {line!r}"
        parsed.append((match.group(1), int(match.group(2))))
    assert any(status == "OK" for status, _ in parsed), f"Log {log_path} does not contain any fresh '[OK]' entries"
    unique_times = sorted(set(timestamp for _, timestamp in parsed))
    assert any(1 <= b - a <= 3 for a, b in zip(unique_times, unique_times[1:])), "Fresh monitor entries are not approximately 2 seconds apart"

    with open(log_path, "r", encoding="utf-8") as f:
        content = f.read()
    assert "[OK]" in content, f"Log {log_path} does not contain any '[OK]' entries. Is the API healthy and the script running?"


def test_04_clean_users_csv():
    """Ensure every CSV data row is exactly derived from the valid legacy records."""
    csv_path = "/home/user/clean_users.csv"
    assert os.path.isfile(csv_path), f"Missing extracted CSV file at {csv_path}"
    with open(csv_path, "r", encoding="utf-8", newline="") as f:
        rows = list(csv.reader(f))

    assert len(rows) == 5001, f"Expected exactly 5001 rows (1 header + 5000 data rows), but got {len(rows)}"
    header = [c.strip() for c in rows[0]]
    assert header == ["username", "email", "role"], f"Incorrect CSV header. Expected ['username', 'email', 'role'], got {header}"

    expected = expected_legacy_rows()
    assert len(expected) == 5000, "Legacy fixture does not contain the expected 5000 records"
    assert rows[1:] == expected, "CSV rows do not exactly match the valid records in legacy_users.txt"


def test_05_import_users_performance_and_database_contents():
    """Execute the importer, require 5000 HTTP posts, and verify exact PostgreSQL contents under 12 seconds."""
    script_path = "/home/user/import_users.py"
    assert os.path.isfile(script_path), f"Missing Python import script at {script_path}"

    try:
        del_res = requests.delete(f"{BASE_URL}/users", timeout=5)
        del_res.raise_for_status()
    except Exception as e:
        pytest.fail(f"Failed to clear the database prior to testing import: {e}")
    assert int(db_query("SELECT COUNT(*) FROM users;").strip()) == 0

    api_cid = container_id("api")
    before_posts = docker_logs(api_cid).count('"POST /users HTTP/1.1"')

    start = time.monotonic()
    res = subprocess.run(["python3", script_path], capture_output=True, text=True, timeout=30)
    duration = time.monotonic() - start
    assert res.returncode == 0, f"Import script failed with exit code {res.returncode}.\nstdout: {res.stdout}\nstderr: {res.stderr}"

    after_posts = docker_logs(api_cid).count('"POST /users HTTP/1.1"')
    assert after_posts - before_posts == 5000, f"Importer made {after_posts - before_posts} successful POST /users requests instead of 5000"

    try:
        count_response = requests.get(f"{BASE_URL}/users/count", timeout=5)
        count_response.raise_for_status()
        count_res = count_response.json()
    except Exception as e:
        pytest.fail(f"Failed to fetch user count from API after import: {e}")
    actual_count = count_res.get("count")
    assert actual_count == 5000, f"Expected 5000 users in the database, but got {actual_count}"

    raw_rows = db_query("COPY (SELECT username, email, role FROM users) TO STDOUT WITH (FORMAT csv);")
    actual_rows = list(csv.reader(raw_rows.splitlines()))
    expected_rows = expected_legacy_rows()
    assert len(actual_rows) == 5000
    assert Counter(map(tuple, actual_rows)) == Counter(map(tuple, expected_rows)), "PostgreSQL rows do not exactly match the extracted legacy users"

    assert duration <= 12.0, f"Execution too slow: {duration:.2f} seconds (Threshold: <= 12.0s). Ensure you are using asynchronous I/O or a thread pool."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
