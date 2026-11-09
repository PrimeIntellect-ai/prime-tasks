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
import random
import re
import shutil
import signal
import string
import subprocess
import time
from pathlib import Path

import pytest
import requests

ROLES_PATH = Path("/home/user/roles.json")
DEPLOY_PATH = Path("/home/user/deploy.exp")
GATEWAY_MANIFEST = Path("/home/user/gateway/Cargo.toml")
VM_CONSOLE = Path("/app/vm_console.sh")


def read_config_from_image():
    result = subprocess.run(
        ["tesseract", "/app/deploy_config.png", "stdout"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, f"OCR failed: {result.stderr}"
    token_match = re.search(r"AUTH_TOKEN:\s*([^\s]+)", result.stdout)
    port_match = re.search(r"PORT:\s*(\d+)", result.stdout)
    assert token_match, f"Could not extract AUTH_TOKEN from image OCR: {result.stdout!r}"
    assert port_match, f"Could not extract PORT from image OCR: {result.stdout!r}"
    return token_match.group(1), int(port_match.group(1))


AUTH_TOKEN, PORT = read_config_from_image()
assert AUTH_TOKEN == "S3cr3t_R0ll0ut", f"Unexpected OCR token: {AUTH_TOKEN!r}"
assert PORT == 8181, f"Unexpected OCR port: {PORT}"
BASE_URL = f"http://127.0.0.1:{PORT}"


def test_roles_json_exists_and_valid():
    path = "/home/user/roles.json"
    assert os.path.exists(path), f"{path} does not exist"

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{path} is not valid JSON")

    assert "users" in data, "Key 'users' missing in roles.json"
    assert "release_bot" in data["users"], "User 'release_bot' missing in roles.json"
    assert data["users"]["release_bot"].get("group") == "deployment_admins", "User 'release_bot' is not in 'deployment_admins' group"
    assert data == {
        "users": {"release_bot": {"group": "deployment_admins"}}
    }, "roles.json does not have the exact required structure"


def test_deploy_exp_exists():
    path = "/home/user/deploy.exp"
    assert os.path.exists(path), f"{path} does not exist"
    assert os.path.isfile(path), f"{path} is not a regular file"
    assert os.access(path, os.X_OK), f"{path} is not executable"


def test_deploy_exp_drives_vm_console_correctly(tmp_path):
    transcript = tmp_path / "vm-input.txt"
    original_console = VM_CONSOLE.read_bytes()
    original_mode = VM_CONSOLE.stat().st_mode
    harness = f'''#!/bin/bash
set -e
printf 'login: '
IFS= read -r username
printf '%s\\n' "$username" >> {str(transcript)!r}
printf 'Password: '
IFS= read -r password
printf '%s\\n' "$password" >> {str(transcript)!r}
printf 'root@vm:~# '
IFS= read -r command
printf '%s\\n' "$command" >> {str(transcript)!r}
printf 'root@vm:~# '
IFS= read -r command
printf '%s\\n' "$command" >> {str(transcript)!r}
[ "$username" = admin ]
[ "$password" = root123 ]
'''
    try:
        VM_CONSOLE.write_text(harness)
        os.chmod(VM_CONSOLE, 0o755)
        result = subprocess.run(
            [str(DEPLOY_PATH)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"deploy.exp failed against the VM console (exit {result.returncode}). "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        assert transcript.exists(), "deploy.exp did not interact with /app/vm_console.sh"
        assert transcript.read_text().splitlines() == [
            "admin",
            "root123",
            "touch /opt/deploy_success.flag",
            "exit",
        ], "deploy.exp sent the wrong login credentials or VM commands"
    finally:
        VM_CONSOLE.write_bytes(original_console)
        os.chmod(VM_CONSOLE, original_mode & 0o7777)


def test_rust_project_exists():
    path = "/home/user/gateway/Cargo.toml"
    assert os.path.exists(path), f"Rust project Cargo.toml not found at {path}"
    assert os.path.isfile(path), f"{path} is not a regular file"
    sources = list(Path("/home/user/gateway").glob("src/**/*.rs"))
    assert sources, "Rust project contains no .rs source files"


def kill_port_listener(port):
    inodes = set()
    port_hex = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == port_hex and fields[3] == "0A":
                inodes.add(fields[9])

    victims = set()
    for proc_dir in Path("/proc").glob("[0-9]*"):
        try:
            for fd in (proc_dir / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    victims.add(int(proc_dir.name))
        except OSError:
            continue

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    if victims:
        time.sleep(0.5)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def build_gateway():
    target_dir = Path("/tmp/verifier-gateway-target")
    shutil.rmtree(target_dir, ignore_errors=True)
    command = [
        "cargo", "build",
        "--manifest-path", str(GATEWAY_MANIFEST),
        "--target-dir", str(target_dir),
        "--message-format=json-render-diagnostics",
    ]
    result = subprocess.run(
        command,
        cwd="/home/user/gateway",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert result.returncode == 0, f"Cargo build failed:\n{result.stdout}\n{result.stderr}"

    executables = []
    for line in result.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        executable = message.get("executable")
        target = message.get("target", {})
        if executable and "bin" in target.get("kind", []):
            executables.append(executable)
    assert executables, "Cargo build produced no Rust binary executable"
    executable = Path(executables[-1])
    assert executable.is_file() and os.access(executable, os.X_OK), "Built Rust gateway is not executable"
    return executable


@pytest.fixture(scope="module")
def running_gateway():
    original_roles = ROLES_PATH.read_bytes()
    original_deploy = DEPLOY_PATH.read_bytes()
    original_deploy_mode = DEPLOY_PATH.stat().st_mode
    suffix = "".join(random.SystemRandom().choices(string.ascii_lowercase + string.digits, k=14))
    admin_user = f"admin_{suffix}"
    ordinary_user = f"viewer_{suffix}"
    probe_path = Path(f"/tmp/deploy-probe-{suffix}.log")

    dynamic_roles = {
        "users": {
            "release_bot": {"group": "deployment_admins"},
            admin_user: {"group": "deployment_admins"},
            ordinary_user: {"group": "read_only"},
        }
    }
    ROLES_PATH.write_text(json.dumps(dynamic_roles))
    DEPLOY_PATH.write_text(f"#!/bin/sh\nprintf 'invoked\\n' >> {probe_path}\nexit 0\n")
    os.chmod(DEPLOY_PATH, 0o755)

    process = None
    try:
        kill_port_listener(PORT)
        executable = build_gateway()
        process = subprocess.Popen(
            [str(executable)],
            cwd="/home/user/gateway",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        deadline = time.time() + 12
        while time.time() < deadline:
            assert process.poll() is None, "Built Rust gateway exited before accepting requests"
            try:
                requests.post(f"{BASE_URL}/deploy", json={"username": "release_bot"}, timeout=0.4)
                break
            except requests.RequestException:
                time.sleep(0.15)
        else:
            pytest.fail("Built Rust gateway did not start listening on the OCR-derived port")

        yield {
            "process": process,
            "admin_user": admin_user,
            "ordinary_user": ordinary_user,
            "probe_path": probe_path,
        }
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=3)
        ROLES_PATH.write_bytes(original_roles)
        DEPLOY_PATH.write_bytes(original_deploy)
        os.chmod(DEPLOY_PATH, original_deploy_mode & 0o7777)
        try:
            probe_path.unlink()
        except FileNotFoundError:
            pass


def probe_count(state):
    path = state["probe_path"]
    return len(path.read_text().splitlines()) if path.exists() else 0


def test_gateway_unauthorized(running_gateway):
    url = "http://127.0.0.1:8181/deploy"
    headers = {"Content-Type": "application/json"}
    body = {"username": "release_bot"}

    try:
        resp = requests.post(url, headers=headers, json=body, timeout=5)
        assert resp.status_code == 401, f"Expected 401 Unauthorized for missing auth token, got {resp.status_code}. Response: {resp.text}"
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to gateway service: {e}")


def test_gateway_rejects_random_invalid_token(running_gateway):
    bad_token = AUTH_TOKEN + "_" + "".join(random.SystemRandom().choices(string.ascii_letters, k=12))
    before = probe_count(running_gateway)
    resp = requests.post(
        f"{BASE_URL}/deploy",
        headers={"Authorization": f"Bearer {bad_token}"},
        json={"username": running_gateway["admin_user"]},
        timeout=5,
    )
    assert resp.status_code == 401, f"Invalid randomized token returned {resp.status_code}: {resp.text}"
    assert probe_count(running_gateway) == before, "Deployment script ran for an invalid token"


def test_gateway_forbidden(running_gateway):
    url = "http://127.0.0.1:8181/deploy"
    headers = {
        "Authorization": "Bearer S3cr3t_R0ll0ut",
        "Content-Type": "application/json"
    }
    body = {"username": "unknown_user"}

    try:
        resp = requests.post(url, headers=headers, json=body, timeout=5)
        assert resp.status_code == 403, f"Expected 403 Forbidden for unknown user, got {resp.status_code}. Response: {resp.text}"
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to gateway service: {e}")


def test_gateway_uses_roles_json_for_random_non_admin(running_gateway):
    before = probe_count(running_gateway)
    resp = requests.post(
        f"{BASE_URL}/deploy",
        headers={"Authorization": f"Bearer {AUTH_TOKEN}"},
        json={"username": running_gateway["ordinary_user"]},
        timeout=5,
    )
    assert resp.status_code == 403, f"Non-admin user returned {resp.status_code}: {resp.text}"
    assert probe_count(running_gateway) == before, "Deployment script ran for a non-admin user"


def test_gateway_success(running_gateway):
    url = "http://127.0.0.1:8181/deploy"
    headers = {
        "Authorization": "Bearer S3cr3t_R0ll0ut",
        "Content-Type": "application/json"
    }
    body = {"username": "release_bot"}
    before = probe_count(running_gateway)

    try:
        resp = requests.post(url, headers=headers, json=body, timeout=10)
        assert resp.status_code == 200, f"Expected 200 OK for valid request, got {resp.status_code}. Response: {resp.text}"

        try:
            data = resp.json()
        except ValueError:
            pytest.fail(f"Expected JSON response, got: {resp.text}")

        assert data.get("status") == "deployed", f"Expected {{'status': 'deployed'}}, got {data}"
        assert probe_count(running_gateway) == before + 1, "Gateway did not execute /home/user/deploy.exp"
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to gateway service: {e}")


def test_gateway_authorizes_random_admin_from_roles_file(running_gateway):
    before = probe_count(running_gateway)
    resp = requests.post(
        f"{BASE_URL}/deploy",
        headers={"Authorization": f"Bearer {AUTH_TOKEN}"},
        json={"username": running_gateway["admin_user"]},
        timeout=10,
    )
    assert resp.status_code == 200, f"Random admin from roles.json returned {resp.status_code}: {resp.text}"
    assert resp.json().get("status") == "deployed"
    assert probe_count(running_gateway) == before + 1, "Gateway did not invoke deploy.exp for the randomized admin"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
