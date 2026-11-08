#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shlex
import signal
import subprocess
import time
import uuid

import pytest


def test_symlink_fixed():
    symlink_path = "/home/user/service_configs/monitor.json"
    assert os.path.islink(symlink_path), f"Expected {symlink_path} to be a symlink."

    target = os.readlink(symlink_path)
    expected_target = "/home/user/system_data/monitor.json"
    assert target == expected_target, f"Symlink target is incorrect. Expected {expected_target}, got {target}."


def test_supervisor_script_exists():
    script_path = "/home/user/supervisor.py"
    assert os.path.isfile(script_path), f"Supervisor script {script_path} does not exist."


def test_services_json_correct():
    services_path = "/home/user/services.json"
    assert os.path.isfile(services_path), f"Services definition file {services_path} does not exist."

    with open(services_path, "r") as f:
        try:
            services = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{services_path} is not a valid JSON file.")

    assert isinstance(services, list), f"Expected {services_path} to contain a JSON array."
    assert "qemu-system-x86_64 -display vnc=127.0.0.1:2 -nodefaults -no-reboot" in services, "QEMU command missing from services.json."
    assert "python3 /home/user/monitor.py" in services, "Monitor command missing from services.json."


def test_uptime_log_vnc_ok():
    uptime_log_path = "/home/user/uptime.log"
    assert os.path.isfile(uptime_log_path), f"Uptime log {uptime_log_path} does not exist."

    with open(uptime_log_path, "r") as f:
        lines = f.readlines()

    vnc_ok_count = sum(1 for line in lines if "VNC_OK" in line)
    assert vnc_ok_count >= 5, f"Expected at least 5 'VNC_OK' lines in {uptime_log_path}, found {vnc_ok_count}."


def test_supervisor_log_started_format():
    supervisor_log_path = "/home/user/supervisor.log"
    assert os.path.isfile(supervisor_log_path), f"Supervisor log {supervisor_log_path} does not exist."

    with open(supervisor_log_path, "r") as f:
        content = f.read()

    qemu_started = "STARTED: qemu-system-x86_64 -display vnc=127.0.0.1:2 -nodefaults -no-reboot"
    monitor_started = "STARTED: python3 /home/user/monitor.py"

    assert qemu_started in content, f"Expected '{qemu_started}' in {supervisor_log_path}."
    assert monitor_started in content, f"Expected '{monitor_started}' in {supervisor_log_path}."


def _wait_for(predicate, timeout, message):
    deadline = time.time() + timeout
    while time.time() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.1)
    pytest.fail(message)


def _state_records(path):
    try:
        with open(path, "r") as f:
            return [line.strip().split() for line in f if line.strip()]
    except FileNotFoundError:
        return []


def _proc_table():
    table = {}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode(errors="replace").strip()
            with open(f"/proc/{entry}/status", "r") as f:
                ppid = None
                for line in f:
                    if line.startswith("PPid:"):
                        ppid = int(line.split()[1])
                        break
            table[int(entry)] = (ppid, cmdline)
        except (FileNotFoundError, ProcessLookupError, PermissionError, ValueError):
            pass
    return table


def _service_supervisors_and_children():
    table = _proc_table()
    supervisors = [
        pid for pid, (_, cmd) in table.items()
        if "/home/user/supervisor.py" in cmd and "/home/user/services.json" in cmd
    ]
    results = []
    for supervisor_pid in supervisors:
        descendants = set()
        frontier = {supervisor_pid}
        while frontier:
            new = {
                pid for pid, (ppid, _) in table.items()
                if ppid in frontier and pid not in descendants
            }
            descendants.update(new)
            frontier = new
        commands = [table[pid][1] for pid in descendants if pid in table]
        results.append((supervisor_pid, commands))
    return results


