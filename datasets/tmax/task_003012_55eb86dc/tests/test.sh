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
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import socket
import subprocess
import time

import pytest
import requests

PROJECT = "/app/go-numcalc-v1.2.3"
BUILD_SCRIPT = os.path.join(PROJECT, "build.sh")
RUN_SCRIPT = os.path.join(PROJECT, "run.sh")
BINARY = os.path.join(PROJECT, "numcalc")


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, encoding="ascii") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        local_port = int(fields[1].rsplit(":", 1)[1], 16)
                        if local_port == port:
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
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def stop_existing_listeners():
    pids = (listener_pids(8080) | listener_pids(8081)) - {os.getpid()}
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass

    deadline = time.time() + 3
    while time.time() < deadline:
        if not (listener_pids(8080) | listener_pids(8081)):
            return
        time.sleep(0.1)

    for pid in listener_pids(8080) | listener_pids(8081):
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass

    deadline = time.time() + 2
    while time.time() < deadline:
        if not (listener_pids(8080) | listener_pids(8081)):
            return
        time.sleep(0.1)
    pytest.fail("Could not clear ports 8080 and 8081 before testing the scripts")


def wait_for_service_process():
    deadline = time.time() + 8
    while time.time() < deadline:
        tcp_pids = listener_pids(8080)
        http_pids = listener_pids(8081)
        common = tcp_pids & http_pids
        for pid in common:
            try:
                if os.path.samefile(f"/proc/{pid}/exe", BINARY):
                    return pid
            except (FileNotFoundError, OSError):
                pass
        time.sleep(0.1)
    pytest.fail("run.sh did not start the compiled numcalc binary on both required ports")


@pytest.fixture(scope="session", autouse=True)
def rebuild_and_start_with_scripts():
    for script in (BUILD_SCRIPT, RUN_SCRIPT):
        assert os.path.isfile(script), f"Required script {script} does not exist"
        assert os.access(script, os.X_OK), f"Required script {script} is not executable"
        syntax = subprocess.run(
            ["bash", "-n", script],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert syntax.returncode == 0, f"Bash syntax error in {script}: {syntax.stderr}"

    with open(RUN_SCRIPT, encoding="utf-8") as f:
        run_text = f.read()
    export_pattern = re.compile(
        r"^\s*export\s+AUTH_TOKEN\s*=\s*(?:calc_secure_99|'calc_secure_99'|\"calc_secure_99\")\s*(?:#.*)?$",
        re.MULTILINE,
    )
    assert export_pattern.search(run_text), "run.sh must export AUTH_TOKEN=calc_secure_99"

    stop_existing_listeners()
    try:
        os.remove(BINARY)
    except FileNotFoundError:
        pass

    clean_env = os.environ.copy()
    clean_env.pop("AUTH_TOKEN", None)

    build = subprocess.run(
        [BUILD_SCRIPT],
        cwd=PROJECT,
        env=clean_env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert build.returncode == 0, (
        f"build.sh failed with exit code {build.returncode}\n"
        f"stdout:\n{build.stdout}\nstderr:\n{build.stderr}"
    )
    assert os.path.isfile(BINARY), "build.sh did not create the numcalc binary"
    assert os.access(BINARY, os.X_OK), "numcalc produced by build.sh is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "numcalc is not a compiled ELF executable"

    build_info = subprocess.run(
        ["go", "version", "-m", BINARY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert build_info.returncode == 0, "numcalc is not a valid Go binary"
    assert re.search(r"(?m)^\s*path\s+go-numcalc\s*$", build_info.stdout), (
        "numcalc was not compiled from the go-numcalc module"
    )

    runner = subprocess.Popen(
        [RUN_SCRIPT],
        cwd=PROJECT,
        env=clean_env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        return_code = runner.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(runner.pid, signal.SIGKILL)
        pytest.fail("run.sh did not return after starting numcalc in the background")
    assert return_code == 0, f"run.sh exited with status {return_code}"

    service_pid = wait_for_service_process()
    with open(f"/proc/{service_pid}/environ", "rb") as f:
        environment = f.read().split(b"\0")
    assert b"AUTH_TOKEN=calc_secure_99" in environment, (
        "The numcalc process started by run.sh does not have the required AUTH_TOKEN"
    )

    yield


def test_binary_exists():
    binary_path = "/app/go-numcalc-v1.2.3/numcalc"
    assert os.path.isfile(binary_path), f"Expected compiled binary at {binary_path} does not exist."
    assert os.access(binary_path, os.X_OK), f"The file at {binary_path} is not executable."


def test_http_health_check():
    try:
        response = requests.get("http://localhost:8081/health", timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP health check at localhost:8081: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response, got: {response.text}")

    assert data.get("status") == "ok", f"Expected JSON {{'status': 'ok'}}, got {data}"


def test_tcp_protocol():
    try:
        s = socket.create_connection(("localhost", 8080), timeout=5)
    except socket.error as e:
        pytest.fail(f"Failed to connect to TCP service at localhost:8080: {e}")

    with s:
        def send_and_receive(msg: str) -> str:
            s.sendall(msg.encode("utf-8"))
            f = s.makefile("r", encoding="utf-8")
            return f.readline()

        auth_resp = send_and_receive("AUTH calc_secure_99\n")
        assert auth_resp.strip() == "OK", f"Expected 'OK' after AUTH, got {repr(auth_resp)}"

        eval_resp = send_and_receive("EVAL 5 + 5\n")
        assert eval_resp.strip() == "RESULT 10", f"Expected 'RESULT 10' after EVAL 5 + 5, got {repr(eval_resp)}"

        pi_resp = send_and_receive("CONCURRENT_PI 1000\n")
        assert pi_resp.strip() == "RESULT 3.141", f"Expected 'RESULT 3.141' after CONCURRENT_PI 1000, got {repr(pi_resp)}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
