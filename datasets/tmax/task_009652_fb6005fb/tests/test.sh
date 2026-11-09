#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import re
import signal
import subprocess
import time

import pytest

CONFIG = "/home/user/.config/finops/supervisor.conf"
SCRIPT = "/home/user/supervisor.sh"
LOG = "/home/user/supervisor.log"
PIDFILE = "/home/user/supervisor.pid"
HEARTBEAT = "/home/user/heartbeat.txt"
BEHAVIOR = "/home/user/cost_analyzer_behavior.txt"
TARGET = "/home/user/cost_analyzer.py"

restart_pattern = re.compile(r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] Restarted target process$")
exit_pattern = re.compile(r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] Max restarts reached, exiting$")


def read_lines(path=LOG):
    if not os.path.isfile(path):
        return []
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def proc_args(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
    except (FileNotFoundError, PermissionError, ProcessLookupError):
        return []


def live(pid):
    try:
        with open(f"/proc/{pid}/stat", "r") as f:
            state = f.read().split()[2]
        return state != "Z"
    except (FileNotFoundError, ProcessLookupError, PermissionError, IndexError):
        return False


def matching_pids(argument):
    result = []
    for name in os.listdir("/proc"):
        if name.isdigit():
            pid = int(name)
            if live(pid) and argument in proc_args(pid):
                result.append(pid)
    return result


def stop_matching_processes():
    me = os.getpid()
    candidates = set(matching_pids(SCRIPT) + matching_pids(TARGET))
    candidates.discard(me)
    for sig in (signal.SIGTERM, signal.SIGKILL):
        for pid in list(candidates):
            if live(pid):
                try:
                    os.kill(pid, sig)
                except ProcessLookupError:
                    pass
        time.sleep(0.3)


def reset_runtime(behavior):
    stop_matching_processes()
    for path in (LOG, PIDFILE, HEARTBEAT):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
    with open(BEHAVIOR, "w") as f:
        f.write(behavior + "\n")


def demote_to_user():
    account = pwd.getpwnam("user")
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


def start_supervisor():
    return subprocess.Popen(
        ["bash", SCRIPT],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
        preexec_fn=demote_to_user,
    )


def stop_process(proc):
    if proc is None or proc.poll() is not None:
        return
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        pass


def wait_for(predicate, timeout, message):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.1)
    pytest.fail(message)


def assert_exact_cycle_log():
    lines = read_lines()
    assert len(lines) == 4, f"Expected exactly 4 lines in the log file, but found {len(lines)}."
    for i in range(3):
        assert restart_pattern.match(lines[i]), (
            f"Log line {i+1} does not match the expected restart format. Got: '{lines[i]}'"
        )
    assert exit_pattern.match(lines[3]), (
        f"Log line 4 does not match the expected exit format. Got: '{lines[3]}'"
    )


def test_config_file_contents():
    assert os.path.isfile(CONFIG), f"Config file {CONFIG} does not exist."
    with open(CONFIG, "r") as f:
        content = f.read()

    assert 'TARGET_CMD="/home/user/cost_analyzer.py"' in content, "TARGET_CMD is missing or incorrect in config."
    assert 'HEARTBEAT_FILE="/home/user/heartbeat.txt"' in content, "HEARTBEAT_FILE is missing or incorrect in config."
    assert 'LOG_FILE="/home/user/supervisor.log"' in content, "LOG_FILE is missing or incorrect in config."
    assert 'MAX_RESTARTS=3' in content or 'MAX_RESTARTS="3"' in content, "MAX_RESTARTS is missing or incorrect in config."


def test_supervisor_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"Supervisor script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Supervisor script {SCRIPT} is not executable."


def test_supervisor_log_contents():
    assert os.path.isfile(LOG), f"Log file {LOG} does not exist. Did the supervisor run and create it?"
    assert_exact_cycle_log()


def test_crash_supervision_generates_real_cycle():
    reset_runtime("crash")
    proc = start_supervisor()
    try:
        try:
            proc.wait(timeout=18)
        except subprocess.TimeoutExpired:
            pytest.fail("Supervisor did not complete the configured crash/restart cycle.")
        assert_exact_cycle_log()
        assert not matching_pids(TARGET), "Target process was left running after max restarts were reached."
    finally:
        stop_process(proc)
        stop_matching_processes()


def test_pidfile_idempotency_and_healthy_heartbeat():
    reset_runtime("normal")
    first = start_supervisor()
    second = None
    try:
        wait_for(lambda: os.path.isfile(PIDFILE), 4, "Supervisor did not create /home/user/supervisor.pid.")

        def valid_pidfile():
            try:
                text = open(PIDFILE).read().strip()
                pid = int(text)
                return pid if live(pid) and SCRIPT in proc_args(pid) else False
            except (OSError, ValueError):
                return False

        recorded_pid = wait_for(valid_pidfile, 2, "PID file does not identify the running supervisor.")
        assert recorded_pid == first.pid, "PID file does not identify the original supervisor instance."
        initial_targets = wait_for(lambda: matching_pids(TARGET), 4, "Supervisor did not start the configured target.")
        assert len(initial_targets) == 1, "Expected exactly one target process."
        initial_target = initial_targets[0]

        second = start_supervisor()
        try:
            second.wait(timeout=3)
        except subprocess.TimeoutExpired:
            pytest.fail("A second supervisor instance did not exit promptly.")

        assert first.poll() is None, "Second invocation displaced or killed the original supervisor."
        assert matching_pids(TARGET) == [initial_target], "Second invocation started an additional target process."

        time.sleep(7)
        assert first.poll() is None, "Supervisor exited while its target was healthy."
        assert live(initial_target), "Healthy target was unnecessarily killed or restarted."
        assert not read_lines(), "Supervisor logged a restart despite a fresh heartbeat and live target."
    finally:
        stop_process(second)
        stop_process(first)
        stop_matching_processes()


def test_stale_heartbeat_kills_and_restarts_target():
    reset_runtime("hang")
    proc = start_supervisor()
    started = time.monotonic()
    try:
        initial = wait_for(lambda: matching_pids(TARGET), 4, "Supervisor did not start the hanging target.")
        assert len(initial) == 1, "Expected exactly one initial target process."
        old_pid = initial[0]
        wait_for(lambda: os.path.isfile(HEARTBEAT), 3, "Target did not create its heartbeat file.")

        def restart_logged():
            lines = read_lines()
            return lines if any(restart_pattern.match(line) for line in lines) else False

        wait_for(restart_logged, 12, "Supervisor did not restart a live target with a stale heartbeat.")
        assert time.monotonic() - started >= 4.5, "Supervisor restarted before the heartbeat could become stale."
        wait_for(lambda: not live(old_pid), 3, "Stuck target process was not killed during restart.")

        def replacement_pid():
            pids = [pid for pid in matching_pids(TARGET) if pid != old_pid]
            return pids[0] if pids else False

        new_pid = wait_for(replacement_pid, 3, "Supervisor did not launch a replacement target.")
        assert new_pid != old_pid and live(new_pid), "Replacement target is not running."
    finally:
        stop_process(proc)
        stop_matching_processes()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
