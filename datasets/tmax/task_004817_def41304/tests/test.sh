#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import re
import secrets
import shutil
import subprocess
import tempfile
import time
import xml.etree.ElementTree as ET

import pytest

REQUIRED_KEY_TYPE = "ssh-ed25519"
REQUIRED_KEY_DATA = "AAAAC3NzaC1lZDI1NTE5AAAAIMYyHq/MdfiQ/hXmR9T7C8yWwGqK3yB7a1s7Q/X4zW2a"
REQUIRED_KEX = {"curve25519-sha256@libssh.org"}
REQUIRED_CIPHERS = {"chacha20-poly1305@openssh.com"}
REQUIRED_MACS = {"hmac-sha2-512-etm@openssh.com"}


def run(cmd, timeout=30):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def listener_pid():
    wanted_inode = None
    with open("/proc/net/tcp", "r") as f:
        for line in f.readlines()[1:]:
            fields = line.split()
            local, state = fields[1], fields[3]
            if local.upper() == "0100007F:08AE" and state == "0A":
                wanted_inode = fields[9]
                break
    assert wanted_inode, "No TCP listener exists on 127.0.0.1:2222"

    needle = "socket:[%s]" % wanted_inode
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = "/proc/%s/fd" % pid
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(os.path.join(fd_dir, fd)) == needle:
                        return int(pid)
                except OSError:
                    pass
        except OSError:
            pass
    pytest.fail("Could not identify the process listening on 127.0.0.1:2222")


def parse_effective_config(text):
    values = {}
    for line in text.splitlines():
        if not line.strip():
            continue
        key, _, value = line.partition(" ")
        values.setdefault(key.lower(), []).append(value.strip())
    return values


@pytest.fixture(scope="session")
def ssh_state():
    pid = listener_pid()
    exe = os.path.realpath("/proc/%d/exe" % pid)
    assert os.path.basename(exe) == "sshd", "Port 2222 is not served by OpenSSH sshd"

    try:
        raw_cmdline = open("/proc/%d/cmdline" % pid, "rb").read().replace(b"\0", b" ").decode(errors="replace")
    except OSError as e:
        pytest.fail("Cannot inspect the running sshd process: %s" % e)

    match = re.search(r"(?:^|\s)-f\s+([^\s]+)", raw_cmdline)
    config_path = match.group(1) if match else "/etc/ssh/sshd_config"
    assert os.path.isfile(config_path), "Running sshd configuration was not found: %s" % config_path

    result = run([
        "/usr/sbin/sshd", "-T", "-f", config_path,
        "-C", "user=user,host=localhost,addr=127.0.0.1"
    ])
    assert result.returncode == 0, "Unable to evaluate running sshd configuration: %s" % result.stderr
    config = parse_effective_config(result.stdout)

    assert config.get("passwordauthentication") == ["no"]
    assert config.get("pubkeyauthentication") == ["yes"]
    assert set(config.get("kexalgorithms", [""])[0].split(",")) == REQUIRED_KEX
    assert set(config.get("ciphers", [""])[0].split(",")) == REQUIRED_CIPHERS
    assert set(config.get("macs", [""])[0].split(",")) == REQUIRED_MACS
    assert "127.0.0.1:2222" in config.get("listenaddress", []), "sshd is not configured for 127.0.0.1:2222"

    auth_specs = config.get("authorizedkeysfile", [""])[0].split()
    assert auth_specs, "No AuthorizedKeysFile is configured"
    home = "/home/user"
    auth_paths = []
    for spec in auth_specs:
        spec = spec.replace("%%", "%").replace("%h", home).replace("%u", "user")
        if not os.path.isabs(spec):
            spec = os.path.join(home, spec)
        auth_paths.append(os.path.normpath(spec))

    required_path = None
    for path in auth_paths:
        if not os.path.isfile(path):
            continue
        with open(path, "r", errors="replace") as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) >= 2 and parts[0] == REQUIRED_KEY_TYPE and parts[1] == REQUIRED_KEY_DATA:
                    required_path = path
                    break
        if required_path:
            break
    assert required_path, "The required audit public key is absent from sshd's authorized keys file"

    yield {"pid": pid, "config": config, "authorized_keys": required_path}


def parse_algorithm_scan(xml_data):
    root = ET.fromstring(xml_data)
    assert root.tag == "nmaprun", "Scan is not nmap XML"

    matching_ports = []
    for host in root.findall("host"):
        addresses = {node.get("addr") for node in host.findall("address")}
        for port in host.findall("./ports/port"):
            if port.get("portid") == "2222" and port.get("protocol") == "tcp":
                matching_ports.append((addresses, port))
    assert matching_ports, "The nmap XML does not contain TCP port 2222"

    selected = None
    for addresses, port in matching_ports:
        state = port.find("state")
        script = port.find("./script[@id='ssh2-enum-algos']")
        if state is not None and state.get("state") == "open" and script is not None:
            selected = (addresses, script)
            break
    assert selected is not None, "Port 2222 was not open with ssh2-enum-algos results"

    addresses, script = selected
    if addresses:
        assert "127.0.0.1" in addresses, "The scan does not target 127.0.0.1"

    tables = {}
    for table in script.findall("table"):
        tables[table.get("key")] = [elem.text for elem in table.findall("elem") if elem.text]

    kex = set(tables.get("kex_algorithms", []))
    # OpenSSH may advertise protocol markers in addition to configured KEX methods.
    kex = {x for x in kex if not x.startswith("kex-strict-") and not x.startswith("ext-info-")}
    assert kex == REQUIRED_KEX, "Unexpected SSH key-exchange algorithms: %r" % sorted(kex)
    assert set(tables.get("encryption_algorithms", [])) == REQUIRED_CIPHERS, \
        "Unexpected SSH ciphers: %r" % tables.get("encryption_algorithms", [])
    assert set(tables.get("mac_algorithms", [])) == REQUIRED_MACS, \
        "Unexpected SSH MAC algorithms: %r" % tables.get("mac_algorithms", [])


