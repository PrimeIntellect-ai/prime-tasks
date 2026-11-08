#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import secrets
import socket
import stat
import subprocess
import time
import pytest

PROVISION = "/home/user/provision.exp"
SOURCE = "/home/user/edge_server.cpp"
BINARY = "/home/user/edge_server"
LOG = "/home/user/data/payload.log"


def regular_file(path):
    try:
        return stat.S_ISREG(os.lstat(path).st_mode)
    except FileNotFoundError:
        return False


def proc_exe(pid):
    try:
        return os.path.realpath(f"/proc/{pid}/exe")
    except OSError:
        return None


def pids_for_executable(path):
    target = os.path.realpath(path)
    result = set()
    for name in os.listdir("/proc"):
        if name.isdigit() and proc_exe(name) == target:
            result.add(int(name))
    return result


def listening_socket_inodes(port, address=None):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local, state, inode = fields[1], fields[3], fields[9]
            host_hex, port_hex = local.rsplit(":", 1)
            if state != "0A" or int(port_hex, 16) != port:
                continue
            if address == "127.0.0.1" and not (table.endswith("tcp") and host_hex == "0100007F"):
                continue
            result.add(inode)
    return result


def socket_owner_pids(inodes):
    owners = set()
    wanted = {f"socket:[{inode}]" for inode in inodes}
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            fds = os.listdir(fd_dir)
        except OSError:
            continue
        for fd in fds:
            try:
                if os.readlink(f"{fd_dir}/{fd}") in wanted:
                    owners.add(int(name))
                    break
            except OSError:
                pass
    return owners


