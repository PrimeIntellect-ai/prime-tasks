#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import pwd
import re
import signal
import socket
import subprocess
import tempfile
import time
import urllib.request
from zoneinfo import ZoneInfo

import pytest

FSTAB = "/home/user/fstab_mock"
SOURCE = "/home/user/uptime_monitor.c"
BINARY = "/home/user/uptime_monitor"


def mount_point():
    with open(FSTAB, "r") as f:
        for line in f:
            if "# sre_logs" in line:
                fields = line.split("#", 1)[0].split()
                assert len(fields) >= 2, "Malformed sre_logs fstab entry"
                return fields[1]
    pytest.fail("No fstab entry marked '# sre_logs'")


def ss_output(port):
    return subprocess.check_output(
        ["ss", "-ltnp", f"sport = :{port}"], text=True, stderr=subprocess.STDOUT
    )


def listener_pids(port):
    return {int(x) for x in re.findall(r"pid=(\d+)", ss_output(port))}


def wait_for_listener(port, present=True, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            found = bool(listener_pids(port))
        except subprocess.CalledProcessError:
            found = False
        if found == present:
            return
        time.sleep(0.1)
    pytest.fail(f"Port {port} listener state did not become present={present}")


def raw_request(port=9090):
    with socket.create_connection(("127.0.0.1", port), timeout=2) as sock:
        sock.settimeout(2)
        sock.sendall(b"GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n")
        chunks = []
        while True:
            data = sock.recv(4096)
            if not data:
                break
            chunks.append(data)
    return b"".join(chunks)


def start_as_user(path):
    account = pwd.getpwnam("user")

    def demote():
        os.initgroups(account.pw_name, account.pw_gid)
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    return subprocess.Popen(
        [path], cwd="/home/user", stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True, preexec_fn=demote
    )


def stop_process_group(proc):
    if proc is None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
        proc.wait(timeout=3)
    except (ProcessLookupError, subprocess.TimeoutExpired):
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def test_mount_point_created():
    assert mount_point() == "/home/user/app_logs"
    assert os.path.isdir(mount_point()), "Mount point directory was not created"


def test_uptime_monitor_running():
    output = subprocess.check_output(["ps", "-e", "-o", "command"], text=True)
    assert "uptime_monitor" in output, "uptime_monitor process is not running."

    assert os.path.isfile(BINARY), f"{BINARY} does not exist"
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not an ELF binary"

    pids = listener_pids(8080)
    assert pids, "Nothing is listening on port 8080"
    expected = os.path.realpath(BINARY)
    assert any(os.path.realpath(f"/proc/{pid}/exe") == expected for pid in pids), (
        "Port 8080 is not served by /home/user/uptime_monitor"
    )


def test_ssh_tunnel_running():
    output = subprocess.check_output(["ss", "-tln"], text=True)
    assert ":9090" in output, "SSH tunnel is not listening on port 9090."

    pids = listener_pids(9090)
    assert pids, "No process owns the port 9090 listener"
    valid = False
    for pid in pids:
        try:
            exe = os.path.basename(os.path.realpath(f"/proc/{pid}/exe"))
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                command = " ".join(x.decode(errors="replace") for x in f.read().split(b"\0") if x)
        except OSError:
            continue
        forward = re.search(
            r"(?:^|\s)-L\s*(?:127\.0\.0\.1:)?9090:127\.0\.0\.1:8080(?:\s|$)", command
        )
        destination = re.search(r"(?:^|\s)(?:[^\s]+@)?localhost(?:\s|$)", command)
        if exe == "ssh" and forward and destination:
            valid = True
            break
    assert valid, "Port 9090 is not owned by the required localhost SSH forward"


def test_result_txt():
    result_path = "/home/user/result.txt"
    assert os.path.isfile(result_path), f"{result_path} does not exist."
    with open(result_path, "r") as f:
        content = f.read().strip()
    assert content == "5", f"Expected '5' in {result_path}, got '{content}'."


def test_log_rotation_and_content():
    log_file = "/home/user/app_logs/uptime.log.1"
    assert os.path.isfile(log_file), f"Rotated log file {log_file} does not exist."
    with open(log_file, "r") as f:
        lines = f.readlines()

    jst_lines = [line for line in lines if "JST] SYSTEM_UP" in line]
    assert len(jst_lines) == 5, f"Expected exactly 5 'JST] SYSTEM_UP' lines in {log_file}, found {len(jst_lines)}."
    pattern = re.compile(r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} JST\] SYSTEM_UP\n$")
    for line in jst_lines:
        assert pattern.match(line), f"Log line format incorrect: {line}"


