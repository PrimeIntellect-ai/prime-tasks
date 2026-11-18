#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import pathlib
import re
import secrets
import signal
import socket
import subprocess
import tempfile
import time
from zoneinfo import ZoneInfo

FSTAB = "/home/user/operator_fstab"
OPERATOR = "/home/user/operator"
SOURCE = "/home/user/operator.c"
STATUS = b"STATUS: OPERATIONAL"


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    result = set()
    for entry in os.scandir("/proc"):
        if not entry.name.isdigit():
            continue
        try:
            for fd in os.scandir(f"/proc/{entry.name}/fd"):
                try:
                    target = os.readlink(fd.path)
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    result.add(int(entry.name))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return result


def stop_port(port):
    pids = listener_pids(port)
    for pid in pids:
        if pid not in (1, os.getpid()):
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids(port):
        time.sleep(0.05)
    for pid in listener_pids(port):
        if pid not in (1, os.getpid()):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def wait_for_port(port, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.25)
            if sock.connect_ex(("127.0.0.1", port)) == 0:
                return
        time.sleep(0.05)
    raise AssertionError(f"Port {port} did not start listening")


def fetch_status(port):
    with socket.create_connection(("127.0.0.1", port), timeout=3) as sock:
        sock.settimeout(3)
        chunks = []
        while True:
            data = sock.recv(4096)
            if not data:
                break
            chunks.append(data)
    return b"".join(chunks)


def test_operator_fstab():
    assert os.path.isfile(FSTAB), f"File {FSTAB} does not exist."
    with open(FSTAB, "r") as f:
        content = f.read().strip()
    assert content == "/home/user/source_manifests /home/user/target_state", f"Incorrect content in {FSTAB}."


def test_source_files():
    dep_path = "/home/user/source_manifests/deployment.yaml"
    svc_path = "/home/user/source_manifests/service.yaml"
    assert os.path.isfile(dep_path), f"Source file {dep_path} missing."
    assert os.path.isfile(svc_path), f"Source file {svc_path} missing."
    with open(dep_path, "r") as f:
        assert f.read().strip() == "kind: Deployment", "Incorrect content in source deployment.yaml."
    with open(svc_path, "r") as f:
        assert f.read().strip() == "kind: Service", "Incorrect content in source service.yaml."


def test_target_files():
    dep_path = "/home/user/target_state/deployment.yaml"
    svc_path = "/home/user/target_state/service.yaml"
    assert os.path.isfile(dep_path), f"Target file {dep_path} missing."
    assert os.path.isfile(svc_path), f"Target file {svc_path} missing."

    time_pattern = re.compile(r"\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] Applied")
    with open(dep_path, "r") as f:
        dep_content = f.read()
    assert "kind: Deployment" in dep_content, "Missing original content in target deployment.yaml."
    assert time_pattern.search(dep_content), "Missing or incorrect timestamp format in target deployment.yaml."

    with open(svc_path, "r") as f:
        svc_content = f.read()
    assert "kind: Service" in svc_content, "Missing original content in target service.yaml."
    assert time_pattern.search(svc_content), "Missing or incorrect timestamp format in target service.yaml."


def test_c_operator_files():
    assert os.path.isfile(SOURCE), "C source file /home/user/operator.c missing."
    assert os.path.isfile(OPERATOR), "Compiled executable /home/user/operator missing."
    assert os.access(OPERATOR, os.X_OK), "/home/user/operator is not executable."
    with open(OPERATOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/operator is not a compiled executable."
    subprocess.run(["gcc", SOURCE, "-o", "/tmp/operator_from_source"], check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def test_tunnel_log():
    log_path = "/home/user/tunnel_test.log"
    assert os.path.isfile(log_path), f"Log file {log_path} missing."
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert "STATUS: OPERATIONAL" in content, "Tunnel log does not contain 'STATUS: OPERATIONAL'."
    assert content == "STATUS: OPERATIONAL", "Tunnel log response is not exact."


def test_ports_listening():
    def is_port_listening(port):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            return s.connect_ex(("127.0.0.1", port)) == 0

    assert is_port_listening(7777), "Operator is not listening on port 7777."
    assert is_port_listening(8888), "SSH tunnel is not listening on port 8888."


def test_ssh_tunnel_is_real_and_functional():
    pids = listener_pids(8888)
    assert pids, "Nothing is listening on tunnel port 8888."
    valid = False
    for pid in pids:
        try:
            exe = os.path.realpath(f"/proc/{pid}/exe")
            args = pathlib.Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
            args = [a.decode(errors="replace") for a in args if a]
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue
        if os.path.basename(exe) != "ssh":
            continue
        joined = " ".join(args)
        if re.search(r"(?:^|\s)-L(?:\s*)8888:(?:127\.0\.0\.1|localhost):7777(?:\s|$)", joined):
            valid = True
            break
    assert valid, "Port 8888 is not owned by an SSH client forwarding to localhost:7777."
    assert fetch_status(8888) == STATUS, "The SSH tunnel did not return the exact operator response."


def validate_outputs(destination, expected):
    pattern = re.compile(rb"\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] Applied")
    for name, original in expected.items():
        output = pathlib.Path(destination, name)
        assert output.is_file(), f"Operator did not copy arbitrary file {name}."
        data = output.read_bytes()
        prefix = original + b"\n"
        assert data.startswith(prefix), f"Copied contents for {name} were changed."
        suffix = data[len(prefix):]
        match = pattern.fullmatch(suffix)
        assert match, f"Timestamp suffix for {name} is not exact."
        stamped = datetime.datetime.strptime(match.group(1).decode(), "%Y-%m-%d %H:%M:%S")
        tokyo_now = datetime.datetime.now(ZoneInfo("Asia/Tokyo")).replace(tzinfo=None)
        assert abs((tokyo_now - stamped).total_seconds()) < 15, "Timestamp is not current Tokyo local time."


def run_dynamic_case(binary):
    with tempfile.TemporaryDirectory(prefix="operator-dynamic-") as root:
        source = os.path.join(root, "source")
        destination = os.path.join(root, "target")
        os.mkdir(source)
        os.mkdir(destination)
        token = secrets.token_hex(20).encode()
        expected = {
            "unexpected-name.txt": b"dynamic payload " + token,
            "extra-config.json": b'{"nonce":"' + token + b'"}',
        }
        for name, data in expected.items():
            pathlib.Path(source, name).write_bytes(data)
        pathlib.Path(FSTAB).write_text(source + " " + destination + "\n")

        stop_port(7777)
        env = os.environ.copy()
        env["TZ"] = "UTC"
        proc = subprocess.Popen([binary], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            wait_for_port(7777)
            validate_outputs(destination, expected)
            assert fetch_status(7777) == STATUS, "Operator health response was not exact."
            assert fetch_status(7777) == STATUS, "Operator did not continue serving connections in a loop."
            assert fetch_status(8888) == STATUS, "SSH tunnel did not forward to the executed operator."
        finally:
            try:
                proc.terminate()
                proc.wait(timeout=2)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                try:
                    proc.kill()
                except ProcessLookupError:
                    pass
            stop_port(7777)


def test_z_execute_operator_and_source_with_dynamic_configuration():
    original_fstab = pathlib.Path(FSTAB).read_bytes()
    try:
        run_dynamic_case(OPERATOR)
        run_dynamic_case("/tmp/operator_from_source")
    finally:
        pathlib.Path(FSTAB).write_bytes(original_fstab)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
