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
import ast
import hashlib
import importlib
import json
import os
import socket
import subprocess
import sys
import time
import uuid

import pytest
import requests

PACKAGE_DIR = "/app/vendored/legacy-sso-server-1.0.0"
CONFIG_PATH = os.path.join(PACKAGE_DIR, "config.json")
AUTH_PATH = os.path.join(PACKAGE_DIR, "legacy_sso", "auth.py")
SETUP_PATH = os.path.join(PACKAGE_DIR, "setup.py")
BASE_URL = "http://127.0.0.1:8080"


def recovered_password():
    with open(CONFIG_PATH, "r") as f:
        config = json.load(f)
    target = config.get("admin_hash", "b2f5ff47436671b6e533d8dc3614845d")
    with open("/app/wordlist.txt", "r") as f:
        matches = [w.strip() for w in f if hashlib.md5(w.strip().encode()).hexdigest() == target]
    assert len(matches) == 1, "Could not uniquely derive the admin password from the supplied hash and wordlist"
    return matches[0]


def wait_for_server(url, proc=None):
    deadline = time.time() + 10
    while time.time() < deadline:
        if proc is not None and proc.poll() is not None:
            pytest.fail("Vendored gateway exited before becoming ready")
        try:
            requests.get(url + "/admin", timeout=0.5)
            return
        except requests.RequestException:
            time.sleep(0.15)
    pytest.fail(f"Server did not become ready at {url}")


@pytest.fixture(scope="session")
def fresh_gateway():
    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()

    proc = subprocess.Popen(
        [sys.executable, "-m", "legacy_sso.server", "--port", str(port), "--config", "config.json"],
        cwd=PACKAGE_DIR,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    url = f"http://127.0.0.1:{port}"
    try:
        wait_for_server(url, proc)
        yield url
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()


def test_package_files_are_repaired_and_auth_logic_is_patched():
    assert os.path.isfile(AUTH_PATH), f"Missing {AUTH_PATH}"
    assert os.path.isfile(SETUP_PATH), f"Missing {SETUP_PATH}"

    subprocess.run([sys.executable, "-m", "py_compile", AUTH_PATH, SETUP_PATH], check=True)
    result = subprocess.run(
        [sys.executable, "setup.py", "--name"],
        cwd=PACKAGE_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert result.returncode == 0, f"setup.py is not functional: {result.stderr}"
    assert "legacy-sso-server" in result.stdout

    with open(SETUP_PATH, "r") as f:
        tree = ast.parse(f.read())
    requirements = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and getattr(node.func, "id", None) == "setup":
            for keyword in node.keywords:
                if keyword.arg == "install_requires":
                    requirements = ast.literal_eval(keyword.value)
    assert "Flask==2.0.0" in requirements, "setup.py must contain the corrected Flask requirement"

    sys.path.insert(0, PACKAGE_DIR)
    try:
        auth = importlib.import_module("legacy_sso.auth")
        auth = importlib.reload(auth)
    finally:
        sys.path.pop(0)

    class FakeRequest:
        def __init__(self, value):
            self.headers = {"X-Internal-Debug-Bypass": value}

    for value in ("true", "True", "1", uuid.uuid4().hex):
        assert auth.check_admin(FakeRequest(value)) is False, "The debug-header admin bypass remains active"

    password = recovered_password()
    config = {"admin_password_plaintext": password}
    assert auth.check_login("admin", password, config) is True
    assert auth.check_login("admin", password + uuid.uuid4().hex, config) is False
    assert auth.check_login("not-admin-" + uuid.uuid4().hex, password, config) is False


def test_config_updated():
    assert os.path.isfile(CONFIG_PATH), f"Config file not found at {CONFIG_PATH}"
    with open(CONFIG_PATH, "r") as f:
        data = json.load(f)
    assert "admin_password_plaintext" in data, "admin_password_plaintext missing from config.json"
    assert data["admin_password_plaintext"] == "supernova", "admin_password_plaintext value is incorrect in config.json"
    assert data["admin_password_plaintext"] == recovered_password()


def test_privilege_escalation_patched():
    try:
        response = requests.get(f"{BASE_URL}/admin", headers={"X-Internal-Debug-Bypass": "true"}, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to server: {e}")
    assert response.status_code in (401, 403), (
        f"Expected HTTP 401 or 403 for unauthorized access, but got {response.status_code}. "
        "The privilege escalation backdoor may not have been correctly patched."
    )


def test_login_and_secure_access():
    session = requests.Session()
    try:
        login_response = session.post(
            f"{BASE_URL}/login",
            json={"username": "admin", "password": "supernova"},
            timeout=5,
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to server for login: {e}")
    assert login_response.status_code == 200, f"Login failed. Expected HTTP 200, got {login_response.status_code}. Response: {login_response.text}"
    assert len(session.cookies) > 0, "No cookies were set by the login endpoint."
    try:
        admin_response = session.get(f"{BASE_URL}/admin", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to server for admin access: {e}")
    assert admin_response.status_code == 200, f"Admin access failed with valid session. Expected HTTP 200, got {admin_response.status_code}. Response: {admin_response.text}"


def exercise_gateway(url):
    password = recovered_password()

    for bypass_value in ("true", "True", "1", uuid.uuid4().hex):
        response = requests.get(
            url + "/admin",
            headers={"X-Internal-Debug-Bypass": bypass_value},
            timeout=5,
        )
        assert response.status_code in (401, 403)

    for username, candidate in (
        ("admin", password + uuid.uuid4().hex),
        ("user-" + uuid.uuid4().hex, password),
    ):
        response = requests.post(
            url + "/login",
            json={"username": username, "password": candidate},
            timeout=5,
        )
        assert response.status_code in (401, 403)

    session = requests.Session()
    login = session.post(
        url + "/login",
        json={"username": "admin", "password": password},
        timeout=5,
    )
    assert login.status_code == 200
    assert "auth_token" in session.cookies, "Login did not issue the gateway's authentication cookie"
    token = session.cookies.get("auth_token")
    assert token and token not in ("admin", password), "Authentication cookie exposes plaintext credentials"
    assert session.get(url + "/admin", timeout=5).status_code == 200

    arbitrary = requests.Session()
    arbitrary.cookies.set("auth_token", uuid.uuid4().hex)
    assert arbitrary.get(url + "/admin", timeout=5).status_code in (401, 403)

    tampered = requests.Session()
    replacement = ("A" if token[:1] != "A" else "B") + token[1:]
    tampered.cookies.set("auth_token", replacement)
    assert tampered.get(url + "/admin", timeout=5).status_code in (401, 403)


def test_vendored_gateway_itself_is_executable_and_secure(fresh_gateway):
    exercise_gateway(fresh_gateway)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
