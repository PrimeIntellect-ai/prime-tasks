#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import subprocess
import tempfile
import time

import pytest

AGENT = "/home/user/metrics_agent.py"
RUN_ALL = "/home/user/run_all.sh"
STORAGE = "/home/user/app_storage"
DASHBOARD = "/home/user/dashboard.json"


def read_dashboard():
    assert os.path.exists(DASHBOARD), f"Output file {DASHBOARD} was not created."
    try:
        with open(DASHBOARD, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"{DASHBOARD} does not contain valid JSON.")

    assert set(data) == {"storage_bytes", "default_gateway", "status"}, \
        f"Dashboard has incorrect schema: {set(data)}"
    assert data["status"] == "active"
    assert isinstance(data["storage_bytes"], int) and not isinstance(data["storage_bytes"], bool)
    assert isinstance(data["default_gateway"], str)
    return data


def system_gateway():
    result = subprocess.run(["ip", "route"], capture_output=True, text=True)
    for line in result.stdout.splitlines():
        if line.startswith("default"):
            parts = line.split()
            if len(parts) >= 3:
                return parts[2]
    return None


def reset_storage(files):
    os.makedirs(STORAGE, exist_ok=True)
    for name in os.listdir(STORAGE):
        path = os.path.join(STORAGE, name)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)

    total = 0
    for relative, content in files.items():
        path = os.path.join(STORAGE, relative)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(content)
        total += len(content)
    return total


def make_fake_ip(directory, gateway):
    path = os.path.join(directory, "ip")
    with open(path, "w") as f:
        f.write("#!/bin/sh\n")
        f.write("[ \"$1\" = route ] || exit 2\n")
        f.write("printf '%s\\n' '172.20.0.0/16 dev test0 scope link' ")
        f.write("'default via %s dev test0 proto dhcp metric 77'\n" % gateway)
    os.chmod(path, 0o755)


def run_controlled_case(delay):
    if os.path.exists(DASHBOARD):
        os.unlink(DASHBOARD)

    first_size = 2048 + secrets.randbelow(4096)
    nested_size = 313 + secrets.randbelow(1700)
    expected = reset_storage({
        "initial_data.bin": os.urandom(first_size),
        "nested/deeper/metrics.bin": os.urandom(nested_size),
        "empty.dat": b"",
    })

    gateway = "10.%d.%d.%d" % (
        1 + secrets.randbelow(240),
        1 + secrets.randbelow(240),
        1 + secrets.randbelow(240),
    )

    with tempfile.TemporaryDirectory() as command_dir:
        make_fake_ip(command_dir, gateway)
        env = os.environ.copy()
        env["PATH"] = command_dir + os.pathsep + env.get("PATH", "")

        started = time.monotonic()
        proc = subprocess.Popen([AGENT], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, env=env)
        time.sleep(delay)

        # Create all application data before the dependency marker, avoiding the
        # app.sock/app.log race in the supplied mock application.
        log = os.urandom(701 + secrets.randbelow(1900))
        with open(os.path.join(STORAGE, "app.log"), "wb") as f:
            f.write(log)
        expected += len(log)

        sock_data = os.urandom(17 + secrets.randbelow(80))
        with open(os.path.join(STORAGE, "app.sock"), "wb") as f:
            f.write(sock_data)
        expected += len(sock_data)

        try:
            stdout, stderr = proc.communicate(timeout=4)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.communicate()
            pytest.fail("metrics_agent.py did not notice app.sock within the polling interval")
        elapsed = time.monotonic() - started

    assert proc.returncode == 0, \
        f"metrics_agent.py failed. stdout: {stdout}\nstderr: {stderr}"
    assert elapsed >= delay, "metrics_agent.py completed before app.sock was created"
    assert elapsed <= delay + 3.0, "metrics_agent.py did not poll for app.sock approximately once per second"

    data = read_dashboard()
    assert data["storage_bytes"] == expected, \
        f"Expected recursive file-size sum {expected}, got {data['storage_bytes']}"
    assert data["default_gateway"] == gateway, \
        f"Expected parsed gateway {gateway}, got {data['default_gateway']}"


def test_metrics_agent_execution_and_output():
    assert os.path.isfile(AGENT), f"{AGENT} is missing or is not a file."
    assert os.access(AGENT, os.X_OK), f"{AGENT} is not executable."
    assert os.path.exists(RUN_ALL), f"{RUN_ALL} is missing."

    try:
        result = subprocess.run([RUN_ALL], capture_output=True, text=True, timeout=30)
    except subprocess.TimeoutExpired:
        pytest.fail("run_all.sh timed out after 30 seconds. The metrics agent likely did not handle the startup dependency correctly.")

    assert result.returncode == 0, \
        f"run_all.sh failed with return code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"
    data = read_dashboard()
    assert data["storage_bytes"] >= 0

    expected_gateway = system_gateway()
    if expected_gateway:
        assert data["default_gateway"] == expected_gateway, \
            f"Expected default_gateway '{expected_gateway}', got '{data['default_gateway']}'"


def test_dynamic_storage_gateway_and_polling():
    # A short and a long startup exercise actual polling rather than a fixed sleep.
    run_controlled_case(1.2)
    run_controlled_case(5.2)


def test_dependency_timeout_is_bounded_and_not_immediate():
    if os.path.exists(DASHBOARD):
        os.unlink(DASHBOARD)
    reset_storage({"waiting.bin": os.urandom(100 + secrets.randbelow(500))})

    started = time.monotonic()
    try:
        result = subprocess.run([AGENT], capture_output=True, text=True, timeout=18.5)
    except subprocess.TimeoutExpired:
        pytest.fail("metrics_agent.py exceeded the required 15-second dependency wait")
    elapsed = time.monotonic() - started

    assert result.returncode != 0, "metrics_agent.py should fail if app.sock never appears"
    assert elapsed >= 13.0, "metrics_agent.py failed immediately instead of polling for up to 15 seconds"
    assert elapsed <= 18.0, "metrics_agent.py did not enforce a bounded dependency wait"
    assert not os.path.exists(DASHBOARD), "metrics_agent.py wrote active metrics without its dependency"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
