#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import socket
import sqlite3
import time
import urllib.error
import urllib.parse
import urllib.request

import pytest

DB_PATH = "/home/user/app/data/recovered_cache.db"
ENGINE_PATH = "/home/user/app/engine/engine"
GATEWAY_PATH = "/home/user/app/gateway/app.py"


def listening_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except OSError:
            pass

    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except OSError:
            continue
    return pids


def api_get(id_value, timeout=2):
    encoded = urllib.parse.quote(str(id_value), safe="")
    response = urllib.request.urlopen(
        f"http://localhost:8000/price?id={encoded}", timeout=timeout
    )
    return response.getcode(), response.read().decode().strip()


def engine_get(value, timeout=2):
    with socket.create_connection(("127.0.0.1", 8001), timeout=timeout) as sock:
        sock.settimeout(timeout)
        sock.sendall(str(value).encode())
        sock.shutdown(socket.SHUT_WR)
        chunks = []
        while True:
            data = sock.recv(1024)
            if not data:
                break
            chunks.append(data)
    return b"".join(chunks).decode().strip()


def test_recovered_database_exists_and_valid():
    assert os.path.isfile(DB_PATH), f"Recovered database not found at {DB_PATH}"

    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("PRAGMA integrity_check;")
        result = cursor.fetchone()
        assert result and result[0] == "ok", "Recovered database failed integrity check."

        cursor.execute("SELECT id, price FROM cache ORDER BY rowid")
        rows = cursor.fetchall()
        conn.close()
    except sqlite3.Error as e:
        pytest.fail(f"Failed to open or validate recovered database: {e}")

    assert len(rows) == 1, f"Recovered cache has unexpected contents: {rows!r}"
    assert rows[0][0] == "test", f"Recovered cache is missing id 'test': {rows!r}"
    assert math.isclose(float(rows[0][1]), 99.99, rel_tol=0, abs_tol=1e-12), \
        f"Recovered price is incorrect: {rows[0][1]!r}"


def test_services_are_running_and_are_required_artifacts():
    assert os.path.isfile(ENGINE_PATH), f"Compiled engine not found at {ENGINE_PATH}"
    assert os.access(ENGINE_PATH, os.X_OK), "Compiled engine is not executable"
    with open(ENGINE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Engine is not a compiled ELF executable"

    flask_up = False
    for _ in range(5):
        try:
            urllib.request.urlopen("http://localhost:8000/", timeout=1)
            flask_up = True
            break
        except urllib.error.HTTPError:
            flask_up = True
            break
        except urllib.error.URLError:
            time.sleep(1)
    assert flask_up, "Flask API Gateway is not responding on port 8000."

    engine_pids = listening_pids(8001)
    assert engine_pids, "No service is listening on port 8001."
    for pid in engine_pids:
        try:
            assert os.path.samefile(ENGINE_PATH, f"/proc/{pid}/exe"), \
                f"Port 8001 is owned by pid {pid}, not the compiled engine"
        except OSError as e:
            pytest.fail(f"Could not validate the port 8001 process: {e}")

    gateway_pids = listening_pids(8000)
    assert gateway_pids, "No service is listening on port 8000."
    for pid in gateway_pids:
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                argv = [part.decode(errors="replace") for part in f.read().split(b"\0") if part]
        except OSError as e:
            pytest.fail(f"Could not validate the port 8000 process: {e}")
        assert GATEWAY_PATH in argv, \
            f"Port 8000 is not running the required gateway: {argv!r}"


def test_gateway_serves_recovered_cache():
    status, body = api_get("test")
    assert status == 200
    assert math.isclose(float(body), 99.99, rel_tol=0, abs_tol=1e-12), \
        f"Gateway did not return recovered cached data: {body!r}"


def test_pricing_accuracy_mse():
    # Preserve the original direct availability assertion for id=1, but also
    # validate unpredictable requests against a verifier-derived reference.
    status, first_body = api_get("1")
    assert status == 200, "API did not return 200 OK for /price?id=1"
    assert math.isfinite(float(first_body))

    rng = random.SystemRandom()
    values = [-3.0, -1.0, -0.25, 0.0, 0.25, 1.0, 3.0]
    values.extend(rng.uniform(-3.0, 3.0) for _ in range(13))

    api_errors = []
    engine_errors = []
    for value in values:
        request_value = format(value, ".12f")
        expected = math.sin(float(request_value))

        status, api_body = api_get(request_value)
        assert status == 200
        try:
            api_value = float(api_body)
        except ValueError:
            pytest.fail(f"API returned a non-numeric result for {request_value}: {api_body!r}")
        assert math.isfinite(api_value)
        api_errors.append((api_value - expected) ** 2)

        engine_body = engine_get(request_value)
        try:
            engine_value = float(engine_body)
        except ValueError:
            pytest.fail(f"Engine returned a non-numeric result for {request_value}: {engine_body!r}")
        assert math.isfinite(engine_value)
        engine_errors.append((engine_value - expected) ** 2)

    api_mse = sum(api_errors) / len(api_errors)
    engine_mse = sum(engine_errors) / len(engine_errors)
    threshold = 1e-8
    assert api_mse < threshold, f"API MSE {api_mse} is not below {threshold}"
    assert engine_mse < threshold, f"Engine MSE {engine_mse} is not below {threshold}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
