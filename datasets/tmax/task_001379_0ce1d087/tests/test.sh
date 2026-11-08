#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import secrets
import shutil
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

import pytest

WORKSPACE = "/home/user/workspace"
EXPECTED_WEIGHTS = {
    "utils": 10.0,
    "db": 25.0,
    "auth": 27.5,
    "api": 48.75,
}


def get_json(url, timeout=5):
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=timeout) as response:
        assert response.status == 200, f"Expected HTTP 200 from {url}, got {response.status}"
        content_type = response.headers.get("Content-Type", "")
        assert "application/json" in content_type, f"Expected application/json from {url}, got {content_type}"
        return json.loads(response.read().decode("utf-8"))


def listener_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r", encoding="ascii") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    pids = set()
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
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except OSError:
            pass
    return pids


def kill_port(port):
    for pid in listener_pids(port):
        try:
            os.kill(pid, 15)
        except (ProcessLookupError, PermissionError):
            pass
    deadline = time.time() + 2
    while listener_pids(port) and time.time() < deadline:
        time.sleep(0.05)
    for pid in listener_pids(port):
        try:
            os.kill(pid, 9)
        except (ProcessLookupError, PermissionError):
            pass


def wait_for_json(url, expected, timeout=10):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            data = get_json(url, timeout=1)
            if data == expected:
                return data
            last_error = AssertionError(f"Got {data}, expected {expected}")
        except Exception as exc:
            last_error = exc
        time.sleep(0.15)
    raise AssertionError(f"Did not receive expected JSON from {url}: {last_error}")


