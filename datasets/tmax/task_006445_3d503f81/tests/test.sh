#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import time
import pytest

DASHBOARD = "/home/user/dashboard"
LOGIN_EXP = f"{DASHBOARD}/login.exp"
START_FEED = f"{DASHBOARD}/start_feed.sh"
PID_FILE = f"{DASHBOARD}/feed.pid"
LOG_FILE = f"{DASHBOARD}/feed.log"
TELEMETRY = "/home/user/bin/telemetry-cli"
EXPECTED_ENV = {
    "TZ": "UTC",
    "LC_ALL": "en_US.UTF-8",
    "METRICS_DASHBOARD_URL": "http://localhost:9090/api/push",
}
EXPECTED_TELEMETRY = b'''#!/bin/bash

if [ "$TZ" != "UTC" ]; then
    echo "Error: TZ must be UTC"
    exit 1
fi

if [ "$LC_ALL" != "en_US.UTF-8" ]; then
    echo "Error: LC_ALL must be en_US.UTF-8"
    exit 1
fi

if [ "$METRICS_DASHBOARD_URL" != "http://localhost:9090/api/push" ]; then
    echo "Error: METRICS_DASHBOARD_URL is incorrect"
    exit 1
fi

echo -n "Enter telemetry password: "
read -s password
echo

if [ "$password" != "obsv-dash-2024" ]; then
    echo "Authentication failed."
    exit 1
fi

echo "Authentication successful."
echo "Dashboard feed active. Pushing to $METRICS_DASHBOARD_URL"
while true; do
    sleep 5
    echo "Pushed 10 metrics..."
done
'''


def proc_pids():
    return {int(name) for name in os.listdir("/proc") if name.isdigit()}


def cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return [part.decode(errors="replace") for part in f.read().split(b"\0") if part]
    except OSError:
        return []


def environ(pid):
    result = {}
    try:
        with open(f"/proc/{pid}/environ", "rb") as f:
            entries = f.read().split(b"\0")
        for entry in entries:
            if b"=" in entry:
                key, value = entry.split(b"=", 1)
                result[key.decode(errors="replace")] = value.decode(errors="replace")
    except OSError:
        pass
    return result


def ppid(pid):
    try:
        with open(f"/proc/{pid}/stat", "r") as f:
            data = f.read()
        return int(data[data.rfind(")") + 2:].split()[1])
    except (OSError, ValueError, IndexError):
        return None


def descendants(root):
    found = set()
    changed = True
    while changed:
        changed = False
        parents = {root} | found
        for pid in proc_pids() - found - {root}:
            if ppid(pid) in parents:
                found.add(pid)
                changed = True
    return found


# Exercise the submitted launcher ourselves with the required variables absent from
# its inherited environment. Removing the old outputs ensures the assertions below
# cannot be satisfied by stale files from an unrelated process.
PREEXISTING_PIDS = proc_pids()
for path in (PID_FILE, LOG_FILE):
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass

launch_env = os.environ.copy()
for key in EXPECTED_ENV:
    launch_env.pop(key, None)

LAUNCH = subprocess.run(
    [START_FEED],
    cwd=DASHBOARD,
    env=launch_env,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    timeout=10,
)
assert LAUNCH.returncode == 0, (
    f"start_feed.sh exited with {LAUNCH.returncode}; "
    f"stdout={LAUNCH.stdout!r}, stderr={LAUNCH.stderr!r}"
)

