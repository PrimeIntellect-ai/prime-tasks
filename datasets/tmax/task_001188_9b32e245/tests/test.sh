#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shlex
import signal
import socket
import subprocess
import time
import uuid
import pytest

UPLOADER = "/home/user/secure_uploader"
SOURCE = "/home/user/secure_uploader.c"
VAULT = "/home/user/evidence_vault"
REBUILT = "/tmp/verified_secure_uploader"
_rebuilt_process = None


def listener_entries(port):
    entries = []
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    address, port_hex = fields[1].rsplit(":", 1)
                    if int(port_hex, 16) == port and fields[3] == "0A":
                        entries.append((table, address, fields[9]))
        except FileNotFoundError:
            pass
    return entries


def listener_pids(port):
    inodes = {entry[2] for entry in listener_entries(port)}
    found = set()
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
                if match and match.group(1) in inodes:
                    found.add(int(name))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return found


def wait_for_listener(port, timeout=4):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if listener_entries(port):
            return
        time.sleep(0.05)
    pytest.fail(f"No listener appeared on port {port}")


def stop_port(port):
    pids = listener_pids(port)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_entries(port):
        time.sleep(0.05)
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_entries(port):
        time.sleep(0.05)
    assert not listener_entries(port), f"Could not stop existing listener on port {port}"


def read_to_close(sock):
    chunks = []
    sock.settimeout(2)
    while True:
        try:
            chunk = sock.recv(4096)
        except socket.timeout:
            pytest.fail("Daemon did not close the connection")
        if not chunk:
            return b"".join(chunks)
        chunks.append(chunk)


def send_upload(filename, content, fragmented=False):
    message = b"STORE " + filename.encode() + b"\n" + content
    with socket.create_connection(("127.0.0.1", 8080), timeout=2) as sock:
        if fragmented:
            cuts = [1, 3, 7, len(b"STORE " + filename.encode()), len(b"STORE " + filename.encode()) + 1]
            start = 0
            for end in cuts:
                end = min(end, len(message))
                if end > start:
                    sock.sendall(message[start:end])
                    time.sleep(0.015)
                start = end
            if start < len(message):
                for pos in range(start, len(message), 317):
                    sock.sendall(message[pos:pos + 317])
        else:
            sock.sendall(message)
        sock.shutdown(socket.SHUT_WR)
        return read_to_close(sock)


def wait_for_file(path, expected, timeout=3):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with open(path, "rb") as f:
                if f.read() == expected:
                    return
        except FileNotFoundError:
            pass
        time.sleep(0.05)
    pytest.fail(f"Uploaded file {path} was not created with the expected content")


def test_forensics_report_exists():
    """Check that the forensics report was created and records the recovered facts."""
    path = "/home/user/forensics_report.txt"
    assert os.path.exists(path), f"Missing forensics report at {path}"
    assert os.path.isfile(path), f"{path} is not a file"
    with open(path, "r", errors="replace") as f:
        report = f.read()
    assert "STORE" in report, "Report does not identify the STORE command"
    assert "sys_update_bin" in report, "Report does not identify the exact backdoor filename"
    assert ".." in report and "/" in report, "Report does not describe the traversal characters"
    assert re.search(r"newline|\\n|line feed", report, re.IGNORECASE), "Report does not describe the filename delimiter"


def test_secure_uploader_binary():
    """Check that the secure uploader was compiled and is the running listener."""
    path = UPLOADER
    assert os.path.exists(path), f"Missing secure uploader binary at {path}"
    assert os.access(path, os.X_OK), f"Secure uploader at {path} is not executable"
    assert os.path.isfile(SOURCE), f"Missing C source at {SOURCE}"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "secure_uploader is not a compiled ELF binary"

    entries = listener_entries(8080)
    assert entries, "Secure uploader is not listening on port 8080"
    assert all(table == "/proc/net/tcp" and address == "0100007F" for table, address, _ in entries), \
        "Secure uploader must listen only on IPv4 address 127.0.0.1"
    pids = listener_pids(8080)
    assert pids, "Could not identify the process listening on port 8080"
    assert any(os.path.samefile(f"/proc/{pid}/exe", path) for pid in pids), \
        "The process listening on port 8080 is not /home/user/secure_uploader"


