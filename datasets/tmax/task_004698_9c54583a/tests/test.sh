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

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pwd
import stat
import subprocess
import time
import uuid

import pytest
import requests

CONFIG = "/home/user/capacity_config.json"
API = "/home/user/planner_api.py"
UNIT = "/home/user/.config/systemd/user/capacity-planner.service"
URL = "http://127.0.0.1:8123/api/v1/capacity"
USER = pwd.getpwnam("user")


def user_systemctl(*args, check=True):
    runtime = f"/run/user/{USER.pw_uid}"
    env_args = [
        f"HOME={USER.pw_dir}",
        f"USER={USER.pw_name}",
        f"LOGNAME={USER.pw_name}",
        f"XDG_RUNTIME_DIR={runtime}",
        f"DBUS_SESSION_BUS_ADDRESS=unix:path={runtime}/bus",
    ]
    return subprocess.run(
        ["runuser", "-u", "user", "--", "env", *env_args,
         "systemctl", "--user", *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=check,
    )


def auth_pin():
    digits = format(stat.S_IMODE(os.stat("/app/init_capacity_db.sh").st_mode), "03o")
    return digits + digits


def request_capacity(pin=None):
    return requests.get(
        URL,
        headers={"X-Planner-Auth": pin if pin is not None else auth_pin()},
        timeout=5,
    )


def wait_for_api():
    last = None
    for _ in range(30):
        try:
            response = request_capacity()
            if response.status_code == 200:
                return
            last = f"HTTP {response.status_code}: {response.text}"
        except requests.RequestException as exc:
            last = str(exc)
        time.sleep(0.2)
    pytest.fail(f"Capacity API did not become ready after systemd restart: {last}")


@pytest.fixture(scope="session", autouse=True)
def managed_service():
    assert os.path.isfile(API), f"Python service {API} is missing or is not a regular file"
    assert os.path.isfile(UNIT), f"Systemd user service file {UNIT} is missing or is not regular"

    verify = subprocess.run(
        ["runuser", "-u", "user", "--", "env",
         f"HOME={USER.pw_dir}", f"XDG_RUNTIME_DIR=/run/user/{USER.pw_uid}",
         "systemd-analyze", "--user", "verify", UNIT],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    assert verify.returncode == 0, (
        f"Invalid systemd user unit:\n{verify.stdout}\n{verify.stderr}"
    )

    enabled = user_systemctl("is-enabled", "capacity-planner.service", check=False)
    assert enabled.returncode == 0 and enabled.stdout.strip() == "enabled", (
        "capacity-planner.service is not enabled in the user manager: "
        f"{enabled.stdout}{enabled.stderr}"
    )

    restart = user_systemctl("restart", "capacity-planner.service", check=False)
    assert restart.returncode == 0, (
        "The service could not be restarted by user systemd: "
        f"{restart.stdout}{restart.stderr}"
    )
    wait_for_api()


def test_config_file_permissions():
    assert os.path.exists(CONFIG), f"Config file {CONFIG} does not exist."

    st = os.stat(CONFIG)
    assert stat.S_ISREG(st.st_mode), f"Config file {CONFIG} is not a regular file"
    assert st.st_uid == USER.pw_uid, f"Config file must be owned by user, uid is {st.st_uid}"

    perms = stat.S_IMODE(st.st_mode)
    assert (perms & stat.S_IRWXG) == 0, f"Group has permissions on {CONFIG}: {oct(perms)}"
    assert (perms & stat.S_IRWXO) == 0, f"Others have permissions on {CONFIG}: {oct(perms)}"
    assert (perms & stat.S_IRUSR) != 0, f"Owner does not have read permission on {CONFIG}"

    acl = subprocess.run(
        ["getfacl", "-cp", CONFIG], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True,
    ).stdout
    entries = [line.strip() for line in acl.splitlines() if line and not line.startswith("#")]
    parsed = {}
    for line in entries:
        fields = line.split(":")
        assert len(fields) >= 3, f"Unrecognized ACL entry: {line}"
        kind, name, rights = fields[0], fields[1], fields[2]
        parsed[(kind, name)] = rights
        if (kind == "user" and name) or kind == "group":
            assert rights == "---", f"ACL grants another identity permissions: {line}"
    assert "r" in parsed.get(("user", ""), ""), "Owner ACL does not grant read access"
    assert parsed.get(("group", "")) == "---", "Owning group ACL is not empty"
    assert parsed.get(("other", "")) == "---", "Other ACL is not empty"


def test_initialized_config_contents():
    with open(CONFIG, encoding="utf-8") as handle:
        data = json.load(handle)
    assert data == {"cpu_threshold": 85, "source": "init_db"}, (
        f"Configuration was not initialized with the memo specification: {data}"
    )


def test_systemd_service_exists():
    assert os.path.exists(UNIT), f"Systemd user service file {UNIT} is missing."


def test_systemd_service_is_active_and_runs_planner():
    shown = user_systemctl(
        "show", "capacity-planner.service",
        "--property=ActiveState,SubState,MainPID,FragmentPath,ExecStart",
        "--value", check=False,
    )
    assert shown.returncode == 0, f"Cannot inspect user service: {shown.stderr}"

    props = user_systemctl(
        "show", "capacity-planner.service",
        "--property=ActiveState,SubState,MainPID,FragmentPath,ExecStart",
        check=True,
    ).stdout
    values = {}
    for line in props.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key] = value

    assert values.get("ActiveState") == "active", f"Service is not active: {props}"
    assert values.get("SubState") == "running", f"Service is not running: {props}"
    assert os.path.realpath(values.get("FragmentPath", "")) == os.path.realpath(UNIT), (
        f"User systemd loaded an unexpected unit file: {props}"
    )
    assert API in values.get("ExecStart", ""), f"Unit does not execute {API}: {props}"

    pid = int(values.get("MainPID", "0"))
    assert pid > 0 and os.path.exists(f"/proc/{pid}"), f"Invalid MainPID: {pid}"
    assert os.stat(f"/proc/{pid}").st_uid == USER.pw_uid, "Service process is not owned by user"
    with open(f"/proc/{pid}/cmdline", "rb") as handle:
        cmdline = handle.read().replace(b"\0", b" ").decode(errors="replace")
    assert API in cmdline, f"Managed process is not executing planner_api.py: {cmdline}"

    socket_inodes = set()
    for fd in os.listdir(f"/proc/{pid}/fd"):
        try:
            target = os.readlink(f"/proc/{pid}/fd/{fd}")
        except OSError:
            continue
        if target.startswith("socket:["):
            socket_inodes.add(target[8:-1])

    listening = False
    with open(f"/proc/{pid}/net/tcp", encoding="ascii") as handle:
        next(handle)
        for line in handle:
            fields = line.split()
            local_address, state, inode = fields[1], fields[3], fields[9]
            address, port = local_address.split(":")
            if (address == "0100007F" and int(port, 16) == 8123 and
                    state == "0A" and inode in socket_inodes):
                listening = True
                break
    assert listening, "Managed planner process is not listening on 127.0.0.1:8123"


def test_api_response():
    try:
        response = request_capacity()
    except requests.exceptions.RequestException as exc:
        assert False, f"Failed to connect to the API at {URL}: {exc}"

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        assert False, f"Response is not valid JSON: {response.text}"

    expected_data = {
        "cpu_threshold": 85,
        "source": "init_db",
        "status": "analyzing",
    }
    assert data == expected_data, f"Unexpected JSON response. Expected {expected_data}, got {data}"


def test_api_reads_configuration_for_each_request():
    with open(CONFIG, "rb") as handle:
        original = handle.read()

    nonce = uuid.uuid4().hex
    changed = {
        "cpu_threshold": 17,
        "source": f"dynamic-{nonce}",
        "verification_nonce": nonce,
    }
    try:
        with open(CONFIG, "w", encoding="utf-8") as handle:
            json.dump(changed, handle)
            handle.flush()
            os.fsync(handle.fileno())

        response = request_capacity()
        assert response.status_code == 200, response.text
        assert response.json() == {**changed, "status": "analyzing"}, (
            "API did not return the current exact contents of capacity_config.json"
        )
    finally:
        with open(CONFIG, "wb") as handle:
            handle.write(original)
            handle.flush()
            os.fsync(handle.fileno())


def test_api_auth_failure():
    try:
        response = request_capacity("wrongpin")
    except requests.exceptions.RequestException as exc:
        assert False, f"Failed to connect to the API at {URL}: {exc}"
    assert response.status_code != 200, "API did not reject invalid authentication"


def test_api_auth_header_is_required():
    response = requests.get(URL, timeout=5)
    assert response.status_code != 200, "API accepted a request without X-Planner-Auth"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