def _live_service_supervisor():
    qemu_text = "qemu-system-x86_64 -display vnc=127.0.0.1:2 -nodefaults -no-reboot"
    monitor_text = "python3 /home/user/monitor.py"
    for pid, commands in _service_supervisors_and_children():
        if any(qemu_text in cmd for cmd in commands) and any(monitor_text in cmd for cmd in commands):
            return pid
    return None


def test_supervisor_executes_concurrently_and_restarts_exited_children(tmp_path):
    token = uuid.uuid4().hex
    worker = tmp_path / "worker.py"
    worker.write_text(
        "import os, sys, time\n"
        "with open(sys.argv[1], 'a') as f:\n"
        "    f.write(f'{sys.argv[2]} {os.getpid()} {time.time()}\\n')\n"
        "    f.flush()\n"
        "while True:\n"
        "    time.sleep(1)\n"
    )

    state_a = str(tmp_path / "a.state")
    state_b = str(tmp_path / "b.state")
    command_a = "python3 {} {} {}".format(
        shlex.quote(str(worker)), shlex.quote(state_a), shlex.quote(token + "-a")
    )
    command_b = "python3 {} {} {}".format(
        shlex.quote(str(worker)), shlex.quote(state_b), shlex.quote(token + "-b")
    )
    config = tmp_path / "services.json"
    config.write_text(json.dumps([command_a, command_b]))

    log_path = "/home/user/supervisor.log"
    old_log_size = os.path.getsize(log_path) if os.path.exists(log_path) else 0
    proc = subprocess.Popen(
        ["python3", "/home/user/supervisor.py", str(config)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        def both_started():
            a = _state_records(state_a)
            b = _state_records(state_b)
            return (a, b) if a and b else None

        records_a, records_b = _wait_for(
            both_started, 6, "The submitted supervisor did not start both test commands concurrently."
        )
        assert proc.poll() is None, "The submitted supervisor exited after starting its children."
        first_a = records_a[0]
        first_b = records_b[0]
        assert abs(float(first_a[2]) - float(first_b[2])) < 3.0, "Test commands were not started concurrently."

        first_pid = int(first_a[1])
        os.kill(first_pid, signal.SIGKILL)

        def restarted_a():
            records = _state_records(state_a)
            if len(records) >= 2 and int(records[-1][1]) != first_pid:
                return records
            return None

        restarted = _wait_for(
            restarted_a, 6, "The submitted supervisor did not restart a child after it exited."
        )
        assert proc.poll() is None, "The submitted supervisor did not remain running after a restart."
        restarted_pid = int(restarted[-1][1])
        os.kill(restarted_pid, 0)

        def expected_log_lines_present():
            try:
                with open(log_path, "r") as f:
                    f.seek(old_log_size)
                    lines = f.read().splitlines()
            except FileNotFoundError:
                return None
            required = {
                f"STARTED: {command_a}",
                f"STARTED: {command_b}",
                f"RESTARTED: {command_a}",
            }
            return lines if required.issubset(set(lines)) else None

        _wait_for(
            expected_log_lines_present, 3,
            "Supervisor did not append the exact STARTED and RESTARTED log lines for executed commands."
        )
    finally:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()


def test_required_services_are_supervised_running_and_produce_fresh_uptime():
    supervisor_pid = _wait_for(
        _live_service_supervisor, 5,
        "No running submitted supervisor had both required services as live descendants."
    )

    uptime_path = "/home/user/uptime.log"
    with open(uptime_path, "w"):
        pass

    def five_fresh_vnc_lines():
        try:
            with open(uptime_path, "r") as f:
                count = sum(1 for line in f if line.strip() == "VNC_OK")
            return count >= 5
        except FileNotFoundError:
            return False

    _wait_for(
        five_fresh_vnc_lines, 10,
        "The running supervised QEMU and monitor did not produce five fresh VNC_OK records."
    )

    assert os.path.exists(f"/proc/{supervisor_pid}"), "The required service supervisor stopped running."
    assert _live_service_supervisor(), "Both required services were not still running under the supervisor."
TEST_EOF

if timeout 45s python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
