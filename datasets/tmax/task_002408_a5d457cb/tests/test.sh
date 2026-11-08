#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import math
import os
import random
import socket
import subprocess
import time
import urllib.error
import urllib.request

import pytest

PROJECT = "/home/user/pricing-engine"
VERIFIED_BINARY = "/tmp/pricing-engine-verified"


def listener_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return pids


def stop_existing_service():
    for pid in listener_pids(8080):
        try:
            os.kill(pid, 15)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listener_pids(8080):
        time.sleep(0.05)
    for pid in listener_pids(8080):
        try:
            os.kill(pid, 9)
        except ProcessLookupError:
            pass


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def request_value(rate, timeout=5):
    url = f"http://localhost:8080/calculate?rate={rate}"
    try:
        with urllib.request.urlopen(urllib.request.Request(url), timeout=timeout) as response:
            assert response.status == 200, f"Expected HTTP 200 status code, got {response.status}"
            body = response.read().decode("utf-8").strip()
    except urllib.error.HTTPError as e:
        pytest.fail(f"Service returned an HTTP error: {e.code} {e.reason}")
    except urllib.error.URLError as e:
        pytest.fail(f"Could not connect to the service at {url}: {e.reason}")
    except TimeoutError:
        pytest.fail(f"Request to {url} timed out. The infinite loop bug might still be present.")

    try:
        value = float(body)
    except ValueError:
        pytest.fail(f"Service returned '{body}', which is not a valid floating point number.")
    assert math.isfinite(value), f"Service returned a non-finite result '{body}'"
    return value


def test_bug_report():
    path = "/home/user/bug_report.txt"
    assert os.path.exists(path), f"File {path} does not exist. You must create the bug report."

    with open(path, "r") as f:
        content = f.read().strip()

    lines = [line.strip() for line in content.split("\n") if line.strip()]
    assert len(lines) == 2, f"Expected exactly 2 lines in {path}, got {len(lines)}. Content was: {content}"
    assert lines[0] == "A103", f"Expected tx_id 'A103' on line 1, got '{lines[0]}'"
    assert lines[1] == "0.3333333", f"Expected rate '0.3333333' on line 2, got '{lines[1]}'"


def test_run_sh_executable():
    path = "/home/user/run.sh"
    assert os.path.exists(path), f"Script {path} does not exist. You must create the startup script."
    assert os.access(path, os.X_OK), f"Script {path} is not executable. Please make it executable (e.g., chmod +x)."


def test_project_builds_with_standard_go_build():
    result = subprocess.run(
        ["go", "build", "-o", VERIFIED_BINARY, "."],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"The pricing-engine project does not build successfully:\n{result.stdout}"
    assert os.path.isfile(VERIFIED_BINARY) and os.access(VERIFIED_BINARY, os.X_OK)


def test_run_script_launches_submitted_service_and_calculates_correctly():
    stop_existing_service()
    try:
        result = subprocess.run(
            ["/home/user/run.sh"],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=60,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("/home/user/run.sh did not return after starting the service in the background")
    assert result.returncode == 0, f"run.sh failed:\n{result.stdout}"

    deadline = time.time() + 10
    pids = set()
    while time.time() < deadline:
        pids = listener_pids(8080)
        if pids:
            break
        time.sleep(0.1)
    assert pids, "run.sh did not start a service listening on port 8080"

    expected_hash = sha256_file(VERIFIED_BINARY)
    running_hashes = []
    for pid in pids:
        try:
            running_hashes.append(sha256_file(f"/proc/{pid}/exe"))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    assert expected_hash in running_hashes, (
        "The process listening on port 8080 is not the binary built from the submitted "
        "pricing-engine project"
    )

    # Preserve the original crashing-rate check.
    value = request_value("0.3333333")
    assert 0.577 < value < 0.578, (
        f"Calculated value {value} is incorrect for rate=0.3333333. Expected ~0.577350."
    )

    # Exercise unpredictable inputs so a fixed response cannot satisfy the verifier.
    rng = random.SystemRandom()
    rates = [round(rng.uniform(0.01, 4.0), 7) for _ in range(10)]
    for rate in rates:
        value = request_value(format(rate, ".7f"))
        expected = math.sqrt(rate)
        assert math.isclose(value, expected, rel_tol=2e-6, abs_tol=2e-6), (
            f"Calculated value {value} is incorrect for rate={rate}; expected {expected}"
        )

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
