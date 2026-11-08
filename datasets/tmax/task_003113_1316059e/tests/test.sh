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
import json
import os
import re
import signal
import subprocess
import time
import uuid

import pytest
import requests

URL = "http://127.0.0.1:8080/api/v1/reports"
TOKEN = "SuperSecretDragon99"
PROJECT = "/app/vuln_dashboard"
DATA_PATH = "/app/data/raw_vulns.json"


def request(headers=None, timeout=5):
    try:
        return requests.get(URL, headers=headers, timeout=timeout)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the service at {URL}: {exc}")


def test_01_unauthorized_request():
    response = request()
    assert response.status_code == 401, (
        f"Expected HTTP 401 Unauthorized for missing token, got {response.status_code}"
    )

    response = request({"Authorization": "Bearer definitely-not-the-token"})
    assert response.status_code == 401, (
        f"Expected HTTP 401 Unauthorized for an incorrect token, got {response.status_code}"
    )


def test_02_authorized_request_original_data():
    response = request({"Authorization": f"Bearer {TOKEN}"})
    assert response.status_code == 200, (
        f"Expected HTTP 200 OK with valid token, got {response.status_code}"
    )

    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response body is not valid JSON")

    assert isinstance(data, list), "Expected response JSON to be a list"
    assert len(data) == 3, f"Expected 3 deduplicated vulnerabilities, got {len(data)}"

    assert data[0].get("cve_id") == "CVE-2023-0001", (
        f"Expected first item to be CVE-2023-0001, got {data[0].get('cve_id')}"
    )
    assert data[0].get("severity") == "CRITICAL", (
        f"Expected first item severity to be CRITICAL, got {data[0].get('severity')}"
    )

    assert data[1].get("cve_id") == "CVE-2024-1111", (
        f"Expected second item to be CVE-2024-1111, got {data[1].get('cve_id')}"
    )
    assert data[1].get("severity") == "HIGH", (
        f"Expected second item severity to be HIGH, got {data[1].get('severity')}"
    )

    assert data[2].get("cve_id") == "CVE-2023-0002", (
        f"Expected third item to be CVE-2023-0002, got {data[2].get('cve_id')}"
    )
    assert data[2].get("severity") == "MEDIUM", (
        f"Expected third item severity to be MEDIUM, got {data[2].get('severity')}"
    )

    endpoints = data[2].get("affected_endpoints", [])
    assert isinstance(endpoints, list), "affected_endpoints should be a list"
    assert len(endpoints) == 2, (
        f"Expected 2 affected endpoints for CVE-2023-0002, got {len(endpoints)}"
    )
    assert "/api/users" in endpoints
    assert "/api/profile" in endpoints


