#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import pwd
import re
import socket
import subprocess
import time

import pytest
import requests


def run(command, **kwargs):
    return subprocess.run(command, capture_output=True, text=True, **kwargs)


def public_key_fields(private_key):
    result = run(["ssh-keygen", "-y", "-f", private_key], timeout=5)
    assert result.returncode == 0, f"Invalid SSH private key {private_key}: {result.stderr}"
    fields = result.stdout.strip().split()
    assert len(fields) >= 2, f"Could not derive public key from {private_key}"
    return fields[:2]


def assert_ed25519_private_key(path):
    result = run(["ssh-keygen", "-lf", path], timeout=5)
    assert result.returncode == 0, f"Invalid SSH key {path}: {result.stderr}"
    assert "ED25519" in result.stdout.upper(), f"{path} is not an Ed25519 key: {result.stdout}"
    assert public_key_fields(path)[0] == "ssh-ed25519", f"{path} is not an Ed25519 private key"


def proc_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode(errors="replace").strip()
    except OSError:
        return ""


def proc_parent(pid):
    try:
        with open(f"/proc/{pid}/stat", "r") as f:
            data = f.read()
        return int(data[data.rfind(")") + 2:].split()[1])
    except (OSError, ValueError, IndexError):
        return 0


def socket_entries(port):
    entries = []
    for table, ipv6 in (("/proc/net/tcp", False), ("/proc/net/tcp6", True)):
        try:
            with open(table, "r") as f:
                lines = f.readlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local_address, state, inode = fields[1], fields[3], fields[9]
            address, hex_port = local_address.split(":")
            if int(hex_port, 16) == port:
                entries.append((address, state, inode, ipv6))
    return entries


def pids_owning_inodes(inodes):
    wanted = {f"socket:[{inode}]" for inode in inodes}
    owners = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(os.path.join(fd_dir, fd)) in wanted:
                        owners.add(int(name))
                        break
                except OSError:
                    pass
        except OSError:
            pass
    return owners


def test_hash_file():
    hash_file_path = "/home/user/old_hash.txt"
    assert os.path.isfile(hash_file_path), f"Missing hash file: {hash_file_path}"

    with open(hash_file_path, "r") as f:
        actual_hash = f.read().strip()

    expected_text = "RELIANT_DEFENSE_99"
    expected_hash = hashlib.sha256(expected_text.encode("utf-8")).hexdigest()

    assert actual_hash == expected_hash, f"Hash mismatch. Expected {expected_hash}, got {actual_hash}"


def test_http_service():
    url = "http://127.0.0.1:8080/"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"HTTP GET request to {url} failed: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"

    csp_header = response.headers.get("Content-Security-Policy", "")
    assert "default-src 'none'" in csp_header, f"Missing or incorrect Content-Security-Policy header. Got: {csp_header}"

    assert response.text.strip() == "Secure System", f"Incorrect response body. Got: {response.text}"


def test_ssh_service():
    key_path = "/home/user/admin_key"
    assert os.path.isfile(key_path), f"Missing SSH private key: {key_path}"

    os.chmod(key_path, 0o600)

    ssh_command = [
        "ssh",
        "-i", key_path,
        "-p", "2222",
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "BatchMode=yes",
        "user@127.0.0.1",
        "echo 'SSH_SUCCESS'"
    ]

    try:
        result = subprocess.run(ssh_command, capture_output=True, text=True, timeout=10)
    except subprocess.TimeoutExpired:
        pytest.fail("SSH connection timed out.")

    assert result.returncode == 0, f"SSH connection failed. stderr: {result.stderr}"
    assert "SSH_SUCCESS" in result.stdout, f"Expected 'SSH_SUCCESS' in output, got: {result.stdout}"


def test_files_exist():
    required_files = [
        "/home/user/host_key",
        "/home/user/sshd_config",
        "/home/user/httpd.sh"
    ]
    for filepath in required_files:
        assert os.path.isfile(filepath), f"Required file {filepath} is missing."


def test_key_material_and_authorized_keys():
    for path in ("/home/user/admin_key", "/home/user/host_key"):
        assert os.path.isfile(path), f"Missing private key: {path}"
        assert_ed25519_private_key(path)

    admin_fields = public_key_fields("/home/user/admin_key")
    pub_path = "/home/user/admin_key.pub"
    assert os.path.isfile(pub_path), f"Missing public key: {pub_path}"
    with open(pub_path, "r") as f:
        pub_fields = f.read().strip().split()
    assert pub_fields[:2] == admin_fields, "admin_key.pub does not match admin_key"

    authorized_path = "/home/user/.ssh/authorized_keys"
    assert os.path.isfile(authorized_path), f"Missing authorized_keys: {authorized_path}"
    with open(authorized_path, "r") as f:
        authorized = [line.split()[:2] for line in f if line.strip() and not line.lstrip().startswith("#")]
    assert admin_fields in authorized, "admin_key.pub is not present in authorized_keys"


