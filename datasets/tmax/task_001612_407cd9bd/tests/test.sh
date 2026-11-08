#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import random
import secrets
import stat
import subprocess
import textwrap

import pytest

SCRIPT_PATH = "/home/user/setup_user.py"
CONFIG_PATH = "/home/user/new_user_config.ini"
CLI_PATH = "/home/user/bin/usermanager_cli"
REPORT_PATH = "/home/user/setup_report.json"
DB_PATH = "/home/user/user_db.txt"
ROUTING_SCRIPT_PATH = "/home/user/user_routing.sh"
DAEMON_PATH = "/home/user/bin/quota_daemon.py"
EXPECTED_KEYS = {"username", "uid", "assigned_ip", "quota_mb", "quota_daemon_pid"}


def load_report():
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} does not exist."
    with open(REPORT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{REPORT_PATH} is not valid JSON.")


def assert_daemon(pid):
    assert type(pid) is int, "quota_daemon_pid must be an integer."
    cmdline_path = f"/proc/{pid}/cmdline"
    assert os.path.isfile(cmdline_path), f"Process with PID {pid} is not running."
    with open(cmdline_path, "rb") as f:
        cmdline = f.read().replace(b"\x00", b" ").decode(errors="replace")
    assert "quota_daemon.py" in cmdline, (
        f"Process {pid} does not appear to be quota_daemon.py. Cmdline: {cmdline}"
    )


def test_00_script_exists_and_uses_pexpect_spawn():
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} does not exist."
    with open(SCRIPT_PATH, "r") as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=SCRIPT_PATH)
    except SyntaxError as exc:
        pytest.fail(f"{SCRIPT_PATH} is not valid Python: {exc}")

    module_aliases = set()
    spawn_aliases = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "pexpect":
                    module_aliases.add(alias.asname or "pexpect")
        elif isinstance(node, ast.ImportFrom) and node.module == "pexpect":
            for alias in node.names:
                if alias.name == "spawn":
                    spawn_aliases.add(alias.asname or "spawn")

    assert module_aliases or spawn_aliases, "setup_user.py must import pexpect."
    uses_spawn = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in spawn_aliases:
            uses_spawn = True
        if (isinstance(node.func, ast.Attribute)
                and node.func.attr == "spawn"
                and isinstance(node.func.value, ast.Name)
                and node.func.value.id in module_aliases):
            uses_spawn = True
    assert uses_spawn, "setup_user.py must use pexpect.spawn to invoke the CLI."


def test_01_original_setup_report_json():
    data = load_report()
    assert "username" in data, "Missing 'username' in report."
    assert "uid" in data, "Missing 'uid' in report."
    assert "assigned_ip" in data, "Missing 'assigned_ip' in report."
    assert "quota_mb" in data, "Missing 'quota_mb' in report."
    assert "quota_daemon_pid" in data, "Missing 'quota_daemon_pid' in report."
    assert set(data) == EXPECTED_KEYS, "Report must contain exactly the required fields."
    assert data["username"] == "dev_intern", "Username in report should be 'dev_intern'."
    assert type(data["username"]) is str
    assert type(data["uid"]) is int
    assert data["assigned_ip"] == "10.0.0.50", "Assigned IP in report should be '10.0.0.50'."
    assert type(data["assigned_ip"]) is str
    assert data["quota_mb"] == 500, "Quota MB in report should be 500."
    assert type(data["quota_mb"]) is int
    assert type(data["quota_daemon_pid"]) is int


def test_02_original_uid_matches_db_and_inputs():
    assert os.path.isfile(DB_PATH), f"{DB_PATH} does not exist. Was the CLI tool run successfully?"
    with open(DB_PATH, "r") as f:
        lines = f.read().strip().split("\n")
    dev_intern_lines = [line for line in lines if line.startswith("dev_intern:")]
    assert len(dev_intern_lines) > 0, "No entry for 'dev_intern' found in user_db.txt."
    last_entry = dev_intern_lines[-1]
    parts = last_entry.split(":")
    assert len(parts) == 5, "Invalid format in user_db.txt."
    assert parts[1] == "securepass", "The configured password was not supplied to the CLI."
    assert parts[2] == "y", "The configured sandbox response was not supplied to the CLI."
    assert parts[3] == "500", "The configured quota was not supplied to the CLI."
    db_uid = int(parts[4])
    data = load_report()
    assert data["uid"] == db_uid, (
        f"UID in report ({data['uid']}) does not match UID in DB ({db_uid})."
    )


