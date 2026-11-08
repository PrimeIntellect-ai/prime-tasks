#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib
import importlib.metadata
import json
import os
import re
import secrets
import shutil
import signal
import socket
import subprocess
import time
import urllib.error
import urllib.request

import pytest


def stop_port_5000_listeners():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[3] == "0A" and int(fields[1].split(":")[1], 16) == 5000:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    victims = set()
    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(pid))
                    break
        except (FileNotFoundError, PermissionError):
            continue

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.5)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


@pytest.fixture(scope="session", autouse=True)
def run_installed_console_entry_point():
    command = shutil.which("run-math-api")
    assert command, "The installed run-math-api console command was not found on PATH."
    stop_port_5000_listeners()

    output = open("/tmp/run-math-api-verifier.log", "w+")
    proc = subprocess.Popen([command], stdout=output, stderr=subprocess.STDOUT)
    deadline = time.time() + 10
    ready = False
    while time.time() < deadline:
        if proc.poll() is not None:
            break
        try:
            with socket.create_connection(("127.0.0.1", 5000), timeout=0.25):
                ready = True
                break
        except OSError:
            time.sleep(0.1)

    if not ready:
        output.flush()
        output.seek(0)
        details = output.read()
        proc.terminate()
        pytest.fail(f"run-math-api did not start a server on 127.0.0.1:5000. Output: {details}")

    yield

    proc.terminate()
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
    output.close()


def post_json(path, payload):
    req = urllib.request.Request(
        "http://127.0.0.1:8080" + path,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=5) as response:
        assert response.status == 200, f"Expected HTTP 200 from {path}, got {response.status}"
        assert "application/json" in response.headers.get("Content-Type", "").lower()
        return json.loads(response.read().decode("utf-8"))


def test_setup_py_exists():
    """Verify that the setup.py file exists in the correct location."""
    setup_path = "/home/user/math_ops/setup.py"
    assert os.path.isfile(setup_path), f"Expected {setup_path} to exist."


def test_package_is_installed_with_console_entry_point_and_flask_dependency():
    matches = []
    for dist in importlib.metadata.distributions():
        for ep in dist.entry_points:
            if ep.group == "console_scripts" and ep.name == "run-math-api":
                matches.append((dist, ep))
    assert matches, "No installed distribution defines the run-math-api console entry point."

    project_root = os.path.realpath("/home/user/math_ops") + os.sep
    valid_project_entry = False
    has_flask_requirement = False
    for dist, ep in matches:
        module_name = ep.value.split(":", 1)[0].strip()
        try:
            module = importlib.import_module(module_name)
            module_file = os.path.realpath(module.__file__ or "")
        except Exception:
            continue
        if module_file.startswith(project_root):
            valid_project_entry = True
            requirements = dist.requires or []
            has_flask_requirement = any(
                re.match(r"(?i)^flask(?:\s|$|[<>=!~;\[])", requirement.strip())
                for requirement in requirements
            )
    assert valid_project_entry, "run-math-api is not an entry point for code in /home/user/math_ops."
    assert has_flask_requirement, "The installed math package does not declare Flask as a dependency."


def test_test_results_log():
    """Verify the contents of the test_results.log file."""
    log_path = "/home/user/test_results.log"
    assert os.path.isfile(log_path), f"Expected {log_path} to exist."

    with open(log_path, "r") as f:
        raw_lines = f.read().splitlines()
    assert len(raw_lines) == 3, f"Expected exactly 3 lines in {log_path}, found {len(raw_lines)}."
    assert all(line.strip() for line in raw_lines), "The log must not contain blank lines."
    lines = [line.strip() for line in raw_lines if line.strip()]

    try:
        res1 = json.loads(lines[0])
        res2 = json.loads(lines[1])
        res3 = json.loads(lines[2])
    except json.JSONDecodeError:
        assert False, "Failed to parse lines in test_results.log as JSON."

    assert res1.get("result") == [-2, 3, 5, 10], f"Sort result incorrect: {res1}"
    assert res2.get("result") == [1, 2, 5, 5, 8, 9], f"Merge result incorrect: {res2}"
    assert res3.get("result") == [1, 2, 5, 6], f"Diff result incorrect: {res3}"


def test_nginx_configuration_and_process():
    config_path = "/home/user/nginx.conf"
    assert os.path.isfile(config_path), f"Expected {config_path} to exist."
    checked = subprocess.run(
        ["nginx", "-t", "-c", config_path], capture_output=True, text=True
    )
    assert checked.returncode == 0, f"nginx configuration is invalid: {checked.stderr}"

    with open(config_path) as f:
        config = re.sub(r"#.*", "", f.read())
    for directive in (
        "pid", "error_log", "client_body_temp_path", "proxy_temp_path",
        "fastcgi_temp_path", "uwsgi_temp_path", "scgi_temp_path",
    ):
        match = re.search(rf"\b{directive}\s+([^;\s]+)", config)
        assert match, f"Missing required nginx directive: {directive}"
        path = match.group(1).strip("\"'")
        assert path.startswith("/home/user/"), f"{directive} must point inside /home/user/: {path}"
    assert re.search(r"\blisten\s+8080\s*;", config), "Nginx must listen on port 8080."
    assert re.search(r"\bproxy_pass\s+http://127\.0\.0\.1:5000\s*;", config), \
        "Nginx must proxy requests to http://127.0.0.1:5000."

    found_master = False
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            cmdline = open(f"/proc/{pid}/cmdline", "rb").read().replace(b"\0", b" ")
        except (FileNotFoundError, PermissionError):
            continue
        if b"nginx" in cmdline and b"/home/user/nginx.conf" in cmdline:
            found_master = True
            break
    assert found_master, "Nginx is not running with /home/user/nginx.conf."


def test_nginx_proxy_active():
    """Verify that Nginx is running on port 8080 and proxying to the Flask app."""
    body = post_json("/api/sort", {"data": []})
    assert "result" in body, "Expected 'result' key in response JSON."
    assert body["result"] == [], f"Expected empty array for empty sort, got {body['result']}"


def test_all_api_operations_with_runtime_generated_inputs():
    n = secrets.randbelow(1_000_000) + 10_000

    sort_data = [n + 7, -n, 0, n + 7, -3, n - 11]
    assert post_json("/api/sort", {"data": sort_data}) == {"result": sorted(sort_data)}

    list1 = [n + 4, -2, n + 4, 11]
    list2 = [n + 1, -2, 9, n - 8]
    assert post_json("/api/merge", {"list1": list1, "list2": list2}) == {
        "result": sorted(list1 + list2)
    }

    diff1 = [n, n + 1, 5, 5, -n]
    diff2 = [n + 1, n + 2, 7, -n]
    assert post_json("/api/diff", {"list1": diff1, "list2": diff2}) == {
        "result": sorted(set(diff1).symmetric_difference(diff2))
    }
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