def test_ssh_scan_xml_and_live_algorithms(ssh_state):
    xml_path = "/home/user/ssh_scan.xml"
    assert os.path.exists(xml_path), "Nmap scan output does not exist"
    assert os.path.isfile(xml_path), "%s is not a file" % xml_path
    with open(xml_path, "rb") as f:
        parse_algorithm_scan(f.read())

    live = subprocess.run([
        "nmap", "-Pn", "-p", "2222", "--script", "ssh2-enum-algos",
        "-oX", "-", "127.0.0.1"
    ], capture_output=True, timeout=40)
    assert live.returncode == 0, "Live nmap algorithm scan failed: %s" % live.stderr.decode(errors="replace")
    parse_algorithm_scan(live.stdout)


def test_ssh_authentication_and_rejections(ssh_state):
    work = tempfile.mkdtemp(prefix="verifier-ssh-")
    key_path = os.path.join(work, "id_ed25519")
    generated = run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", key_path])
    assert generated.returncode == 0, generated.stderr

    auth_path = ssh_state["authorized_keys"]
    stat = os.stat(auth_path)
    with open(auth_path, "rb") as f:
        original = f.read()
    with open(key_path + ".pub", "rb") as f:
        temporary_public_key = f.read().strip()

    try:
        with open(auth_path, "ab") as f:
            if original and not original.endswith(b"\n"):
                f.write(b"\n")
            f.write(temporary_public_key + b"\n")
        os.chmod(auth_path, stat.st_mode & 0o7777)
        os.chown(auth_path, stat.st_uid, stat.st_gid)

        marker = "ssh_auth_" + secrets.token_hex(12)
        success = run([
            "ssh", "-i", key_path, "-p", "2222",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "BatchMode=yes",
            "user@127.0.0.1", "printf", marker
        ])
        assert success.returncode == 0, "SSH public-key connection failed: %s" % success.stderr
        assert success.stdout == marker

        password = run([
            "ssh", "-p", "2222",
            "-o", "PreferredAuthentications=password",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "BatchMode=yes",
            "user@127.0.0.1", "echo failure"
        ])
        assert password.returncode != 0, "SSH password authentication unexpectedly succeeded"
        assert "permission denied" in password.stderr.lower() or "connection closed" in password.stderr.lower()

        weak = run([
            "ssh", "-i", key_path, "-p", "2222", "-c", "aes128-cbc",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "BatchMode=yes",
            "user@127.0.0.1", "echo failure"
        ])
        assert weak.returncode != 0, "SSH accepted the weak aes128-cbc cipher"
        assert "no matching cipher found" in weak.stderr.lower() or "cipher" in weak.stderr.lower()
    finally:
        with open(auth_path, "wb") as f:
            f.write(original)
        os.chmod(auth_path, stat.st_mode & 0o7777)
        os.chown(auth_path, stat.st_uid, stat.st_gid)
        shutil.rmtree(work, ignore_errors=True)


def test_http_audit_service_with_legacy_sender():
    sender = "/app/legacy_audit_sender"
    assert os.path.isfile(sender) and os.access(sender, os.X_OK)
    log_path = "/home/user/audit_trail.log"
    before = b""
    if os.path.exists(log_path):
        with open(log_path, "rb") as f:
            before = f.read()

    messages = [
        "AUDIT_" + secrets.token_hex(7),
        "legacy-event-" + secrets.token_urlsafe(19),
        "X" + secrets.token_hex(31) + "_END"
    ]
    for message in messages:
        result = subprocess.run([sender, message], capture_output=True, text=True, timeout=15)
        assert result.returncode == 0, "Legacy sender failed: %s" % result.stderr

    deadline = time.time() + 5
    current = before
    while time.time() < deadline:
        if os.path.isfile(log_path):
            with open(log_path, "rb") as f:
                current = f.read()
            try:
                added_lines = current[len(before):].decode("utf-8").splitlines()
            except UnicodeDecodeError:
                added_lines = []
            if added_lines == messages:
                break
        time.sleep(0.1)

    assert current.startswith(before), "The audit service overwrote the existing audit trail"
    added = current[len(before):]
    assert added.decode("utf-8").splitlines() == messages, \
        "The service did not decode and append the sender's randomized payloads exactly"
    assert added.endswith(b"\n"), "Decoded audit entries must each be followed by a newline"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