def test_sshd_configuration_and_running_instance():
    config = "/home/user/sshd_config"
    result = run(["/usr/sbin/sshd", "-T", "-f", config,
                  "-C", "user=user,host=localhost,addr=127.0.0.1"], timeout=10)
    assert result.returncode == 0, f"Invalid sshd_config: {result.stderr}"

    values = {}
    for line in result.stdout.splitlines():
        parts = line.split(None, 1)
        if len(parts) == 2:
            values.setdefault(parts[0].lower(), []).append(parts[1].strip())

    assert values.get("port") == ["2222"], f"sshd port is not 2222: {values.get('port')}"
    assert values.get("hostkey") == ["/home/user/host_key"], f"Wrong HostKey: {values.get('hostkey')}"
    assert values.get("passwordauthentication") == ["no"], "PasswordAuthentication must be disabled"
    assert values.get("strictmodes") == ["no"], "StrictModes must be disabled"
    assert values.get("pidfile") == ["/home/user/sshd.pid"], f"Wrong PidFile: {values.get('pidfile')}"
    assert values.get("authorizedkeysfile") == ["/home/user/.ssh/authorized_keys"], \
        f"Wrong AuthorizedKeysFile: {values.get('authorizedkeysfile')}"

    pidfile = "/home/user/sshd.pid"
    assert os.path.isfile(pidfile), "Configured sshd PidFile is missing"
    with open(pidfile, "r") as f:
        pid_text = f.read().strip()
    assert pid_text.isdigit(), f"Invalid sshd PID: {pid_text!r}"
    pid = int(pid_text)
    assert os.path.isdir(f"/proc/{pid}"), "The sshd process named by sshd.pid is not running"
    cmdline = proc_cmdline(pid)
    assert "sshd" in cmdline and config in cmdline, f"Running sshd is not using {config}: {cmdline}"

    with open(f"/proc/{pid}/status", "r") as f:
        status = f.read()
    uid_match = re.search(r"^Uid:\s+(\d+)", status, re.MULTILINE)
    assert uid_match, "Could not determine sshd process owner"
    assert int(uid_match.group(1)) == pwd.getpwnam("user").pw_uid, "sshd is not running as user"

    listeners = [entry for entry in socket_entries(2222) if entry[1] == "0A"]
    assert listeners, "No listening TCP socket found on port 2222"
    ipv4 = [entry for entry in listeners if not entry[3]]
    assert any(entry[0] in ("0100007F", "00000000") for entry in ipv4), \
        "SSH must bind to IPv4 127.0.0.1 or 0.0.0.0"
    listener_owners = pids_owning_inodes([entry[2] for entry in listeners])
    assert pid in listener_owners, "The configured sshd process does not own the port 2222 listener"

    scan = run(["ssh-keyscan", "-T", "5", "-p", "2222", "127.0.0.1"], timeout=8)
    scanned = [line.split()[1:3] for line in scan.stdout.splitlines()
               if line.strip() and not line.startswith("#") and len(line.split()) >= 3]
    assert public_key_fields("/home/user/host_key") in scanned, \
        "The SSH service is not presenting /home/user/host_key"


def test_http_is_running_bash_script_and_binding_is_allowed():
    script = "/home/user/httpd.sh"
    with open(script, "rb") as f:
        first_line = f.readline().decode(errors="replace").strip()
    assert re.match(r"^#!\s*(/bin/bash|/usr/bin/bash|/usr/bin/env\s+bash)(?:\s|$)", first_line), \
        "httpd.sh must be a Bash script"
    syntax = run(["bash", "-n", script], timeout=5)
    assert syntax.returncode == 0, f"httpd.sh has invalid Bash syntax: {syntax.stderr}"

    listeners = [entry for entry in socket_entries(8080) if entry[1] == "0A"]
    assert listeners, "No listening TCP socket found on port 8080"
    ipv4 = [entry for entry in listeners if not entry[3]]
    assert any(entry[0] in ("0100007F", "00000000") for entry in ipv4), \
        "HTTP must bind to IPv4 127.0.0.1 or 0.0.0.0"

    client = socket.create_connection(("127.0.0.1", 8080), timeout=5)
    try:
        owners = set()
        deadline = time.time() + 2
        while time.time() < deadline and not owners:
            related = [entry for entry in socket_entries(8080) if entry[1] in ("0A", "01")]
            owners = pids_owning_inodes([entry[2] for entry in related])
            if not owners:
                time.sleep(0.05)

        found_bash_script = False
        for owner in owners:
            pid = owner
            for _ in range(12):
                if pid <= 1:
                    break
                cmdline = proc_cmdline(pid)
                try:
                    executable = os.path.basename(os.readlink(f"/proc/{pid}/exe"))
                except OSError:
                    executable = ""
                if executable.startswith("bash") and script in cmdline:
                    found_bash_script = True
                    break
                pid = proc_parent(pid)
            if found_bash_script:
                break
        assert found_bash_script, "The port 8080 service is not being run by /home/user/httpd.sh under Bash"

        client.sendall(b"GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n")
        data = b""
        while True:
            chunk = client.recv(4096)
            if not chunk:
                break
            data += chunk
    finally:
        client.close()

    text = data.decode("iso-8859-1", errors="replace")
    head, separator, body = text.partition("\r\n\r\n")
    assert separator, f"HTTP response is malformed: {text!r}"
    assert head.startswith("HTTP/1.1 200 OK\r\n"), f"Expected HTTP/1.1 200 OK, got: {head!r}"
    assert re.search(r"(?im)^Content-Security-Policy:\s*default-src 'none';\s*$", head), \
        f"Missing exact CSP header: {head!r}"
    assert body.strip() == "Secure System", f"Incorrect response body: {body!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
