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
import hashlib
import os
import pwd
import re
import stat
import subprocess
import time
import uuid
from datetime import datetime

import pytest
import requests

SOURCE_DIR = "/app/bash-webhook-1.0"
SOURCE_SERVER = f"{SOURCE_DIR}/webhook-server"
INSTALLED_SERVER = "/home/user/.local/bin/webhook-server"
PROVISION_SCRIPT = "/home/user/provision.sh"
LOG_FILE = "/home/user/logs/deploy.log"


def file_hash(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def run_as_user(argv, cwd=None, timeout=10):
    account = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    env = os.environ.copy()
    env.update({"HOME": account.pw_dir, "USER": "user", "LOGNAME": "user"})
    return subprocess.run(
        argv,
        cwd=cwd,
        env=env,
        preexec_fn=demote,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )


def read_log_lines():
    with open(LOG_FILE, "r") as f:
        return f.read().splitlines()


def expected_log_line(project, dates):
    return {f"[{date}] Provisioning project: {project}" for date in dates}


def date_today():
    return datetime.now().strftime("%Y-%m-%d")


def listener_socket_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) < 10:
                        continue
                    local = fields[1]
                    state = fields[3]
                    if state != "0A":
                        continue
                    try:
                        local_port = int(local.rsplit(":", 1)[1], 16)
                    except ValueError:
                        continue
                    if local_port == port:
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def pids_holding_sockets(inodes):
    holders = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    holders.add(int(entry))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return holders


def process_chain(pid):
    chain = []
    seen = set()
    while pid > 1 and pid not in seen:
        seen.add(pid)
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                argv = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
            with open(f"/proc/{pid}/status", "r") as f:
                status = f.read()
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            break
        chain.append(argv)
        match = re.search(r"^PPid:\s+(\d+)$", status, re.MULTILINE)
        if not match:
            break
        pid = int(match.group(1))
    return chain


def find_installed_listener(timeout=3):
    deadline = time.time() + timeout
    while time.time() < deadline:
        inodes = listener_socket_inodes(8080)
        for pid in pids_holding_sockets(inodes):
            chain = process_chain(pid)
            flattened = [arg for argv in chain for arg in argv]
            if (INSTALLED_SERVER in flattened and "8080" in flattened
                    and "/deploy" in flattened and PROVISION_SCRIPT in flattened):
                return chain
        time.sleep(0.1)
    return None


def post_project(project):
    try:
        return requests.post(
            "http://127.0.0.1:8080/deploy",
            json={"project": project},
            timeout=5,
        )
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the webhook server: {exc}")


def wait_for_new_exact_line(project, baseline, dates, timeout=3):
    expected = expected_log_line(project, dates)
    old_count = sum(line in expected for line in baseline)
    deadline = time.time() + timeout
    while time.time() < deadline:
        current = read_log_lines()
        if sum(line in expected for line in current) > old_count:
            return current
        time.sleep(0.1)
    pytest.fail(f"No new exact provisioning line for {project!r} was written to {LOG_FILE}")


def test_logs_directory_permissions():
    log_dir = "/home/user/logs"
    assert os.path.isdir(log_dir), f"Directory {log_dir} does not exist."
    perms = stat.S_IMODE(os.stat(log_dir).st_mode)
    assert perms == 0o750, f"Expected {log_dir} permissions to be 750, but got {oct(perms)}."


def test_deploy_log_permissions():
    assert os.path.isfile(LOG_FILE), f"File {LOG_FILE} does not exist."
    perms = stat.S_IMODE(os.stat(LOG_FILE).st_mode)
    assert perms == 0o640, f"Expected {LOG_FILE} permissions to be 640, but got {oct(perms)}."


def test_provision_script_executable():
    assert os.path.isfile(PROVISION_SCRIPT), f"Script {PROVISION_SCRIPT} does not exist."
    assert os.access(PROVISION_SCRIPT, os.X_OK), f"Script {PROVISION_SCRIPT} is not executable."


def test_provision_script_uses_its_argument():
    project = "direct-" + uuid.uuid4().hex
    baseline = read_log_lines()
    before = date_today()
    result = run_as_user([PROVISION_SCRIPT, project])
    after = date_today()
    assert result.returncode == 0, f"provision.sh failed as user: {result.stdout}"
    wait_for_new_exact_line(project, baseline, {before, after})


def test_webhook_server_installed_from_fixed_source():
    assert os.path.isfile(SOURCE_SERVER), f"Source server {SOURCE_SERVER} is missing."
    assert os.path.isfile(INSTALLED_SERVER), f"Binary {INSTALLED_SERVER} does not exist."
    assert os.access(INSTALLED_SERVER, os.X_OK), f"Binary {INSTALLED_SERVER} is not executable."

    with open(SOURCE_SERVER, "r") as f:
        source = f.read()
    active_source = "\n".join(
        line for line in source.splitlines() if not line.lstrip().startswith("#")
    )
    assert not re.search(r"\$\{?REQUEST_METHOD\}?", active_source), (
        "The vendored webhook-server still reads the incorrect REQUEST_METHOD variable."
    )
    assert re.search(r"\$\{?HTTP_METHOD\}?", active_source), (
        "The vendored webhook-server does not check the parsed HTTP_METHOD variable."
    )
    assert file_hash(SOURCE_SERVER) == file_hash(INSTALLED_SERVER), (
        "The installed webhook-server is not the fixed vendored source artifact."
    )


def test_make_install_targets_user_local_bin():
    result = run_as_user(["make", "-n", "install"], cwd=SOURCE_DIR)
    assert result.returncode == 0, f"make install is not usable by user:\n{result.stdout}"
    output = result.stdout
    assert "/home/user/.local/bin" in output and "webhook-server" in output, (
        "The install target does not place webhook-server in /home/user/.local/bin. "
        f"Dry-run output:\n{output}"
    )


def test_installed_server_is_the_listener():
    chain = find_installed_listener()
    assert chain is not None, (
        "Port 8080 is not being served by a process launched from the installed "
        "webhook-server with arguments 8080, /deploy, and /home/user/provision.sh."
    )


def test_webhook_server_live_request():
    # Preserve the original fixed request and assertions.
    baseline = read_log_lines()
    response = post_project("alpha-omega")
    assert response.status_code == 200, f"Expected HTTP 200 OK, but got {response.status_code}."
    time.sleep(0.5)
    log_contents = "\n".join(read_log_lines())
    expected_string = "Provisioning project: alpha-omega"
    assert expected_string in log_contents, (
        f"Expected string '{expected_string}' not found in {LOG_FILE}. Actual contents:\n{log_contents}"
    )
    today_iso = datetime.now().strftime("%Y-%m-%d")
    expected_line_prefix = f"[{today_iso}]"
    assert expected_line_prefix in log_contents, (
        f"Expected date prefix '{expected_line_prefix}' not found in {LOG_FILE}. "
        f"Actual contents:\n{log_contents}"
    )

    # Exercise an unpredictable value and require a newly appended exact line.
    project = "webhook-" + uuid.uuid4().hex
    dynamic_baseline = read_log_lines()
    before = date_today()
    dynamic_response = post_project(project)
    after = date_today()
    assert dynamic_response.status_code == 200, (
        f"Expected HTTP 200 for dynamic project, got {dynamic_response.status_code}."
    )
    wait_for_new_exact_line(project, dynamic_baseline, {before, after})
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
