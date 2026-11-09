#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import pwd
import re
import secrets
import socket
import stat
import subprocess
import tempfile
import time

PIN = "4826"
USER_UID = pwd.getpwnam("user").pw_uid
SOURCE = "/home/user/telemetry_daemon.c"
DAEMON = "/home/user/telemetry_daemon"
CONFIG = "/home/user/haproxy.cfg"
LOG = "/home/user/logs/telemetry.log"
ROTATE = "/home/user/rotate_and_backup.sh"
BACKUPS = "/home/user/backups"
LOG_LINE = re.compile(r"^\[[^\]\r\n]+\] Connection received$")


def send_request(port, message, chunks=False):
    with socket.create_connection(("127.0.0.1", port), timeout=3) as sock:
        sock.settimeout(3)
        data = message.encode("utf-8")
        if chunks:
            for byte in data:
                sock.sendall(bytes([byte]))
                time.sleep(0.002)
        else:
            sock.sendall(data)
        sock.shutdown(socket.SHUT_WR)
        response = bytearray()
        while True:
            chunk = sock.recv(1024)
            if not chunk:
                break
            response.extend(chunk)
        return response.decode("utf-8")


def listener_inode(ip_hex, port):
    wanted_port = f"{port:04X}"
    matches = []
    with open("/proc/net/tcp", "r") as handle:
        next(handle)
        for line in handle:
            fields = line.split()
            address, found_port = fields[1].split(":")
            if fields[3] == "0A" and address == ip_hex and found_port == wanted_port:
                matches.append(fields[9])
    assert len(matches) == 1, f"Expected exactly one IPv4 listener on {ip_hex}:{port}, found {len(matches)}"
    return matches[0]


def process_for_inode(inode):
    owners = []
    for proc_path in glob.glob("/proc/[0-9]*"):
        pid = int(proc_path.rsplit("/", 1)[1])
        try:
            for fd in os.listdir(os.path.join(proc_path, "fd")):
                try:
                    target = os.readlink(os.path.join(proc_path, "fd", fd))
                except OSError:
                    continue
                if target == f"socket:[{inode}]":
                    owners.append(pid)
                    break
        except OSError:
            continue
    assert len(owners) == 1, f"Expected one process to own listener inode {inode}, found {owners}"
    return owners[0]


def process_info_for_listener(ip_hex, port):
    pid = process_for_inode(listener_inode(ip_hex, port))
    executable = os.path.realpath(f"/proc/{pid}/exe")
    with open(f"/proc/{pid}/cmdline", "rb") as handle:
        cmdline = [part.decode(errors="replace") for part in handle.read().split(b"\0") if part]
    uid = os.stat(f"/proc/{pid}").st_uid
    return pid, executable, cmdline, uid


def valid_log_lines():
    assert os.path.exists(LOG), f"Log file {LOG} does not exist."
    with open(LOG, "r", errors="replace") as handle:
        lines = handle.read().splitlines()
    assert any("Connection received" in line for line in lines), "Log file does not contain 'Connection received'."
    assert all(LOG_LINE.fullmatch(line) for line in lines if "Connection received" in line), "Connection log entries do not have the required '[TIMESTAMP] Connection received' format."
    return [line for line in lines if LOG_LINE.fullmatch(line)]


def assert_real_topology():
    daemon_pid, daemon_exe, _, daemon_uid = process_info_for_listener("0100007F", 9090)
    assert daemon_exe == DAEMON, f"Port 9090 is owned by {daemon_exe}, not {DAEMON}"
    assert daemon_uid == USER_UID, "Telemetry daemon is not running as the user account"

    haproxy_pid, haproxy_exe, haproxy_cmdline, haproxy_uid = process_info_for_listener("00000000", 8080)
    assert os.path.basename(haproxy_exe) == "haproxy", f"Port 8080 is owned by {haproxy_exe}, not HAProxy"
    assert haproxy_uid == USER_UID, "HAProxy is not running as the user account"
    assert any(CONFIG in arg for arg in haproxy_cmdline), f"Running HAProxy was not started with {CONFIG}: {haproxy_cmdline}"
    assert daemon_pid != haproxy_pid, "The daemon and HAProxy listeners must be separate processes"


