#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import socket
import subprocess
import time
import urllib.request

import pytest
import redis

SUBMIT = "/home/user/submit_telemetry.py"
RUN_ALL = "/home/user/run_all.sh"
PROJECT = "/home/user/telemetry_fmt"
BINARY = "/home/user/telemetry_fmt/target/release/telemetry_fmt"
RAW = "/home/user/raw_telemetry.txt"


def raw_lines():
    with open(RAW, "r", encoding="utf-8") as f:
        return f.read().splitlines()


def redis_values():
    r = redis.Redis(host="127.0.0.1", port=6379, db=0, decode_responses=True)
    return r.lrange("telemetry_data", 0, -1)


def wait_port(port, should_be_open=True, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        s = socket.socket()
        s.settimeout(0.2)
        try:
            s.connect(("127.0.0.1", port))
            opened = True
        except OSError:
            opened = False
        finally:
            s.close()
        if opened == should_be_open:
            return
        time.sleep(0.05)
    raise AssertionError(f"port {port} did not reach expected state open={should_be_open}")


def assert_original_redis_shape():
    dbsize_res = subprocess.run(["redis-cli", "DBSIZE"], capture_output=True, text=True)
    dbsize = int(dbsize_res.stdout.strip())

    if dbsize == 50000:
        pass
    else:
        keys_res = subprocess.run(["redis-cli", "KEYS", "*"], capture_output=True, text=True)
        keys = keys_res.stdout.strip().split()
        found_50k = False
        for key in keys:
            type_res = subprocess.run(["redis-cli", "TYPE", key], capture_output=True, text=True)
            ktype = type_res.stdout.strip()
            if ktype == "list":
                len_res = subprocess.run(["redis-cli", "LLEN", key], capture_output=True, text=True)
                if int(len_res.stdout.strip()) == 50000:
                    found_50k = True
                    break
            elif ktype == "set":
                len_res = subprocess.run(["redis-cli", "SCARD", key], capture_output=True, text=True)
                if int(len_res.stdout.strip()) == 50000:
                    found_50k = True
                    break
        assert found_50k or dbsize == 50000, "Could not find exactly 50,000 records inserted into Redis."


def test_files_exist():
    assert os.path.isfile(SUBMIT), f"Missing Python script: {SUBMIT}"
    assert os.path.isfile(RUN_ALL), f"Missing bash script: {RUN_ALL}"


def test_nginx_proxy_configured():
    # Preserve the original live-port assertion.
    res = subprocess.run(["curl", "-I", "http://localhost:8080/"], capture_output=True, text=True)
    assert "nginx" in res.stdout.lower() or "gunicorn" in res.stdout.lower() or "werkzeug" in res.stdout.lower() or res.returncode == 0, "Nginx is not proxying port 8080 properly."

    config = subprocess.run(["nginx", "-T"], capture_output=True, text=True)
    rendered = config.stdout + config.stderr
    assert config.returncode == 0, rendered
    assert re.search(r"\blisten\s+(?:[^;]*:)?8080\b", rendered), "Nginx is not configured to listen on port 8080"
    assert re.search(r"proxy_pass\s+http://(?:127\.0\.0\.1|localhost):5000\s*;", rendered), "Nginx does not proxy to the Flask service on port 5000"

    # Exercise the real Nginx -> Flask -> Redis path with verifier-derived data.
    token = "VERIFIER_PROXY_" + os.urandom(12).hex()
    req = urllib.request.Request(
        "http://127.0.0.1:8080/api/batch",
        data=json.dumps({"telemetry": [token]}).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=5) as response:
        assert response.status == 200
    r = redis.Redis(host="127.0.0.1", port=6379, db=0, decode_responses=True)
    assert token in r.lrange("telemetry_data", 0, -1), "The proxied API request did not reach Redis"
    r.flushall()


def test_rust_tool_and_run_all():
    cargo = shutil.which("cargo")
    assert cargo, "cargo is unavailable"

    # First verify that the repaired Rust source really compiles and implements
    # the required streaming transformation on independently chosen inputs.
    build = subprocess.run([cargo, "build", "--release"], cwd=PROJECT, capture_output=True, text=True, timeout=60)
    assert build.returncode == 0, build.stdout + build.stderr
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), "Missing release Rust binary"
    probes = ["probe_" + os.urandom(8).hex(), "SecondValue", "z"]
    run = subprocess.run([BINARY], input="\n".join(probes) + "\n", capture_output=True, text=True, timeout=5)
    assert run.returncode == 0, run.stderr
    assert run.stdout.splitlines() == ["MOBILE_V1:" + x for x in probes]

    # Stop all three services and remove the built artifact. run_all.sh must
    # actually invoke cargo, restart the services, and perform the submission.
    subprocess.run(["nginx", "-s", "stop"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-f", "gunicorn.*api:app"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["redis-cli", "SHUTDOWN", "NOSAVE"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.3)
    if os.path.exists(BINARY):
        os.remove(BINARY)

    os.makedirs("/tmp/verifier-bin", exist_ok=True)
    cargo_marker = "/tmp/run_all_called_cargo"
    if os.path.exists(cargo_marker):
        os.remove(cargo_marker)
    cargo_wrapper = "/tmp/verifier-bin/cargo"
    with open(cargo_wrapper, "w") as f:
        f.write("#!/bin/sh\necho called >> %s\nexec %s \"$@\"\n" % (cargo_marker, cargo))
    os.chmod(cargo_wrapper, 0o755)

    env = os.environ.copy()
    env["PATH"] = "/tmp/verifier-bin:" + env.get("PATH", "")
    result = subprocess.run(["bash", RUN_ALL], capture_output=True, text=True, env=env, timeout=90)
    assert result.returncode == 0, f"run_all.sh failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(cargo_marker), "run_all.sh did not compile the Rust project with cargo"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), "run_all.sh did not produce the release binary"
    wait_port(6379)
    wait_port(5000)
    wait_port(8080)

    expected = ["MOBILE_V1:" + x for x in raw_lines()]
    actual = redis_values()
    assert actual == list(reversed(expected)), "run_all.sh did not submit the exact formatted telemetry through the provided API"


def test_execution_time_api_payload_and_single_batch_binary_use():
    expected_raw = raw_lines()
    assert len(expected_raw) == 50000

    # Replace only the required release executable with an instrumented
    # equivalent. A conforming orchestrator must invoke it once with all input.
    real_binary = BINARY + ".verifier-real"
    shutil.copy2(BINARY, real_binary)
    stdin_log = "/tmp/telemetry_fmt_stdin"
    calls_log = "/tmp/telemetry_fmt_calls"
    for path in (stdin_log, calls_log, "/tmp/api_capture_ok", "/tmp/api_capture_error"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    wrapper = '''#!/usr/bin/python3
import sys
raw = sys.stdin.buffer.read()
with open("/tmp/telemetry_fmt_calls", "ab") as f:
    f.write(b"1\\n")
with open("/tmp/telemetry_fmt_stdin", "ab") as f:
    f.write(raw)
for line in raw.decode("utf-8").splitlines():
    print("MOBILE_V1:" + line)
'''
    with open(BINARY, "w") as f:
        f.write(wrapper)
    os.chmod(BINARY, 0o755)

    # Move Nginx away temporarily and put a validating HTTP endpoint on exactly
    # port 8080. It accepts only the required path and exact derived payload,
    # then performs the same Redis writes as the supplied Flask API.
    subprocess.run(["nginx", "-s", "stop"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    wait_port(8080, should_be_open=False)
    server_code = r'''
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
import redis

class ReusableHTTPServer(HTTPServer):
    allow_reuse_address = True

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        try:
            n = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(n)
            data = json.loads(body)
            with open("/home/user/raw_telemetry.txt", encoding="utf-8") as f:
                expected = ["MOBILE_V1:" + x for x in f.read().splitlines()]
            assert self.path == "/api/batch"
            assert set(data.keys()) == {"telemetry"}
            assert data["telemetry"] == expected
            r = redis.Redis(host="127.0.0.1", port=6379, db=0)
            pipe = r.pipeline()
            for item in data["telemetry"]:
                pipe.lpush("telemetry_data", item)
            pipe.execute()
            with open("/tmp/api_capture_ok", "w") as f:
                f.write("ok")
            payload = json.dumps({"status": "ok", "inserted": len(expected)}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        except Exception as exc:
            with open("/tmp/api_capture_error", "w") as f:
                f.write(repr(exc))
            self.send_response(400)
            self.end_headers()
    def log_message(self, *args):
        pass

open("/tmp/capture_server_ready", "w").close()
ReusableHTTPServer(("127.0.0.1", 8080), Handler).serve_forever()
'''
    with open("/tmp/capture_server.py", "w") as f:
        f.write(server_code)
    try:
        os.remove("/tmp/capture_server_ready")
    except FileNotFoundError:
        pass
    server = subprocess.Popen(["python3", "/tmp/capture_server.py"], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    wait_port(8080)

    subprocess.run(["redis-cli", "FLUSHALL"], check=True)
    start_time = time.time()
    res = subprocess.run(["python3", SUBMIT], capture_output=True, text=True)
    end_time = time.time()
    duration = end_time - start_time

    try:
        assert res.returncode == 0, f"submit_telemetry.py failed with error: {res.stderr}"
        assert duration <= 2.5, f"Execution time {duration:.3f} seconds exceeds the threshold of 2.5 seconds."
        assert duration < 2.5, f"Execution time must be strictly less than 2.5 seconds, got {duration:.3f}."
        assert os.path.isfile("/tmp/api_capture_ok"), "No valid POST was made to http://localhost:8080/api/batch"
        assert not os.path.exists("/tmp/api_capture_error"), open("/tmp/api_capture_error").read() if os.path.exists("/tmp/api_capture_error") else ""

        with open(calls_log, "rb") as f:
            calls = f.read().splitlines()
        assert len(calls) == 1, "The Rust formatter must be invoked exactly once for the full batch"
        with open(stdin_log, "rb") as f:
            formatter_input = f.read().decode("utf-8").splitlines()
        assert formatter_input == expected_raw, "The Rust formatter did not receive all 50,000 raw records in one batch"

        actual = redis_values()
        expected = ["MOBILE_V1:" + x for x in expected_raw]
        assert actual == list(reversed(expected)), "Redis does not contain the exact API-submitted formatted records"
        assert_original_redis_shape()
    finally:
        server.terminate()
        try:
            server.wait(timeout=3)
        except subprocess.TimeoutExpired:
            server.kill()
        shutil.move(real_binary, BINARY)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