def test_03_rust_project_builds_with_required_static_linkage():
    build_rs = os.path.join(PROJECT, "build.rs")
    processor_rs = os.path.join(PROJECT, "src", "processor.rs")
    assert os.path.isfile(build_rs), "build.rs is missing"
    assert os.path.isfile(processor_rs), "src/processor.rs is missing"

    with open(processor_rs, "r", encoding="utf-8") as handle:
        processor_source = handle.read()
    initial_stub = "pub fn process() {\n    // TODO\n}\n"
    assert processor_source != initial_stub, "src/processor.rs is still the supplied stub"
    assert len(processor_source.strip()) > 35, "src/processor.rs does not contain an implementation"

    clean = subprocess.run(
        ["cargo", "clean"], cwd=PROJECT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert clean.returncode == 0, f"cargo clean failed:\n{clean.stdout}"

    built = subprocess.run(
        ["cargo", "build", "-vv"], cwd=PROJECT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120
    )
    assert built.returncode == 0, f"Rust project does not compile:\n{built.stdout}"

    output = built.stdout
    has_lib = (
        "rustc-link-lib=static=secutils" in output
        or "-l static=secutils" in output
        or "-lstatic=secutils" in output
    )
    has_search = (
        re.search(r"rustc-link-search(?:=native)?=[^\n]*lib", output) is not None
        or re.search(r"-L(?:native=)?[^\s]*lib", output) is not None
    )
    assert has_lib, "build.rs did not emit static linkage for secutils"
    assert has_search, "build.rs did not add the project's lib directory to the link search path"


def listener_pid():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r", encoding="ascii") as handle:
                lines = handle.readlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[1].upper().endswith(":1F90") and fields[3] == "0A":
                inodes.add(fields[9])

    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    return int(entry)
        except OSError:
            continue
    return None


def capture_process(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as handle:
        argv = [part.decode("utf-8", "surrogateescape") for part in handle.read().split(b"\0") if part]
    assert argv, "Could not determine the command used to run the service"
    cwd = os.readlink(f"/proc/{pid}/cwd")
    with open(f"/proc/{pid}/environ", "rb") as handle:
        entries = [part for part in handle.read().split(b"\0") if b"=" in part]
    env = {}
    for entry in entries:
        key, value = entry.split(b"=", 1)
        env[key.decode("utf-8", "surrogateescape")] = value.decode("utf-8", "surrogateescape")
    return argv, cwd, env


def stop_pid(pid):
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    for _ in range(30):
        if not os.path.exists(f"/proc/{pid}"):
            return
        time.sleep(0.1)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    time.sleep(0.2)


def start_service(command):
    argv, cwd, env = command
    proc = subprocess.Popen(
        argv, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True
    )
    deadline = time.time() + 15
    while time.time() < deadline:
        try:
            requests.get(URL, timeout=0.3)
            return proc
        except requests.exceptions.RequestException:
            if proc.poll() is not None:
                pytest.fail(f"Service command exited with status {proc.returncode} after restart")
            time.sleep(0.2)
    pytest.fail("Restarted service did not listen on 127.0.0.1:8080")


def assert_dynamic_response(data, expected):
    assert isinstance(data, list), "Expected response JSON to be a list"
    assert len(data) == len(expected), (
        f"Expected {len(expected)} dynamically processed vulnerabilities, got {len(data)}"
    )
    for index, (actual, wanted) in enumerate(zip(data, expected)):
        assert isinstance(actual, dict), f"Item {index} is not an object"
        assert actual.get("cve_id") == wanted["cve_id"], f"Incorrect cve_id at index {index}"
        assert actual.get("severity") == wanted["severity"], f"Incorrect severity at index {index}"
        endpoints = actual.get("affected_endpoints")
        assert isinstance(endpoints, list), f"affected_endpoints at index {index} is not a list"
        assert len(endpoints) == len(set(endpoints)), f"Endpoints at index {index} were not deduplicated"
        assert set(endpoints) == set(wanted["affected_endpoints"]), (
            f"Incorrect merged endpoints at index {index}: {endpoints}"
        )


def test_04_service_processes_changed_input_instead_of_fixed_constants():
    pid = listener_pid()
    assert pid is not None, "No process is listening on port 8080"
    command = capture_process(pid)

    with open(DATA_PATH, "r", encoding="utf-8") as handle:
        original_data = handle.read()

    marker = uuid.uuid4().hex[:10].upper()
    payload = [
        {"cve_id": f"CVE-{marker}-30", "severity": "LOW", "affected_endpoints": [f"/low/{marker}"]},
        {"cve_id": f"CVE-{marker}-20", "severity": "HIGH", "affected_endpoints": [f"/high/a/{marker}"]},
        {"cve_id": f"CVE-{marker}-10", "severity": "CRITICAL", "affected_endpoints": [f"/critical/{marker}"]},
        {"cve_id": f"CVE-{marker}-20", "severity": "HIGH", "affected_endpoints": [f"/high/b/{marker}", f"/high/a/{marker}"]},
        {"cve_id": f"CVE-{marker}-25", "severity": "HIGH", "affected_endpoints": [f"/high/c/{marker}"]},
        {"cve_id": f"CVE-{marker}-40", "severity": "MEDIUM", "affected_endpoints": [f"/medium/{marker}"]},
    ]
    expected = [
        {"cve_id": f"CVE-{marker}-10", "severity": "CRITICAL", "affected_endpoints": [f"/critical/{marker}"]},
        {"cve_id": f"CVE-{marker}-20", "severity": "HIGH", "affected_endpoints": [f"/high/a/{marker}", f"/high/b/{marker}"]},
        {"cve_id": f"CVE-{marker}-25", "severity": "HIGH", "affected_endpoints": [f"/high/c/{marker}"]},
        {"cve_id": f"CVE-{marker}-40", "severity": "MEDIUM", "affected_endpoints": [f"/medium/{marker}"]},
        {"cve_id": f"CVE-{marker}-30", "severity": "LOW", "affected_endpoints": [f"/low/{marker}"]},
    ]

    replacement_proc = None
    try:
        with open(DATA_PATH, "w", encoding="utf-8") as handle:
            json.dump(payload, handle)
            handle.flush()
            os.fsync(handle.fileno())

        stop_pid(pid)
        replacement_proc = start_service(command)

        response = request({"Authorization": f"Bearer {TOKEN}"})
        assert response.status_code == 200, (
            f"Expected HTTP 200 OK with valid token after restart, got {response.status_code}"
        )
        try:
            dynamic_data = response.json()
        except ValueError:
            pytest.fail("Dynamic response body is not valid JSON")
        assert_dynamic_response(dynamic_data, expected)

        assert request().status_code == 401
        assert request({"Authorization": "Bearer wrong"}).status_code == 401
    finally:
        with open(DATA_PATH, "w", encoding="utf-8") as handle:
            handle.write(original_data)
        current = listener_pid()
        if current is not None:
            stop_pid(current)
        try:
            start_service(command)
        except BaseException:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