EXPECT_PID = None
TELEMETRY_PID = None
deadline = time.time() + 12
last_detail = "PID file was not ready"
while time.time() < deadline:
    try:
        raw_pid = open(PID_FILE, "r").read().strip()
    except OSError:
        time.sleep(0.1)
        continue
    if not raw_pid.isdigit():
        last_detail = f"PID file contained {raw_pid!r}"
        time.sleep(0.1)
        continue

    candidate = int(raw_pid)
    if candidate in PREEXISTING_PIDS:
        last_detail = f"PID {candidate} existed before start_feed.sh was executed"
        time.sleep(0.1)
        continue
    if not os.path.exists(f"/proc/{candidate}"):
        last_detail = f"PID {candidate} is not running"
        time.sleep(0.1)
        continue

    candidate_cmd = cmdline(candidate)
    try:
        candidate_exe = os.path.realpath(f"/proc/{candidate}/exe")
    except OSError:
        candidate_exe = ""
    if os.path.basename(candidate_exe) != "expect" or LOGIN_EXP not in candidate_cmd:
        last_detail = f"PID {candidate} is not Expect running login.exp: {candidate_cmd!r}"
        time.sleep(0.1)
        continue
    if any(environ(candidate).get(k) != v for k, v in EXPECTED_ENV.items()):
        last_detail = f"Expect PID {candidate} does not have the required exported environment"
        time.sleep(0.1)
        continue

    children = descendants(candidate)
    telemetry_candidates = [pid for pid in children if TELEMETRY in cmdline(pid)]
    if not telemetry_candidates:
        last_detail = f"Expect PID {candidate} has not launched {TELEMETRY}"
        time.sleep(0.1)
        continue

    authenticated_pid = None
    for telemetry_pid in telemetry_candidates:
        child_env = environ(telemetry_pid)
        if any(child_env.get(k) != v for k, v in EXPECTED_ENV.items()):
            continue
        # The unmodified exporter only reaches its endless sleep loop after it has
        # received and accepted the password. A descendant `sleep 5` therefore
        # proves that it is past the interactive authentication, rather than merely
        # blocked at the password prompt while a success phrase was forged in a log.
        telemetry_desc = descendants(telemetry_pid)
        if any(args[:2] == ["sleep", "5"] or (args and os.path.basename(args[0]) == "sleep" and args[1:] == ["5"])
               for args in (cmdline(pid) for pid in telemetry_desc)):
            authenticated_pid = telemetry_pid
            break
    if authenticated_pid is None:
        last_detail = "telemetry-cli was not observed in its authenticated feed loop"
        time.sleep(0.1)
        continue

    try:
        content = open(LOG_FILE, "r").read()
    except OSError:
        content = ""
    if "Authentication successful." not in content or "Dashboard feed active" not in content:
        last_detail = "fresh feed.log does not contain telemetry-cli authentication/feed output"
        time.sleep(0.1)
        continue

    EXPECT_PID = candidate
    TELEMETRY_PID = authenticated_pid
    break

assert EXPECT_PID is not None, f"Submitted scripts did not start a real authenticated telemetry feed: {last_detail}"


def test_telemetry_cli_is_original_executable():
    assert os.path.isfile(TELEMETRY), f"{TELEMETRY} is not a file."
    assert os.access(TELEMETRY, os.X_OK), f"{TELEMETRY} is not executable."
    with open(TELEMETRY, "rb") as f:
        assert f.read() == EXPECTED_TELEMETRY, f"{TELEMETRY} was modified."


def test_login_exp_exists_and_executable():
    path = "/home/user/dashboard/login.exp"
    assert os.path.exists(path), f"File {path} does not exist."
    assert os.path.isfile(path), f"{path} is not a file."
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_start_feed_sh_exists_and_executable():
    path = "/home/user/dashboard/start_feed.sh"
    assert os.path.exists(path), f"File {path} does not exist."
    assert os.path.isfile(path), f"{path} is not a file."
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_feed_pid_exists_and_process_running():
    pid_file = "/home/user/dashboard/feed.pid"
    assert os.path.exists(pid_file), f"PID file {pid_file} does not exist."

    with open(pid_file, "r") as f:
        pid_str = f.read().strip()

    assert pid_str.isdigit(), f"PID file {pid_file} does not contain a valid numeric PID (found: {pid_str})."

    pid = int(pid_str)
    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f"Process with PID {pid} (from {pid_file}) is not running.")

    cmdline_file = f"/proc/{pid}/cmdline"
    if os.path.exists(cmdline_file):
        with open(cmdline_file, "r") as f:
            process_cmdline = f.read().replace('\x00', ' ')
        assert "expect" in process_cmdline or "login.exp" in process_cmdline, f"Process {pid} does not appear to be the expect script (cmdline: {process_cmdline})"


def test_pid_is_exact_expect_process_with_real_telemetry_child():
    with open(PID_FILE, "r") as f:
        pid = int(f.read().strip())
    assert pid == EXPECT_PID, "feed.pid changed and no longer identifies the verified Expect process."
    assert TELEMETRY_PID in descendants(pid), "The authenticated telemetry-cli is no longer a descendant of the recorded Expect PID."
    assert TELEMETRY in cmdline(TELEMETRY_PID), "The verified telemetry-cli process is no longer running."
    for key, value in EXPECTED_ENV.items():
        assert environ(pid).get(key) == value, f"Expect process is missing {key}={value}."
        assert environ(TELEMETRY_PID).get(key) == value, f"telemetry-cli is missing {key}={value}."


def test_feed_log_exists_and_contains_correct_output():
    log_file = "/home/user/dashboard/feed.log"
    assert os.path.exists(log_file), f"Log file {log_file} does not exist."

    with open(log_file, "r") as f:
        log_content = f.read()

    assert "Dashboard feed active" in log_content, "Log file does not contain the success message 'Dashboard feed active'."
    assert "Authentication failed" not in log_content, "Log file contains 'Authentication failed'."
    assert "Error:" not in log_content, "Log file contains 'Error:' messages indicating missing environment variables."
    assert "Authentication successful." in log_content, "Log file does not contain telemetry-cli's authentication success output."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
