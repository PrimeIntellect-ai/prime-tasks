#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
import time
from datetime import datetime, timedelta, timezone

import pytest

LOG = "/home/user/capacity_data/metrics.log"
SOURCE = "/home/user/monitor/cap_monitor.cpp"
BINARY = "/home/user/monitor/cap_monitor"
SUPERVISOR = "/home/user/monitor/supervise.sh"
LINE_RE = re.compile(r'^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] IFACE:([a-zA-Z0-9_-]+) GW:([0-9.]+) LOAD:([0-9.]+)$')


def default_route():
    try:
        output = subprocess.check_output(["ip", "route"], text=True)
    except subprocess.CalledProcessError:
        pytest.fail("Failed to run 'ip route'.")

    expected_iface = None
    expected_gw = None
    for line in output.splitlines():
        if line.startswith("default"):
            parts = line.split()
            if "dev" in parts:
                expected_iface = parts[parts.index("dev") + 1]
            if "via" in parts:
                expected_gw = parts[parts.index("via") + 1]
            break

    assert expected_iface is not None, "Could not determine default interface from 'ip route'."
    assert expected_gw is not None, "Could not determine default gateway from 'ip route'."
    return expected_iface, expected_gw


def kill_matching(pattern):
    result = subprocess.run(["pgrep", "-f", pattern], text=True, capture_output=True)
    if result.returncode == 0:
        for value in result.stdout.split():
            pid = int(value)
            if pid != os.getpid():
                try:
                    os.kill(pid, 15)
                except ProcessLookupError:
                    pass
    time.sleep(0.4)
    result = subprocess.run(["pgrep", "-f", pattern], text=True, capture_output=True)
    if result.returncode == 0:
        for value in result.stdout.split():
            pid = int(value)
            if pid != os.getpid():
                try:
                    os.kill(pid, 9)
                except ProcessLookupError:
                    pass


def stop_managed_processes():
    kill_matching("/home/user/monitor/supervise.sh")
    kill_matching("/home/user/monitor/cap_monitor")


