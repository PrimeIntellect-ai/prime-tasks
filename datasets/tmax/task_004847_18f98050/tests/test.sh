#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import socket
import string
import subprocess
import threading
import pytest


def test_provision_directory_and_symlink():
    instance_id = "vm-alpha-88"
    dir_path = f"/home/user/provision/{instance_id}"
    symlink_path = os.path.join(dir_path, "latest-disk")

    assert os.path.isdir(dir_path), f"Directory {dir_path} does not exist."
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink."

    target = os.readlink(symlink_path)
    assert target == "/app/base.qcow2", f"Symlink {symlink_path} points to {target}, expected /app/base.qcow2"


def _listening_socket_inodes(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) < 10:
                        continue
                    local_address = fields[1]
                    state = fields[3]
                    if state != "0A":
                        continue
                    try:
                        local_port = int(local_address.rsplit(":", 1)[1], 16)
                    except ValueError:
                        continue
                    if local_port == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass
    return inodes


def _process_socket_inodes(pid):
    inodes = set()
    fd_dir = f"/proc/{pid}/fd"
    for name in os.listdir(fd_dir):
        try:
            target = os.readlink(os.path.join(fd_dir, name))
        except OSError:
            continue
        if target.startswith("socket:[") and target.endswith("]"):
            inodes.add(target[8:-1])
    return inodes


def test_ssh_tunnel_pid_and_forwarding():
    pid_file = "/home/user/tunnel.pid"
    assert os.path.isfile(pid_file), f"PID file {pid_file} does not exist."

    with open(pid_file, "r") as f:
        pid_str = f.read().strip()

    assert pid_str.isdigit(), f"PID file {pid_file} does not contain a valid integer PID."
    pid = int(pid_str)

    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f"Process with PID {pid} from {pid_file} is not running.")

    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            cmdline = f.read().replace(b"\x00", b" ").decode("utf-8", errors="replace")
    except FileNotFoundError:
        pytest.fail(f"Process with PID {pid} disappeared during verification.")

    assert "ssh" in cmdline, f"Process {pid} is not an ssh command: {cmdline}"
    assert "8080:localhost:9922" in cmdline or "8080:127.0.0.1:9922" in cmdline, \
        f"SSH command does not contain the correct port forwarding: {cmdline}"

    listener_inodes = _listening_socket_inodes(8080)
    process_inodes = _process_socket_inodes(pid)
    assert listener_inodes & process_inodes, \
        f"SSH process {pid} does not own a listening socket on local port 8080."

    backend = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    backend.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        backend.bind(("127.0.0.1", 9922))
    except OSError as exc:
        pytest.fail(f"Cannot start forwarding test backend on localhost:9922: {exc}")
    backend.listen(1)
    backend.settimeout(5)

    payload = os.urandom(64)
    expected = b"ACK:" + hashlib.sha256(payload).digest()
    backend_result = {"error": None}

    def serve_once():
        try:
            conn, _ = backend.accept()
            with conn:
                conn.settimeout(5)
                received = b""
                while len(received) < len(payload):
                    chunk = conn.recv(len(payload) - len(received))
                    if not chunk:
                        break
                    received += chunk
                if received != payload:
                    raise AssertionError(f"Backend received {len(received)} incorrect bytes")
                conn.sendall(expected)
        except BaseException as exc:
            backend_result["error"] = exc
        finally:
            backend.close()

    thread = threading.Thread(target=serve_once, daemon=True)
    thread.start()

    received = b""
    try:
        with socket.create_connection(("127.0.0.1", 8080), timeout=5) as client:
            client.settimeout(5)
            client.sendall(payload)
            while len(received) < len(expected):
                chunk = client.recv(len(expected) - len(received))
                if not chunk:
                    break
                received += chunk
    except OSError as exc:
        pytest.fail(f"Local SSH forward on port 8080 is not usable: {exc}")

    thread.join(timeout=6)
    assert not thread.is_alive(), "Forwarding test backend did not complete."
    assert backend_result["error"] is None, f"Forwarding backend failed: {backend_result['error']}"
    assert received == expected, "Data was not correctly forwarded between local port 8080 and localhost:9922."


def test_proxy_filter_fuzz_equivalence():
    source_file = "/home/user/proxy_filter.go"
    agent_bin = "/home/user/proxy_filter"
    oracle_bin = "/tests/reference_proxy_filter"

    assert os.path.isfile(source_file), f"Go source {source_file} does not exist."
    assert os.path.isfile(agent_bin), f"Agent binary {agent_bin} does not exist."
    assert os.access(agent_bin, os.X_OK), f"Agent binary {agent_bin} is not executable."

    assert os.path.isfile(oracle_bin), f"Oracle binary {oracle_bin} does not exist."
    assert os.access(oracle_bin, os.X_OK), f"Oracle binary {oracle_bin} is not executable."

    with open(agent_bin, "rb") as f:
        agent_bytes = f.read()
    with open(oracle_bin, "rb") as f:
        oracle_bytes = f.read()
    assert agent_bytes != oracle_bytes, "Agent binary is byte-identical to the reference implementation."

    random.seed(42)
    charset = string.ascii_letters + string.digits

    def generate_input():
        length = random.randint(10, 100)
        chars = [random.choice(charset) for _ in range(length)]
        insert_pos = random.randint(0, max(0, length - 3))
        chars[insert_pos:insert_pos + 3] = list("DEV")
        if random.random() > 0.5:
            insert_pos2 = random.randint(0, max(0, len(chars) - 3))
            chars[insert_pos2:insert_pos2 + 3] = list("DEV")
        return "".join(chars) + "\n"

    inputs = [generate_input() for _ in range(1000)]
    input_data = "".join(inputs).encode("utf-8")

    agent_proc = subprocess.run([agent_bin], input=input_data, capture_output=True)
    oracle_proc = subprocess.run([oracle_bin], input=input_data, capture_output=True)

    assert agent_proc.returncode == 0, \
        f"Agent binary failed with return code {agent_proc.returncode}\nStderr: {agent_proc.stderr.decode(errors='replace')}"
    assert oracle_proc.returncode == 0, f"Oracle binary failed with return code {oracle_proc.returncode}"

    agent_out = agent_proc.stdout.decode("utf-8").splitlines()
    oracle_out = oracle_proc.stdout.decode("utf-8").splitlines()

    assert len(agent_out) == len(oracle_out), \
        f"Output line count mismatch: agent={len(agent_out)}, oracle={len(oracle_out)}"

    for i, (a_line, o_line) in enumerate(zip(agent_out, oracle_out)):
        if a_line != o_line:
            orig_input = inputs[i].strip()
            pytest.fail(
                f"Mismatch on input line {i + 1}: '{orig_input}'\nExpected: '{o_line}'\nGot:      '{a_line}'"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
