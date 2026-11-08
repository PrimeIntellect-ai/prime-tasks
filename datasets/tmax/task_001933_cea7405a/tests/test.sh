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
import random
import re
import signal
import socket
import subprocess
import time

import pytest
import requests

BASE_URL = "http://127.0.0.1:9090/api/v1/compute"
AUTH_HEADER = {"Authorization": "Bearer secret-QA-8821"}


def encode_expr(expr: str) -> str:
    """Encode expressions according to the legacy binary protocol."""
    return "".join(f"{ord(c) ^ 0x5A:02x}" for c in expr)


def test_ci_script_exists():
    """Verify the CI test script exists and is executable."""
    path = "/home/user/ci_test.sh"
    assert os.path.isfile(path), f"Missing {path}"
    assert os.access(path, os.X_OK), f"{path} is not executable"


def test_unauthorized():
    """Verify that requests without proper authentication are rejected with 401."""
    time.sleep(10.1)
    resp = requests.post(BASE_URL, json={"data": encode_expr("1+1")})
    assert resp.status_code == 401, f"Expected 401 Unauthorized, got {resp.status_code}. Response: {resp.text}"


def test_bad_request():
    """Verify that malformed requests are rejected with 400."""
    time.sleep(10.1)

    resp1 = requests.post(BASE_URL, headers=AUTH_HEADER, json={"wrong_key": encode_expr("1+1")})
    assert resp1.status_code == 400, f"Expected 400 Bad Request for missing 'data' key, got {resp1.status_code}. Response: {resp1.text}"

    resp2 = requests.post(BASE_URL, headers=AUTH_HEADER, json={"data": "not-a-valid-hex-string"})
    assert resp2.status_code == 400, f"Expected 400 Bad Request for non-hex data, got {resp2.status_code}. Response: {resp2.text}"


def test_valid_computation():
    """Preserve the original substantive computation assertion."""
    time.sleep(10.1)

    expr = "15*3"
    resp = requests.post(BASE_URL, headers=AUTH_HEADER, json={"data": encode_expr(expr)})
    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}. Response: {resp.text}"

    try:
        data = resp.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {resp.text}")

    assert "result" in data, f"Response JSON missing 'result' key. Got: {data}"
    assert data["result"] == 45, f"Expected result 45 for '15*3', got {data['result']}"


def test_unpredictable_computations():
    """Exercise every supported operation with operands selected after the agent run."""
    time.sleep(10.1)
    rng = random.SystemRandom()
    cases = []
    for op in ("+", "-", "*"):
        a = rng.randint(20, 500)
        b = rng.randint(2, 50)
        expected = a + b if op == "+" else a - b if op == "-" else a * b
        cases.append((f"{a}{op}{b}", expected))

    for expr, expected in cases:
        resp = requests.post(BASE_URL, headers=AUTH_HEADER, json={"data": encode_expr(expr)})
        assert resp.status_code == 200, f"Expected 200 for {expr!r}, got {resp.status_code}. Response: {resp.text}"
        try:
            body = resp.json()
        except ValueError:
            pytest.fail(f"Response for {expr!r} is not valid JSON: {resp.text}")
        assert "result" in body, f"Response JSON missing 'result' for {expr!r}: {body}"
        assert body["result"] == expected, f"Expected {expected} for {expr!r}, got {body['result']}"


def test_rate_limiting():
    """Preserve the original exact rate-limit assertion."""
    time.sleep(10.1)

    payload = {"data": encode_expr("2+2")}
    for i in range(3):
        resp = requests.post(BASE_URL, headers=AUTH_HEADER, json=payload)
        assert resp.status_code == 200, f"Request {i+1}/3 failed with {resp.status_code}, expected 200. Response: {resp.text}"

    resp_429 = requests.post(BASE_URL, headers=AUTH_HEADER, json=payload)
    assert resp_429.status_code == 429, f"Expected 429 Too Many Requests for 4th request, got {resp_429.status_code}. Response: {resp_429.text}"


def _kill_port_9090():
    """Stop the already-running service so ci_test.sh must start its own server."""
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].split(":")[-1].upper() == "2382" and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    victims = set()
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(name))
                    break
        except OSError:
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

    deadline = time.time() + 3
    while time.time() < deadline:
        with socket.socket() as sock:
            sock.settimeout(0.15)
            if sock.connect_ex(("127.0.0.1", 9090)) != 0:
                return
        time.sleep(0.1)
    pytest.fail("Could not stop the existing service on port 9090 before running ci_test.sh")


