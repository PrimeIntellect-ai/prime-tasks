#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pathlib
import signal
import socket
import subprocess
import time
import uuid

import pytest


def test_app_config_exists_and_valid():
    """Check that app_config.json exists and contains the expected services."""
    config_path = "/home/user/app_config.json"
    assert os.path.exists(config_path), f"{config_path} does not exist."

    with open(config_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{config_path} is not valid JSON.")

    assert "services" in data, "Key 'services' not found in app_config.json."
    services = data["services"]
    assert len(services) >= 2, "Expected at least 2 services in app_config.json."

    service_names = [s.get("name") for s in services]
    assert "auth_service" in service_names, "auth_service missing from config."
    assert "data_service" in service_names, "data_service missing from config."

    expected = {
        "services": [
            {"name": "auth_service", "port": 9010, "cmd": "python3 /home/user/mock_auth.py"},
            {"name": "data_service", "port": 9011, "cmd": "python3 /home/user/mock_data.py"},
        ]
    }
    assert data == expected, "app_config.json does not contain the exact requested configuration."


def test_mock_scripts_exist():
    """Check that the mock service scripts were created."""
    assert os.path.exists("/home/user/mock_auth.py"), "/home/user/mock_auth.py is missing."
    assert os.path.exists("/home/user/mock_data.py"), "/home/user/mock_data.py is missing."

    expected_auth = """import http.server, sys
server = http.server.HTTPServer(('127.0.0.1', 9010), http.server.BaseHTTPRequestHandler)
server.serve_forever()"""
    expected_data = """import http.server, sys
server = http.server.HTTPServer(('127.0.0.1', 9011), http.server.BaseHTTPRequestHandler)
server.serve_forever()"""
    assert pathlib.Path("/home/user/mock_auth.py").read_text().strip() == expected_auth
    assert pathlib.Path("/home/user/mock_data.py").read_text().strip() == expected_data


def test_health_monitor_exists():
    """Check that the health monitor script was created."""
    path = "/home/user/health_monitor.py"
    assert os.path.exists(path), f"{path} is missing."
    assert os.path.isfile(path), f"{path} is not a regular file."


def test_status_csv_content():
    """Check that status.csv contains exactly the expected sequence of states."""
    csv_path = "/home/user/status.csv"
    assert os.path.exists(csv_path), f"{csv_path} does not exist."

    with open(csv_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "auth_service,RESTARTED",
        "data_service,RESTARTED",
        "auth_service,UP",
        "data_service,UP",
    ]
    assert lines == expected_lines, f"Contents of {csv_path} do not match expected output. Got: {lines}"


def test_ports_listening():
    """Check that ports 9010 and 9011 are actively listening on localhost."""
    for port in [9010, 9011]:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(1)
            result = s.connect_ex(("127.0.0.1", port))
            assert result == 0, f"Port {port} is not actively accepting connections."


def listener_pids(ports):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = pathlib.Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[3] == "0A":
                port = int(fields[1].rsplit(":", 1)[1], 16)
                if port in ports:
                    inodes.add(fields[9])

    result = set()
    for proc in pathlib.Path("/proc").iterdir():
        if not proc.name.isdigit() or int(proc.name) == os.getpid():
            continue
        fd_dir = proc / "fd"
        try:
            fds = list(fd_dir.iterdir())
        except OSError:
            continue
        for fd in fds:
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                result.add(int(proc.name))
                break
    return result


def stop_listeners(ports):
    for pid in listener_pids(set(ports)):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids(set(ports)):
        time.sleep(0.05)
    for pid in listener_pids(set(ports)):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.1)


def wait_for_port(port, timeout=3):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return True
        except OSError:
            time.sleep(0.05)
    return False


def free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def test_mock_services_and_monitor_behavior():
    config_path = pathlib.Path("/home/user/app_config.json")
    status_path = pathlib.Path("/home/user/status.csv")
    original_config = config_path.read_bytes()
    original_status = status_path.read_bytes() if status_path.exists() else None
    cleanup_ports = [9010, 9011]
    children = []

    try:
        # Remove any pre-existing or arbitrary listeners, then execute the submitted
        # mock scripts themselves and verify that they bind their requested ports.
        stop_listeners([9010, 9011])
        for script in ("/home/user/mock_auth.py", "/home/user/mock_data.py"):
            children.append(subprocess.Popen(
                ["python3", script],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            ))
        assert wait_for_port(9010), "Executing mock_auth.py did not open port 9010."
        assert wait_for_port(9011), "Executing mock_data.py did not open port 9011."
        assert all(p.poll() is None for p in children), "A mock service exited after startup."

        for child in children:
            child.terminate()
        for child in children:
            try:
                child.wait(timeout=2)
            except subprocess.TimeoutExpired:
                child.kill()
        children.clear()
        stop_listeners([9010, 9011])

        # Exercise the monitor against unpredictable names, ports, and commands so
        # a prewritten CSV or fixed-port implementation cannot satisfy the test.
        port1 = free_port()
        port2 = free_port()
        while port2 == port1:
            port2 = free_port()
        cleanup_ports.extend([port1, port2])

        token = uuid.uuid4().hex
        name1 = "svc_a_" + token
        name2 = "svc_b_" + token
        helper = pathlib.Path("/tmp/monitor_test_service.py")
        helper.write_text(
            "import http.server, sys\n"
            "server = http.server.HTTPServer(('127.0.0.1', int(sys.argv[1])), "
            "http.server.BaseHTTPRequestHandler)\n"
            "server.serve_forever()\n"
        )
        dynamic_config = {
            "services": [
                {"name": name1, "port": port1, "cmd": f"python3 {helper} {port1}"},
                {"name": name2, "port": port2, "cmd": f"python3 {helper} {port2}"},
            ]
        }
        config_path.write_text(json.dumps(dynamic_config))
        if status_path.exists():
            status_path.unlink()

        first = subprocess.run(
            ["python3", "/home/user/health_monitor.py"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=10,
        )
        assert first.returncode == 0, "health_monitor.py failed on its first execution."
        assert wait_for_port(port1), f"The monitor did not start the configured service on port {port1}."
        assert wait_for_port(port2), f"The monitor did not start the configured service on port {port2}."
        assert status_path.read_text().splitlines() == [
            f"{name1},RESTARTED",
            f"{name2},RESTARTED",
        ]

        second = subprocess.run(
            ["python3", "/home/user/health_monitor.py"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=10,
        )
        assert second.returncode == 0, "health_monitor.py failed on its second execution."
        assert status_path.read_text().splitlines() == [
            f"{name1},RESTARTED",
            f"{name2},RESTARTED",
            f"{name1},UP",
            f"{name2},UP",
        ]
    finally:
        for child in children:
            if child.poll() is None:
                child.kill()
        stop_listeners(cleanup_ports)
        config_path.write_bytes(original_config)
        if original_status is None:
            status_path.unlink(missing_ok=True)
        else:
            status_path.write_bytes(original_status)

        # Restore the requested final running-service state after destructive tests.
        for script in ("/home/user/mock_auth.py", "/home/user/mock_data.py"):
            if pathlib.Path(script).is_file():
                subprocess.Popen(
                    ["python3", script],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    start_new_session=True,
                )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
