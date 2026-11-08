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
import signal
import socket
import sqlite3
import subprocess
import sys
import time
import uuid

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
API_KEY = "X88-912-SYS-AUTH"
DB_PATH = "/app/data/metrics_recovered.db"
DYNAMIC_HOST = "verifier-" + uuid.uuid4().hex
DYNAMIC_UPTIME = 91.0 + (int(uuid.uuid4().hex[:6], 16) % 8000) / 1000.0


def get(path, **kwargs):
    try:
        return requests.get(f"{BASE_URL}{path}", timeout=2, **kwargs)
    except requests.exceptions.ConnectionError:
        pytest.fail(f"Failed to connect to the API server at {BASE_URL}. Is it running?")
    except requests.exceptions.Timeout:
        pytest.fail(f"Request to {BASE_URL}{path} timed out.")
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Request failed: {exc}")


def assert_health_requests(count=5):
    for i in range(1, count + 1):
        response = get("/health")
        assert response.status_code == 200, (
            f"Expected status code 200 on request {i}, got {response.status_code}"
        )
        try:
            data = response.json()
        except ValueError:
            pytest.fail(f"Expected JSON response from /health, got: {response.text}")
        assert data == {"status": "ok"}, (
            f"Expected {{'status': 'ok'}} on request {i}, got {data}"
        )


def assert_metric(hostname, expected):
    response = get(
        f"/metrics/{hostname}",
        headers={"Authorization": f"Bearer {API_KEY}"},
    )
    assert response.status_code == 200, (
        f"Expected status code 200 for authorized request, got "
        f"{response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response from /metrics/{hostname}, got: {response.text}")
    assert data.get("hostname") == hostname, (
        f"Expected hostname {hostname!r}, got {data.get('hostname')!r}"
    )
    uptime = data.get("uptime")
    assert uptime is not None, "Response missing 'uptime' field."
    assert abs(float(uptime) - expected) < 0.001, (
        f"Expected uptime ~{expected}, got {uptime}"
    )


def listener_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as handle:
                next(handle, None)
                for line in handle:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    result = set()
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    result.add(int(name))
                    break
        except OSError:
            continue
    return result


def stop_port_8080():
    pids = listener_pids(8080)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listener_pids(8080):
        time.sleep(0.05)
    for pid in listener_pids(8080):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids(8080):
        time.sleep(0.05)
    assert not listener_pids(8080), "Could not stop the existing listener on port 8080"


def test_recovered_db_exists_and_contents():
    assert os.path.isfile(DB_PATH), f"Expected recovered database at {DB_PATH}."
    assert os.path.getsize(DB_PATH) > 0, "Recovered database is empty."

    try:
        conn = sqlite3.connect(f"file:{DB_PATH}?mode=rw", uri=True)
        integrity = conn.execute("PRAGMA integrity_check").fetchall()
        assert integrity == [("ok",)], f"SQLite integrity check failed: {integrity}"

        schema = conn.execute("PRAGMA table_info(uptime)").fetchall()
        assert [row[1] for row in schema] == ["hostname", "uptime_percentage"], (
            f"Unexpected uptime schema: {schema}"
        )
        assert schema[0][2].upper() == "TEXT", f"hostname must be TEXT: {schema}"
        assert schema[1][2].upper() == "REAL", f"uptime_percentage must be REAL: {schema}"

        rows = conn.execute(
            "SELECT hostname, uptime_percentage FROM uptime ORDER BY hostname"
        ).fetchall()
        assert len(rows) == 2, f"Expected exactly two recovered uptime rows, got {rows}"
        recovered = {host: float(value) for host, value in rows}
        assert set(recovered) == {"db-node-01", "cache-node-02"}, (
            f"Unexpected recovered hostnames: {recovered}"
        )
        assert abs(recovered["db-node-01"] - 99.98) < 0.001
        assert abs(recovered["cache-node-02"] - 99.50) < 0.001
    finally:
        if 'conn' in locals():
            conn.close()


def test_health_endpoint_and_bug_fix():
    assert_health_requests(5)


def test_metrics_unauthorized():
    response = get("/metrics/db-node-01")
    assert response.status_code in (401, 403), (
        f"Expected status code 401 or 403 for unauthorized request, got {response.status_code}"
    )

    response = get(
        "/metrics/db-node-01",
        headers={"Authorization": "Bearer definitely-not-the-admin-token"},
    )
    assert response.status_code in (401, 403), (
        "A nonempty but incorrect bearer token must not be accepted"
    )


def test_metrics_authorized_for_all_recovered_rows():
    assert_metric("db-node-01", 99.98)
    assert_metric("cache-node-02", 99.50)


def test_service_reads_the_recovered_database():
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute(
            "INSERT INTO uptime(hostname, uptime_percentage) VALUES (?, ?)",
            (DYNAMIC_HOST, DYNAMIC_UPTIME),
        )
        conn.commit()
    finally:
        conn.close()

    assert_metric(DYNAMIC_HOST, DYNAMIC_UPTIME)


def test_fixed_api_server_source_itself_runs_correctly():
    assert os.path.isfile("/app/api_server.py"), "Expected /app/api_server.py to exist"
    stop_port_8080()

    env = os.environ.copy()
    env["API_KEY"] = API_KEY
    process = subprocess.Popen(
        [sys.executable, "/app/api_server.py"],
        cwd="/app",
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    deadline = time.time() + 5
    while time.time() < deadline:
        if process.poll() is not None:
            pytest.fail(f"/app/api_server.py exited with status {process.returncode}")
        try:
            response = requests.get(f"{BASE_URL}/health", timeout=0.25)
            if response.status_code == 200:
                break
        except requests.exceptions.RequestException:
            pass
        time.sleep(0.05)
    else:
        process.terminate()
        pytest.fail("/app/api_server.py did not start listening on port 8080")

    # The readiness request above counts as a request, so this also crosses the
    # original fourth-request crash point while executing the submitted source.
    assert_health_requests(5)
    assert_metric("db-node-01", 99.98)
    assert_metric("cache-node-02", 99.50)
    assert_metric(DYNAMIC_HOST, DYNAMIC_UPTIME)

    wrong = get(
        "/metrics/db-node-01",
        headers={"Authorization": "Bearer wrong-but-nonempty"},
    )
    assert wrong.status_code in (401, 403)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
