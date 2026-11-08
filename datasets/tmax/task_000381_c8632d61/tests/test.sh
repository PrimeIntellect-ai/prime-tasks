#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import socket
import subprocess
import urllib.request
import pytest

SOURCE = "/home/user/exporter.c"
BINARY = "/home/user/exporter"
METRICS = "/home/user/dashboard_data/metrics_source.txt"
LOG = "/home/user/dashboard_test.log"
KEY = "/home/user/.ssh/id_rsa"


def proc_exe(pid):
    try:
        return os.path.realpath(f"/proc/{pid}/exe")
    except OSError:
        return None


def proc_args(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return [x.decode("utf-8", "surrogateescape") for x in f.read().split(b"\0") if x]
    except OSError:
        return []


def listening_inodes(address, port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local_hex, state, inode = fields[1], fields[3], fields[9]
                    if state != "0A":
                        continue
                    hex_addr, hex_port = local_hex.split(":")
                    if int(hex_port, 16) != port:
                        continue
                    if table.endswith("tcp"):
                        decoded = socket.inet_ntop(socket.AF_INET, bytes.fromhex(hex_addr)[::-1])
                    else:
                        raw = bytes.fromhex(hex_addr)
                        raw = b"".join(raw[i:i+4][::-1] for i in range(0, 16, 4))
                        decoded = socket.inet_ntop(socket.AF_INET6, raw)
                    if decoded == address:
                        result.add(inode)
        except FileNotFoundError:
            pass
    return result


def owners_of_inodes(inodes):
    owners = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    owners.add(int(entry))
                    break
        except OSError:
            continue
    return owners


def listener_owners(address, port):
    inodes = listening_inodes(address, port)
    assert inodes, f"No listener found on {address}:{port}"
    return owners_of_inodes(inodes)


def same_executable(pid, path):
    try:
        return os.path.samefile(f"/proc/{pid}/exe", path)
    except OSError:
        return False


def ssh_has_required_forward(args):
    forwards = []
    identities = []
    has_no_command = False

    i = 1
    while i < len(args):
        arg = args[i]
        if arg == "-L" and i + 1 < len(args):
            forwards.append(args[i + 1])
            i += 2
            continue
        if arg.startswith("-L") and len(arg) > 2:
            forwards.append(arg[2:])
        if arg == "-i" and i + 1 < len(args):
            identities.append(args[i + 1])
            i += 2
            continue
        if arg.startswith("-i") and len(arg) > 2:
            identities.append(arg[2:])
        if arg == "-N" or (arg.startswith("-") and not arg.startswith("--") and "N" in arg[1:]):
            has_no_command = True
        i += 1

    valid_forward = any(spec in (
        "9090:127.0.0.1:8000",
        "127.0.0.1:9090:127.0.0.1:8000",
    ) for spec in forwards)
    valid_identity = any(os.path.abspath(value) == KEY for value in identities)
    valid_destination = "user@127.0.0.1" in args
    return valid_forward and valid_identity and valid_destination and has_no_command


def raw_http_request(port, request):
    with socket.create_connection(("127.0.0.1", port), timeout=5) as sock:
        sock.sendall(request)
        sock.shutdown(socket.SHUT_WR)
        chunks = []
        while True:
            data = sock.recv(65536)
            if not data:
                break
            chunks.append(data)
    response = b"".join(chunks)
    assert b"\r\n\r\n" in response, "Response lacks a valid HTTP header terminator"
    header, body = response.split(b"\r\n\r\n", 1)
    lines = header.split(b"\r\n")
    assert lines[0] == b"HTTP/1.1 200 OK", f"Unexpected status line: {lines[0]!r}"
    headers = {}
    for line in lines[1:]:
        assert b":" in line, f"Malformed HTTP header: {line!r}"
        name, value = line.split(b":", 1)
        headers[name.strip().lower()] = value.strip().lower()
    assert headers.get(b"content-type") == b"text/plain", "Content-Type must be text/plain"
    return body


def test_exporter_source_and_binary_exist():
    assert os.path.exists(SOURCE), f"C source file not found at {SOURCE}"
    assert os.path.exists(BINARY), f"Compiled binary not found at {BINARY}"
    assert os.path.isfile(BINARY), f"Compiled binary is not a regular file: {BINARY}"
    assert os.access(BINARY, os.X_OK), f"File at {BINARY} is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Exporter is not a compiled ELF executable"

    compiled = "/tmp/exporter_source_check"
    result = subprocess.run(["gcc", SOURCE, "-o", compiled], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, timeout=20)
    assert result.returncode == 0, f"exporter.c does not compile:\n{result.stderr}"
    assert os.access(compiled, os.X_OK)


def test_exporter_process_running_and_owns_port_8000():
    # Preserve the original process assertion.
    try:
        output = subprocess.check_output(["pgrep", "-f", "exporter"]).decode("utf-8")
        assert output.strip(), "Exporter process is not running"
    except subprocess.CalledProcessError:
        pytest.fail("Exporter process is not running")

    owners = listener_owners("127.0.0.1", 8000)
    real_exporters = [pid for pid in owners if same_executable(pid, BINARY)]
    assert real_exporters, (
        "Port 127.0.0.1:8000 is not owned by the submitted /home/user/exporter executable"
    )


def test_ssh_tunnel_running_and_owns_port_9090():
    # Preserve the original command-line assertion.
    try:
        output = subprocess.check_output(
            ["pgrep", "-f", "ssh.*-L.*9090:.*8000"]
        ).decode("utf-8")
        assert output.strip(), "SSH tunnel process is not running"
    except subprocess.CalledProcessError:
        pytest.fail("SSH tunnel process is not running (could not find ssh -L 9090:...:8000)")

    owners = listener_owners("127.0.0.1", 9090)
    valid = []
    for pid in owners:
        exe = proc_exe(pid)
        args = proc_args(pid)
        if exe == "/usr/bin/ssh" and ssh_has_required_forward(args):
            valid.append(pid)
    assert valid, (
        "Port 127.0.0.1:9090 must be owned by a real /usr/bin/ssh process configured "
        "with -N, the supplied key, user@127.0.0.1, and a local forward to 127.0.0.1:8000"
    )


def test_dashboard_test_log():
    assert os.path.exists(LOG), f"Log file not found at {LOG}"
    assert os.path.exists(METRICS), f"Source file not found at {METRICS}"
    with open(METRICS, "r") as f:
        expected_content = f.read().strip()
    with open(LOG, "r") as f:
        actual_content = f.read().strip()
    assert actual_content == expected_content, f"Content of {LOG} does not match {METRICS}"


def test_tunnel_responds():
    try:
        req = urllib.request.Request("http://127.0.0.1:9090/")
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.getcode() == 200, f"Expected HTTP 200, got {response.getcode()}"
            body = response.read().decode("utf-8").strip()
        with open(METRICS, "r") as f:
            expected_content = f.read().strip()
        assert expected_content in body, "Response body does not contain expected metrics data"
    except Exception as e:
        pytest.fail(f"Failed to fetch from http://127.0.0.1:9090/ - {e}")


def test_live_exporter_and_tunnel_use_metrics_file_exactly():
    with open(METRICS, "rb") as f:
        original = f.read()
    randomized = ("verifier_metric_" + secrets.token_hex(20) + " 917\n").encode("ascii")
    request = (
        b"POST /arbitrary/path?probe=1 HTTP/1.1\r\n"
        b"Host: 127.0.0.1\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    )
    try:
        with open(METRICS, "wb") as f:
            f.write(randomized)
            f.flush()
            os.fsync(f.fileno())

        direct_body = raw_http_request(8000, request)
        tunnel_body = raw_http_request(9090, request)
        assert direct_body == randomized, "Exporter did not return the exact current metrics file"
        assert tunnel_body == randomized, "SSH-forwarded response did not match the exporter response"
    finally:
        with open(METRICS, "wb") as f:
            f.write(original)
            f.flush()
            os.fsync(f.fileno())
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
