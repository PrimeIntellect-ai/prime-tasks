#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import asyncio
import json
import os
import random
import re
import shutil
import socket
import string
import subprocess
import sys
import tempfile
import time


def test_nginx_listening_8090():
    """Keep the original listening assertion, and require nginx to own the listener."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    result = sock.connect_ex(("127.0.0.1", 8090))
    sock.close()
    assert result == 0, "Nothing is listening on 127.0.0.1:8090 (Nginx expected)."

    result = subprocess.run(["ss", "-ltnp"], capture_output=True, text=True, check=True)
    listener_lines = [line for line in result.stdout.splitlines() if re.search(r"(?:127\.0\.0\.1|0\.0\.0\.0|\*|\[::\]):8090\b", line)]
    assert listener_lines, "Port 8090 is not shown as a listening socket."
    assert any("nginx" in line.lower() for line in listener_lines), \
        f"Port 8090 is not owned by nginx:\n{result.stdout}"


def test_nginx_configuration_and_websocket_proxy():
    path = "/home/user/nginx.conf"
    assert os.path.isfile(path), f"{path} does not exist."

    checked = subprocess.run(
        ["nginx", "-t", "-c", path], capture_output=True, text=True
    )
    assert checked.returncode == 0, f"nginx configuration is invalid:\n{checked.stdout}\n{checked.stderr}"

    dumped = subprocess.run(
        ["nginx", "-T", "-c", path], capture_output=True, text=True
    )
    assert dumped.returncode == 0, f"Could not load nginx.conf:\n{dumped.stdout}\n{dumped.stderr}"
    config = re.sub(r"#.*", "", dumped.stdout + "\n" + dumped.stderr)

    assert not re.search(r"(?m)^\s*user\s+root\s*;", config), "nginx must not use user root."
    assert re.search(r"(?m)^\s*user\s+user(?:\s+user)?\s*;", config), \
        "nginx must be configured to run workers as the current unprivileged user."
    assert re.search(r"(?m)^\s*listen\s+(?:127\.0\.0\.1:)?8090(?:\s+[^;]+)?\s*;", config), \
        "nginx.conf does not listen on port 8090."
    assert re.search(r"(?m)^\s*pid\s+/home/user/[^;\s]+\s*;", config), "pid must be under /home/user/."
    assert re.search(r"(?m)^\s*access_log\s+/home/user/[^;\s]+", config), "access_log must be under /home/user/."
    assert re.search(r"(?m)^\s*error_log\s+/home/user/[^;\s]+", config), "error_log must be under /home/user/."
    assert re.search(r"location\s+(?:=\s*)?/stream(?:\s|\{)", config), "A /stream location is required."
    assert re.search(r"proxy_pass\s+http://127\.0\.0\.1:8080(?:/)?\s*;", config), \
        "/stream must proxy to 127.0.0.1:8080."
    assert re.search(r"proxy_http_version\s+1\.1\s*;", config), "WebSocket proxying requires HTTP/1.1."
    assert re.search(r"proxy_set_header\s+Upgrade\s+\$http_upgrade\s*;", config, re.I), \
        "The WebSocket Upgrade header is not forwarded."
    assert re.search(r"proxy_set_header\s+Connection\s+(?:['\"]?upgrade['\"]?|\$connection_upgrade)\s*;", config, re.I), \
        "The WebSocket Connection header is not configured."

    processes = subprocess.run(["ps", "-eo", "args="], capture_output=True, text=True, check=True).stdout
    assert any("nginx" in line and ("/home/user/nginx.conf" in line or "-c nginx.conf" in line)
               for line in processes.splitlines()), \
        "The running nginx master was not started with /home/user/nginx.conf."

    async def receive_through_proxy():
        import websockets
        async with websockets.connect("ws://127.0.0.1:8090/stream", open_timeout=4) as ws:
            return await asyncio.wait_for(ws.recv(), timeout=4)

    raw = asyncio.run(receive_through_proxy())
    payload = json.loads(raw)
    assert isinstance(payload, dict)
    assert {"artifact_id", "status", "metrics"}.issubset(payload)
    assert isinstance(payload["metrics"], dict)
    assert {"size_bytes", "build_time_sec"}.issubset(payload["metrics"])


def test_failed_artifacts_log():
    """Keep the original log assertions."""
    log_path = "/home/user/failed_artifacts.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist."
    with open(log_path, "r") as f:
        lines = f.read().strip().split("\n")
    assert len(lines) > 0 and lines[0] != "", "Log file is empty."
    pattern = re.compile(r"^build-\d+,\d+,\d+(\.\d+)?$")
    valid_lines = sum(1 for line in lines if line.strip() and pattern.match(line))
    assert valid_lines > 0, "No correctly formatted lines found in failed_artifacts.log."


def _oracle(value):
    try:
        data = json.loads(value)
    except json.JSONDecodeError:
        return None
    try:
        if data["status"] != "failure":
            return None
        return f'{data["artifact_id"]},{data["metrics"]["size_bytes"]},{data["metrics"]["build_time_sec"]}'
    except (KeyError, TypeError):
        return None


def test_client_script_and_function():
    """Keep the original cases and add verifier-derived randomized cases."""
    client_path = "/home/user/client.py"
    assert os.path.isfile(client_path), f"{client_path} does not exist."
    sys.path.insert(0, "/home/user")
    try:
        import client
    except ImportError as exc:
        raise AssertionError(f"Could not import client.py: {exc}")
    assert hasattr(client, "parse_and_transform"), "client.py is missing parse_and_transform."
    func = client.parse_and_transform

    valid_json = '{"artifact_id": "build-123", "status": "failure", "metrics": {"size_bytes": 1024, "build_time_sec": 45.2}}'
    assert func(valid_json) == "build-123,1024,45.2"
    success_json = '{"artifact_id": "build-124", "status": "success", "metrics": {"size_bytes": 1024, "build_time_sec": 45.2}}'
    assert func(success_json) is None
    invalid_json = '{"artifact_id": "build-125"'
    assert func(invalid_json) is None

    rng = random.SystemRandom()
    cases = ["", "null", "[]", "{}", '"failure"', "{", "[1,", "true", "123"]
    for _ in range(80):
        artifact = "artifact-" + "".join(rng.choice(string.ascii_letters + string.digits + " _-") for _ in range(rng.randint(1, 30)))
        size = rng.randint(-10**9, 10**9)
        build_time = round(rng.uniform(-10000, 10000), rng.randint(0, 6))
        cases.append(json.dumps({
            "artifact_id": artifact,
            "status": "failure",
            "metrics": {"size_bytes": size, "build_time_sec": build_time},
            "extra": rng.randint(0, 1000000),
        }))
        cases.append(json.dumps({
            "artifact_id": artifact,
            "status": rng.choice(["success", "running", "queued", "FAILURE", ""]),
            "metrics": {"size_bytes": size, "build_time_sec": build_time},
        }))
        cases.append(json.dumps(rng.choice([
            {"status": "failure", "metrics": {"size_bytes": size, "build_time_sec": build_time}},
            {"artifact_id": artifact, "status": "failure", "metrics": {}},
            {"artifact_id": artifact, "status": "failure", "metrics": None},
            {"artifact_id": artifact},
        ])))
        cases.append("".join(rng.choice(string.printable) for _ in range(rng.randint(0, 80))))

    for case in cases:
        try:
            actual = func(case)
        except Exception as exc:
            raise AssertionError(f"parse_and_transform raised {type(exc).__name__} for {case!r}") from exc
        expected = _oracle(case)
        assert actual == expected, f"Wrong result for verifier-generated input {case!r}: {actual!r} != {expected!r}"
        assert actual is None or isinstance(actual, str)


def _contains_call(node, name):
    return any(isinstance(n, ast.Call) and
               ((isinstance(n.func, ast.Name) and n.func.id == name) or
                (isinstance(n.func, ast.Attribute) and n.func.attr == name))
               for n in ast.walk(node))


def test_pytest_hypothesis_suite():
    """Run the suite and verify that its Hypothesis property is non-vacuous."""
    test_path = "/home/user/test_client.py"
    assert os.path.isfile(test_path), f"{test_path} does not exist."
    content = open(test_path, encoding="utf-8").read()
    assert "hypothesis" in content, "test_client.py does not appear to use hypothesis."

    tree = ast.parse(content, filename=test_path)
    meaningful = False
    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        given_decorators = [d for d in node.decorator_list if isinstance(d, ast.Call) and
                            ((isinstance(d.func, ast.Name) and d.func.id == "given") or
                             (isinstance(d.func, ast.Attribute) and d.func.attr == "given"))]
        if not given_decorators or not any(_contains_call(d, "text") for d in given_decorators):
            continue
        parameters = {a.arg for a in node.args.args}
        for call in (n for n in ast.walk(node) if isinstance(n, ast.Call) and
                     ((isinstance(n.func, ast.Name) and n.func.id == "parse_and_transform") or
                      (isinstance(n.func, ast.Attribute) and n.func.attr == "parse_and_transform"))):
            if any(isinstance(n, ast.Name) and n.id in parameters for arg in call.args for n in ast.walk(arg)):
                meaningful = True
    assert meaningful, "A @given(...text()...) property must pass its generated string to parse_and_transform."

    result = subprocess.run([sys.executable, "-m", "pytest", test_path], capture_output=True, text=True, timeout=35)
    assert result.returncode == 0, f"pytest on {test_path} failed:\n{result.stdout}\n{result.stderr}"

    # A property promising that arbitrary strings never raise must reject a function that always raises.
    with tempfile.TemporaryDirectory() as tmp:
        shutil.copy2(test_path, os.path.join(tmp, "test_client.py"))
        with open(os.path.join(tmp, "client.py"), "w") as f:
            f.write("def parse_and_transform(json_str):\n    raise RuntimeError('injected failure')\n")
        env = os.environ.copy()
        env["PYTHONPATH"] = tmp
        mutant = subprocess.run(
            [sys.executable, "-m", "pytest", "test_client.py"], cwd=tmp, env=env,
            capture_output=True, text=True, timeout=35
        )
        assert mutant.returncode != 0, \
            "The submitted property test passes even when parse_and_transform always raises."


def test_client_is_running_and_log_is_live():
    client_pids = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            raw = open(f"/proc/{entry}/cmdline", "rb").read().replace(b"\0", b" ").decode(errors="replace")
            cwd = os.readlink(f"/proc/{entry}/cwd")
        except (OSError, PermissionError):
            continue
        if re.search(r"(?:^|\s)(?:/home/user/)?client\.py(?:\s|$)", raw) and cwd == "/home/user":
            client_pids.append(int(entry))
    assert client_pids, "No background Python process running /home/user/client.py was found."

    connected = False
    deadline = time.time() + 5
    while time.time() < deadline:
        sockets = subprocess.run(["ss", "-tnp", "state", "established"], capture_output=True, text=True).stdout
        if any(f"pid={pid}," in sockets for pid in client_pids) and re.search(r"127\.0\.0\.1:8090\b", sockets):
            connected = True
            break
        time.sleep(0.25)
    assert connected, "The running client has no established WebSocket connection through port 8090."

    log_path = "/home/user/failed_artifacts.log"
    start = os.path.getsize(log_path)
    new_data = ""
    deadline = time.time() + 12
    pattern = re.compile(r"^build-\d+,\d+,\d+(?:\.\d+)?$")
    while time.time() < deadline:
        with open(log_path, "r") as f:
            f.seek(start)
            new_data = f.read()
        if any(pattern.fullmatch(line) for line in new_data.splitlines()):
            break
        time.sleep(0.25)
    assert any(pattern.fullmatch(line) for line in new_data.splitlines()), \
        "The running client did not append a newly received failure to failed_artifacts.log."
TEST_EOF

if timeout 90 python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
