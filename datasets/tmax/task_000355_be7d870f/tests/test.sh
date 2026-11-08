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
import math
import os
import random
import signal
import socket
import sqlite3
import subprocess
import time
from decimal import Decimal
from pathlib import Path

import pytest
import requests

SERVICE = Path('/app/recovery_service.py')
DATABASE = Path('/app/sensor_data.db')
URL = 'http://127.0.0.1:8080/api/data'


def test_api_data_response():
    url = "http://127.0.0.1:8080/api/data"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the web service at {url}. Error: {e}")

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response, but failed to parse. Response text: {response.text}")

    assert "id" in data, "Response JSON is missing the 'id' key."
    assert "calibrated_value" in data, "Response JSON is missing the 'calibrated_value' key."

    assert data["id"] == 105, f"Expected id to be 105, got {data['id']}"

    expected_value = 42.1234
    actual_value = data["calibrated_value"]

    assert isinstance(actual_value, (int, float)), f"Expected 'calibrated_value' to be a number, got {type(actual_value)}"
    assert math.isclose(actual_value, expected_value, rel_tol=1e-5), f"Expected calibrated_value to be close to {expected_value}, got {actual_value}"


def listener_pids(port):
    inodes = set()
    wanted = f'{port:04X}'
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if fields[1].rsplit(':', 1)[-1].upper() == wanted and fields[3] == '0A':
                inodes.add(fields[9])

    pids = set()
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / 'fd').iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    pids.add(int(proc.name))
        except OSError:
            continue
    return pids


def stop_port(port):
    for pid in listener_pids(port):
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    deadline = time.time() + 3
    while time.time() < deadline:
        if not listener_pids(port):
            return
        time.sleep(0.05)
    for pid in listener_pids(port):
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    time.sleep(0.2)


def test_recovered_database_and_service_artifact_are_real_and_dynamic():
    assert SERVICE.is_file(), '/app/recovery_service.py is missing or is not a regular file'
    assert SERVICE.stat().st_size > 0, '/app/recovery_service.py is empty'
    assert DATABASE.is_file(), '/app/sensor_data.db is missing or is not a regular file'
    assert DATABASE.read_bytes()[:16] == b'SQLite format 3\x00', 'sensor_data.db is not a SQLite database'

    with sqlite3.connect(DATABASE, timeout=5) as conn:
        integrity = conn.execute('PRAGMA integrity_check').fetchone()[0]
        assert integrity == 'ok', f'SQLite integrity check failed: {integrity}'
        columns = {row[1] for row in conn.execute('PRAGMA table_info(sensor)')}
        assert {'id', 'value'} <= columns, 'Recovered database lacks the required sensor table columns'
        maximum = conn.execute('SELECT COALESCE(MAX(id), 0) FROM sensor').fetchone()[0]
        test_id = int(maximum) + random.SystemRandom().randint(1000, 1000000)
        raw_decimal = Decimal(random.SystemRandom().randint(-250000000, 250000000)) / Decimal(1000000)
        raw_value = float(raw_decimal)
        conn.execute('INSERT INTO sensor(id, value) VALUES (?, ?)', (test_id, raw_value))
        conn.commit()

    expected = float(Decimal(str(raw_value)) + Decimal('0.0001') * Decimal(10000))
    stop_port(8080)
    log = open('/tmp/recovery_service_verifier.log', 'w')
    proc = None
    try:
        proc = subprocess.Popen(
            ['python3', str(SERVICE)],
            cwd='/app',
            stdout=log,
            stderr=subprocess.STDOUT,
        )

        deadline = time.time() + 10
        response = None
        last_error = None
        while time.time() < deadline:
            try:
                candidate = requests.get(URL, timeout=1)
                if candidate.status_code:
                    response = candidate
                    break
            except requests.exceptions.RequestException as exc:
                last_error = exc
            time.sleep(0.1)

        if response is None:
            log.flush()
            details = Path('/tmp/recovery_service_verifier.log').read_text(errors='replace')
            pytest.fail(f'Executing /app/recovery_service.py did not start the service: {last_error}\n{details}')

        assert response.status_code == 200, f'Expected HTTP 200 from executed service, got {response.status_code}'
        try:
            data = response.json()
        except ValueError:
            pytest.fail(f'Executed service returned non-JSON data: {response.text}')

        assert 'id' in data, "Response JSON is missing the 'id' key."
        assert 'calibrated_value' in data, "Response JSON is missing the 'calibrated_value' key."
        assert data['id'] == test_id, f"Service did not return the dynamically inserted highest ID: {data.get('id')}"
        actual = data['calibrated_value']
        assert isinstance(actual, (int, float)), f"Expected numeric calibrated_value, got {type(actual)}"
        assert math.isclose(actual, expected, rel_tol=1e-9, abs_tol=1e-8), \
            f'Expected stable 10,000-step calibration result {expected}, got {actual}'
    finally:
        if proc is not None and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
        stop_port(8080)
        log.close()
        with sqlite3.connect(DATABASE, timeout=5) as conn:
            conn.execute('DELETE FROM sensor WHERE id = ?', (test_id,))
            conn.commit()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