def start_supervisor_and_wait():
    subprocess.Popen(
        ["nohup", SUPERVISOR],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    deadline = time.time() + 7
    while time.time() < deadline:
        supervisor_ok = subprocess.run(
            ["pgrep", "-f", "supervise.sh"], capture_output=True
        ).returncode == 0
        daemon_ok = subprocess.run(
            ["pgrep", "-f", "cap_monitor"], capture_output=True
        ).returncode == 0
        try:
            line_count = len(open(LOG, encoding="utf-8").readlines())
        except OSError:
            line_count = 0
        if supervisor_ok and daemon_ok and line_count >= 3:
            return
        time.sleep(0.25)
    pytest.fail("Supervisor did not resume daemon logging after behavioral tests.")


def assert_bad_argument_count(path, args):
    before = os.path.getsize(LOG)
    proc = subprocess.Popen([path] + args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        return_code = proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
        pytest.fail(f"{path} did not reject argument count {len(args)} promptly.")

    assert return_code != 0, f"{path} accepted argument count {len(args)} instead of requiring exactly two arguments."
    time.sleep(0.2)
    assert os.path.getsize(LOG) == before, f"{path} wrote metrics after being invoked with {len(args)} arguments."


def exercise_monitor(path, iface, gateway):
    open(LOG, "w").close()
    env = os.environ.copy()
    env["TZ"] = "Asia/Tokyo"
    proc = subprocess.Popen(
        [path, iface, gateway], env=env,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )

    observed_loads = []
    arrivals = []
    seen = 0
    deadline = time.monotonic() + 4.4
    try:
        while time.monotonic() < deadline:
            assert proc.poll() is None, f"{path} exited despite receiving exactly two arguments."
            with open("/proc/loadavg", encoding="ascii") as f:
                observed_loads.append(float(f.read().split()[0]))
            with open(LOG, encoding="utf-8") as f:
                count = len(f.readlines())
            if count > seen:
                now = time.monotonic()
                arrivals.extend([now] * (count - seen))
                seen = count
            time.sleep(0.05)
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()

    with open(LOG, "r", encoding="utf-8") as f:
        lines_with_endings = f.readlines()

    assert 3 <= len(lines_with_endings) <= 6, f"{path} produced {len(lines_with_endings)} lines in 4.4 seconds instead of logging once per second."
    assert all(line.endswith("\n") for line in lines_with_endings), "Each metric must be appended as one complete line."
    assert len(arrivals) == len(lines_with_endings), "Metric lines were not observable as periodic appends."

    for left, right in zip(arrivals, arrivals[1:]):
        interval = right - left
        assert 0.60 <= interval <= 1.60, f"Metric append interval was {interval:.2f}s instead of approximately one second."

    parsed_times = []
    for raw in lines_with_endings:
        line = raw.rstrip("\n")
        match = LINE_RE.fullmatch(line)
        assert match is not None, f"Log line format is incorrect: {line}"
        timestamp, logged_iface, logged_gateway, logged_load = match.groups()
        assert logged_iface == iface, f"Monitor did not log its supplied interface argument '{iface}'."
        assert logged_gateway == gateway, f"Monitor did not log its supplied gateway argument '{gateway}'."

        load_value = float(logged_load)
        assert any(abs(load_value - sample) <= 0.011 for sample in observed_loads), (
            f"Logged LOAD {logged_load} does not match the 1-minute load observed in /proc/loadavg."
        )

        parsed = datetime.strptime(timestamp, "%Y-%m-%d %H:%M:%S").replace(
            tzinfo=timezone(timedelta(hours=9))
        )
        parsed_times.append(parsed)
        assert abs((datetime.now(timezone.utc) - parsed).total_seconds()) < 15, (
            f"Logged time {timestamp} is not current Asia/Tokyo local time."
        )

    for left, right in zip(parsed_times, parsed_times[1:]):
        assert (right - left).total_seconds() == 1, "Successive logged timestamps are not one second apart."


def test_directories_and_files():
    assert os.path.isdir("/home/user/capacity_data"), "Directory /home/user/capacity_data does not exist."
    assert os.path.isfile(LOG), "File metrics.log does not exist."
    assert os.path.isfile(SOURCE), "File cap_monitor.cpp does not exist."

    assert os.path.isfile(BINARY), "Executable cap_monitor does not exist."
    st = os.stat(BINARY)
    assert bool(st.st_mode & stat.S_IXUSR), "cap_monitor is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "cap_monitor is not a compiled executable."

    assert os.path.isfile(SUPERVISOR), "Script supervise.sh does not exist."
    st = os.stat(SUPERVISOR)
    assert bool(st.st_mode & stat.S_IXUSR), "supervise.sh is not executable."


def test_acls():
    try:
        output = subprocess.check_output(["getfacl", LOG], text=True)
    except subprocess.CalledProcessError:
        pytest.fail("Failed to run getfacl on metrics.log.")

    assert any(re.match(r'^user:nobody:r--', line) for line in output.splitlines()), (
        "ACL rule for user 'nobody' with read-only access (r--) is missing."
    )
    assert any(line == "user::rw-" for line in output.splitlines()), (
        "The owning user does not retain read/write access to metrics.log."
    )


def test_submitted_cpp_and_executable_behavior():
    stop_managed_processes()
    rebuilt = "/tmp/cap_monitor_from_source"
    try:
        compile_result = subprocess.run(
            ["g++", "-std=c++17", SOURCE, "-o", rebuilt],
            text=True, capture_output=True, timeout=20
        )
        assert compile_result.returncode == 0, f"cap_monitor.cpp does not compile: {compile_result.stderr}"

        for path in (rebuilt, BINARY):
            open(LOG, "w").close()
            assert_bad_argument_count(path, [])
            assert_bad_argument_count(path, ["only_one"])
            assert_bad_argument_count(path, ["a", "192.0.2.1", "extra"])

            token = str((os.getpid() + (1 if path == rebuilt else 2)) % 10000)
            exercise_monitor(path, "verify_" + token, "198.51.100." + str(10 + int(token) % 200))
    finally:
        stop_managed_processes()
        open(LOG, "w").close()
        start_supervisor_and_wait()


def test_supervisor_and_daemon_state():
    try:
        subprocess.check_output(["pgrep", "-f", "supervise.sh"])
    except subprocess.CalledProcessError:
        pytest.fail("supervise.sh is not running.")

    try:
        subprocess.check_output(["pgrep", "-f", "cap_monitor"])
    except subprocess.CalledProcessError:
        pytest.fail("cap_monitor is not running.")


def test_log_formatting_and_routing_data():
    expected_iface, expected_gw = default_route()
    with open(LOG, "r", encoding="utf-8") as f:
        lines = f.readlines()

    assert len(lines) >= 3, "metrics.log does not contain at least 3 lines."
    last_line = lines[-1].strip()
    match = LINE_RE.fullmatch(last_line)
    assert match is not None, f"Log line format is incorrect: {last_line}"

    log_time_str, log_iface, log_gw, log_load = match.groups()
    assert log_iface == expected_iface, f"Logged interface '{log_iface}' does not match expected '{expected_iface}'."
    assert log_gw == expected_gw, f"Logged gateway '{log_gw}' does not match expected '{expected_gw}'."

    with open("/proc/loadavg", encoding="ascii") as f:
        current_load = float(f.read().split()[0])
    assert abs(float(log_load) - current_load) <= 0.15, (
        f"Logged LOAD '{log_load}' is inconsistent with /proc/loadavg value '{current_load}'."
    )

    log_time = datetime.strptime(log_time_str, "%Y-%m-%d %H:%M:%S").replace(
        tzinfo=timezone(timedelta(hours=9))
    )
    current_time = datetime.now(timezone.utc)
    delta = abs((current_time - log_time).total_seconds())
    assert delta < 10, f"Logged time {log_time_str} (JST) is too far from current time. Delta: {delta}s."


def test_restart_policy():
    try:
        pid_out = subprocess.check_output(["pgrep", "-f", "cap_monitor"], text=True).strip()
        old_pids = set(pid_out.split())
    except subprocess.CalledProcessError:
        pytest.fail("cap_monitor is not running before restart test.")

    subprocess.run(["pkill", "-f", "cap_monitor"])
    time.sleep(3)

    try:
        pid_out = subprocess.check_output(["pgrep", "-f", "cap_monitor"], text=True).strip()
        new_pids = set(pid_out.split())
    except subprocess.CalledProcessError:
        pytest.fail("cap_monitor was not restarted by the supervisor.")

    assert new_pids != old_pids, "cap_monitor PID did not change or it wasn't killed successfully."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
