#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import socket
import subprocess
import time
import pytest


def test_device_fstab_conf():
    path = "/home/user/device_fstab.conf"
    assert os.path.isfile(path), f"{path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "DATA_MOUNT=/home/user/sensor_data", f"Incorrect content in {path}."


def test_c_service_files():
    source = "/home/user/src/edge_server.c"
    compiled = "/home/user/src/edge_server"
    deployed = "/home/user/deploy/v1/edge_server"

    assert os.path.isfile(source), "C source file edge_server.c is missing."
    assert os.path.isfile(compiled), "Compiled edge_server executable is missing."
    assert os.access(compiled, os.X_OK), "edge_server is not executable."
    with open(compiled, "rb") as f:
        assert f.read(4) == b"\x7fELF", "edge_server is not a compiled ELF executable."
    assert os.path.isfile(deployed), "Deployed edge_server is missing."
    with open(compiled, "rb") as f:
        compiled_bytes = f.read()
    with open(deployed, "rb") as f:
        deployed_bytes = f.read()
    assert deployed_bytes == compiled_bytes, "The staged edge_server is not a copy of the compiled executable."


def test_staged_deployment_symlink():
    symlink_path = "/home/user/deploy/active"
    target_dir = "/home/user/deploy/v1"

    assert os.path.islink(symlink_path), f"{symlink_path} is not a symbolic link."
    target = os.readlink(symlink_path)

    if not os.path.isabs(target):
        target = os.path.normpath(os.path.join(os.path.dirname(symlink_path), target))

    assert target == target_dir, f"Symlink {symlink_path} does not point to {target_dir}."
    assert os.path.isfile(os.path.join(symlink_path, "edge_server")), "edge_server not found in the active deployment."


def test_ssh_connectivity():
    result = subprocess.run(
        [
            "runuser", "-u", "user", "--",
            "ssh", "-F", "/home/user/.ssh/config",
            "-i", "/home/user/.ssh/iot_rsa",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            "user@localhost", "true",
        ],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"Passwordless SSH to localhost failed: {result.stderr}"
    assert result.stdout == "", "SSH connectivity check produced unexpected output."


def _listener_inodes(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                rows = f.readlines()[1:]
        except OSError:
            continue
        for row in rows:
            fields = row.split()
            local = fields[1]
            state = fields[3]
            if state != "0A":
                continue
            try:
                local_port = int(local.rsplit(":", 1)[1], 16)
            except (ValueError, IndexError):
                continue
            if local_port == port:
                inodes.add(fields[9])
    return inodes


def _owners_of_inodes(inodes):
    owners = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            fds = os.listdir(fd_dir)
        except OSError:
            continue
        for fd in fds:
            try:
                link = os.readlink(os.path.join(fd_dir, fd))
            except OSError:
                continue
            if link.startswith("socket:[") and link[8:-1] in inodes:
                owners.add(int(entry))
    return owners


def test_processes_running():
    try:
        output = subprocess.check_output(["ps", "-eo", "command"], text=True)
    except subprocess.CalledProcessError:
        pytest.fail("Failed to execute ps command.")

    lines = output.splitlines()

    edge_server_running = any("edge_server" in line and "ps " not in line for line in lines)
    assert edge_server_running, "The edge_server process is not running."

    ssh_forwarding_running = False
    for line in lines:
        if line.startswith("ssh ") or line.find("/ssh ") != -1:
            if "-L" in line and "9090" in line and "8080" in line:
                ssh_forwarding_running = True
                break
    assert ssh_forwarding_running, "SSH port forwarding process (9090 to 8080) is not running."

    edge_owners = _owners_of_inodes(_listener_inodes(8080))
    assert edge_owners, "No process is listening on TCP port 8080."
    deployed = "/home/user/deploy/v1/edge_server"
    deployed_owner = False
    for pid in edge_owners:
        try:
            if os.path.samefile(f"/proc/{pid}/exe", deployed):
                deployed_owner = True
                break
        except OSError:
            pass
    assert deployed_owner, "Port 8080 is not owned by the staged edge_server executable."

    forward_owners = _owners_of_inodes(_listener_inodes(9090))
    assert forward_owners, "No process is listening on TCP port 9090."
    ssh_owner = False
    for pid in forward_owners:
        try:
            exe = os.path.realpath(f"/proc/{pid}/exe")
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode(errors="replace")
        except OSError:
            continue
        if os.path.basename(exe) == "ssh" and "-L" in cmdline and "9090" in cmdline and "8080" in cmdline:
            ssh_owner = True
            break
    assert ssh_owner, "Port 9090 is not owned by the required SSH forwarding process."


def test_deploy_result_log():
    log_path = "/home/user/deploy_result.log"
    reading_path = "/home/user/sensor_data/reading.txt"

    assert os.path.isfile(log_path), f"{log_path} does not exist."
    assert os.path.isfile(reading_path), f"{reading_path} does not exist."

    with open(log_path, "r") as f:
        log_content = f.read()
    with open(reading_path, "r") as f:
        reading_content = f.read()

    assert log_content == reading_content, "The contents of deploy_result.log do not match reading.txt."


def _receive(port):
    deadline = time.time() + 5
    last_error = None
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=2) as sock:
                sock.settimeout(3)
                chunks = []
                while True:
                    chunk = sock.recv(4096)
                    if not chunk:
                        return b"".join(chunks)
                    chunks.append(chunk)
        except OSError as exc:
            last_error = exc
            time.sleep(0.2)
    pytest.fail(f"Could not retrieve data from port {port}: {last_error}")


def test_live_service_and_forwarding():
    reading_path = "/home/user/sensor_data/reading.txt"
    with open(reading_path, "rb") as f:
        original = f.read()

    payload = ("VERIFIER_DYNAMIC_READING=" + os.urandom(24).hex() + "\n").encode()
    try:
        with open(reading_path, "wb") as f:
            f.write(payload)
            f.flush()
            os.fsync(f.fileno())

        direct = _receive(8080)
        assert direct == payload, "The live edge_server on port 8080 did not return the current reading exactly."

        forwarded = _receive(9090)
        assert forwarded == payload, "The SSH-forwarded port 9090 did not return the current reading exactly."
    finally:
        with open(reading_path, "wb") as f:
            f.write(original)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
