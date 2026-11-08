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
echo "0" > /logs/verifier/reward.txt

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.metadata
import json
import os
import secrets
import signal
import socket
import stat
import subprocess
import sys
import time

import pytest
import requests

SERVER_PATH = "/home/user/server.py"
PATCH_PATH = "/home/user/py2num_migration.patch"
LOG_PATH = "/home/user/server.log"
URL = "http://127.0.0.1:8080/compute"
AUTH = {"X-Migration-Auth": "99887766"}


def expected_sum(n):
    return n * (n + 1) * (2 * n + 1) // 6


def listening_pids(port=8080):
    inodes = set()
    wanted_port = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[1].split(":")[-1] == wanted_port and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    result = set()
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
                    result.add(int(name))
                    break
        except OSError:
            pass
    return result


def stop_existing_server():
    pids = listening_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listening_pids():
        time.sleep(0.05)
    for pid in listening_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


@pytest.fixture(scope="session", autouse=True)
def run_submitted_server():
    assert os.path.isfile(SERVER_PATH), f"Server source missing at {SERVER_PATH}"
    subprocess.run([sys.executable, "-m", "py_compile", SERVER_PATH], check=True)

    stop_existing_server()
    verifier_log = open("/tmp/verifier-server.log", "wb")
    proc = subprocess.Popen(
        [sys.executable, SERVER_PATH],
        cwd="/home/user",
        stdout=verifier_log,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )

    deadline = time.time() + 10
    while time.time() < deadline:
        if proc.poll() is not None:
            verifier_log.flush()
            with open("/tmp/verifier-server.log", "rb") as f:
                pytest.fail(f"server.py exited during startup:\n{f.read().decode(errors='replace')}")
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=0.2):
                break
        except OSError:
            time.sleep(0.05)
    else:
        pytest.fail("server.py did not listen on 127.0.0.1:8080")

    yield proc
    # Deliberately leave the successfully tested service running, as requested.


def test_patch_file_exists_and_contains_diffs():
    assert os.path.isfile(PATCH_PATH), f"Patch file missing at {PATCH_PATH}"
    with open(PATCH_PATH, "r", errors="replace") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "setup.py" in content, "Patch file does not contain changes for setup.py"
    assert "core.py" in content, "Patch file does not contain changes for core.py"

    # It must be a real unified patch documenting both Python 2 compatibility fixes.
    assert "--- " in content and "+++ " in content and "@@" in content
    assert any(line.startswith("-") and 'print "Installing py2num..."' in line for line in content.splitlines())
    assert any(line.startswith("-") and "xrange(1, long(n) + 1)" in line for line in content.splitlines())

    reverse_ok = False
    for cwd in ("/app/vendored/py2num", "/app/vendored", "/"):
        result = subprocess.run(
            ["git", "apply", "--check", "--reverse", PATCH_PATH],
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if result.returncode == 0:
            reverse_ok = True
            break
    assert reverse_ok, "Patch is not a valid unified diff of the current vendored package"


def test_vendored_package_is_fixed_and_installed():
    setup_path = "/app/vendored/py2num/setup.py"
    core_path = "/app/vendored/py2num/py2num/core.py"
    subprocess.run([sys.executable, "-m", "py_compile", setup_path, core_path], check=True)

    with open(core_path, "r") as f:
        core = f.read()
    assert "xrange" not in core and "long(" not in core

    # Distribution metadata proves that installation, rather than source presence alone, occurred.
    assert importlib.metadata.version("py2num"), "py2num is not installed"

    values = [secrets.randbelow(100000) + 1 for _ in range(5)]
    code = (
        "import json; from py2num import sum_of_squares; "
        f"xs={values!r}; print(json.dumps([sum_of_squares(x) for x in xs]))"
    )
    env = os.environ.copy()
    env.pop("PYTHONPATH", None)
    output = subprocess.check_output([sys.executable, "-c", code], cwd="/tmp", env=env, text=True)
    assert json.loads(output.strip().splitlines()[-1]) == [expected_sum(n) for n in values]


def test_server_log_exists():
    assert os.path.exists(LOG_PATH), f"Server log missing at {LOG_PATH}"
    mode = os.stat(LOG_PATH).st_mode
    assert stat.S_ISREG(mode), "Server log is not a regular file"
    assert os.path.getsize(LOG_PATH) > 0, "Server log is empty and does not record startup"


def test_api_missing_auth():
    response = requests.post(URL, json={"n": 10}, timeout=2)
    assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}"


def test_api_incorrect_auth():
    response = requests.post(URL, json={"n": 10}, headers={"X-Migration-Auth": "wrong"}, timeout=2)
    assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}"


def test_api_invalid_payload():
    response = requests.post(URL, data="not a json", headers=AUTH, timeout=2)
    assert response.status_code == 400, f"Expected 400 Bad Request, got {response.status_code}"
    response = requests.post(URL, json={"wrong": 10}, headers=AUTH, timeout=2)
    assert response.status_code == 400, f"Expected 400 Bad Request, got {response.status_code}"


def assert_computation(n, timeout=5):
    response = requests.post(URL, json={"n": n}, headers=AUTH, timeout=timeout)
    assert response.status_code == 200, f"Expected 200 OK for n={n}, got {response.status_code}"
    assert "application/json" in response.headers.get("Content-Type", "").lower()
    assert response.json().get("result") == expected_sum(n), f"Incorrect result for n={n}"


def test_api_valid_computations():
    # Preserve the original fixed cases, then add unpredictable derived cases.
    assert_computation(5)
    assert_computation(100)
    for _ in range(8):
        assert_computation(secrets.randbelow(900000) + 1000)


def process_tree_rss_mb(root_pid):
    parent = {}
    rss_kb = {}
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            ppid = None
            rss = 0
            with open(f"/proc/{name}/status") as f:
                for line in f:
                    if line.startswith("PPid:"):
                        ppid = int(line.split()[1])
                    elif line.startswith("VmRSS:"):
                        rss = int(line.split()[1])
            parent[int(name)] = ppid
            rss_kb[int(name)] = rss
        except (OSError, ValueError):
            pass

    included = {root_pid}
    changed = True
    while changed:
        changed = False
        for pid, ppid in parent.items():
            if ppid in included and pid not in included:
                included.add(pid)
                changed = True
    return sum(rss_kb.get(pid, 0) for pid in included) / 1024.0


def test_memory_leak_fixed(run_submitted_server):
    pid = run_submitted_server.pid
    assert run_submitted_server.poll() is None
    peak_mb = process_tree_rss_mb(pid)

    # Exercise the stated workload and validate every large response, rather than
    # allowing a low-memory placeholder result to satisfy the memory check.
    n = 5_000_000
    answer = expected_sum(n)
    for _ in range(200):
        response = requests.post(URL, json={"n": n}, headers=AUTH, timeout=10)
        assert response.status_code == 200
        assert response.json().get("result") == answer
        peak_mb = max(peak_mb, process_tree_rss_mb(pid))

    assert run_submitted_server.poll() is None, "Server exited during the memory workload"
    assert peak_mb < 100, f"Memory usage is too high: {peak_mb:.2f} MB"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
fi
