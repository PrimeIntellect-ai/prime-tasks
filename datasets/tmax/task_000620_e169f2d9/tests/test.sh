#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import subprocess
import time
import pytest


def test_analyze_logs_output():
    script_path = "/home/user/analyze_logs.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    result = subprocess.run([script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Script {script_path} failed with return code {result.returncode}."

    output_lines = [line.strip() for line in result.stdout.strip().split('\n') if line.strip()]
    assert set(output_lines) == {"8002", "8003"}, f"Expected output to contain exactly '8002' and '8003', got {output_lines}"


def test_recovery_status_json():
    json_path = "/home/user/recovery_status.json"
    assert os.path.isfile(json_path), f"JSON file {json_path} does not exist."

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} does not contain valid JSON.")

    assert "8002" in data, "Port '8002' missing from recovery_status.json."
    assert "8003" in data, "Port '8003' missing from recovery_status.json."
    assert "8001" not in data, "Port '8001' should not be in recovery_status.json."

    for port in ["8002", "8003"]:
        port_data = data[port]
        assert isinstance(port_data, dict), f"Data for port {port} is not a dictionary."
        assert port_data.get("status") == "recovered", f"Status for port {port} is not 'recovered'."
        assert "new_pid" in port_data, f"'new_pid' missing for port {port}."

        pid_file = f"/home/user/services/pids/{port}.pid"
        assert os.path.isfile(pid_file), f"PID file {pid_file} does not exist."

        with open(pid_file, "r") as pf:
            pid_str = pf.read().strip()
            assert pid_str.isdigit(), f"PID file {pid_file} does not contain a valid PID."
            actual_pid = int(pid_str)

        assert port_data["new_pid"] == actual_pid, f"new_pid for port {port} in JSON ({port_data['new_pid']}) does not match PID file ({actual_pid})."


def test_processes_running():
    for port in ["8001", "8002", "8003"]:
        pid_file = f"/home/user/services/pids/{port}.pid"
        assert os.path.isfile(pid_file), f"PID file {pid_file} does not exist."

        with open(pid_file, "r") as pf:
            pid_str = pf.read().strip()
            assert pid_str.isdigit(), f"PID file {pid_file} does not contain a valid PID."
            pid = int(pid_str)

        try:
            os.kill(pid, 0)
        except OSError:
            pytest.fail(f"Process with PID {pid} for port {port} is not running.")


def _read_pid(port):
    with open(f"/home/user/services/pids/{port}.pid", "r") as f:
        value = f.read().strip()
    assert value.isdigit(), f"PID file for port {port} does not contain a valid PID."
    return int(value)


def _is_live(pid):
    try:
        with open(f"/proc/{pid}/stat", "r") as f:
            state = f.read().split()[2]
        return state != "Z"
    except (FileNotFoundError, ProcessLookupError):
        return False


def _assert_terminated(pid):
    deadline = time.time() + 3
    while time.time() < deadline and _is_live(pid):
        time.sleep(0.05)
    assert not _is_live(pid), f"Old hung process {pid} was not terminated."


def _assert_service(port, pid):
    assert _is_live(pid), f"Restarted process {pid} for port {port} is not running."
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        cmdline = f.read().replace(b"\0", b" ").decode(errors="replace")
    assert "/home/user/services/dummy_service.py" in cmdline, f"PID {pid} is not the expected service process."
    assert str(port) in cmdline.split(), f"PID {pid} was not started for port {port}."


def test_recovery_pipeline_on_derived_inputs_and_repeated_run():
    recover_path = "/home/user/auto_recover.py"
    assert os.path.isfile(recover_path), f"Script {recover_path} does not exist."

    base = 20000 + (os.getpid() % 9000)
    failed_ports = [str(base), str(base + 1)]
    decoy_port = str(base + 2)

    old_pids = {}
    for port in failed_ports:
        result = subprocess.run(
            ["/home/user/services/start_single.sh", port],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, f"Could not start test service for port {port}: {result.stderr}"
        old_pids[port] = _read_pid(port)
        _assert_service(port, old_pids[port])

    with open("/home/user/net_diag.log", "w") as f:
        f.write(f"INFO probe 10.4.0.1:{decoy_port} OK\n")
        f.write(f"ERROR probe 10.4.0.2:{failed_ports[0]} FAILED timeout\n")
        f.write(f"DEBUG duplicate 10.4.0.2:{failed_ports[0]} FAILED again\n")
        f.write(f"CRITICAL Connection refused 10.4.0.3:{failed_ports[1]}\n")
        f.write(f"INFO lowercase failed 10.4.0.4:{base + 3}\n")
        f.write(f"INFO uppercase REFUSED 10.4.0.5:{base + 4}\n")

    parsed = subprocess.run(
        ["/home/user/analyze_logs.sh"], capture_output=True, text=True
    )
    assert parsed.returncode == 0, f"analyze_logs.sh failed on derived input: {parsed.stderr}"
    parsed_ports = [line.strip() for line in parsed.stdout.splitlines() if line.strip()]
    assert set(parsed_ports) == set(failed_ports), f"Expected exactly {failed_ports}, got {parsed_ports}"
    assert len(parsed_ports) == len(failed_ports), "Failed ports were not output uniquely."

    first = subprocess.run(
        ["python3", recover_path], capture_output=True, text=True, timeout=15
    )
    assert first.returncode == 0, f"auto_recover.py failed: {first.stderr}"

    first_new_pids = {}
    for port in failed_ports:
        first_new_pids[port] = _read_pid(port)
        assert first_new_pids[port] != old_pids[port], f"Service on port {port} was not restarted."
        _assert_terminated(old_pids[port])
        _assert_service(port, first_new_pids[port])

    with open("/home/user/recovery_status.json", "r") as f:
        data = json.load(f)
    assert decoy_port not in data, f"Non-failing port {decoy_port} was marked recovered."
    for port in failed_ports:
        assert data.get(port) == {
            "status": "recovered",
            "new_pid": first_new_pids[port],
        }, f"Incorrect recovery status for port {port}."

    second = subprocess.run(
        ["python3", recover_path], capture_output=True, text=True, timeout=15
    )
    assert second.returncode == 0, f"Second auto_recover.py run failed: {second.stderr}"

    with open("/home/user/recovery_status.json", "r") as f:
        second_data = json.load(f)
    for port in failed_ports:
        second_pid = _read_pid(port)
        assert second_pid != first_new_pids[port], f"Repeated recovery did not restart port {port}."
        _assert_terminated(first_new_pids[port])
        _assert_service(port, second_pid)
        assert second_data.get(port) == {
            "status": "recovered",
            "new_pid": second_pid,
        }, f"Repeated recovery did not idempotently update port {port}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
