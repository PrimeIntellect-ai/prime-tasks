#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import signal
import stat
import subprocess
import time

CPP = "/home/user/workspace/mda_supervisor.cpp"
EXE = "/home/user/workspace/mda_supervisor"
LOG = "/home/user/dashboard_metrics.log"
OUTBOX = "/home/user/mail/outbox"
NEXT_VERSION = "/home/user/next_version.txt"
LINE_RE = re.compile(r"INSTANCE ([123]) VERSION (\S+) EVENT (START|CRASH|GRACEFUL_STOP)")


def wait_until(predicate, timeout=8.0, interval=0.05, message="condition not met"):
    deadline = time.monotonic() + timeout
    last_error = None
    while time.monotonic() < deadline:
        try:
            if predicate():
                return
        except (FileNotFoundError, ProcessLookupError, OSError, UnicodeDecodeError) as exc:
            last_error = exc
        time.sleep(interval)
    if last_error:
        raise AssertionError(f"{message}; last error: {last_error}")
    raise AssertionError(message)


def read_log():
    with open(LOG, "r", encoding="utf-8") as f:
        raw = f.read()
    lines = raw.splitlines()
    for line in lines:
        assert LINE_RE.fullmatch(line), f"Malformed metrics line: {line!r}"
    return lines


def direct_children(ppid):
    result = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/stat", "r", encoding="utf-8") as f:
                data = f.read()
            # The comm field can contain spaces and parentheses, so parse after its final ')'.
            fields = data[data.rfind(")") + 2:].split()
            if int(fields[1]) == ppid:
                result.append(int(entry))
        except (FileNotFoundError, ProcessLookupError, ValueError, IndexError):
            pass
    return result


