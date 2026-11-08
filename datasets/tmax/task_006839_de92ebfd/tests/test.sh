#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import signal
import socket
import stat
import subprocess
import tempfile
import time

import pytest

HOME = "/home/user"
DASHBOARD_JSON = HOME + "/dashboard.json"
STATUS_JSON = HOME + "/status.json"
SUPERVISOR_PID_FILE = HOME + "/supervisor.pid"
SUPERVISE_LOG = HOME + "/supervise.log"
CRASH_FILE = HOME + "/crash_now"
DEPLOY_SH = HOME + "/deploy.sh"
UPDATE_SCRIPT = HOME + "/update_dash.py"
COLLECTOR_SCRIPT = HOME + "/check_targets.py"
SUPERVISOR_SCRIPT = HOME + "/supervise.py"


def read_json_when(path, predicate=lambda value: True, timeout=6.0):
    deadline = time.monotonic() + timeout
    last_error = None
    while time.monotonic() < deadline:
        try:
            with open(path) as f:
                value = json.load(f)
            if predicate(value):
                return value
        except (OSError, ValueError) as exc:
            last_error = exc
        time.sleep(0.1)
    raise AssertionError(f"Timed out waiting for valid expected JSON in {path}: {last_error}")


def process_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode(errors="replace")
    except OSError:
        return ""


def stop_pipeline_processes():
    needles = (COLLECTOR_SCRIPT, SUPERVISOR_SCRIPT)
    me = os.getpid()
    for sig in (signal.SIGTERM, signal.SIGKILL):
        for entry in os.listdir("/proc"):
            if not entry.isdigit() or int(entry) == me:
                continue
            cmd = process_cmdline(int(entry))
            if any(needle in cmd for needle in needles):
                try:
                    os.kill(int(entry), sig)
                except OSError:
                    pass
        time.sleep(0.35)


def test_dashboard_json_updated():
    """Verify that update_dash.py correctly modified dashboard.json."""
    assert os.path.exists(DASHBOARD_JSON), f"Missing {DASHBOARD_JSON}"

    with open(DASHBOARD_JSON, "r") as f:
        data = json.load(f)

    users = data.get("users", [])
    obs_admin_found = any(
        u.get("username") == "obs_admin" and u.get("group") == "obs_group"
        for u in users
    )
    assert obs_admin_found, "User 'obs_admin' with group 'obs_group' not found in users list."

    targets = data.get("monitored_targets", [])
    assert "127.0.0.1:8001" in targets, "127.0.0.1:8001 is missing from monitored_targets."
    assert "127.0.0.1:8002" in targets, "127.0.0.1:8002 is missing from monitored_targets."


def test_deploy_sh_executable():
    """Verify deploy.sh is executable."""
    assert os.path.exists(DEPLOY_SH), f"Missing {DEPLOY_SH}"
    assert os.access(DEPLOY_SH, os.X_OK), f"{DEPLOY_SH} is not executable."


def test_supervisor_running():
    """Verify that supervisor.pid contains a valid running PID."""
    assert os.path.exists(SUPERVISOR_PID_FILE), f"Missing {SUPERVISOR_PID_FILE}"
    with open(SUPERVISOR_PID_FILE, "r") as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"PID file {SUPERVISOR_PID_FILE} does not contain a valid integer."
    pid = int(pid_str)
    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f"Process with PID {pid} from {SUPERVISOR_PID_FILE} is not running.")


def test_status_json_content():
    """Verify status.json contains the correct connectivity results."""
    for _ in range(10):
        if os.path.exists(STATUS_JSON):
            break
        time.sleep(0.5)
    assert os.path.exists(STATUS_JSON), f"Missing {STATUS_JSON}"
    with open(STATUS_JSON, "r") as f:
        status_data = json.load(f)
    assert status_data.get("127.0.0.1:9090") == "DOWN", "Expected 127.0.0.1:9090 to be DOWN"
    assert status_data.get("127.0.0.1:8001") == "UP", "Expected 127.0.0.1:8001 to be UP"
    assert status_data.get("127.0.0.1:8002") == "DOWN", "Expected 127.0.0.1:8002 to be DOWN"