def test_custom_daemon_valid_upload():
    """Test that the custom daemon accepts valid uploads."""
    host, port = "127.0.0.1", 8080
    filename = "evidence1.txt"
    content = b"test_evidence_data"

    if not os.path.exists(VAULT):
        os.makedirs(VAULT, exist_ok=True)

    target_file = os.path.join(VAULT, filename)
    if os.path.exists(target_file):
        os.remove(target_file)

    try:
        with socket.create_connection((host, port), timeout=2) as s:
            s.sendall(f"STORE {filename}\n".encode() + content)
    except Exception as e:
        pytest.fail(f"Failed to connect or send data to daemon on {host}:{port}: {e}")

    time.sleep(0.5)
    assert os.path.exists(target_file), f"Daemon did not write to {target_file}"
    with open(target_file, "rb") as f:
        assert f.read() == content, "File content does not match uploaded data"


def test_custom_daemon_path_traversal():
    """Test that the custom daemon rejects path traversal."""
    host, port = "127.0.0.1", 8080
    try:
        with socket.create_connection((host, port), timeout=2) as s:
            s.sendall(b"STORE ../../../etc/shadow\nmalicious_data")
            response = s.recv(1024)
            assert response == b"ERROR: INVALID PATH\n", f"Expected ERROR: INVALID PATH\\n, got {response}"
    except Exception as e:
        pytest.fail(f"Failed during path traversal test: {e}")


def test_custom_daemon_backdoor():
    """Test that the custom daemon rejects the backdoor filename."""
    host, port = "127.0.0.1", 8080
    try:
        with socket.create_connection((host, port), timeout=2) as s:
            s.sendall(b"STORE sys_update_bin\nmalicious_data")
            response = s.recv(1024)
            assert response == b"ERROR: INVALID PATH\n", f"Expected ERROR: INVALID PATH\\n, got {response}"
    except Exception as e:
        pytest.fail(f"Failed during backdoor test: {e}")


