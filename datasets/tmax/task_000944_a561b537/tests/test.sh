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
import shutil
import signal
import socket
import subprocess
import time
import uuid

import pytest
import requests

DEPLOY_SCRIPT = "/home/user/deploy.py"
STORAGE_DIR = "/home/user/app_data/storage"
VENDORED_DIR = "/app/vendored/py-state-manager-1.0.0"
APP_PATH = os.path.join(VENDORED_DIR, "app.py")


def listener_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == "0A":
                        if fields[1].rsplit(":", 1)[-1].upper() == wanted:
                            inodes.add(fields[9])
        except OSError:
            pass

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
        except OSError:
            continue
    return pids


def stop_listeners(port):
    pids = listener_pids(port)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listener_pids(port):
        time.sleep(0.05)
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids(port):
        time.sleep(0.05)
    assert not listener_pids(port), f"Could not clear existing listener on port {port}"


def process_environment(pid):
    with open(f"/proc/{pid}/environ", "rb") as f:
        entries = f.read().split(b"\0")
    env = {}
    for entry in entries:
        if b"=" in entry:
            key, value = entry.split(b"=", 1)
            env[key.decode(errors="replace")] = value.decode(errors="replace")
    return env


def process_runs_vendored_app(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        argv = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
    try:
        cwd = os.readlink(f"/proc/{pid}/cwd")
    except OSError:
        cwd = ""
    for arg in argv[1:]:
        candidate = arg if os.path.isabs(arg) else os.path.join(cwd, arg)
        if os.path.realpath(candidate) == os.path.realpath(APP_PATH):
            return True
    return False


@pytest.fixture(scope="session", autouse=True)
def freshly_run_deployment():
    assert os.path.isfile(DEPLOY_SCRIPT), f"Deploy script {DEPLOY_SCRIPT} is missing."
    stop_listeners(9090)
    shutil.rmtree("/home/user/app_data", ignore_errors=True)

    try:
        result = subprocess.run(
            ["python3", DEPLOY_SCRIPT],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
    except subprocess.TimeoutExpired as exc:
        pytest.fail(f"Deployment script did not exit cleanly after starting the background service: {exc}")

    assert result.returncode == 0, (
        f"Deployment script exited with {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert "Deployment successful" in result.stdout, (
        f"Deployment script did not print the required success message: {result.stdout!r}"
    )

    # The script is required to wait for readiness before it exits, so the
    # listener must exist immediately after subprocess.run returns.
    pids = listener_pids(9090)
    assert pids, "No background service is listening on port 9090 after deploy.py exited."
    yield result


def test_deploy_script_exists():
    """Check if the deployment script was created."""
    assert os.path.isfile(DEPLOY_SCRIPT), f"Deploy script {DEPLOY_SCRIPT} is missing."


def test_deployment_process_and_environment():
    """Ensure deploy.py started the vendored application with the required environment."""
    pids = listener_pids(9090)
    assert pids, "The deployed service is not listening on port 9090."
    matching = []
    for pid in pids:
        try:
            env = process_environment(pid)
            if process_runs_vendored_app(pid):
                matching.append((pid, env))
        except OSError:
            continue
    assert matching, "The port 9090 listener is not the vendored py-state-manager app.py."
    assert any(
        env.get("HOST") == "127.0.0.1"
        and env.get("PORT") == "9090"
        and env.get("AUTH_TOKEN") == "DeployMagic99"
        and env.get("STORAGE_DIR") == STORAGE_DIR
        for _, env in matching
    ), "The vendored service was not started with the required environment variables."


def test_storage_dir_permissions():
    """Check if the target storage directory exists and has 0755 permissions."""
    assert os.path.isdir(STORAGE_DIR), f"Target directory {STORAGE_DIR} is missing."
    st = os.stat(STORAGE_DIR)
    permissions = oct(st.st_mode & 0o777)
    assert permissions == '0o755', f"Expected permissions 0o755 for {STORAGE_DIR}, but got {permissions}."


def test_service_running_and_writing():
    """Test the service via HTTP and verify filesystem state."""
    base_url = "http://127.0.0.1:9090"
    headers = {"Authorization": "Bearer DeployMagic99"}
    payload = {"data": "healthcheck_123"}

    try:
        r_post = requests.post(f"{base_url}/write", json=payload, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {base_url}/write: {e}")
    assert r_post.status_code == 200, f"Expected 200 OK for POST /write, got {r_post.status_code}. Response: {r_post.text}"

    try:
        r_get = requests.get(f"{base_url}/read", headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {base_url}/read: {e}")
    assert r_get.status_code == 200, f"Expected 200 OK for GET /read, got {r_get.status_code}. Response: {r_get.text}"

    try:
        response_json = r_get.json()
    except ValueError:
        pytest.fail(f"Response from GET /read is not valid JSON: {r_get.text}")
    assert response_json.get("data") == "healthcheck_123", f"Expected data 'healthcheck_123' in GET /read response, got {response_json}"

    state_file = os.path.join(STORAGE_DIR, "state.json")
    assert os.path.isfile(state_file), f"State file {state_file} was not created. The service might still be writing to the wrong location."
    with open(state_file, "r") as f:
        try:
            file_data = json.load(f)
        except ValueError:
            pytest.fail(f"State file {state_file} does not contain valid JSON.")
    assert file_data.get("data") == "healthcheck_123", f"Expected data 'healthcheck_123' in {state_file}, got {file_data}"

    random_value = uuid.uuid4().hex
    random_payload = {"data": random_value, "nonce": uuid.uuid4().hex}
    unauthorized = requests.post(f"{base_url}/write", json=random_payload, timeout=5)
    assert unauthorized.status_code == 401, "The deployed service accepted a request without the configured token."
    written = requests.post(f"{base_url}/write", json=random_payload, headers=headers, timeout=5)
    assert written.status_code == 200, written.text
    read_back = requests.get(f"{base_url}/read", headers=headers, timeout=5)
    assert read_back.status_code == 200, read_back.text
    assert read_back.json() == random_payload
    with open(state_file, "r") as f:
        assert json.load(f) == random_payload


def test_vendored_package_respects_storage_dir_directly(tmp_path):
    """Run the vendored release directly with STORAGE_DIR as its only storage setting."""
    direct_storage = tmp_path / "direct-storage"
    token = "token-" + uuid.uuid4().hex
    payload = {"value": uuid.uuid4().hex, "sequence": [1, 3, 7]}

    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()

    env = os.environ.copy()
    env.pop("STORAG_DIR", None)
    env.update({
        "HOST": "127.0.0.1",
        "PORT": str(port),
        "AUTH_TOKEN": token,
        "STORAGE_DIR": str(direct_storage),
    })
    proc = subprocess.Popen(
        ["python3", APP_PATH],
        cwd=VENDORED_DIR,
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        base_url = f"http://127.0.0.1:{port}"
        deadline = time.time() + 10
        while time.time() < deadline:
            if proc.poll() is not None:
                pytest.fail(f"Vendored application exited early with code {proc.returncode}")
            try:
                response = requests.get(
                    f"{base_url}/read",
                    headers={"Authorization": f"Bearer {token}"},
                    timeout=0.5,
                )
                if response.status_code == 200:
                    break
            except requests.RequestException:
                pass
            time.sleep(0.05)
        else:
            pytest.fail("Vendored application did not start on its configured port.")

        headers = {"Authorization": f"Bearer {token}"}
        response = requests.post(f"{base_url}/write", json=payload, headers=headers, timeout=3)
        assert response.status_code == 200, response.text
        response = requests.get(f"{base_url}/read", headers=headers, timeout=3)
        assert response.status_code == 200, response.text
        assert response.json() == payload

        state_file = direct_storage / "state.json"
        assert state_file.is_file(), "Vendored app ignored STORAGE_DIR when run directly."
        with state_file.open() as f:
            assert json.load(f) == payload
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=3)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
