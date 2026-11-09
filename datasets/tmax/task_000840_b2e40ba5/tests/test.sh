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
import os
import signal
import subprocess
import time

import pytest
import requests

BINARY = "/app/ab_service/target/release/ab_service"
PORT_HEX = format(8888, "04X")
SERVICE_PROCESS = None


def listener_pids():
    inodes = set()
    with open("/proc/net/tcp", "r") as f:
        next(f)
        for line in f:
            fields = line.split()
            local_address = fields[1]
            state = fields[3]
            inode = fields[9]
            _, port = local_address.rsplit(":", 1)
            if port.upper() == PORT_HEX and state == "0A":
                inodes.add(inode)

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
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return pids


def assert_pid_runs_binary(pid):
    exe_path = f"/proc/{pid}/exe"
    assert os.path.exists(exe_path), f"Listening process {pid} has no executable."
    assert os.path.samefile(exe_path, BINARY), (
        f"Process {pid} serving port 8888 is not {BINARY}."
    )


def test_build_rs_fixed():
    """Verify that the build.rs file contains the fixed configuration."""
    build_rs_path = "/app/ab_service/build.rs"
    assert os.path.isfile(build_rs_path), f"The file {build_rs_path} does not exist."

    with open(build_rs_path, "r") as f:
        content = f.read()

    expected_line = 'println!("cargo:rustc-env=MATH_CONFIG=bayes_v1");'
    assert expected_line in content, "The build.rs file was not fixed correctly."


def test_csv_file_created_correctly():
    """Verify that the data.csv file was created with the exact content."""
    csv_path = "/home/user/data.csv"
    assert os.path.isfile(csv_path), f"The file {csv_path} does not exist."

    with open(csv_path, "r") as f:
        content = f.read().strip()

    expected_content = "variant_name,trials,successes\ncontrol,1000,150\ntreatment,1000,180"
    content_normalized = "\n".join([line.strip() for line in content.splitlines() if line.strip()])
    expected_normalized = "\n".join([line.strip() for line in expected_content.splitlines() if line.strip()])

    assert content_normalized == expected_normalized, "The data.csv file does not have the expected content."


def test_release_binary_exists_and_is_serving():
    """Require the release artifact to exist and already be the port-8888 server."""
    assert os.path.isfile(BINARY), f"Release binary {BINARY} does not exist."
    assert os.access(BINARY, os.X_OK), f"Release binary {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not an ELF executable."

    pids = listener_pids()
    assert pids, "No process is listening on port 8888."
    for pid in pids:
        assert_pid_runs_binary(pid)


def test_cargo_release_build_succeeds():
    """Verify that the project really succeeds under the requested release build."""
    result = subprocess.run(
        ["cargo", "build", "--release"],
        cwd="/app/ab_service",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, f"cargo build --release failed:\n{result.stdout}"
    assert os.path.isfile(BINARY), f"Release binary {BINARY} was not produced."
    assert os.access(BINARY, os.X_OK), f"Release binary {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not an ELF executable."


def test_service_running_and_responding():
    """Execute the built artifact and verify its authenticated HTTP behavior."""
    global SERVICE_PROCESS

    for pid in listener_pids():
        os.kill(pid, signal.SIGTERM)

    deadline = time.time() + 5
    while listener_pids() and time.time() < deadline:
        time.sleep(0.05)
    assert not listener_pids(), "The previous service did not stop cleanly."

    SERVICE_PROCESS = subprocess.Popen(
        [BINARY],
        cwd="/app/ab_service",
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    url = "http://127.0.0.1:8888/stats"
    headers = {"Authorization": "Token stat_token_99"}
    response = None
    deadline = time.time() + 10
    while time.time() < deadline:
        if SERVICE_PROCESS.poll() is not None:
            pytest.fail(f"The release binary exited with code {SERVICE_PROCESS.returncode}.")
        try:
            response = requests.get(url, headers=headers, timeout=1)
            break
        except (requests.exceptions.ConnectionError, requests.exceptions.Timeout):
            time.sleep(0.1)

    assert response is not None, "Could not connect to the service at 127.0.0.1:8888."
    pids = listener_pids()
    assert SERVICE_PROCESS.pid in pids, "The launched release binary is not serving port 8888."
    assert_pid_runs_binary(SERVICE_PROCESS.pid)

    assert response.status_code == 200, f"Expected status code 200, but got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail("The response from the service was not valid JSON.")

    assert "treatment_better_prob" in response.text, "The response JSON does not contain 'treatment_better_prob'."
    assert data == {"treatment_better_prob": 0.95}, f"Unexpected statistics response: {data!r}"

    unauthorized = requests.get(url, timeout=5)
    assert unauthorized.status_code == 401, (
        f"Expected unauthenticated request to return 401, got {unauthorized.status_code}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
