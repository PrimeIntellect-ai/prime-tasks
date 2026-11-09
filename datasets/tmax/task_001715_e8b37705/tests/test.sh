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
import importlib.util
import os
import random
import signal
import string
import subprocess
import time

import pytest
import rdflib
import requests

APP_DIR = "/app/backup_graph_server"
DATASET = "/home/user/backups.ttl"
URL = "http://127.0.0.1:9000/api/failed_backups"


def test_api_endpoint_failed_backups():
    """Preserve the original endpoint assertions against the shipped data."""
    url = URL + "?date=2023-10-15"

    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Could not connect to the API at http://127.0.0.1:9000. The service is either not running or not bound to 0.0.0.0.")
    except requests.exceptions.Timeout:
        pytest.fail("The request to the API timed out.")

    assert response.status_code == 200, f"Expected HTTP 200 OK, but got {response.status_code}. Response: {response.text}"

    content_type = response.headers.get("Content-Type", "")
    assert "application/json" in content_type, f"Expected Content-Type to be application/json, got {content_type}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Failed to parse response as JSON. Response body: {response.text}")

    assert isinstance(data, list), f"Expected the JSON response to be a list, got {type(data)}"

    expected_data = [{"serverName": "db-01", "jobId": "job-102"}]
    sorted_data = sorted(data, key=lambda x: (x.get("serverName", ""), x.get("jobId", "")))
    sorted_expected = sorted(expected_data, key=lambda x: (x.get("serverName", ""), x.get("jobId", "")))

    assert sorted_data == sorted_expected, (
        f"API returned incorrect data.\nExpected: {sorted_expected}\nActual: {sorted_data}\n"
        "If you see a Cartesian product (multiple servers for the same job), the SPARQL query join is still incorrect."
    )


def listener_inodes(port=9000):
    wanted = f"{port:04X}"
    found = set()
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(path) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        found.add(fields[9])
        except FileNotFoundError:
            pass
    return found


def kill_port(port=9000):
    inodes = listener_inodes(port)
    if not inodes:
        return
    victims = set()
    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(pid))
                    break
        except OSError:
            continue
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while listener_inodes(port) and time.time() < deadline:
        time.sleep(0.05)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def ipv4_wildcard_listener(port=9000):
    wanted = f"{port:04X}"
    with open("/proc/net/tcp") as f:
        next(f)
        for line in f:
            fields = line.split()
            address, found_port = fields[1].split(":")
            if found_port.upper() == wanted and fields[3] == "0A" and address == "00000000":
                return True
    return False


def wait_for_service(date, timeout=10):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.get(URL, params={"date": date}, timeout=1)
            if response.status_code == 200:
                return response
            last_error = f"HTTP {response.status_code}: {response.text}"
        except requests.RequestException as exc:
            last_error = str(exc)
        time.sleep(0.1)
    pytest.fail(f"Service launched through start.sh did not become ready: {last_error}")


def sorted_result(value):
    assert isinstance(value, list), f"Expected JSON list, got {type(value)}"
    assert all(isinstance(x, dict) for x in value), "Every result must be a JSON object"
    return sorted(value, key=lambda x: (x.get("serverName", ""), x.get("jobId", "")))


def test_query_start_script_and_dynamic_dataset():
    start_path = os.path.join(APP_DIR, "start.sh")
    query_path = os.path.join(APP_DIR, "queries.py")
    assert os.path.isfile(start_path), "start.sh is missing"
    assert os.access(start_path, os.X_OK), "start.sh must be executable"
    assert os.path.isfile(query_path), "queries.py is missing"

    token = "".join(random.SystemRandom().choices(string.ascii_lowercase + string.digits, k=12))
    date1 = f"2041-{random.randint(1, 12):02d}-{random.randint(1, 28):02d}"
    date2 = f"2042-{random.randint(1, 12):02d}-{random.randint(1, 28):02d}"
    server1, server2 = f"srv-a-{token}", f"srv-b-{token}"
    job1, job2, job3 = f"failed-a-{token}", f"failed-b-{token}", f"ok-{token}"

    ttl = f'''@prefix ex: <http://backup.local/vocab#> .
<http://dynamic.local/server/a-{token}> a ex:Server ; ex:name "{server1}" ;
    ex:hasJob <http://dynamic.local/job/a-{token}>, <http://dynamic.local/job/ok-{token}> .
<http://dynamic.local/server/b-{token}> a ex:Server ; ex:name "{server2}" ;
    ex:hasJob <http://dynamic.local/job/b-{token}> .
<http://dynamic.local/job/a-{token}> a ex:BackupJob ; ex:jobId "{job1}" ; ex:date "{date1}" ; ex:status "FAILED" .
<http://dynamic.local/job/b-{token}> a ex:BackupJob ; ex:jobId "{job2}" ; ex:date "{date2}" ; ex:status "FAILED" .
<http://dynamic.local/job/ok-{token}> a ex:BackupJob ; ex:jobId "{job3}" ; ex:date "{date1}" ; ex:status "SUCCESS" .
'''

    # Exercise the submitted query generator directly on unpredictable graph data.
    spec = importlib.util.spec_from_file_location("submitted_queries", query_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    graph = rdflib.Graph()
    graph.parse(data=ttl, format="turtle")
    rows1 = sorted((str(r.serverName), str(r.jobId)) for r in graph.query(module.get_failed_backups_query(date1)))
    rows2 = sorted((str(r.serverName), str(r.jobId)) for r in graph.query(module.get_failed_backups_query(date2)))
    assert rows1 == [(server1, job1)], f"Submitted SPARQL query produced incorrect joined rows: {rows1}"
    assert rows2 == [(server2, job2)], f"Submitted SPARQL query produced incorrect joined rows: {rows2}"

    original_data = open(DATASET, "rb").read()
    process = None
    try:
        kill_port()
        with open(DATASET, "w") as f:
            f.write(ttl)

        log = open("/tmp/backup_graph_start.log", "w")
        process = subprocess.Popen(
            ["/bin/bash", "./start.sh"],
            cwd=APP_DIR,
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )

        response1 = wait_for_service(date1)
        assert "application/json" in response1.headers.get("Content-Type", "")
        assert sorted_result(response1.json()) == [{"serverName": server1, "jobId": job1}]

        response2 = requests.get(URL, params={"date": date2}, timeout=5)
        assert response2.status_code == 200
        assert "application/json" in response2.headers.get("Content-Type", "")
        assert sorted_result(response2.json()) == [{"serverName": server2, "jobId": job2}]

        empty = requests.get(URL, params={"date": "2099-12-31"}, timeout=5)
        assert empty.status_code == 200
        assert sorted_result(empty.json()) == []

        assert ipv4_wildcard_listener(9000), "Service is not listening on the required IPv4 wildcard address 0.0.0.0:9000"
    finally:
        if process is not None and process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        kill_port()
        with open(DATASET, "wb") as f:
            f.write(original_data)
        # Leave the repaired service running with the original dataset.
        subprocess.Popen(
            ["/bin/bash", "./start.sh"],
            cwd=APP_DIR,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
