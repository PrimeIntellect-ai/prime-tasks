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
import socket
import subprocess
import time
import requests
import pytest

REPO = "/app/services/proxy_src"
REPRO = "/home/user/minimal_repro.sh"


def listening_pids(port):
    result = subprocess.run(
        ["bash", "-lc", f"fuser -n tcp {port} 2>/dev/null || true"],
        capture_output=True, text=True
    )
    return [int(x) for x in result.stdout.split() if x.isdigit()]


def proxy_pid():
    pids = listening_pids(9000)
    assert len(pids) == 1, f"Expected exactly one process listening on 9000, got {pids}"
    return pids[0]


def fd_count(pid):
    return len(os.listdir(f"/proc/{pid}/fd"))


def wait_http(timeout=10):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            response = requests.get("http://localhost:9000/", timeout=1)
            if response.status_code == 200:
                return
            last = f"HTTP {response.status_code}"
        except Exception as exc:
            last = exc
        time.sleep(0.1)
    pytest.fail(f"Proxy did not become healthy: {last}")


def test_source_build_and_running_binary():
    source = os.path.join(REPO, "main.cpp")
    assert os.path.isfile(source), f"Missing repaired source at {source}"

    running = proxy_pid()
    running_exe = os.path.realpath(f"/proc/{running}/exe")
    expected_exe = os.path.realpath(os.path.join(REPO, "proxy_daemon"))
    assert running_exe == expected_exe, (
        f"Port 9000 is served by {running_exe}, not the required {expected_exe}"
    )

    subprocess.run(["make", "clean"], cwd=REPO, check=True, capture_output=True, text=True)
    subprocess.run(["make"], cwd=REPO, check=True, capture_output=True, text=True)
    rebuilt = os.path.join(REPO, "proxy_daemon")
    assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK), "Rebuild did not produce proxy_daemon"

    # Restart using the freshly compiled artifact, so runtime checks exercise main.cpp.
    subprocess.run(["pkill", "-f", "/app/services/proxy_src/proxy_daemon"], check=False)
    subprocess.run(["pkill", "-x", "proxy_daemon"], check=False)
    deadline = time.time() + 5
    while time.time() < deadline and (listening_pids(9000) or listening_pids(9002)):
        time.sleep(0.1)
    proc = subprocess.Popen(
        [rebuilt], cwd=REPO, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True
    )
    wait_http()
    assert proc.poll() is None, "Freshly rebuilt proxy exited"
    assert os.path.realpath(f"/proc/{proxy_pid()}/exe") == os.path.realpath(rebuilt)


def test_minimal_repro_leaks_exactly_one_resource_on_bad_commit():
    assert os.path.isfile(REPRO), f"Missing minimal repro script at {REPRO}"
    assert os.access(REPRO, os.X_OK), f"Minimal repro is not executable: {REPRO}"

    # Build the historical bad source in an isolated worktree, then execute the
    # submitted reproducer once against it and measure the server's descriptors.
    result = subprocess.run(
        ["git", "log", "--grep=Refactor header parsing", "--format=%H"],
        cwd=REPO, capture_output=True, text=True, check=True
    )
    bad_hash = result.stdout.strip().splitlines()[0].strip()
    worktree = "/tmp/bad_proxy_worktree"
    subprocess.run(["rm", "-rf", worktree], check=True)
    subprocess.run(["git", "worktree", "prune"], cwd=REPO, check=True)
    subprocess.run(["git", "worktree", "add", "--detach", worktree, bad_hash], cwd=REPO, check=True,
                   capture_output=True, text=True)
    subprocess.run(["make", "clean"], cwd=worktree, check=True, capture_output=True, text=True)
    subprocess.run(["make"], cwd=worktree, check=True, capture_output=True, text=True)

    subprocess.run(["pkill", "-f", "/app/services/proxy_src/proxy_daemon"], check=False)
    subprocess.run(["pkill", "-x", "proxy_daemon"], check=False)
    deadline = time.time() + 5
    while time.time() < deadline and (listening_pids(9000) or listening_pids(9002)):
        time.sleep(0.1)
    bad_proc = subprocess.Popen(
        [os.path.join(worktree, "proxy_daemon")], cwd=worktree,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True
    )
    try:
        wait_http()
        pid = proxy_pid()
        before = fd_count(pid)
        run = subprocess.run(
            ["/bin/bash", REPRO], cwd="/home/user", timeout=10,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        assert run.returncode == 0, f"Minimal repro exited with status {run.returncode}"
        time.sleep(0.5)
        assert bad_proc.poll() is None, "Minimal repro killed the proxy instead of leaking one resource"
        after = fd_count(pid)
        assert after - before == 1, f"Expected exactly one leaked descriptor, observed delta {after - before}"
    finally:
        bad_proc.terminate()
        try:
            bad_proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            bad_proc.kill()
            bad_proc.wait()

    # Restore the freshly built repaired daemon for all remaining integration tests.
    subprocess.run(["make", "clean"], cwd=REPO, check=True, capture_output=True, text=True)
    subprocess.run(["make"], cwd=REPO, check=True, capture_output=True, text=True)
    fixed_proc = subprocess.Popen(
        [os.path.join(REPO, "proxy_daemon")], cwd=REPO,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True
    )
    wait_http()
    assert fixed_proc.poll() is None


def test_bad_commit_hash():
    path = "/home/user/bad_commit.txt"
    assert os.path.isfile(path), f"Missing bad commit file at {path}"
    with open(path, "r") as f:
        user_hash = f.read().strip()
    result = subprocess.run(
        ["git", "log", "--grep=Refactor header parsing", "--format=%H"],
        cwd=REPO, capture_output=True, text=True, check=True
    )
    expected_hash = result.stdout.strip().split("\n")[0].strip()
    assert expected_hash, "Could not find commit with message 'Refactor header parsing'"
    assert user_hash == expected_hash, f"Expected bad commit hash {expected_hash}, but got {user_hash}"


def test_proxy_http_basic():
    try:
        response = requests.get("http://localhost:9000/", timeout=5)
        assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
    except requests.RequestException as e:
        pytest.fail(f"Basic HTTP request to proxy failed: {e}")


def test_proxy_tcp_mgmt():
    try:
        with socket.create_connection(("localhost", 9002), timeout=5) as s:
            s.sendall(b"STATUS\n")
            data = s.recv(1024)
            response = data.decode("utf-8").strip()
            assert "PROXY_OK" in response, f"Expected PROXY_OK, got {response}"
    except Exception as e:
        pytest.fail(f"TCP management request to proxy failed: {e}")


def test_proxy_leak_fix():
    pid = proxy_pid()
    before = fd_count(pid)
    for _ in range(2000):
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(1)
            s.connect(("localhost", 9000))
            s.close()
        except Exception:
            pass
    time.sleep(1)
    after = fd_count(pid)
    assert after <= before + 3, f"Rebuilt proxy leaked descriptors: before={before}, after={after}"
    try:
        response = requests.get("http://localhost:9000/", timeout=5)
        assert response.status_code == 200, f"Expected HTTP 200 OK after leak test, got {response.status_code}"
    except requests.RequestException as e:
        pytest.fail(f"HTTP request to proxy failed after leak test (likely exhausted file descriptors): {e}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
