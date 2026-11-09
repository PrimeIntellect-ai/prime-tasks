#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess
import time
import urllib.request
import uuid
import pytest

EXPECT_PATH = "/home/user/automate_init.exp"
INIT_PATH = "/home/user/init_server.sh"
WATCHDOG_PATH = "/home/user/watchdog.sh"
EXPECTED_SERVER_ARGS = ["-m", "http.server", "8080", "--directory", "/home/user/webroot"]
EXPECTED_LOG_LINE = "[RESTART] python http server crashed, restarting..."


def process_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return [part.decode(errors="replace") for part in f.read().split(b"\0") if part]
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        return []


def process_ppid(pid):
    try:
        with open(f"/proc/{pid}/status", "r") as f:
            for line in f:
                if line.startswith("PPid:"):
                    return int(line.split()[1])
    except (FileNotFoundError, ProcessLookupError, PermissionError, ValueError):
        pass
    return None


def all_pids():
    return [int(name) for name in os.listdir("/proc") if name.isdigit()]


def get_python_server_pids():
    result = []
    for pid in all_pids():
        args = process_cmdline(pid)
        if args and os.path.basename(args[0]).startswith("python3") and args[1:] == EXPECTED_SERVER_ARGS:
            result.append(pid)
    return result


def get_watchdog_pids():
    result = []
    for pid in all_pids():
        args = process_cmdline(pid)
        if any(arg == WATCHDOG_PATH for arg in args):
            result.append(pid)
    return result


def is_descendant(pid, ancestor):
    seen = set()
    current = pid
    while current and current not in seen:
        if current == ancestor:
            return True
        seen.add(current)
        current = process_ppid(current)
    return False


def fetch_expected_page(timeout=2):
    with urllib.request.urlopen("http://localhost:8080/", timeout=timeout) as response:
        html = response.read().decode()
    assert "AutoProvisionedWeb" in html, "HTTP server not serving expected content"


def test_expect_script_exists_and_runs_init_server():
    assert os.path.isfile(EXPECT_PATH), f"{EXPECT_PATH} does not exist"
    assert os.path.getsize(EXPECT_PATH) > 0, f"{EXPECT_PATH} is empty"

    token = uuid.uuid4().hex
    backup = f"/tmp/init_server_{token}.sh"
    marker = f"/tmp/init_server_{token}.called"
    original_mode = stat.S_IMODE(os.stat(INIT_PATH).st_mode)
    shutil.copyfile(INIT_PATH, backup)
    os.chmod(backup, original_mode)

    wrapper = f'''#!/bin/bash
: > "{marker}"
exec "{backup}" "$@"
'''

    try:
        with open(INIT_PATH, "w") as f:
            f.write(wrapper)
        os.chmod(INIT_PATH, 0o755)

        for path in ("/home/user/server.conf", "/home/user/webroot/index.html"):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        try:
            os.rmdir("/home/user/webroot")
        except (FileNotFoundError, OSError):
            pass

        result = subprocess.run(
            ["runuser", "-u", "user", "--", "expect", EXPECT_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"Expect script failed with exit code {result.returncode}: "
            f"{result.stdout}{result.stderr}"
        )
        assert os.path.isfile(marker), "Expect script did not execute /home/user/init_server.sh"
    finally:
        shutil.copyfile(backup, INIT_PATH)
        os.chmod(INIT_PATH, original_mode)
        for path in (backup, marker):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass


def test_server_conf_contents():
    conf_path = "/home/user/server.conf"
    assert os.path.isfile(conf_path), f"{conf_path} does not exist"
    with open(conf_path, "r") as f:
        content = f.read()
    assert "PORT=8080" in content, "server.conf does not contain PORT=8080"
    assert "DIR=/home/user/webroot" in content, "server.conf does not contain DIR=/home/user/webroot"


def test_webroot_and_index():
    index_path = "/home/user/webroot/index.html"
    assert os.path.isfile(index_path), f"{index_path} does not exist"
    with open(index_path, "r") as f:
        content = f.read()
    assert "AutoProvisionedWeb" in content, "index.html does not contain AutoProvisionedWeb"


def test_server_running_and_watchdog_behavior():
    assert os.path.isfile(WATCHDOG_PATH), f"{WATCHDOG_PATH} does not exist"
    assert os.path.getsize(WATCHDOG_PATH) > 0, f"{WATCHDOG_PATH} is empty"
    syntax = subprocess.run(
        ["bash", "-n", WATCHDOG_PATH], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert syntax.returncode == 0, f"watchdog.sh has invalid Bash syntax: {syntax.stderr}"

    try:
        fetch_expected_page()
    except Exception as e:
        pytest.fail(f"Could not connect to HTTP server on port 8080: {e}")

    watchdog_pids = get_watchdog_pids()
    assert watchdog_pids, "No running /home/user/watchdog.sh process found"

    old_server_pids = get_python_server_pids()
    assert old_server_pids, "Python HTTP server process not found with the required command"
    supervising_watchdogs = {
        watchdog_pid
        for watchdog_pid in watchdog_pids
        if any(is_descendant(server_pid, watchdog_pid) for server_pid in old_server_pids)
    }
    assert supervising_watchdogs, "The required Python server is not supervised by watchdog.sh"

    log_path = "/home/user/watchdog.log"
    old_log_size = os.path.getsize(log_path) if os.path.isfile(log_path) else 0

    for pid in old_server_pids:
        try:
            os.kill(pid, 9)
        except ProcessLookupError:
            pass

    deadline = time.time() + 7
    new_server_pids = []
    while time.time() < deadline:
        current = get_python_server_pids()
        new_server_pids = [pid for pid in current if pid not in old_server_pids]
        if new_server_pids and any(
            is_descendant(server_pid, watchdog_pid)
            for server_pid in new_server_pids
            for watchdog_pid in supervising_watchdogs
        ):
            try:
                fetch_expected_page(timeout=1)
                break
            except Exception:
                pass
        time.sleep(0.2)
    else:
        pytest.fail("Watchdog failed to start a new required Python server process after the old one was killed")

    assert all(os.path.exists(f"/proc/{pid}") for pid in supervising_watchdogs), (
        "The supervising watchdog process exited"
    )

    log_deadline = time.time() + 3
    appended = ""
    while time.time() < log_deadline:
        if os.path.isfile(log_path) and os.path.getsize(log_path) >= old_log_size:
            with open(log_path, "rb") as f:
                f.seek(old_log_size)
                appended = f.read().decode(errors="replace")
            if EXPECTED_LOG_LINE in appended.splitlines():
                break
        time.sleep(0.1)

    assert os.path.isfile(log_path), f"{log_path} does not exist"
    with open(log_path, "r") as f:
        log_content = f.read()
    assert EXPECTED_LOG_LINE in log_content, "Watchdog log does not contain the expected restart message"
    assert EXPECTED_LOG_LINE in appended.splitlines(), (
        "Watchdog did not append the exact restart message after the verifier killed the server"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
