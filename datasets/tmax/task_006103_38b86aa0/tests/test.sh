#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import contextlib
import importlib.util
import json
import os
import random
import re
import secrets
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

import pytest

WORKSPACE = "/home/user/workspace"


def test_venv_exists():
    venv_dir = os.path.join(WORKSPACE, "venv")
    assert os.path.isdir(venv_dir), f"Virtual environment directory {venv_dir} does not exist."
    python_bin = os.path.join(venv_dir, "bin", "python")
    assert os.path.isfile(python_bin), f"Python executable not found in {venv_dir}."


def test_requirements_txt():
    req_path = os.path.join(WORKSPACE, "requirements.txt")
    assert os.path.isfile(req_path), f"{req_path} does not exist."
    with open(req_path, "r") as f:
        content = f.read().lower()

    for pkg in ["flask", "requests", "pytest", "hypothesis"]:
        assert pkg in content, f"Package {pkg} is missing from requirements.txt."

    python_bin = os.path.join(WORKSPACE, "venv", "bin", "python")
    result = subprocess.run(
        [python_bin, "-c", "import flask, requests, pytest, hypothesis"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Required packages are not installed in the venv:\n{result.stderr}"


def test_build_tree_independently():
    path = os.path.join(WORKSPACE, "build_tree.py")
    assert os.path.isfile(path), f"{path} does not exist."
    spec = importlib.util.spec_from_file_location("submitted_build_tree", path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert hasattr(module, "BuildTree"), "build_tree.py does not define BuildTree"

    tree = module.BuildTree()
    p1 = "p-" + uuid.uuid4().hex
    p2 = "p-" + uuid.uuid4().hex
    b1 = "b-" + uuid.uuid4().hex
    b2 = "b-" + uuid.uuid4().hex
    assert tree.get_latest(p1, b1) is None

    major = secrets.randbelow(50) + 1
    versions = [
        f"{major}.2.2",
        f"{major}.2.10",
        f"{major}.11.0",
        f"{major + 1}.0.0",
        f"{major}.9.999",
    ]
    shuffled = versions[:]
    random.SystemRandom().shuffle(shuffled)
    for version in shuffled:
        tree.insert(p1, b1, version)
    assert tree.get_latest(p1, b1) == f"{major + 1}.0.0"

    tree.insert(p1, b2, "99.0.0")
    tree.insert(p2, b1, "100.0.0")
    assert tree.get_latest(p1, b1) == f"{major + 1}.0.0"
    assert tree.get_latest(p1, b2) == "99.0.0"
    assert tree.get_latest(p2, b1) == "100.0.0"


def test_pytest_passes():
    pytest_bin = os.path.join(WORKSPACE, "venv", "bin", "pytest")
    test_file = os.path.join(WORKSPACE, "test_tree.py")

    assert os.path.isfile(test_file), f"Test file {test_file} does not exist."
    assert os.path.isfile(pytest_bin), f"pytest executable not found at {pytest_bin}."

    with open(test_file, "r") as f:
        source = f.read()
    parsed = ast.parse(source, filename=test_file)
    has_hypothesis_import = any(
        (isinstance(node, ast.Import) and any(alias.name == "hypothesis" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "hypothesis")
        for node in ast.walk(parsed)
    )
    functions = [
        node for node in ast.walk(parsed)
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        and node.name == "test_highest_version_returned"
    ]
    assert has_hypothesis_import, "test_tree.py must import hypothesis"
    assert functions, "test_tree.py must define test_highest_version_returned"

    def is_given(dec):
        target = dec.func if isinstance(dec, ast.Call) else dec
        return (isinstance(target, ast.Name) and target.id == "given") or (
            isinstance(target, ast.Attribute) and target.attr == "given"
        )

    assert any(is_given(dec) for fn in functions for dec in fn.decorator_list), \
        "test_highest_version_returned must be a Hypothesis @given property test"

    result = subprocess.run([pytest_bin, test_file], capture_output=True, text=True, timeout=120)
    assert result.returncode == 0, f"pytest failed on {test_file}:\n{result.stdout}\n{result.stderr}"


def test_nginx_config_valid():
    nginx_conf = os.path.join(WORKSPACE, "nginx.conf")
    assert os.path.isfile(nginx_conf), f"Nginx config {nginx_conf} does not exist."

    result = subprocess.run(["nginx", "-t", "-c", nginx_conf], capture_output=True, text=True)
    assert result.returncode == 0, f"Nginx config syntax check failed:\n{result.stderr}"


def test_uploader_binary_exists():
    uploader_bin = os.path.join(WORKSPACE, "uploader")
    assert os.path.isfile(uploader_bin), f"Compiled Go binary {uploader_bin} does not exist."
    assert os.access(uploader_bin, os.X_OK), f"File {uploader_bin} is not executable."
    with open(uploader_bin, "rb") as f:
        assert f.read(4) == b"\x7fELF", "uploader is not a compiled Linux executable"


def _request(method, url, payload=None, timeout=3):
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    headers = {} if payload is None else {"Content-Type": "application/json"}
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.status, response.read().decode("utf-8")


def _cleanup_services():
    conf = os.path.join(WORKSPACE, "nginx.conf")
    subprocess.run(
        ["runuser", "-u", "user", "--", "nginx", "-s", "quit", "-c", conf],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    subprocess.run(["pkill", "-f", os.path.join(WORKSPACE, "server.py")], check=False)
    time.sleep(0.25)


@contextlib.contextmanager
def _running_stack():
    server_path = os.path.join(WORKSPACE, "server.py")
    conf = os.path.join(WORKSPACE, "nginx.conf")
    python_bin = os.path.join(WORKSPACE, "venv", "bin", "python")
    assert os.path.isfile(server_path), "server.py does not exist"

    _cleanup_services()
    server = subprocess.Popen(
        ["runuser", "-u", "user", "--", python_bin, server_path],
        cwd=WORKSPACE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    with open(conf, "r") as f:
        conf_text = f.read()
    nginx_cmd = ["runuser", "-u", "user", "--", "nginx", "-c", conf]
    if not re.search(r"(?m)^\s*daemon\s+", conf_text):
        nginx_cmd += ["-g", "daemon off;"]
    nginx_proc = subprocess.Popen(
        nginx_cmd,
        cwd=WORKSPACE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    probe = "http://127.0.0.1:9090/latest?" + urllib.parse.urlencode(
        {"platform": "probe-" + uuid.uuid4().hex, "branch": "probe"}
    )
    last_error = None
    for _ in range(60):
        if server.poll() is not None:
            out, err = server.communicate(timeout=1)
            raise AssertionError(f"server.py exited before serving requests:\n{out}\n{err}")
        try:
            status, _ = _request("GET", probe, timeout=1)
            if status == 200:
                break
        except Exception as exc:
            last_error = exc
            time.sleep(0.1)
    else:
        raise AssertionError(f"Server/proxy did not become reachable: {last_error}")

    try:
        yield
    finally:
        for proc in (nginx_proc, server):
            if proc.poll() is None:
                proc.terminate()
        for proc in (nginx_proc, server):
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2)
        _cleanup_services()


def _assert_latest(base, platform, branch, expected):
    query = urllib.parse.urlencode({"platform": platform, "branch": branch})
    status, body = _request("GET", f"{base}/latest?{query}")
    assert status == 200
    data = json.loads(body)
    assert data == {"version": expected}, f"Unexpected latest response: {data}"


def _exercise_api(base):
    platform = "platform-" + uuid.uuid4().hex
    branch = "branch-" + uuid.uuid4().hex
    other_branch = "branch-" + uuid.uuid4().hex
    major = secrets.randbelow(30) + 2
    versions = [f"{major}.3.9", f"{major}.3.12", f"{major}.10.0", f"{major}.9.99"]
    random.SystemRandom().shuffle(versions)
    for version in versions:
        status, _ = _request("POST", f"{base}/add", {
            "platform": platform, "branch": branch, "version": version
        })
        assert status == 200
    _request("POST", f"{base}/add", {
        "platform": platform, "branch": other_branch, "version": "99.0.0"
    })
    _assert_latest(base, platform, branch, f"{major}.10.0")
    _assert_latest(base, platform, other_branch, "99.0.0")


def test_live_server_proxy_and_uploader():
    source = os.path.join(WORKSPACE, "uploader.go")
    submitted_binary = os.path.join(WORKSPACE, "uploader")
    rebuilt_binary = "/tmp/rebuilt_uploader"
    assert os.path.isfile(source), "uploader.go does not exist"

    build = subprocess.run(
        ["go", "build", "-o", rebuilt_binary, source],
        cwd=WORKSPACE,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert build.returncode == 0, f"uploader.go does not compile:\n{build.stdout}\n{build.stderr}"

    # Exercise the source-built program against a fresh real Flask/nginx stack.
    with _running_stack():
        _exercise_api("http://127.0.0.1:9090")
        result = subprocess.run([rebuilt_binary], capture_output=True, text=True, timeout=20)
        assert result.returncode == 0, f"Rebuilt uploader failed:\n{result.stdout}\n{result.stderr}"
        _assert_latest("http://127.0.0.1:9090", "android", "release", "1.0.12")

    # Also execute the required artifact at the requested path on clean state.
    with _running_stack():
        result = subprocess.run([submitted_binary], capture_output=True, text=True, timeout=20)
        assert result.returncode == 0, f"Submitted uploader failed:\n{result.stdout}\n{result.stderr}"
        _assert_latest("http://127.0.0.1:9090", "android", "release", "1.0.12")
        # Confirm the Flask service itself is bound on the specified direct port.
        direct_platform = "direct-" + uuid.uuid4().hex
        status, _ = _request("POST", "http://127.0.0.1:8080/add", {
            "platform": direct_platform, "branch": "main", "version": "2.0.1"
        })
        assert status == 200
        _assert_latest("http://127.0.0.1:9090", direct_platform, "main", "2.0.1")


def test_final_result_log():
    log_path = os.path.join(WORKSPACE, "final_result.log")
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    with open(log_path, "r") as f:
        content = f.read().strip()

    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        pytest.fail(f"Content of {log_path} is not valid JSON: {content}")

    assert "version" in data, f"'version' key missing in final_result.log JSON: {data}"
    assert data["version"] == "1.0.12", f"Expected version '1.0.12', but got '{data['version']}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