def test_c_source_rebuild_and_general_protocol():
    """Compile the submitted C source and exercise the rebuilt implementation on fresh inputs."""
    global _rebuilt_process
    build = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE, "-o", REBUILT],
        capture_output=True, text=True
    )
    assert build.returncode == 0, f"Submitted C source does not compile:\n{build.stderr}"
    with open(REBUILT, "rb") as f:
        assert f.read(4) == b"\x7fELF"

    stop_port(8080)
    _rebuilt_process = subprocess.Popen([REBUILT], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    wait_for_listener(8080)
    entries = listener_entries(8080)
    assert all(table == "/proc/net/tcp" and address == "0100007F" for table, address, _ in entries), \
        "Rebuilt daemon did not bind specifically to 127.0.0.1"
    assert any(os.path.samefile(f"/proc/{pid}/exe", REBUILT) for pid in listener_pids(8080)), \
        "Rebuilt C artifact is not the process serving port 8080"

    for index in range(3):
        filename = f"case_{uuid.uuid4().hex}_{index}.bin"
        content = os.urandom(5000 + index * 173) + b"\x00\nSTORE not_a_header\xff"
        target = os.path.join(VAULT, filename)
        if os.path.exists(target):
            os.remove(target)
        response = send_upload(filename, content, fragmented=True)
        assert response == b"", f"Unexpected success response: {response!r}"
        wait_for_file(target, content)

    bad_names = [
        f"prefix..{uuid.uuid4().hex}",
        f"dir/{uuid.uuid4().hex}",
        f"../{uuid.uuid4().hex}",
        "sys_update_bin",
    ]
    for bad_name in bad_names:
        response = send_upload(bad_name, os.urandom(41), fragmented=True)
        assert response == b"ERROR: INVALID PATH\n", f"Daemon accepted invalid filename {bad_name!r}: {response!r}"


def test_ssh_configuration():
    """Check SSH binding, effective authentication settings, authorized key, and real key login."""
    try:
        with socket.create_connection(("127.0.0.1", 2222), timeout=2) as s:
            banner = s.recv(1024)
            assert b"SSH" in banner, "Service on port 2222 does not appear to be SSH"
    except Exception as e:
        pytest.fail(f"Failed to connect to SSH on port 2222: {e}")

    entries = listener_entries(2222)
    assert entries
    assert all(table == "/proc/net/tcp" and address == "0100007F" for table, address, _ in entries), \
        "SSH must listen only on IPv4 address 127.0.0.1"

    auth_keys_path = "/home/user/.ssh/authorized_keys"
    assert os.path.exists(auth_keys_path), "authorized_keys file not found"
    with open("/home/user/investigator.pub", "r") as f:
        pub_key = f.read().strip()
    with open(auth_keys_path, "r") as f:
        auth_keys = f.read()
    assert pub_key in auth_keys, "Investigator public key not found in authorized_keys"

    effective = subprocess.run(["sshd", "-T"], capture_output=True, text=True)
    assert effective.returncode == 0, f"Unable to read effective sshd configuration: {effective.stderr}"
    settings = {}
    for line in effective.stdout.splitlines():
        parts = line.split(None, 1)
        if len(parts) == 2:
            settings.setdefault(parts[0].lower(), []).append(parts[1].lower())
    assert settings.get("passwordauthentication") == ["no"], "PasswordAuthentication is not disabled"
    assert settings.get("kbdinteractiveauthentication") == ["no"], "Keyboard-interactive password authentication is not disabled"
    assert settings.get("pubkeyauthentication") == ["yes"], "Public-key authentication is not enabled"
    assert "2222" in settings.get("port", []), "Effective SSH port is not 2222"

    key_copy = "/tmp/investigator_verifier_key"
    with open("/home/user/investigator", "rb") as src, open(key_copy, "wb") as dst:
        dst.write(src.read())
    os.chmod(key_copy, 0o600)
    login = subprocess.run([
        "ssh", "-p", "2222", "-i", key_copy,
        "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes",
        "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
        "-o", "ConnectTimeout=3", "user@127.0.0.1", "true"
    ], capture_output=True, text=True, timeout=8)
    assert login.returncode == 0, f"Investigator key could not authenticate as user: {login.stderr}"


def test_iptables_rules():
    """Check INPUT DROP, loopback, unrestricted TCP 2222, and absence of permissive rules."""
    try:
        result = subprocess.run(["iptables", "-S"], capture_output=True, text=True, check=True)
        rules = result.stdout

        assert "-P INPUT DROP" in rules, "Default INPUT policy is not DROP"
        assert "-A INPUT -i lo -j ACCEPT" in rules or "-A INPUT -i lo -m comment" in rules or any("lo" in r and "ACCEPT" in r for r in rules.splitlines() if "-A INPUT" in r), "Loopback interface not explicitly allowed in INPUT"
        assert "-p tcp" in rules and "2222" in rules and "ACCEPT" in rules, "TCP port 2222 not explicitly allowed in INPUT"

        input_result = subprocess.run(["iptables", "-S", "INPUT"], capture_output=True, text=True, check=True)
        parsed = [shlex.split(line) for line in input_result.stdout.splitlines() if line.strip()]
        assert ["-P", "INPUT", "DROP"] in parsed, "INPUT policy is not exactly DROP"

        loopback_ok = False
        ssh_ok = False
        for tokens in parsed:
            if tokens[:2] != ["-A", "INPUT"]:
                continue
            target = tokens[tokens.index("-j") + 1] if "-j" in tokens else None
            if target == "ACCEPT":
                if "-i" in tokens and tokens[tokens.index("-i") + 1] == "lo" and "!" not in tokens:
                    loopback_ok = True
                    continue
                if "--ctstate" in tokens:
                    states = set(tokens[tokens.index("--ctstate") + 1].split(","))
                    if states and states <= {"ESTABLISHED", "RELATED"} and "!" not in tokens:
                        continue
                is_ssh = (
                    "!" not in tokens and "-p" in tokens and tokens[tokens.index("-p") + 1] == "tcp" and
                    "--dport" in tokens and tokens[tokens.index("--dport") + 1] == "2222" and
                    "-i" not in tokens and "-s" not in tokens and "-d" not in tokens
                )
                assert is_ssh, f"Extra or restricted INPUT ACCEPT rule is not allowed: {' '.join(tokens)}"
                ssh_ok = True
            elif target not in ("DROP", "REJECT", "LOG", None):
                pytest.fail(f"INPUT jumps to an unchecked chain/target: {' '.join(tokens)}")

        assert loopback_ok, "Loopback is not accepted"
        assert ssh_ok, "TCP port 2222 is not accepted from every interface/source"
    except FileNotFoundError:
        pytest.fail("iptables command not found")
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to run iptables: {e.stderr}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
