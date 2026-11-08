#!/bin/bash
set -u
mkdir -p /logs/verifier

fail() {
    echo "0" > /logs/verifier/reward.txt
    exit 0
}

# Preserve the original assertions against the agent's final state.
cat <<'TEST_EOF' > /tmp/test_original_state.py
import os
import time
import urllib.error
import urllib.request


def test_expect_script_exists():
    path = "/home/user/get_health.exp"
    assert os.path.isfile(path), f"Expect script not found at {path}"


def test_go_source_exists():
    path = "/home/user/monitor.go"
    assert os.path.isfile(path), f"Go source code not found at {path}"


def test_go_binary_exists_and_executable():
    path = "/home/user/monitor"
    assert os.path.isfile(path), f"Compiled Go binary not found at {path}"
    assert os.access(path, os.X_OK), f"Go binary at {path} is not executable"


def test_metrics_endpoint():
    url = "http://127.0.0.1:8080/metrics"
    output = ""
    for _ in range(3):
        try:
            with urllib.request.urlopen(url, timeout=2) as response:
                output = response.read().decode("utf-8")
                break
        except (urllib.error.URLError, ConnectionError):
            time.sleep(1)
    else:
        assert False, f"Failed to connect to the metrics endpoint at {url}"

    lines = [line.strip() for line in output.split("\n") if line.strip()]
    expected_metric = "legacy_service_uptime_seconds 86400"
    assert any(line == expected_metric for line in lines), (
        f"Expected metric '{expected_metric}' not found in the output.\n"
        f"Actual output:\n{output}"
    )
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_original_state.py -x --tb=short 2>&1 || fail

BACKUP=/tmp/legacy_cli.py.verifier_backup
cp -a /home/user/legacy_cli.py "$BACKUP" || fail
MONITOR_PID=""
cleanup() {
    if [ -n "$MONITOR_PID" ]; then
        kill "$MONITOR_PID" 2>/dev/null || true
        wait "$MONITOR_PID" 2>/dev/null || true
    fi
    cp -a "$BACKUP" /home/user/legacy_cli.py 2>/dev/null || true
}
trap cleanup EXIT

# Replace the CLI only during verification with an equivalent interactive CLI
# whose uptime is unpredictable on every invocation and whose transcript records
# whether it was spawned through the submitted Expect script.
cat <<'CLI_EOF' > /home/user/legacy_cli.py
#!/usr/bin/env python3
import json
import os
import secrets
import sys

LOG = "/tmp/legacy_verifier_calls.jsonl"


def cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode("utf-8", "replace").strip()
    except OSError:
        return ""


sys.stdout.write("Username: ")
sys.stdout.flush()
username = sys.stdin.readline().strip()
sys.stdout.write("Password: ")
sys.stdout.flush()
password = sys.stdin.readline().strip()

if username != "admin" or password != "sre_admin_pass":
    print("Authentication failed.")
    sys.exit(1)

sys.stdout.write("Cmd: ")
sys.stdout.flush()
command = sys.stdin.readline().strip()
if command != "get_uptime":
    print("Unknown command.")
    sys.exit(1)

uptime = 100000 + secrets.randbelow(900000000)
record = {
    "username": username,
    "password": password,
    "command": command,
    "uptime": uptime,
    "parent_cmdline": cmdline(os.getppid()),
}
with open(LOG, "a", encoding="utf-8") as f:
    f.write(json.dumps(record) + "\n")
print(f"System Uptime: {uptime} seconds")
CLI_EOF
chmod +x /home/user/legacy_cli.py
rm -f /tmp/legacy_verifier_calls.jsonl

# Stop whichever process currently owns the listening socket so the submitted
# executable itself can be launched and tested.
python3 <<'PY'
import os
import signal
import time

inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                if fields[1].split(":")[-1].upper() == "1F90" and fields[3] == "0A":
                    inodes.add(fields[9])
    except OSError:
        pass

for name in os.listdir("/proc"):
    if not name.isdigit():
        continue
    fd_dir = f"/proc/{name}/fd"
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                try:
                    os.kill(int(name), signal.SIGTERM)
                except (ProcessLookupError, PermissionError):
                    pass
                break
    except OSError:
        pass

time.sleep(0.5)
PY

/home/user/monitor >/tmp/monitor-verifier.out 2>/tmp/monitor-verifier.err &
MONITOR_PID=$!

cat <<'TEST_EOF' > /tmp/test_dynamic_state.py
import json
import os
import subprocess
import time
import urllib.error
import urllib.request

LOG = "/tmp/legacy_verifier_calls.jsonl"


def read_calls():
    try:
        with open(LOG, encoding="utf-8") as f:
            return [json.loads(line) for line in f if line.strip()]
    except FileNotFoundError:
        return []


def assert_expect_parent(call):
    parent = call["parent_cmdline"]
    assert "/home/user/get_health.exp" in parent, (
        "legacy_cli.py was not invoked through /home/user/get_health.exp; "
        f"parent command was {parent!r}"
    )
    assert "expect" in parent.lower(), (
        f"get_health.exp was not run by Expect; parent command was {parent!r}"
    )


def test_binary_is_a_go_executable_and_source_builds():
    info = subprocess.run(
        ["go", "version", "-m", "/home/user/monitor"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=10,
    )
    assert info.returncode == 0 and "go1." in info.stdout, (
        f"/home/user/monitor is not a Go executable:\n{info.stdout}"
    )
    built = subprocess.run(
        ["go", "build", "-o", "/tmp/monitor-source-check", "/home/user/monitor.go"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert built.returncode == 0, f"monitor.go does not build:\n{built.stdout}"


def test_expect_script_authenticates_runs_command_and_prints_uptime():
    before = len(read_calls())
    result = subprocess.run(
        ["expect", "/home/user/get_health.exp"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Expect script failed with {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    calls = read_calls()
    assert len(calls) == before + 1, "Expect script did not invoke legacy_cli.py exactly once"
    call = calls[-1]
    assert call["username"] == "admin"
    assert call["password"] == "sre_admin_pass"
    assert call["command"] == "get_uptime"
    assert_expect_parent(call)
    expected = f"System Uptime: {call['uptime']} seconds"
    assert expected in result.stdout.splitlines(), (
        f"Expected exact output line {expected!r}. Actual stdout:\n{result.stdout}"
    )


def test_metrics_dynamically_invokes_expect_and_emits_prometheus_gauge():
    before = len(read_calls())
    output = None
    last_error = None
    for _ in range(10):
        try:
            with urllib.request.urlopen("http://127.0.0.1:8080/metrics", timeout=3) as response:
                assert response.status == 200
                output = response.read().decode("utf-8")
                break
        except (urllib.error.URLError, ConnectionError, TimeoutError) as exc:
            last_error = exc
            time.sleep(0.4)
    assert output is not None, f"Submitted monitor did not serve /metrics: {last_error}"

    calls = read_calls()
    assert len(calls) == before + 1, (
        "Each /metrics request must dynamically invoke get_health.exp exactly once"
    )
    call = calls[-1]
    assert call["username"] == "admin"
    assert call["password"] == "sre_admin_pass"
    assert call["command"] == "get_uptime"
    assert_expect_parent(call)

    lines = [line.strip() for line in output.splitlines() if line.strip()]
    assert "# HELP legacy_service_uptime_seconds Uptime of the legacy system" in lines
    assert "# TYPE legacy_service_uptime_seconds gauge" in lines
    expected_metric = f"legacy_service_uptime_seconds {call['uptime']}"
    assert expected_metric in lines, (
        f"Expected dynamically derived metric {expected_metric!r}. Actual output:\n{output}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_dynamic_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
