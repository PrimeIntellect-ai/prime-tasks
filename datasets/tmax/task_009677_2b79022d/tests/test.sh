#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import re
import signal
import socket
import stat
import subprocess
import tempfile
import threading
import time


def run_as_user(argv, **kwargs):
    return subprocess.run(["runuser", "-u", "user", "--"] + argv, **kwargs)


def socket_inodes_for_port(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) < 10 or fields[3] != "0A":
                        continue
                    local_port = int(fields[1].split(":")[1], 16)
                    if local_port == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass
    return inodes


def pids_listening_on(port):
    wanted = socket_inodes_for_port(port)
    found = set()
    if not wanted:
        return found
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in wanted:
                    found.add(int(name))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return found


def proc_exe(pid):
    try:
        return os.path.realpath(f"/proc/{pid}/exe")
    except OSError:
        return ""


def proc_args(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
    except OSError:
        return []


def receive_banner(port, prefix, timeout=3):
    with socket.create_connection(("127.0.0.1", port), timeout=timeout) as sock:
        sock.settimeout(timeout)
        data = sock.recv(128)
    assert data.startswith(prefix), f"Port {port} returned {data!r}, not the expected {prefix!r} banner."
    return data


def assert_real_qemu():
    receive_banner(5900, b"RFB ")
    pids = pids_listening_on(5900)
    assert pids, "No real process is listening on QEMU VNC port 5900."
    assert any(os.path.basename(proc_exe(pid)).startswith("qemu-system-") for pid in pids), \
        f"Port 5900 is not owned by qemu-system-x86_64; listener PIDs were {sorted(pids)}."


def ssh_forward_pid():
    for pid in pids_listening_on(5901):
        if os.path.basename(proc_exe(pid)) != "ssh":
            continue
        args = proc_args(pid)
        joined = " ".join(args)
        has_mapping = re.search(r"(?:127\.0\.0\.1:)?5901:127\.0\.0\.1:5900(?:\s|$)", joined)
        has_port = ("-p" in args and "2222" in args) or any(a == "-p2222" for a in args) or "Port=2222" in joined
        has_host = any(a == "localhost" or a.endswith("@localhost") or a == "127.0.0.1" or a.endswith("@127.0.0.1") for a in args)
        if has_mapping and has_port and has_host:
            return pid
    return None


def assert_real_ssh_server():
    receive_banner(2222, b"SSH-")
    pids = pids_listening_on(2222)
    assert pids, "No real process is listening on SSH port 2222."
    assert any(os.path.basename(proc_exe(pid)) == "sshd" for pid in pids), \
        f"Port 2222 is not owned by sshd; listener PIDs were {sorted(pids)}."


def stop_old_tunnel():
    victims = set(pids_listening_on(5901))
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        args = proc_args(int(name))
        if any("/home/user/start_tunnel.exp" in arg for arg in args):
            victims.add(int(name))
    for sig in (signal.SIGTERM, signal.SIGKILL):
        for pid in list(victims):
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        time.sleep(0.7)
        victims = {pid for pid in victims if os.path.exists(f"/proc/{pid}")}
        if not victims:
            break
    deadline = time.time() + 5
    while pids_listening_on(5901) and time.time() < deadline:
        time.sleep(0.1)
    assert not pids_listening_on(5901), "Could not stop the submitted tunnel for an independent behavior test."


def run_with_test_listener(binary):
    ready = threading.Event()
    accepted = threading.Event()
    errors = []

    def server():
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
                sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                sock.bind(("127.0.0.1", 5901))
                sock.listen(1)
                sock.settimeout(5)
                ready.set()
                conn, _ = sock.accept()
                accepted.set()
                conn.close()
        except Exception as exc:
            errors.append(exc)
            ready.set()

    thread = threading.Thread(target=server, daemon=True)
    thread.start()
    assert ready.wait(3), "Test listener did not start."
    assert not errors, f"Test listener failed: {errors}"
    result = run_as_user([binary], capture_output=True, text=True, timeout=8)
    thread.join(timeout=1)
    assert not errors, f"Test listener failed: {errors}"
    return result, accepted.is_set()


def test_diagnostic_report_exists_and_is_exact():
    report_path = "/home/user/diagnostic_report.txt"
    binary_path = "/home/user/bin/vnc_bridge"
    assert os.path.isfile(report_path), f"{report_path} is missing."
    with open(report_path, "r") as f:
        lines = f.read().splitlines()
    assert len(lines) >= 2, f"{report_path} must contain at least two lines."
    assert len(lines) == 2, f"{report_path} must contain exactly two lines."
    assert lines[0] == "user:user:---", "Line 1 must record the exact ACL entry that initially blocked user."
    with open(binary_path, "rb") as f:
        expected_md5 = hashlib.md5(f.read()).hexdigest()
    assert lines[1] == expected_md5, "Line 2 is not the MD5 checksum of the submitted vnc_bridge binary."


def test_config_acl_resolved():
    config_path = "/home/user/config.json"
    assert os.path.isfile(config_path), f"{config_path} is missing."
    result = subprocess.run(["getfacl", config_path], capture_output=True, text=True)
    assert "user:user:---" not in result.stdout, f"Blocking ACL entry 'user:user:---' is still present on {config_path}."
    assert os.access(config_path, os.R_OK), f"{config_path} is still not readable by the current user."
    assert not os.path.exists("/home/user/.acl_blocked"), "The simulated blocking ACL was not removed."
    user_read = run_as_user(["cat", config_path], capture_output=True, text=True)
    assert user_read.returncode == 0, f"The user account cannot read config.json: {user_read.stderr}"
    config = json.loads(user_read.stdout)
    assert config.get("tunnel_port") == 5901 and config.get("target") == "127.0.0.1", "config.json no longer contains the required tunnel endpoint."


def test_port_5901_listening_and_is_ssh_forward():
    result = subprocess.run(["ss", "-tln"], capture_output=True, text=True)
    assert ":5901" in result.stdout, "No service is listening on port 5901. The Expect script may not be running or failed to establish the tunnel."
    assert_real_qemu()
    assert_real_ssh_server()
    assert ssh_forward_pid() is not None, "Port 5901 is not owned by ssh with the required 5901 -> 127.0.0.1:5900 forwarding arguments."
    receive_banner(5901, b"RFB ")


def test_c_code_and_binary_updated():
    src_path = "/home/user/src/vnc_bridge.c"
    bin_path = "/home/user/bin/vnc_bridge"
    assert os.path.isfile(src_path), f"{src_path} is missing."
    with open(src_path, "r") as f:
        content = f.read()
    assert "5901" in content, f"The C source code {src_path} does not contain the updated port 5901."
    assert os.path.isfile(bin_path), f"{bin_path} is missing. Did you recompile the C code?"
    assert os.access(bin_path, os.X_OK), f"{bin_path} is not executable."
    with open(bin_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{bin_path} is not an ELF executable."
    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "vnc_bridge")
        compiled = subprocess.run(["gcc", src_path, "-o", rebuilt], capture_output=True, text=True)
        assert compiled.returncode == 0, f"The submitted C source does not compile with gcc: {compiled.stderr}"
        with open(rebuilt, "rb") as f:
            assert f.read(4) == b"\x7fELF"


def test_service_status_log():
    log_path = "/home/user/service_status.log"
    assert os.path.isfile(log_path), f"{log_path} is missing. Ensure you ran /home/user/run_bridge.sh."
    with open(log_path, "r") as f:
        content = f.read()
    assert "Service Started." in content, f"{log_path} does not contain 'Service Started.'. The service is still failing."


def test_artifacts_work_when_executed():
    binary = "/home/user/bin/vnc_bridge"
    expect_script = "/home/user/start_tunnel.exp"
    runner = "/home/user/run_bridge.sh"
    assert os.path.isfile(expect_script), "The required Expect script is missing."
    assert os.access(expect_script, os.X_OK), "The Expect script is not executable."
    with open(expect_script, "r", errors="replace") as f:
        first_line = f.readline()
    assert first_line.startswith("#!") and "expect" in first_line, "start_tunnel.exp is not an Expect script."
    assert os.path.isfile(runner) and os.access(runner, os.X_OK), "run_bridge.sh is missing or not executable."

    stop_old_tunnel()

    original_mode = stat.S_IMODE(os.stat("/home/user/config.json").st_mode)
    try:
        os.chmod("/home/user/config.json", 0)
        denied_result, connected = run_with_test_listener(binary)
        assert denied_result.returncode != 0, "vnc_bridge succeeds even when user cannot read config.json."
        assert not connected, "vnc_bridge connected without first reading config.json."
    finally:
        os.chmod("/home/user/config.json", original_mode)

    result, connected = run_with_test_listener(binary)
    assert connected, "The submitted binary did not connect to local port 5901."
    assert result.returncode == 0, f"The submitted binary failed against a listener on 5901: {result.stderr}"
    assert "VNC Bridge connected successfully." in result.stdout, "The binary did not emit its required success message."

    proc = subprocess.Popen(
        ["runuser", "-u", "user", "--", expect_script],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    deadline = time.time() + 15
    tunnel_pid = None
    while time.time() < deadline:
        tunnel_pid = ssh_forward_pid()
        if tunnel_pid is not None:
            try:
                receive_banner(5901, b"RFB ", timeout=1)
                break
            except Exception:
                pass
        time.sleep(0.25)
    else:
        raise AssertionError("Executing start_tunnel.exp did not establish the required SSH VNC tunnel.")

    assert os.path.exists(f"/proc/{tunnel_pid}"), "The SSH tunnel did not remain running."
    direct = run_as_user([binary], capture_output=True, text=True, timeout=8)
    assert direct.returncode == 0, f"vnc_bridge failed through the SSH tunnel: {direct.stderr}"
    assert "VNC Bridge connected successfully." in direct.stdout

    try:
        os.remove("/home/user/service_status.log")
    except FileNotFoundError:
        pass
    ran = run_as_user([runner], capture_output=True, text=True, timeout=8)
    assert ran.returncode == 0, f"run_bridge.sh failed: {ran.stderr}"
    assert os.path.isfile("/home/user/service_status.log"), "run_bridge.sh did not create service_status.log."
    with open("/home/user/service_status.log") as f:
        assert f.read().strip() == "Service Started.", "run_bridge.sh did not record a successful service start."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
