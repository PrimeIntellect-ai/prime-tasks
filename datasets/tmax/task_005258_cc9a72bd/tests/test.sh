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
import secrets
import shlex
import signal
import subprocess
import time

import pytest
import requests

EXPERIMENT = "/home/user/experiment"
EXECUTABLE = os.path.join(EXPERIMENT, "mc_sim")
SCRIPT = os.path.join(EXPERIMENT, "server.sh")
PORT_HEX = "1F90"
BASE_BODY = b'{"steady_state": {"node0": 0.20, "node1": 0.32, "node2": 0.48}}\n'


def expected_output(values):
    f0, f1, f2 = values
    total = f0 + f1 + f2
    if total == 0:
        total = 1
    return (
        f'{{"steady_state": {{"node0": {f0 / total:.2f}, '
        f'"node1": {f1 / total:.2f}, "node2": {f2 / total:.2f}}}}}\n'
    ).encode()


def listener_inodes():
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as handle:
                next(handle, None)
                for line in handle:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == PORT_HEX and fields[3] == "0A":
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def listener_pids():
    inodes = listener_inodes()
    result = set()
    if not inodes:
        return result
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
                    result.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return result


def stop_existing_server():
    for _ in range(10):
        pids = listener_pids()
        if not pids:
            return
        for pid in pids:
            if pid not in (1, os.getpid(), os.getppid()):
                try:
                    os.kill(pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
        time.sleep(0.1)
    for pid in listener_pids():
        if pid not in (1, os.getpid(), os.getppid()):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    time.sleep(0.2)


def wait_for_server_group(process_group, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        for pid in listener_pids():
            try:
                if os.getpgid(pid) == process_group:
                    return
            except ProcessLookupError:
                pass
        time.sleep(0.05)
    pytest.fail("server.sh did not start a listener on TCP port 8080")


def test_mc_sim_compiled():
    """Check that mc_sim is an executable ELF implementing the supplied simulation."""
    assert os.path.isfile(EXECUTABLE), f"Compiled executable {EXECUTABLE} not found."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "mc_sim is not a compiled ELF executable"

    cases = [(5, 8, 12), (0, 0, 0)]
    rng = secrets.SystemRandom()
    cases.extend(tuple(rng.randint(1, 200) for _ in range(3)) for _ in range(3))
    for values in cases:
        completed = subprocess.run(
            [EXECUTABLE, *(str(value) for value in values)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=3,
            check=True,
        )
        assert completed.stdout == expected_output(values), (
            f"mc_sim produced incorrect stdout for arguments {values}: {completed.stdout!r}"
        )


def test_server_script_exists():
    """Check if the Bash server script was created and is syntactically valid."""
    assert os.path.isfile(SCRIPT), f"Server script {SCRIPT} not found."
    checked = subprocess.run(["bash", "-n", SCRIPT], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert checked.returncode == 0, f"server.sh is not valid Bash: {checked.stderr.decode(errors='replace')}"


def test_simulate_endpoint():
    """Execute server.sh and prove /simulate invokes ./mc_sim 5 8 12 verbatim."""
    stop_existing_server()
    server_process = subprocess.Popen(
        ["bash", SCRIPT],
        cwd=EXPERIMENT,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    backup = EXECUTABLE + ".verifier-backup"
    token = secrets.token_hex(24)
    log_path = f"/tmp/mc_sim_invocation_{token}"
    pad = 20 + secrets.randbelow(80)
    response_body = BASE_BODY[:-1] + (b" " * pad) + b"\n"
    replaced = False

    try:
        wait_for_server_group(server_process.pid)

        os.replace(EXECUTABLE, backup)
        wrapper = (
            "#!/bin/bash\n"
            "{\n"
            f"  printf '%s\\n' {shlex.quote(token)}\n"
            "  printf '%s\\n' \"$@\"\n"
            f"}} > {shlex.quote(log_path)}\n"
            f"printf '%s' {shlex.quote(response_body.decode())}\n"
        )
        with open(EXECUTABLE, "w") as handle:
            handle.write(wrapper)
        os.chmod(EXECUTABLE, 0o755)
        replaced = True

        url = "http://localhost:8080/simulate"
        session = requests.Session()
        session.trust_env = False
        try:
            response = session.get(url, timeout=5)
        except requests.exceptions.RequestException as error:
            pytest.fail(f"Failed to connect to the server at {url}. Is it running? Error: {error}")

        assert response.status_code == 200, (
            f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"
        )

        try:
            data = response.json()
        except json.JSONDecodeError:
            pytest.fail(f"Response body is not valid JSON. Response body: {response.text}")

        expected = {"steady_state": {"node0": 0.20, "node1": 0.32, "node2": 0.48}}
        assert data == expected, f"Expected {expected}, but got {data}"
        assert response.content == response_body, (
            "HTTP response body was not exactly the stdout produced by mc_sim"
        )

        assert os.path.isfile(log_path), "The endpoint did not execute ./mc_sim"
        with open(log_path) as handle:
            invocation = handle.read().splitlines()
        assert invocation == [token, "5", "8", "12"], (
            f"Expected ./mc_sim 5 8 12, but recorded invocation was {invocation!r}"
        )
    finally:
        if replaced:
            try:
                os.unlink(EXECUTABLE)
            except FileNotFoundError:
                pass
            os.replace(backup, EXECUTABLE)
        try:
            os.unlink(log_path)
        except FileNotFoundError:
            pass
        try:
            os.killpg(server_process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