def test_required_artifacts_and_process_topology():
    assert os.path.isfile(SOURCE), f"C source {SOURCE} does not exist"
    assert os.path.isfile(DAEMON), f"Compiled daemon {DAEMON} does not exist"
    assert os.access(DAEMON, os.X_OK), f"Compiled daemon {DAEMON} is not executable"
    with open(DAEMON, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", f"{DAEMON} is not an ELF compiled binary"

    with tempfile.TemporaryDirectory() as directory:
        output = os.path.join(directory, "telemetry_daemon")
        result = subprocess.run(["gcc", SOURCE, "-o", output], capture_output=True, text=True)
        assert result.returncode == 0, f"C source does not compile: {result.stderr}"
        with open(output, "rb") as handle:
            assert handle.read(4) == b"\x7fELF"

    assert os.path.isfile(CONFIG), f"HAProxy configuration {CONFIG} does not exist"
    check = subprocess.run(["haproxy", "-c", "-f", CONFIG], capture_output=True, text=True)
    assert check.returncode == 0, f"Invalid HAProxy configuration: {check.stdout}\n{check.stderr}"
    config_text = open(CONFIG, "r", errors="replace").read()
    assert re.search(r"(?im)^\s*bind\s+0\.0\.0\.0:8080(?:\s|$)", config_text), "HAProxy config does not bind 0.0.0.0:8080"
    assert re.search(r"(?im)^\s*server\s+\S+\s+127\.0\.0\.1:9090(?:\s|$)", config_text), "HAProxy config does not route to 127.0.0.1:9090"
    assert_real_topology()


def test_daemon_and_proxy_behavior_with_derived_inputs():
    before = len(valid_log_lines())
    requests = 0

    assert send_request(9090, f"AUTH {PIN}\n", chunks=True) == "TELEMETRY_ACK\n"
    requests += 1
    assert send_request(8080, f"AUTH {PIN}\n", chunks=True) == "TELEMETRY_ACK\n"
    requests += 1

    invalid_pin = PIN
    while invalid_pin == PIN:
        invalid_pin = f"{secrets.randbelow(10000):04d}"
    invalid_messages = ["AUTH 1234\n", f"AUTH {invalid_pin}\n", f"AUTH {PIN}0\n", "NOAUTH 4826\n", "\n"]
    for port in (9090, 8080):
        for message in invalid_messages:
            assert send_request(port, message) == "", f"Invalid request {message!r} received a response on port {port}"
            requests += 1

    after = len(valid_log_lines())
    assert after >= before + requests, "The C daemon did not dynamically log every direct and proxied connection"


def test_rotate_and_backup_script():
    assert os.path.exists(ROTATE), f"Script {ROTATE} does not exist."
    assert os.access(ROTATE, os.X_OK), f"Script {ROTATE} is not executable."

    assert send_request(8080, f"AUTH {PIN}\n") == "TELEMETRY_ACK\n"
    valid_log_lines()
    old_stat = os.stat(LOG)

    result = subprocess.run([ROTATE], capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, f"Backup script failed with output: {result.stderr}"
    time.sleep(1)

    assert os.path.exists(BACKUPS), f"Backup directory {BACKUPS} does not exist."
    backup_files = glob.glob(os.path.join(BACKUPS, "telemetry_*.log"))
    assert len(backup_files) > 0, "No backup file found matching telemetry_*.log"
    assert all(re.fullmatch(r"telemetry_[0-9]+\.log", os.path.basename(path)) for path in backup_files), "Backup filename does not contain a Unix timestamp"
    moved = [path for path in backup_files if os.stat(path).st_dev == old_stat.st_dev and os.stat(path).st_ino == old_stat.st_ino]
    assert moved, "The previous telemetry.log was not moved into the backups directory"

    assert_real_topology()
    assert os.path.exists(LOG), "New log file was not created after backup."
    new_stat = os.stat(LOG)
    assert (new_stat.st_dev, new_stat.st_ino) != (old_stat.st_dev, old_stat.st_ino), "Rotation did not create a fresh telemetry.log"

    response = send_request(8080, f"AUTH {PIN}\n")
    assert response == "TELEMETRY_ACK\n", f"Service did not respond correctly after backup script execution. Got: {response!r}"
    assert valid_log_lines(), "New log file does not contain 'Connection received' after post-backup request."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