def test_03_original_routing_script():
    assert os.path.isfile(ROUTING_SCRIPT_PATH), f"{ROUTING_SCRIPT_PATH} does not exist."
    st = os.stat(ROUTING_SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"{ROUTING_SCRIPT_PATH} is not executable."
    assert stat.S_IMODE(st.st_mode) == 0o755, f"{ROUTING_SCRIPT_PATH} must have mode 0755."
    with open(ROUTING_SCRIPT_PATH, "r") as f:
        content = f.read()
    expected_command = "ip route add 10.0.0.50 dev dev_intern_veth"
    assert expected_command in content, (
        f"Expected command '{expected_command}' not found in {ROUTING_SCRIPT_PATH}."
    )
    assert content in (expected_command, expected_command + "\n"), (
        f"{ROUTING_SCRIPT_PATH} must contain exactly the required routing line."
    )


def test_04_original_daemon_running_and_pid():
    data = load_report()
    pid = data.get("quota_daemon_pid")
    assert pid is not None, "quota_daemon_pid is missing in report."
    assert_daemon(pid)


def test_10_execute_script_against_fresh_derived_inputs_and_real_cli_protocol():
    token = secrets.token_hex(6)
    username = "verify_" + token
    password = "pw_" + secrets.token_hex(8)
    sandbox_yes = bool(secrets.randbits(1))
    sandbox_config = "yes" if sandbox_yes else "no"
    expected_sandbox_reply = "y" if sandbox_yes else "N"
    quota = random.SystemRandom().randint(101, 900)
    assigned_ip = f"10.{random.SystemRandom().randint(20, 220)}.{random.SystemRandom().randint(1, 240)}.{random.SystemRandom().randint(1, 240)}"
    expected_uid = random.SystemRandom().randint(10001, 60000)
    marker_path = "/tmp/usermanager_invoked_" + secrets.token_hex(12) + ".json"

    with open(CONFIG_PATH, "w") as f:
        f.write(textwrap.dedent(f"""\
            [NewUser]
            username = {username}
            password = {password}
            network_sandbox = {sandbox_config}
            quota_mb = {quota}
            assigned_ip = {assigned_ip}
        """))

    wrapper = f'''#!/usr/bin/env python3
import json
username = input("Enter username: ")
password = input("Enter password: ")
sandbox = input("Enable network sandbox? [y/N]: ")
quota = input("Set disk quota (in MB): ")
with open({marker_path!r}, "w") as f:
    json.dump({{"username": username, "password": password, "sandbox": sandbox, "quota": quota}}, f)
with open({DB_PATH!r}, "a") as f:
    f.write(f"{{username}}:{{password}}:{{sandbox}}:{{quota}}:{expected_uid}\\n")
print(f"User {{username}} created with UID {expected_uid}.")
'''
    with open(CLI_PATH, "w") as f:
        f.write(wrapper)
    os.chmod(CLI_PATH, 0o755)

    for path in (REPORT_PATH, ROUTING_SCRIPT_PATH, DB_PATH, marker_path):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    log_path = "/tmp/setup_user_execution.log"
    with open(log_path, "wb") as log:
        try:
            result = subprocess.run(
                ["python3", SCRIPT_PATH],
                stdin=subprocess.DEVNULL,
                stdout=log,
                stderr=subprocess.STDOUT,
                timeout=20,
                cwd="/home/user",
            )
        except subprocess.TimeoutExpired:
            pytest.fail("setup_user.py did not finish within 20 seconds.")
    if result.returncode != 0:
        with open(log_path, "r", errors="replace") as f:
            output = f.read()
        pytest.fail(f"setup_user.py exited with {result.returncode}. Output:\n{output}")

    assert os.path.isfile(marker_path), "The usermanager CLI was not invoked by setup_user.py."
    with open(marker_path, "r") as f:
        supplied = json.load(f)
    assert supplied == {
        "username": username,
        "password": password,
        "sandbox": expected_sandbox_reply,
        "quota": str(quota),
    }, "The values supplied interactively to the CLI did not match the INI configuration."

    assert os.path.isfile(DB_PATH), "The invoked CLI did not create user_db.txt."
    with open(DB_PATH, "r") as f:
        db_lines = f.read().splitlines()
    expected_db_line = f"{username}:{password}:{expected_sandbox_reply}:{quota}:{expected_uid}"
    assert db_lines == [expected_db_line], "The CLI interaction did not create the expected DB entry."

    data = load_report()
    assert set(data) == EXPECTED_KEYS, "Report must contain exactly the required fields."
    assert data["username"] == username and type(data["username"]) is str
    assert data["uid"] == expected_uid and type(data["uid"]) is int
    assert data["assigned_ip"] == assigned_ip and type(data["assigned_ip"]) is str
    assert data["quota_mb"] == quota and type(data["quota_mb"]) is int
    assert type(data["quota_daemon_pid"]) is int
    assert_daemon(data["quota_daemon_pid"])

    assert os.path.isfile(ROUTING_SCRIPT_PATH), f"{ROUTING_SCRIPT_PATH} does not exist."
    expected_route = f"ip route add {assigned_ip} dev {username}_veth"
    with open(ROUTING_SCRIPT_PATH, "r") as f:
        route_content = f.read()
    assert route_content in (expected_route, expected_route + "\n"), (
        "Routing script must contain exactly the command derived from the INI file."
    )
    assert stat.S_IMODE(os.stat(ROUTING_SCRIPT_PATH).st_mode) == 0o755, (
        f"{ROUTING_SCRIPT_PATH} must have mode 0755."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