def test_migration_order_json():
    filepath = "/home/user/workspace/migration_order.json"
    assert os.path.isfile(filepath), f"File {filepath} is missing. The analyzer script must serialize results to this file."
    with open(filepath, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {filepath} does not contain valid JSON.")
    assert data == EXPECTED_WEIGHTS, f"The computed weights in {filepath} do not match the expected values. Got: {data}, Expected: {EXPECTED_WEIGHTS}"


def test_nginx_proxy_routing():
    url = "http://127.0.0.1:8080/api/weights"
    try:
        data = get_json(url)
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to Nginx proxy at {url}. Is Nginx running and configured properly? Error: {e}")
    assert data == EXPECTED_WEIGHTS, f"Proxy response data does not match expected weights. Got: {data}"


def test_pytest_log_exists_and_passed():
    log_path = "/home/user/workspace/test_results.log"
    assert os.path.isfile(log_path), f"Test log file {log_path} is missing."
    with open(log_path, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read().lower()
    assert "passed" in content, f"The test log at {log_path} does not indicate passing tests. Ensure 'pytest' was run and logged."


def test_analyzer_script_exists():
    assert os.path.isfile("/home/user/workspace/analyzer.py"), "The script /home/user/workspace/analyzer.py is missing."


def test_test_analyzer_script_exists():
    assert os.path.isfile("/home/user/workspace/test_analyzer.py"), "The unit test file /home/user/workspace/test_analyzer.py is missing."


def test_nginx_is_really_running_with_local_configuration():
    conf = os.path.join(WORKSPACE, "nginx.conf")
    assert os.path.isfile(conf), "The required nginx.conf is missing."
    text = open(conf, "r", encoding="utf-8", errors="ignore").read()
    compact = re.sub(r"\s+", " ", text)
    assert re.search(r"listen\s+127\.0\.0\.1:8080\s*;", compact), "nginx.conf does not listen on 127.0.0.1:8080"
    assert re.search(r"location\s+(?:=\s*)?/api/weights\s*\{", compact), "nginx.conf lacks the /api/weights location"
    assert re.search(r"proxy_pass\s+http://127\.0\.0\.1:8000/weights\s*;", compact), "nginx.conf does not proxy to the required backend URL"
    assert "/home/user/workspace/nginx" in text, "nginx.conf does not place runtime files under the workspace nginx directory"

    pids = listener_pids(8080)
    assert pids, "No process is listening on port 8080"
    identities = []
    for pid in pids:
        try:
            exe = os.path.basename(os.readlink(f"/proc/{pid}/exe"))
        except OSError:
            exe = ""
        try:
            cmd = open(f"/proc/{pid}/cmdline", "rb").read().replace(b"\0", b" ").decode(errors="ignore")
        except OSError:
            cmd = ""
        identities.append((exe + " " + cmd).lower())
    assert any("nginx" in identity for identity in identities), f"Port 8080 is not owned by Nginx: {identities}"


def test_submitted_unit_tests_are_real_and_pass():
    path = os.path.join(WORKSPACE, "test_analyzer.py")
    source = open(path, "r", encoding="utf-8").read()
    tree = ast.parse(source, filename=path)
    imports_analyzer = any(
        (isinstance(node, ast.Import) and any(alias.name == "analyzer" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "analyzer")
        for node in ast.walk(tree)
    )
    assert imports_analyzer, "test_analyzer.py must import computation logic from analyzer.py"

    env = os.environ.copy()
    env["PYTHONPATH"] = WORKSPACE + os.pathsep + env.get("PYTHONPATH", "")
    collected = subprocess.run(
        ["python3", "-m", "pytest", "--collect-only", "-q", path],
        cwd=WORKSPACE, env=env, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=20,
    )
    assert collected.returncode == 0, f"Could not collect submitted tests:\n{collected.stdout}"
    test_ids = [line for line in collected.stdout.splitlines() if "::" in line and not line.lstrip().startswith("<")]
    assert len(test_ids) >= 2, f"Expected at least two collected tests, found {len(test_ids)}:\n{collected.stdout}"

    run = subprocess.run(
        ["python3", "-m", "pytest", "-q", path], cwd=WORKSPACE,
        env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert run.returncode == 0, f"Submitted unit tests do not pass:\n{run.stdout}"
    match = re.search(r"(\d+)\s+passed", run.stdout)
    assert match and int(match.group(1)) >= 2, f"Pytest did not report at least two passing tests:\n{run.stdout}"


def test_analyzer_computes_unseen_dag_and_serves_it_directly_and_through_nginx():
    projects = os.path.join(WORKSPACE, "projects")
    migration = os.path.join(WORKSPACE, "migration_order.json")
    backup_root = tempfile.mkdtemp(prefix="verifier-backup-")
    backup_projects = os.path.join(backup_root, "projects")
    shutil.copytree(projects, backup_projects)
    backup_migration = os.path.join(backup_root, "migration_order.json")
    if os.path.isfile(migration):
        shutil.copy2(migration, backup_migration)

    suffix = secrets.token_hex(5)
    costs = [secrets.randbelow(31) + 7 for _ in range(5)]
    names = [f"verify_{suffix}_{i}" for i in range(5)]
    records = [
        {"module": names[0], "cost": costs[0], "dependencies": []},
        {"module": names[1], "cost": costs[1], "dependencies": [names[0]]},
        {"module": names[2], "cost": costs[2], "dependencies": [names[0], names[1]]},
        {"module": names[3], "cost": costs[3], "dependencies": [names[1]]},
        {"module": names[4], "cost": costs[4], "dependencies": [names[2], names[3]]},
    ]
    expected = {}
    for record in records:
        expected[record["module"]] = float(record["cost"] + sum(0.5 * expected[d] for d in record["dependencies"]))

    process = None
    try:
        kill_port(8000)
        shutil.rmtree(projects)
        os.makedirs(projects)
        for index, record in enumerate(reversed(records)):
            with open(os.path.join(projects, f"input_{index}_{suffix}.json"), "w") as f:
                json.dump(record, f)
        if os.path.exists(migration):
            os.unlink(migration)

        process = subprocess.Popen(
            ["python3", os.path.join(WORKSPACE, "analyzer.py")], cwd=WORKSPACE,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        wait_for_json("http://127.0.0.1:8000/weights", expected)

        assert os.path.isfile(migration), "Executing analyzer.py did not create migration_order.json"
        with open(migration, "r") as f:
            disk_data = json.load(f)
        assert disk_data == expected, f"Analyzer produced wrong weights for an unseen DAG: {disk_data} != {expected}"

        proxy_data = wait_for_json("http://127.0.0.1:8080/api/weights", expected)
        assert proxy_data == expected
    finally:
        kill_port(8000)
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
        if os.path.exists(projects):
            shutil.rmtree(projects)
        shutil.copytree(backup_projects, projects)
        if os.path.isfile(backup_migration):
            shutil.copy2(backup_migration, migration)
        elif os.path.exists(migration):
            os.unlink(migration)
        shutil.rmtree(backup_root, ignore_errors=True)
        subprocess.Popen(
            ["python3", os.path.join(WORKSPACE, "analyzer.py")], cwd=WORKSPACE,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