def child_identity(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        args = [x.decode("utf-8") for x in f.read().split(b"\0") if x]
    assert "/home/user/mda.sh" in args, f"Child {pid} is not running /home/user/mda.sh: {args!r}"
    index = args.index("/home/user/mda.sh")
    assert args[index + 1:] in (["1", "v1.0"], ["2", "v1.0"], ["3", "v1.0"],
                                ["1", "v2.0"], ["2", "v2.0"], ["3", "v2.0"]), \
        f"Unexpected MDA arguments for child {pid}: {args!r}"
    return int(args[index + 1]), args[index + 2]


def child_state(ppid):
    children = direct_children(ppid)
    state = {}
    for pid in children:
        instance_id, version = child_identity(pid)
        assert instance_id not in state, f"Multiple direct children for instance {instance_id}"
        state[instance_id] = (pid, version)
    return state


def expected_line(instance_id, version, event):
    return f"INSTANCE {instance_id} VERSION {version} EVENT {event}"


def test_supervisor_lifecycle():
    assert os.path.isfile(CPP), f"Source file {CPP} not found."

    result = subprocess.run(
        ["g++", "-std=c++11", CPP, "-o", EXE],
        capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, f"Compilation failed:\n{result.stderr}"
    mode = os.stat(EXE).st_mode
    assert stat.S_ISREG(mode) and os.access(EXE, os.X_OK), "Compiled supervisor is not an executable regular file."

    if os.path.exists(LOG):
        os.remove(LOG)
    if os.path.exists(NEXT_VERSION):
        os.remove(NEXT_VERSION)
    for path in glob.glob(os.path.join(OUTBOX, "alert_*.eml")):
        os.remove(path)

    proc = subprocess.Popen([EXE], start_new_session=True)
    try:
        def initial_ready():
            assert proc.poll() is None, "Supervisor exited during startup."
            lines = read_log()
            state = child_state(proc.pid)
            return len(lines) == 3 and len(state) == 3

        wait_until(initial_ready, message="Supervisor did not start exactly three MDA children.")
        initial_lines = read_log()
        initial_state = child_state(proc.pid)
        assert set(initial_state) == {1, 2, 3}
        assert all(version == "v1.0" for _, version in initial_state.values())
        assert sorted(initial_lines) == sorted(
            expected_line(i, "v1.0", "START") for i in (1, 2, 3)
        ), f"Initial START events were not exact: {initial_lines!r}"
        assert not glob.glob(os.path.join(OUTBOX, "alert_*.eml")), "Alert created before any crashes."

        # Crash instance 1 once and require that same instance/version to be restarted.
        first_pid = initial_state[1][0]
        os.kill(first_pid, signal.SIGKILL)
        after_first = initial_lines + [
            expected_line(1, "v1.0", "CRASH"),
            expected_line(1, "v1.0", "START"),
        ]

        def first_restart_ready():
            assert proc.poll() is None, "Supervisor exited after first child crash."
            state = child_state(proc.pid)
            return read_log() == after_first and set(state) == {1, 2, 3} and \
                state[1][0] != first_pid and all(v == "v1.0" for _, v in state.values())

        wait_until(first_restart_ready, message="Instance 1 was not correctly restarted after its first crash.")
        assert not glob.glob(os.path.join(OUTBOX, "alert_*.eml")), "Alert generated before instance 1 had two crashes."

        # Crash the replacement and require the lifetime crash count to trigger the exact alert.
        second_pid = child_state(proc.pid)[1][0]
        os.kill(second_pid, signal.SIGKILL)
        after_second = after_first + [
            expected_line(1, "v1.0", "CRASH"),
            expected_line(1, "v1.0", "START"),
        ]
        alert_path = os.path.join(OUTBOX, "alert_1.eml")

        def second_restart_ready():
            assert proc.poll() is None, "Supervisor exited after second child crash."
            state = child_state(proc.pid)
            return read_log() == after_second and set(state) == {1, 2, 3} and \
                state[1][0] != second_pid and all(v == "v1.0" for _, v in state.values()) and \
                os.path.isfile(alert_path)

        wait_until(second_restart_ready, message="Second crash did not cause a correct restart and alert.")
        alerts = glob.glob(os.path.join(OUTBOX, "alert_*.eml"))
        assert alerts == [alert_path], f"Expected only alert_1.eml, found {alerts!r}"
        with open(alert_path, "r", encoding="utf-8", newline="") as f:
            alert_content = f.read()
        expected_alert = (
            "To: admin@local\n"
            "Subject: Alert Instance 1\n"
            "\n"
            "Crash loop detected for instance 1 version v1.0.\n"
        )
        assert alert_content == expected_alert, f"Alert content was not exact: {alert_content!r}"

        # Trigger a real rolling deployment and require exact sequential stop/start events.
        before_rollout = child_state(proc.pid)
        with open(NEXT_VERSION, "w", encoding="utf-8") as f:
            f.write("v2.0\n")
        os.kill(proc.pid, signal.SIGUSR1)

        rollout_lines = []
        for instance_id in (1, 2, 3):
            rollout_lines.extend([
                expected_line(instance_id, "v1.0", "GRACEFUL_STOP"),
                expected_line(instance_id, "v2.0", "START"),
            ])
        final_lines = after_second + rollout_lines

        def rollout_ready():
            assert proc.poll() is None, "Supervisor exited while handling SIGUSR1."
            state = child_state(proc.pid)
            return read_log() == final_lines and set(state) == {1, 2, 3} and \
                all(state[i][1] == "v2.0" for i in (1, 2, 3))

        wait_until(rollout_ready, timeout=10.0, message="Rolling deployment did not complete correctly.")
        final_state = child_state(proc.pid)
        for instance_id in (1, 2, 3):
            assert final_state[instance_id][0] != before_rollout[instance_id][0], \
                f"Instance {instance_id} process was not replaced during rollout."
            assert not os.path.exists(f"/proc/{before_rollout[instance_id][0]}"), \
                f"Old process for instance {instance_id} is still alive after rollout."

        # Recheck all lines strictly, including exact counts and instance/version associations.
        assert read_log() == final_lines
        assert sum(line.endswith("EVENT CRASH") for line in final_lines) == 2
        assert sum(line.endswith("EVENT GRACEFUL_STOP") for line in final_lines) == 3
        assert sum("VERSION v2.0 EVENT START" in line for line in final_lines) == 3
    finally:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