def wait_for_listener(port, pid=None, address=None, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        inodes = listening_socket_inodes(port, address)
        owners = socket_owner_pids(inodes)
        if inodes and (pid is None or pid in owners):
            return owners
        time.sleep(0.1)
    return set()


def append_and_check(port, payload):
    before = os.path.getsize(LOG) if os.path.exists(LOG) else 0
    with socket.create_connection(("127.0.0.1", port), timeout=2) as sock:
        sock.sendall(payload)
    deadline = time.time() + 3
    expected = payload + b"\n"
    while time.time() < deadline:
        if os.path.exists(LOG):
            with open(LOG, "rb") as f:
                f.seek(before)
                if expected in f.read():
                    return
        time.sleep(0.1)
    pytest.fail("The server did not append the unpredictable payload followed by a newline")


def test_required_artifacts_and_provision_script():
    assert regular_file(PROVISION), f"{PROVISION} is missing or is not a regular file"
    assert regular_file(SOURCE), f"{SOURCE} is missing or is not a regular C++ source file"
    assert regular_file(BINARY), f"{BINARY} is missing or is not a regular file"
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a compiled ELF binary"

    if os.path.exists("/home/user/device.conf"):
        os.unlink("/home/user/device.conf")
    result = subprocess.run(
        ["expect", PROVISION], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10
    )
    assert result.returncode == 0, f"provision.exp failed when executed:\n{result.stdout}"
    assert os.path.exists("/home/user/device.conf"), "provision.exp did not generate device.conf"


def test_source_compiles_and_implements_server():
    rebuilt = "/tmp/edge_server_from_submission"
    compile_result = subprocess.run(
        ["g++", SOURCE, "-o", rebuilt], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert compile_result.returncode == 0, f"edge_server.cpp does not compile with g++:\n{compile_result.stdout}"
    with open(rebuilt, "rb") as f:
        assert f.read(4) == b"\x7fELF"

    deployed_pids = pids_for_executable(BINARY)
    assert deployed_pids, "The running edge_server is not /home/user/edge_server"
    for pid in deployed_pids:
        try:
            os.kill(pid, 15)
        except ProcessLookupError:
            pass
    deadline = time.time() + 5
    while time.time() < deadline and listening_socket_inodes(8080):
        time.sleep(0.1)
    assert not listening_socket_inodes(8080), "Could not stop the deployed server to test submitted source"

    rebuilt_proc = subprocess.Popen([rebuilt], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        owners = wait_for_listener(8080, rebuilt_proc.pid, "127.0.0.1")
        assert rebuilt_proc.pid in owners, "The program compiled from edge_server.cpp does not listen on 127.0.0.1:8080"
        append_and_check(8080, ("SOURCE_CHECK_" + secrets.token_hex(16)).encode())
    finally:
        if rebuilt_proc.poll() is None:
            rebuilt_proc.terminate()
            try:
                rebuilt_proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                rebuilt_proc.kill()
                rebuilt_proc.wait()

    deployed = subprocess.Popen([BINARY], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    owners = wait_for_listener(8080, deployed.pid, "127.0.0.1")
    assert deployed.pid in owners, "The deployed /home/user/edge_server does not listen on 127.0.0.1:8080"


def test_device_conf():
    """Check that device.conf exists and contains the correct device ID."""
    conf_path = "/home/user/device.conf"
    assert os.path.exists(conf_path), f"{conf_path} does not exist. Expect script may have failed."
    with open(conf_path, "r") as f:
        content = f.read()
    assert "DEVICE=edge-node-99" in content, f"DEVICE=edge-node-99 not found in {conf_path}."
    assert "TOKEN=secure_token_12345" in content, f"TOKEN not found in {conf_path}."


def test_edge_server_running():
    """Check that edge_server is running."""
    try:
        output = subprocess.check_output(["pgrep", "-f", "edge_server"]).decode("utf-8")
        assert output.strip() != "", "edge_server process is not running."
    except subprocess.CalledProcessError:
        pytest.fail("edge_server process is not running.")
    assert pids_for_executable(BINARY), "No process is executing /home/user/edge_server"


def test_socat_running():
    """Check that socat is running."""
    try:
        output = subprocess.check_output(["pgrep", "-f", "socat"]).decode("utf-8")
        assert output.strip() != "", "socat process is not running."
    except subprocess.CalledProcessError:
        pytest.fail("socat process is not running.")


def test_distinct_server_and_socat_listeners():
    edge_pids = pids_for_executable(BINARY)
    owners_8080 = socket_owner_pids(listening_socket_inodes(8080, "127.0.0.1"))
    assert edge_pids & owners_8080, "Port 8080 is not owned by the deployed edge_server binary"

    owners_9090 = socket_owner_pids(listening_socket_inodes(9090))
    socat_pids = {pid for pid in owners_9090 if os.path.basename(proc_exe(pid) or "") == "socat"}
    assert socat_pids, "Port 9090 is not listened to by a real socat process"
    assert not (socat_pids & owners_8080), "Ports 9090 and 8080 must be handled by distinct forwarding and server processes"

    append_and_check(9090, ("FORWARD_CHECK_" + secrets.token_hex(20)).encode())


def test_port_forwarding_and_server():
    """Send a test payload to 9090 and verify it appears in payload.log."""
    payload = "VERIFY_PAYLOAD_12345\n"
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(2)
        s.connect(("127.0.0.1", 9090))
        s.sendall(payload.encode("utf-8"))
        s.close()
    except Exception as e:
        pytest.fail(f"Failed to connect and send data to port 9090: {e}")
    time.sleep(1)
    assert os.path.exists(LOG), f"{LOG} does not exist after sending payload."
    with open(LOG, "r") as f:
        content = f.read()
    assert "VERIFY_PAYLOAD_12345" in content, f"Payload not found in {LOG}. Server or port forwarding might be broken."


def test_payload_log_permissions_and_acl():
    """Check base permissions and ACLs for payload.log."""
    assert os.path.exists(LOG), f"{LOG} does not exist."
    st = os.stat(LOG)
    assert bool(st.st_mode & stat.S_IRUSR), "Owner does not have read permission."
    assert bool(st.st_mode & stat.S_IWUSR), "Owner does not have write permission."
    assert not bool(st.st_mode & stat.S_IROTH), "Others should not have read permission."
    assert not bool(st.st_mode & stat.S_IWOTH), "Others should not have write permission."
    assert not bool(st.st_mode & stat.S_IXOTH), "Others should not have execute permission."
    assert not bool(st.st_mode & stat.S_IWGRP), "Group must not have write permission."
    assert not bool(st.st_mode & stat.S_IXGRP), "Group must not have execute permission."

    try:
        acl_output = subprocess.check_output(["getfacl", "-c", LOG]).decode("utf-8")
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to run getfacl: {e}")
    assert "user:guest:r--" in acl_output, f"ACL for guest user is incorrect or missing. getfacl output:\n{acl_output}"
    acl_lines = {line.strip() for line in acl_output.splitlines() if line.strip()}
    assert "user::rw-" in acl_lines, f"Owner ACL is not rw-:\n{acl_output}"
    assert "other::---" in acl_lines, f"Other users have permissions:\n{acl_output}"

    guest = pwd.getpwnam("guest")
    read_result = subprocess.run(
        ["runuser", "-u", guest.pw_name, "--", "head", "-c", "1", LOG],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert read_result.returncode == 0, "guest cannot actually read payload.log"


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
