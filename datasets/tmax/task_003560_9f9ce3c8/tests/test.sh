#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import signal
import socket
import stat
import subprocess
import time
import urllib.error
import urllib.request


def read_pid(path):
    assert os.path.isfile(path), f"PID file {path} does not exist."
    with open(path, "r") as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"PID file {path} does not contain a valid integer PID."
    pid = int(pid_str)
    try:
        os.kill(pid, 0)
    except OSError:
        assert False, f"Process with PID {pid} from {path} is not running."
    return pid


def listening_socket_inodes(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        with open(table, "r") as f:
            next(f)
            for line in f:
                fields = line.split()
                local_address = fields[1]
                state = fields[3]
                if state != "0A":
                    continue
                if int(local_address.rsplit(":", 1)[1], 16) == port:
                    inodes.add(fields[9])
    return inodes


def pid_socket_inodes(pid):
    result = set()
    fd_dir = f"/proc/{pid}/fd"
    for name in os.listdir(fd_dir):
        try:
            target = os.readlink(os.path.join(fd_dir, name))
        except OSError:
            continue
        if target.startswith("socket:[") and target.endswith("]"):
            result.add(target[8:-1])
    return result


def assert_pid_listens(pid, port):
    listeners = listening_socket_inodes(port)
    assert listeners, f"No process is listening on TCP port {port}."
    owned = pid_socket_inodes(pid)
    assert listeners & owned, f"PID {pid} does not own the listening socket on TCP port {port}."


def fetch(url, timeout=3):
    req = urllib.request.Request(url, headers={"Connection": "close"})
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.read()


def test_generate_report_script_exists():
    path = "/home/user/generate_report.py"
    assert os.path.isfile(path), f"Expected script {path} does not exist."


def test_summary_json_exists_and_permissions():
    path = "/home/user/reports/summary.json"
    assert os.path.isfile(path), f"Expected report file {path} does not exist."

    stat_info = os.stat(path)
    perms = stat_info.st_mode & 0o777
    assert perms == 0o400, f"Expected permissions 0400 for {path}, got {oct(perms)}"


def test_summary_json_content():
    aws_path = "/home/user/aws_cost.json"
    gcp_path = "/home/user/gcp_cost.json"
    summary_path = "/home/user/reports/summary.json"

    with open(aws_path, "r") as f:
        aws_cost = json.load(f)["cost"]
    with open(gcp_path, "r") as f:
        gcp_cost = json.load(f)["cost"]

    expected_sum = aws_cost + gcp_cost

    with open(summary_path, "r") as f:
        summary_data = json.load(f)

    assert "total_cost" in summary_data, "Key 'total_cost' missing in summary.json"
    assert summary_data["total_cost"] == expected_sum, f"Expected total_cost {expected_sum}, got {summary_data['total_cost']}"


def test_generate_report_script_is_functional():
    aws_path = "/home/user/aws_cost.json"
    gcp_path = "/home/user/gcp_cost.json"
    summary_path = "/home/user/reports/summary.json"
    script_path = "/home/user/generate_report.py"

    paths = (aws_path, gcp_path, summary_path)
    backups = {}
    for path in paths:
        with open(path, "rb") as f:
            backups[path] = (f.read(), stat.S_IMODE(os.stat(path).st_mode))

    first = secrets.randbelow(10_000_000) + 1
    second = secrets.randbelow(10_000_000) + 1
    try:
        with open(aws_path, "w") as f:
            json.dump({"cost": first}, f)
        with open(gcp_path, "w") as f:
            json.dump({"cost": second}, f)

        completed = subprocess.run(
            ["python3", script_path],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert completed.returncode == 0, (
            f"generate_report.py failed when executed: {completed.stderr}"
        )
        assert os.path.isfile(summary_path), "Script did not create reports/summary.json."
        with open(summary_path, "r") as f:
            generated = json.load(f)
        assert generated == {"total_cost": first + second}, (
            "generate_report.py did not derive the expected report from the input files."
        )
    finally:
        for path, (contents, mode) in backups.items():
            with open(path, "wb") as f:
                f.write(contents)
            os.chmod(path, mode)


def test_server_pid_running():
    pid = read_pid("/home/user/server.pid")
    assert_pid_listens(pid, 8080)

    with open(f"/proc/{pid}/cmdline", "rb") as f:
        argv = [part.decode(errors="replace") for part in f.read().split(b"\0") if part]
    assert argv, f"Could not inspect command line for server PID {pid}."
    assert "python" in os.path.basename(argv[0]).lower(), (
        f"PID {pid} is not a Python HTTP server process: {argv}"
    )


def test_tunnel_pid_running():
    tunnel_pid = read_pid("/home/user/tunnel.pid")
    server_pid = read_pid("/home/user/server.pid")
    assert tunnel_pid != server_pid, "Server and tunnel PID files must identify distinct processes."
    assert_pid_listens(tunnel_pid, 9090)


def test_server_directory_and_port_forwarding():
    server_pid = read_pid("/home/user/server.pid")
    token = secrets.token_hex(16)
    report_name = f"verifier_probe_{token}.txt"
    outside_name = f"verifier_outside_{token}.txt"
    report_path = os.path.join("/home/user/reports", report_name)
    outside_path = os.path.join("/home/user", outside_name)
    payload = secrets.token_bytes(48)

    try:
        with open(report_path, "wb") as f:
            f.write(payload)
        os.chmod(report_path, 0o444)
        with open(outside_path, "wb") as f:
            f.write(b"must not be served")
        os.chmod(outside_path, 0o444)

        direct_url = f"http://127.0.0.1:8080/{report_name}"
        forwarded_url = f"http://127.0.0.1:9090/{report_name}"
        assert fetch(direct_url) == payload, "The server on port 8080 is not serving the reports directory."

        try:
            fetch(f"http://127.0.0.1:8080/{outside_name}")
            assert False, "The HTTP server exposed a file outside /home/user/reports."
        except urllib.error.HTTPError as e:
            assert e.code == 404, f"Expected 404 for a file outside reports, got HTTP {e.code}."

        assert fetch(forwarded_url) == payload, "Port 9090 did not return data served on port 8080."

        os.kill(server_pid, signal.SIGSTOP)
        time.sleep(0.2)
        try:
            stopped_result = fetch(forwarded_url, timeout=1)
        except Exception:
            stopped_result = None
        finally:
            os.kill(server_pid, signal.SIGCONT)

        assert stopped_result != payload, (
            "Port 9090 continued serving the report while the port 8080 server was stopped; "
            "it is not acting as the required forward."
        )

        deadline = time.time() + 5
        last_error = None
        while time.time() < deadline:
            try:
                if fetch(forwarded_url, timeout=1) == payload:
                    last_error = None
                    break
            except Exception as e:
                last_error = e
            time.sleep(0.2)
        assert last_error is None, f"Port forwarding did not recover after resuming the server: {last_error}"
    finally:
        try:
            os.kill(server_pid, signal.SIGCONT)
        except OSError:
            pass
        for path in (report_path, outside_path):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass


def test_port_forwarding():
    url = "http://127.0.0.1:9090/summary.json"
    try:
        data = json.loads(fetch(url, timeout=5).decode("utf-8"))
        assert "total_cost" in data, "Response JSON missing 'total_cost' key."

        with open("/home/user/aws_cost.json", "r") as f:
            aws_cost = json.load(f)["cost"]
        with open("/home/user/gcp_cost.json", "r") as f:
            gcp_cost = json.load(f)["cost"]
        assert data["total_cost"] == aws_cost + gcp_cost, "Forwarded report contains the wrong total."
    except urllib.error.URLError as e:
        assert False, f"Failed to connect to {url} or retrieve summary.json: {e}"
    except json.JSONDecodeError:
        assert False, f"Failed to parse JSON from {url}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