def _curl_request_details(args):
    headers = []
    body = None
    url = None
    i = 0
    while i < len(args):
        arg = args[i]
        if arg in ("-H", "--header") and i + 1 < len(args):
            headers.append(args[i + 1])
            i += 2
            continue
        if arg.startswith("--header="):
            headers.append(arg.split("=", 1)[1])
        elif arg.startswith("-H") and len(arg) > 2:
            headers.append(arg[2:])
        elif arg in ("-d", "--data", "--data-raw", "--data-binary") and i + 1 < len(args):
            body = args[i + 1]
            i += 2
            continue
        elif any(arg.startswith(prefix) for prefix in ("--data=", "--data-raw=", "--data-binary=")):
            body = arg.split("=", 1)[1]
        elif arg.startswith("-d") and len(arg) > 2:
            body = arg[2:]
        elif arg.startswith("http://") or arg.startswith("https://"):
            url = arg
        i += 1

    auth = None
    for header in headers:
        if header.lower().startswith("authorization:"):
            auth = header.split(":", 1)[1].strip()
    try:
        parsed = json.loads(body) if body is not None else None
    except (TypeError, ValueError):
        parsed = None
    return url, auth, body, parsed


def test_ci_script_executes_and_covers_required_checks():
    """Run the submitted CI artifact and verify that it actually exercises each required case."""
    path = "/home/user/ci_test.sh"
    source = open(path, errors="replace").read()
    assert "curl" in source, "ci_test.sh must use curl as required"
    for status in (200, 400, 401, 429):
        assert re.search(rf"\b{status}\b", source), f"ci_test.sh does not contain an assertion for HTTP {status}"

    _kill_port_9090()

    log_path = f"/tmp/ci-curl-{os.getpid()}.jsonl"
    real_curl = "/usr/bin/curl"
    backup_curl = f"/usr/bin/curl.verifier-{os.getpid()}"
    assert os.path.isfile(real_curl), "curl executable is missing"
    os.rename(real_curl, backup_curl)
    wrapper = f'''#!/usr/bin/python3
import json, os, sys, time
with open({log_path!r}, "a") as f:
    f.write(json.dumps({{"time": time.time(), "args": sys.argv[1:]}}) + "\\n")
os.execv({backup_curl!r}, [{backup_curl!r}] + sys.argv[1:])
'''
    try:
        with open(real_curl, "w") as f:
            f.write(wrapper)
        os.chmod(real_curl, 0o755)
        try:
            completed = subprocess.run(
                [path],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=60,
                env=os.environ.copy(),
            )
        except subprocess.TimeoutExpired as exc:
            pytest.fail(f"ci_test.sh did not finish within 60 seconds. Output: {exc.stdout}")
    finally:
        try:
            os.unlink(real_curl)
        except FileNotFoundError:
            pass
        os.rename(backup_curl, real_curl)

    assert completed.returncode == 0, f"ci_test.sh exited {completed.returncode}. Output:\n{completed.stdout}"
    assert os.path.isfile(log_path), "ci_test.sh did not invoke curl"

    records = []
    with open(log_path) as f:
        for line in f:
            records.append(json.loads(line))

    valid_auth_times = []
    saw_unauthorized = False
    saw_invalid = False
    for record in records:
        url, auth, raw_body, body = _curl_request_details(record["args"])
        if not url or "/api/v1/compute" not in url or raw_body is None:
            continue
        has_valid_data = isinstance(body, dict) and isinstance(body.get("data"), str) and re.fullmatch(r"[0-9a-fA-F]+", body["data"] or "") is not None
        if auth != "Bearer secret-QA-8821" and has_valid_data:
            saw_unauthorized = True
        if auth == "Bearer secret-QA-8821" and not has_valid_data:
            saw_invalid = True
        if auth == "Bearer secret-QA-8821" and has_valid_data:
            valid_auth_times.append(float(record["time"]))

    assert saw_unauthorized, "ci_test.sh did not send a compute request with missing/bad authentication"
    assert saw_invalid, "ci_test.sh did not send an authenticated malformed compute request"
    assert valid_auth_times, "ci_test.sh did not send a valid authenticated compute request"
    valid_auth_times.sort()
    assert any(valid_auth_times[j + 3] - valid_auth_times[j] < 10 for j in range(len(valid_auth_times) - 3)), \
        "ci_test.sh did not send four authenticated valid requests within ten seconds to test rate limiting"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
