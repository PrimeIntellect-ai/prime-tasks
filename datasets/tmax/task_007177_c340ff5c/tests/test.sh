#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import signal
import socket
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

import pytest

PROJECT = "/home/user/polycalc"
SCRIPT = "/home/user/test_polycalc.sh"
LOG = "/home/user/integration_results.log"
BASE = "http://127.0.0.1:8080"


def stop_port_8080_listener():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].endswith(":1F90") and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    victims = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) in (1, os.getpid()):
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            pass

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    if victims:
        time.sleep(0.5)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def request(path):
    req = urllib.request.Request(BASE + path, method="GET")
    try:
        response = urllib.request.urlopen(req, timeout=5)
        status = response.status
        headers = response.headers
        body = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        status = exc.code
        headers = exc.headers
        body = exc.read().decode("utf-8")
    assert headers.get_content_type() == "application/json", headers.get("Content-Type")
    try:
        payload = json.loads(body)
    except json.JSONDecodeError as exc:
        pytest.fail(f"Response was not valid JSON: {body!r}: {exc}")
    return status, payload


def simpson(coeffs, lower, upper, steps):
    def polynomial(x):
        total = 0.0
        power = 1.0
        for coefficient in coeffs:
            total += coefficient * power
            power *= x
        return total

    h = (upper - lower) / steps
    total = polynomial(lower) + polynomial(upper)
    for i in range(1, steps):
        total += (4 if i % 2 else 2) * polynomial(lower + i * h)
    return h * total / 3.0


@pytest.fixture(scope="session", autouse=True)
def built_server():
    assert os.path.isdir(PROJECT), f"Directory {PROJECT} does not exist."
    binary = "/tmp/polycalc_submission"
    build = subprocess.run(
        ["go", "build", "-o", binary, "."],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=90,
    )
    assert build.returncode == 0, f"Go service did not build:\n{build.stdout}"
    assert os.path.isfile(binary) and os.access(binary, os.X_OK)

    stop_port_8080_listener()
    process = subprocess.Popen(
        [binary],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
    )
    deadline = time.time() + 12
    while time.time() < deadline:
        if process.poll() is not None:
            output = process.stdout.read() if process.stdout else ""
            pytest.fail(f"Built server exited before listening on port 8080:\n{output}")
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=0.25):
                break
        except OSError:
            time.sleep(0.15)
    else:
        process.terminate()
        pytest.fail("Built server did not listen on port 8080.")

    yield

    try:
        os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=3)
    except (ProcessLookupError, subprocess.TimeoutExpired):
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def test_go_mod_exists_and_content():
    go_mod_path = "/home/user/polycalc/go.mod"
    assert os.path.exists(go_mod_path), f"File {go_mod_path} does not exist."
    with open(go_mod_path) as f:
        content = f.read()
    assert "module polycalc" in content, "go.mod does not contain 'module polycalc'."
    assert "github.com/gorilla/mux" in content, "go.mod does not require 'github.com/gorilla/mux'."


def test_bash_script_exists_and_executable():
    assert os.path.exists(SCRIPT), f"File {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"File {SCRIPT} is not executable."


def assert_required_log_contents(lines):
    assert len(lines) >= 2, f"Expected at least 2 lines of JSON in {LOG}, got {len(lines)}."
    try:
        resp1 = json.loads(lines[0])
    except json.JSONDecodeError:
        pytest.fail(f"First line of {LOG} is not valid JSON: {lines[0]}")
    assert resp1.get("lower") == 0, f"Expected lower=0, got {resp1.get('lower')}"
    assert resp1.get("upper") == 5, f"Expected upper=5, got {resp1.get('upper')}"
    assert resp1.get("steps") == 100, f"Expected steps=100, got {resp1.get('steps')}"
    result = resp1.get("result")
    assert result is not None, "First response missing 'result' field."
    assert math.isclose(result, 81.66666666666667, rel_tol=1e-5), f"Expected result ~81.66667, got {result}"

    try:
        resp2 = json.loads(lines[1])
    except json.JSONDecodeError:
        pytest.fail(f"Second line of {LOG} is not valid JSON: {lines[1]}")
    expected_error = "steps must be an even integer greater than 0"
    assert resp2.get("error") == expected_error, f"Expected error message '{expected_error}', got '{resp2.get('error')}'"


def test_log_file_contents():
    assert os.path.exists(LOG), f"File {LOG} does not exist."
    with open(LOG) as f:
        lines = [line.strip() for line in f if line.strip()]
    assert_required_log_contents(lines)


def test_randomized_simpson_requests():
    rng = random.SystemRandom()
    for _ in range(6):
        degree = rng.randint(4, 8)
        coeffs = [rng.uniform(-4.0, 4.0) for _ in range(degree + 1)]
        lower = rng.uniform(-2.0, 0.5)
        upper = rng.uniform(0.75, 3.0)
        steps = 2 * rng.randint(2, 35)
        lower_text = format(lower, ".12g")
        upper_text = format(upper, ".12g")
        sent_lower = float(lower_text)
        sent_upper = float(upper_text)
        coeff_texts = [format(value, ".12g") for value in coeffs]
        sent_coeffs = [float(value) for value in coeff_texts]
        query = urllib.parse.urlencode({"coeffs": ",".join(coeff_texts), "steps": str(steps)})
        status, payload = request(f"/api/v1/integrate/{lower_text}/{upper_text}?{query}")
        assert status == 200, payload
        assert set(payload) == {"lower", "upper", "steps", "result"}
        assert math.isclose(float(payload["lower"]), sent_lower, rel_tol=0, abs_tol=1e-12)
        assert math.isclose(float(payload["upper"]), sent_upper, rel_tol=0, abs_tol=1e-12)
        assert payload["steps"] == steps
        expected = simpson(sent_coeffs, sent_lower, sent_upper, steps)
        assert math.isclose(float(payload["result"]), expected, rel_tol=1e-9, abs_tol=1e-8), (payload, expected)


def test_validation_responses():
    coeffs = urllib.parse.quote("1.25,-2,3.5", safe=",")
    expected_steps = {"error": "steps must be an even integer greater than 0"}
    for steps in ("1", "3", "0", "-2", "not-an-integer"):
        status, payload = request(f"/api/v1/integrate/0/2?coeffs={coeffs}&steps={steps}")
        assert status == 400
        assert payload == expected_steps

    for suffix in ("steps=10", "coeffs=1,bad,3&steps=10", "coeffs=&steps=10"):
        status, payload = request(f"/api/v1/integrate/0/2?{suffix}")
        assert status == 400
        assert payload == {"error": "invalid coefficients"}


def test_execute_supplied_script_and_regenerate_log():
    try:
        os.remove(LOG)
    except FileNotFoundError:
        pass
    completed = subprocess.run(
        [SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, f"Test script failed:\n{completed.stdout}"
    assert os.path.exists(LOG), "Executing test_polycalc.sh did not generate integration_results.log."
    with open(LOG) as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == 2, f"The test script must append exactly two JSON response lines; got {len(lines)}."
    assert_required_log_contents(lines)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
