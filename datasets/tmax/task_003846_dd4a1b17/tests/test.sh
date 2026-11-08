#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import pwd
import random
import re
import signal
import subprocess
import threading
import time
from fractions import Fraction
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest
import requests

BASE = "/home/user/calc-feature"
RESULTS = os.path.join(BASE, "e2e_results.json")
NGINX_CONF = os.path.join(BASE, "nginx.conf")
E2E_SCRIPT = os.path.join(BASE, "run_e2e.py")
SERVER_JS = os.path.join(BASE, "nodejs-svc", "server.js")


def assert_results_file():
    filepath = RESULTS
    assert os.path.exists(filepath), f"Expected results file {filepath} does not exist."
    assert os.path.isfile(filepath), f"Expected {filepath} to be a file."

    with open(filepath, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {filepath} does not contain valid JSON.")

    assert "status_response" in data, "Missing 'status_response' key in E2E results."
    status_resp = data["status_response"]
    assert isinstance(status_resp, dict), "'status_response' should be a JSON object."
    assert status_resp.get("status") == "ok", f"Expected status 'ok', got {status_resp.get('status')}."
    assert status_resp.get("service") == "auth", f"Expected service 'auth', got {status_resp.get('service')}."

    assert "calc_response" in data, "Missing 'calc_response' key in E2E results."
    calc_resp = data["calc_response"]
    assert isinstance(calc_resp, dict), "'calc_response' should be a JSON object."

    expected_result = 18
    actual_result = calc_resp.get("result")
    assert actual_result == expected_result, f"Incorrect math result. Expected {expected_result}, got {actual_result}."


def test_e2e_results_exist_and_correct():
    assert_results_file()


def test_nginx_config_exists():
    filepath = NGINX_CONF
    assert os.path.exists(filepath), f"Nginx configuration file {filepath} does not exist."
    assert os.path.isfile(filepath), f"Expected {filepath} to be a file."


def test_e2e_script_exists():
    filepath = E2E_SCRIPT
    assert os.path.exists(filepath), f"E2E script {filepath} does not exist."
    assert os.path.isfile(filepath), f"Expected {filepath} to be a file."


def wait_http(url, timeout=12):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            return requests.get(url, timeout=0.5)
        except Exception as exc:
            last = exc
            time.sleep(0.15)
    raise AssertionError(f"Timed out waiting for {url}: {last}")


def terminate(proc):
    if proc is None or proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=3)


def demote_to_user():
    account = pwd.getpwnam("user")
    os.setgroups([])
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


def make_expression(rng, depth):
    if depth == 0:
        value = rng.randint(1, 20)
        return str(value), Fraction(value)
    op = rng.choice(["+", "-", "*", "/"])
    left_s, left_v = make_expression(rng, depth - 1)
    right_s, right_v = make_expression(rng, depth - 1)
    if op == "/" and right_v == 0:
        right_s, right_v = "1", Fraction(1)
    if op == "+":
        value = left_v + right_v
    elif op == "-":
        value = left_v - right_v
    elif op == "*":
        value = left_v * right_v
    else:
        value = left_v / right_v
    return f"({left_s} {op} {right_s})", value