def test_logrotate_conf():
    conf_path = "/home/user/logrotate.conf"
    assert os.path.isfile(conf_path), f"{conf_path} does not exist."
    with open(conf_path, "r") as f:
        content = f.read()

    assert "copytruncate" in content, "Missing 'copytruncate' in logrotate.conf."
    assert "10" in content, "Missing size directive (e.g. 'size 10') in logrotate.conf."
    assert "3" in content, "Missing rotate directive (e.g. 'rotate 3') in logrotate.conf."

    cleaned = re.sub(r"#.*", "", content)
    block_match = re.search(r"(?m)^\s*" + re.escape(mount_point() + "/uptime.log") + r"\s*\{(.*?)\}", cleaned, re.S)
    assert block_match, "logrotate.conf does not manage the required uptime.log"
    block = block_match.group(1)
    assert re.search(r"(?m)^\s*copytruncate\s*$", block), "copytruncate is not configured as a directive"
    assert re.search(r"(?m)^\s*rotate\s+3\s*$", block), "rotate 3 is not configured"
    assert re.search(r"(?m)^\s*size\s+10(?:[bB])?\s*$", block), "size 10 bytes is not configured"
    assert re.search(r"(?m)^\s*daily\s*$", block), "daily rotation is not configured"

    dry_run = subprocess.run(
        ["logrotate", "-d", "-s", "/tmp/verifier-logrotate.status", conf_path],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    )
    assert dry_run.returncode == 0, f"logrotate rejected the configuration:\n{dry_run.stdout}"


def test_uptime_monitor_c_exists():
    assert os.path.isfile(SOURCE), f"C source file {SOURCE} does not exist."


def test_service_response():
    try:
        req = urllib.request.Request("http://127.0.0.1:9090")
        with urllib.request.urlopen(req, timeout=2) as response:
            body = response.read().decode("utf-8")
            assert body == "UPTIME_OK", f"Expected response 'UPTIME_OK', got '{body}'"
    except Exception as e:
        pytest.fail(f"Failed to connect to service via tunnel on port 9090: {e}")


def test_submitted_source_implements_service_and_logging():
    """Compile the submitted source and exercise that artifact through the real SSH forward."""
    build_dir = tempfile.mkdtemp(prefix="uptime-source-build-")
    built = os.path.join(build_dir, "uptime_monitor")
    compile_result = subprocess.run(
        ["gcc", SOURCE, "-o", built], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20
    )
    assert compile_result.returncode == 0, f"Submitted C source does not compile:\n{compile_result.stdout}"

    original_pids = listener_pids(8080)
    assert original_pids, "Original service is not listening on 8080"
    original_proc = None
    compiled_proc = None
    log_path = os.path.join(mount_point(), "uptime.log")

    try:
        for pid in original_pids:
            os.kill(pid, signal.SIGTERM)
        wait_for_listener(8080, present=False)

        env = os.environ.copy()
        env["TZ"] = "UTC"
        compiled_proc = subprocess.Popen(
            [built], cwd="/home/user", env=env, stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True
        )
        wait_for_listener(8080, present=True)

        if os.path.exists(log_path):
            with open(log_path, "r") as f:
                before = f.readlines()
        else:
            before = []

        request_times = []
        for _ in range(3):
            request_times.append(datetime.datetime.now(ZoneInfo("Asia/Tokyo")))
            response = raw_request(9090)
            assert response == b"HTTP/1.1 200 OK\r\n\r\nUPTIME_OK", f"Incorrect raw response: {response!r}"
            time.sleep(1)

        with open(log_path, "r") as f:
            after = f.readlines()
        assert after[:len(before)] == before, "Service rewrote existing log content instead of appending"
        added = after[len(before):]
        assert len(added) == 3, f"Three connections must append exactly three lines; got {len(added)}"

        pattern = re.compile(r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) JST\] SYSTEM_UP\n$")
        for line, requested_at in zip(added, request_times):
            match = pattern.match(line)
            assert match, f"Invalid generated log line: {line!r}"
            logged = datetime.datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S").replace(tzinfo=ZoneInfo("Asia/Tokyo"))
            assert abs((logged - requested_at).total_seconds()) <= 5, (
                f"Log timestamp is not current Asia/Tokyo time: {line!r}"
            )
    finally:
        stop_process_group(compiled_proc)
        try:
            wait_for_listener(8080, present=False, timeout=3)
        except BaseException:
            pass
        original_proc = start_as_user(BINARY)
        wait_for_listener(8080, present=True)


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