def test_supervision_crash_recovery():
    """Test process supervision by triggering a crash and verifying recovery."""
    initial_restarts = 0
    if os.path.exists(SUPERVISE_LOG):
        with open(SUPERVISE_LOG, "r") as f:
            initial_restarts = f.read().splitlines().count("RESTARTED")
    with open(CRASH_FILE, "w") as f:
        f.write("crash")
    restarted = False
    for _ in range(10):
        time.sleep(0.5)
        if os.path.exists(SUPERVISE_LOG):
            with open(SUPERVISE_LOG, "r") as f:
                if f.read().splitlines().count("RESTARTED") > initial_restarts:
                    restarted = True
                    break
    assert restarted, "Supervisor did not log 'RESTARTED' after triggering a crash."
    assert not os.path.exists(CRASH_FILE), f"Crash file {CRASH_FILE} was not deleted by the agent."


def test_scripts_and_general_pipeline_behavior():
    for path in (UPDATE_SCRIPT, COLLECTOR_SCRIPT, SUPERVISOR_SCRIPT, DEPLOY_SH):
        assert os.path.isfile(path), f"Missing required script {path}"

    # Exercise update_dash.py on independent data and run it twice to verify idempotency.
    with tempfile.TemporaryDirectory() as td:
        sample = os.path.join(td, "sample.json")
        original = {
            "users": [{"username": "alice", "group": "engineering"}],
            "monitored_targets": ["127.0.0.1:4567"],
            "unrelated": {"keep": True},
        }
        with open(sample, "w") as f:
            json.dump(original, f)
        for _ in range(2):
            result = subprocess.run(
                ["python3", UPDATE_SCRIPT, sample], capture_output=True, text=True, timeout=5
            )
            assert result.returncode == 0, result.stderr
        with open(sample) as f:
            changed = json.load(f)
        assert changed["unrelated"] == {"keep": True}
        assert changed["users"].count({"username": "obs_admin", "group": "obs_group"}) == 1
        assert sum(u.get("username") == "obs_admin" for u in changed["users"]) == 1
        assert changed["monitored_targets"].count("127.0.0.1:8001") == 1
        assert changed["monitored_targets"].count("127.0.0.1:8002") == 1
        assert "127.0.0.1:4567" in changed["monitored_targets"]

    saved = {}
    modes = {}
    paths = [DASHBOARD_JSON, STATUS_JSON, SUPERVISE_LOG, COLLECTOR_SCRIPT]
    for path in paths:
        if os.path.exists(path):
            with open(path, "rb") as f:
                saved[path] = f.read()
            modes[path] = stat.S_IMODE(os.stat(path).st_mode)
        else:
            saved[path] = None

    listener = None
    collector = None
    tested_supervisor = None
    try:
        stop_pipeline_processes()
        for path in (CRASH_FILE, STATUS_JSON, SUPERVISOR_PID_FILE):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass

        # Use verifier-selected ports to prove that the collector reads arbitrary targets
        # and performs real, repeated TCP checks rather than emitting fixed answers.
        listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind(("127.0.0.1", 0))
        listener.listen(8)
        open_port = listener.getsockname()[1]

        probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        probe.bind(("127.0.0.1", 0))
        closed_port = probe.getsockname()[1]
        probe.close()
        targets = [f"127.0.0.1:{open_port}", f"127.0.0.1:{closed_port}"]
        with open(DASHBOARD_JSON, "w") as f:
            json.dump({"users": [], "monitored_targets": targets}, f)

        collector = subprocess.Popen(
            ["python3", COLLECTOR_SCRIPT], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        first = read_json_when(
            STATUS_JSON,
            lambda d: d.get(targets[0]) == "UP" and d.get(targets[1]) == "DOWN",
            timeout=4.5,
        )
        assert set(first) == set(targets)
        first_mtime = os.stat(STATUS_JSON).st_mtime_ns
        deadline = time.monotonic() + 3.6
        second_mtime = first_mtime
        while time.monotonic() < deadline and second_mtime == first_mtime:
            time.sleep(0.1)
            second_mtime = os.stat(STATUS_JSON).st_mtime_ns
        assert second_mtime != first_mtime, "Collector did not perform/write another two-second iteration"
        interval = (second_mtime - first_mtime) / 1_000_000_000
        assert 1.2 <= interval <= 3.4, f"Collector iteration interval was {interval:.2f}s, expected about 2s"

        listener.close()
        listener = None
        read_json_when(STATUS_JSON, lambda d: d.get(targets[0]) == "DOWN", timeout=4.5)

        with open(CRASH_FILE, "w") as f:
            f.write("crash")
        assert collector.wait(timeout=3.8) == 1
        collector = None
        assert not os.path.exists(CRASH_FILE), "Collector did not delete crash_now"

        # Run deploy.sh from a clean state and verify it really updates the dashboard,
        # backgrounds the submitted supervisor, and records that supervisor's PID.
        with open(DASHBOARD_JSON, "w") as f:
            json.dump({"users": [], "monitored_targets": ["127.0.0.1:31337"]}, f)
        result = subprocess.run(
            ["./deploy.sh"], cwd=HOME, capture_output=True, text=True, timeout=6
        )
        assert result.returncode == 0, result.stderr
        with open(DASHBOARD_JSON) as f:
            deployed = json.load(f)
        assert any(
            u.get("username") == "obs_admin" and u.get("group") == "obs_group"
            for u in deployed.get("users", [])
        )
        assert "127.0.0.1:8001" in deployed.get("monitored_targets", [])
        assert "127.0.0.1:8002" in deployed.get("monitored_targets", [])
        with open(SUPERVISOR_PID_FILE) as f:
            deployed_pid_text = f.read().strip()
        assert deployed_pid_text.isdigit()
        deployed_pid = int(deployed_pid_text)
        os.kill(deployed_pid, 0)
        assert SUPERVISOR_SCRIPT in process_cmdline(deployed_pid), "Recorded PID is not supervise.py"
        stop_pipeline_processes()

        # Replace only the supervised child temporarily. This executes the submitted
        # supervisor against controlled crashes, including expiration of a rolling window.
        counter = HOME + "/.verifier_launch_count"
        timestamps = HOME + "/.verifier_launch_times"
        for path in (counter, timestamps, SUPERVISE_LOG):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
        helper = f'''import os, time\ncount_path={counter!r}\ntime_path={timestamps!r}\ntry:\n    n=int(open(count_path).read())+1\nexcept Exception:\n    n=1\nopen(count_path,"w").write(str(n))\nwith open(time_path,"a") as f:\n    f.write(str(time.time())+"\\n")\nif n == 3:\n    time.sleep(10.5)\nraise SystemExit(1)\n'''
        with open(COLLECTOR_SCRIPT, "w") as f:
            f.write(helper)

        started = time.monotonic()
        tested_supervisor = subprocess.Popen(
            ["python3", SUPERVISOR_SCRIPT],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        rc = tested_supervisor.wait(timeout=16.0)
        elapsed = time.monotonic() - started
        tested_supervisor = None
        assert rc == 2, f"Supervisor exited with {rc}, expected rolling-policy exit code 2"
        assert elapsed >= 10.0, "Supervisor counted crashes that had expired from the rolling window"
        with open(timestamps) as f:
            launch_times = [float(x) for x in f.read().splitlines()]
        assert len(launch_times) >= 5, "Supervisor exited before three crashes occurred in one rolling window"
        assert launch_times[1] - launch_times[0] < 1.5
        assert launch_times[2] - launch_times[1] < 1.5
        with open(SUPERVISE_LOG) as f:
            log_lines = f.read().splitlines()
        assert len(log_lines) >= 4, "Supervisor did not log its restarts"
        assert all(line == "RESTARTED" for line in log_lines), "Restart log contains a non-exact line"
    finally:
        if listener is not None:
            listener.close()
        for proc in (collector, tested_supervisor):
            if proc is not None and proc.poll() is None:
                proc.kill()
                try:
                    proc.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    pass
        stop_pipeline_processes()
        for path, content in saved.items():
            if content is None:
                try:
                    os.unlink(path)
                except FileNotFoundError:
                    pass
            else:
                with open(path, "wb") as f:
                    f.write(content)
                os.chmod(path, modes[path])
        for path in (
            CRASH_FILE,
            HOME + "/.verifier_launch_count",
            HOME + "/.verifier_launch_times",
        ):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