def test_artifacts_execute_and_full_stack_works():
    for path in (E2E_SCRIPT, NGINX_CONF, SERVER_JS):
        assert os.path.isfile(path), f"Missing required artifact: {path}"
        assert os.path.getsize(path) > 0, f"Required artifact is empty: {path}"

    package_file = os.path.join(BASE, "nodejs-svc", "package.json")
    with open(package_file) as f:
        package = json.load(f)
    dependencies = package.get("dependencies", {})
    assert "express" in dependencies, "The Node service must retain its Express dependency."
    for module in ("express", "cors"):
        module_dir = os.path.join(BASE, "nodejs-svc", "node_modules", module)
        assert os.path.isdir(module_dir), f"npm dependency {module} was not installed."

    with open(SERVER_JS) as f:
        server_source = f.read()
    assert not re.search(r"\beval\s*\(", server_source), "The parser must not use eval()."
    assert "mathjs" not in dependencies and "mathjs" not in server_source, "External math libraries are not allowed."

    with open(NGINX_CONF) as f:
        nginx_text = f.read()
    assert re.search(r"\blisten\s+8080\b", nginx_text), "Nginx must listen on port 8080."
    assert "nginx_run" in nginx_text, "Nginx runtime paths must use nginx_run/."

    # First execute run_e2e.py against an instrumented endpoint. This proves the
    # script itself performs the required GET and POST rather than merely writing
    # a canned result file.
    subprocess.run(["pkill", "-x", "nginx"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    calls = []

    class CaptureHandler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_GET(self):
            calls.append(("GET", self.path, None))
            body = json.dumps({"status": "ok", "service": "auth"}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_POST(self):
            raw = self.rfile.read(int(self.headers.get("Content-Length", "0")))
            try:
                payload = json.loads(raw)
            except Exception:
                payload = None
            calls.append(("POST", self.path, payload))
            body = json.dumps({"result": 18}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    capture = ThreadingHTTPServer(("127.0.0.1", 8080), CaptureHandler)
    thread = threading.Thread(target=capture.serve_forever, daemon=True)
    thread.start()
    try:
        completed = subprocess.run(
            ["python3", E2E_SCRIPT], cwd=BASE, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20
        )
        assert completed.returncode == 0, f"run_e2e.py failed:\n{completed.stdout}"
    finally:
        capture.shutdown()
        capture.server_close()
        thread.join(timeout=2)

    assert ("GET", "/api/status", None) in calls, "run_e2e.py did not GET /api/status."
    assert any(method == "POST" and path == "/api/calc/evaluate" and
               payload == {"expression": "10 + 2 * (6 - (4 / 2))"}
               for method, path, payload in calls), "run_e2e.py did not POST the required expression payload."
    assert_results_file()

    node_proc = python_proc = nginx_proc = None
    try:
        os.makedirs(os.path.join(BASE, "nginx_run"), exist_ok=True)
        subprocess.run(["chmod", "-R", "a+rwX", os.path.join(BASE, "nginx_run")], check=True)
        for root, _, files in os.walk(os.path.join(BASE, "nginx_run")):
            for name in files:
                if name.endswith(".pid"):
                    try:
                        os.remove(os.path.join(root, name))
                    except OSError:
                        pass

        node_proc = subprocess.Popen(
            ["node", "server.js"], cwd=os.path.join(BASE, "nodejs-svc"),
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
            preexec_fn=demote_to_user
        )
        python_proc = subprocess.Popen(
            ["python3", "app.py"], cwd=os.path.join(BASE, "python-svc"),
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
            preexec_fn=demote_to_user
        )
        wait_http("http://127.0.0.1:3002/status")

        check = subprocess.run(
            ["nginx", "-t", "-p", BASE + "/", "-c", NGINX_CONF],
            cwd=BASE, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            preexec_fn=demote_to_user
        )
        assert check.returncode == 0, f"nginx configuration test failed:\n{check.stdout}"

        nginx_proc = subprocess.Popen(
            ["nginx", "-p", BASE + "/", "-c", NGINX_CONF, "-g", "daemon off;"],
            cwd=BASE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
            preexec_fn=demote_to_user
        )
        response = wait_http("http://127.0.0.1:8080/api/status")
        assert response.status_code == 200
        assert response.json() == {"status": "ok", "service": "auth"}

        rng = random.Random(918273)
        cases = [make_expression(rng, rng.choice([2, 3])) for _ in range(12)]
        # Explicitly exercise left associativity as well as generated nesting.
        cases.append(("80 / 4 / 5 + 3 * 2", Fraction(10)))
        for expression, expected in cases:
            response = requests.post(
                "http://127.0.0.1:8080/api/calc/evaluate",
                json={"expression": expression}, timeout=3
            )
            assert response.status_code == 200, f"Expression {expression!r} returned {response.status_code}: {response.text}"
            body = response.json()
            assert isinstance(body.get("result"), (int, float)), f"Missing numeric result for {expression!r}: {body}"
            assert math.isclose(float(body["result"]), float(expected), rel_tol=1e-9, abs_tol=1e-9), \
                f"Wrong result for {expression!r}: expected {float(expected)}, got {body['result']}"

        # Finally run the submitted orchestration script against the submitted
        # services and proxy, then retain and exact-check its required output.
        completed = subprocess.run(
            ["python3", E2E_SCRIPT], cwd=BASE, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20,
            preexec_fn=demote_to_user
        )
        assert completed.returncode == 0, f"run_e2e.py failed against the real stack:\n{completed.stdout}"
        assert_results_file()
    finally:
        terminate(nginx_proc)
        subprocess.run(["pkill", "-x", "nginx"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        terminate(node_proc)
        terminate(python_proc)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
