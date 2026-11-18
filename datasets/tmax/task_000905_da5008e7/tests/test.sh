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
import pwd
import signal
import socket
import stat
import subprocess
import tempfile
import time
import uuid

import pytest
import requests

SOURCE = "/app/auth_proxy-1.2.3/auth_proxy/server.py"
DEPLOY = "/home/user/deploy.sh"
HEALTH = "/home/user/check_health.sh"
USERS = "/home/user/users.json"
VENV = "/home/user/venv"
URL = "http://127.0.0.1:9090/api/whoami"
EXPECTED_USERS = [
    {"username": "admin", "token": "super-secret-99", "group": "sysadmin"},
    {"username": "guest", "token": "guest-token-11", "group": "readonly"},
]


def run_as_user(argv, timeout=120):
    return subprocess.run(
        ["runuser", "-u", "user", "--", *argv],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def matching_service_pids():
    uid = pwd.getpwnam("user").pw_uid
    found = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        proc = f"/proc/{name}"
        try:
            if os.stat(proc).st_uid != uid:
                continue
            with open(f"{proc}/cmdline", "rb") as f:
                args = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        joined = "\0".join(args)
        if (
            "/home/user/venv/bin/auth-proxy" in joined
            and "--config" in args
            and "/home/user/users.json" in args
            and "--port" in args
            and "9090" in args
            and "--host" in args
            and "127.0.0.1" in args
        ):
            found.append(int(name))
    return found


def wait_for_response(url, headers=None, timeout=15):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            return requests.get(url, headers=headers, timeout=1)
        except requests.RequestException as exc:
            last = exc
            time.sleep(0.15)
    pytest.fail(f"Service at {url} did not become reachable: {last}")


def test_bug_fixed_in_server_py():
    assert os.path.isfile(SOURCE), f"server.py is missing: {SOURCE}"
    with open(SOURCE) as f:
        content = f.read()
    assert "Authorisation" not in content, "The typo 'Authorisation' was not fixed in server.py"
    assert "Authorization" in content, "The correct header 'Authorization' is missing in server.py"


def test_scripts_exist_and_are_executable():
    for path, label in [(DEPLOY, "Deployment"), (HEALTH, "Health check")]:
        assert os.path.isfile(path), f"{label} script missing: {path}"
        assert os.stat(path).st_mode & stat.S_IXUSR, f"{label} script is not executable: {path}"


def test_deployment_is_idempotent_and_installs_package():
    first = run_as_user([DEPLOY])
    assert first.returncode == 0, f"First deployment failed:\nstdout={first.stdout}\nstderr={first.stderr}"
    wait_for_response(URL, {"Authorization": "Bearer super-secret-99"})
    first_pids = matching_service_pids()
    assert len(first_pids) == 1, f"Expected exactly one deployed auth-proxy process, found {first_pids}"

    second = run_as_user([DEPLOY])
    assert second.returncode == 0, f"Second deployment failed:\nstdout={second.stdout}\nstderr={second.stderr}"
    wait_for_response(URL, {"Authorization": "Bearer super-secret-99"})
    second_pids = matching_service_pids()
    assert len(second_pids) == 1, f"Rerun left missing or orphaned auth-proxy processes: {second_pids}"
    assert first_pids[0] not in second_pids, "Deployment did not terminate the existing service instance"

    assert os.path.isdir(VENV), f"Virtual environment directory missing: {VENV}"
    python_bin = os.path.join(VENV, "bin", "python")
    proxy_bin = os.path.join(VENV, "bin", "auth-proxy")
    assert os.path.isfile(python_bin), f"Python binary missing in venv: {python_bin}"
    assert os.path.isfile(proxy_bin) and os.access(proxy_bin, os.X_OK), "Installed auth-proxy entry point is missing"

    installed = subprocess.run(
        [python_bin, "-c", "import auth_proxy.server; from importlib.metadata import version; print(version('auth_proxy')); print(auth_proxy.server.__file__)"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert installed.returncode == 0, f"auth_proxy is not importable from the venv: {installed.stderr}"
    assert installed.stdout.splitlines()[0].strip() == "1.2.3", "Wrong auth_proxy package version installed"


def test_users_json_exists_and_is_exact():
    assert os.path.isfile(USERS), f"users.json missing: {USERS}"
    try:
        with open(USERS) as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"Invalid JSON in {USERS}")
    assert "users" in data, "Key 'users' missing in users.json"
    for expected_user in EXPECTED_USERS:
        assert expected_user in data["users"], f"Expected user {expected_user} not found in users.json"
    assert data == {"users": EXPECTED_USERS}, "users.json must contain exactly the two specified users"


def test_service_running_and_responds_correctly():
    response = requests.get(URL, headers={"Authorization": "Bearer super-secret-99"}, timeout=5)
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    try:
        data = response.json()
    except json.JSONDecodeError:
        pytest.fail("Service did not return valid JSON")
    assert data.get("username") == "admin", "Expected username 'admin'"
    assert data.get("group") == "sysadmin", "Expected group 'sysadmin'"

    guest = requests.get(URL, headers={"Authorization": "Bearer guest-token-11"}, timeout=5)
    assert guest.status_code == 200
    assert guest.json() == {"username": "guest", "group": "readonly"}


def test_service_unauthorized_response():
    response = requests.get(URL, headers={"Authorization": "Bearer invalid-token"}, timeout=5)
    assert response.status_code == 401, f"Expected status code 401 for invalid token, got {response.status_code}"
    response = requests.get(URL, timeout=5)
    assert response.status_code == 401, f"Expected status code 401 for missing auth header, got {response.status_code}"
    response = requests.get(URL, headers={"Authorisation": "Bearer super-secret-99"}, timeout=5)
    assert response.status_code == 401, "The misspelled Authorisation header must not authenticate"


def test_health_script_actually_checks_service_with_curl():
    with open(HEALTH) as f:
        content = f.read()
    assert "curl" in content, "Health script must use curl"
    assert URL in content, "Health script does not target the required endpoint"
    assert "Authorization" in content and "Bearer" in content and "super-secret-99" in content, \
        "Health script does not send the required Authorization Bearer token"

    result = run_as_user([HEALTH], timeout=20)
    assert result.returncode == 0, f"Health script failed:\nstdout={result.stdout}\nstderr={result.stderr}"
    try:
        output = json.loads(result.stdout.strip())
    except json.JSONDecodeError:
        pytest.fail(f"Health script did not print the service JSON response: {result.stdout!r}")
    assert output == {"username": "admin", "group": "sysadmin"}


def test_installed_entrypoint_handles_derived_tokens_and_users():
    token = "tok-" + uuid.uuid4().hex
    username = "user-" + uuid.uuid4().hex[:10]
    group = "group-" + uuid.uuid4().hex[:10]
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]

    fd, config = tempfile.mkstemp(prefix="auth-proxy-test-", suffix=".json")
    os.close(fd)
    os.chmod(config, 0o644)
    with open(config, "w") as f:
        json.dump({"users": [{"username": username, "token": token, "group": group}]}, f)

    account = pwd.getpwnam("user")
    def demote():
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    proc = subprocess.Popen(
        [os.path.join(VENV, "bin", "auth-proxy"), "--config", config, "--port", str(port), "--host", "127.0.0.1"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        preexec_fn=demote,
        start_new_session=True,
    )
    dynamic_url = f"http://127.0.0.1:{port}/api/whoami"
    try:
        response = wait_for_response(dynamic_url, {"Authorization": f"Bearer {token}"})
        assert response.status_code == 200
        assert response.json() == {"username": username, "group": group}
        assert requests.get(dynamic_url, headers={"Authorization": "Bearer " + uuid.uuid4().hex}, timeout=3).status_code == 401
        assert requests.get(dynamic_url, headers={"Authorisation": f"Bearer {token}"}, timeout=3).status_code == 401
    finally:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait(timeout=5)
        os.unlink(config)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
