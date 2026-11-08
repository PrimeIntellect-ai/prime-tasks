#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import secrets
import signal
import ssl
import stat
import subprocess
import time
import urllib.error
import urllib.request

import pytest

HOME = "/home/user"
ARCHIVE = f"{HOME}/logs.sqsh"
MOUNT = f"{HOME}/mnt_logs"
ALERT = f"{HOME}/alerts/ssh_alerts.txt"
GENERATE = f"{HOME}/generate_alerts.sh"
SERVE = f"{HOME}/serve.sh"
CERT = f"{HOME}/cert.pem"
KEY = f"{HOME}/key.pem"


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, capture_output=True, **kwargs)


def mount_record(path=MOUNT):
    wanted = os.path.realpath(path)
    with open("/proc/self/mountinfo", encoding="utf-8") as f:
        for line in f:
            fields = line.rstrip("\n").split()
            separator = fields.index("-")
            mountpoint = fields[4].replace("\\040", " ")
            if os.path.realpath(mountpoint) == wanted:
                return fields[separator + 1], fields[separator + 2]
    return None


def wait_for_mount(expected=True, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if (mount_record() is not None) == expected:
            return
        time.sleep(0.1)
    raise AssertionError(f"mount state for {MOUNT} did not become {expected}")


def expected_alert_lines(root=MOUNT):
    result = []
    for directory, dirs, files in os.walk(root):
        dirs.sort()
        for name in sorted(files):
            if not name.endswith(".log"):
                continue
            with open(os.path.join(directory, name), encoding="utf-8") as f:
                for line in f:
                    line = line.rstrip("\n")
                    if "Failed publickey" in line:
                        result.append(line)
    return result


def read_alert_lines():
    with open(ALERT, encoding="utf-8") as f:
        return [line.rstrip("\n") for line in f]


def run_as_user(path):
    return run(["runuser", "-u", "user", "--", path], timeout=15)


def unmount_logs():
    result = run(["umount", MOUNT])
    if result.returncode != 0:
        for tool in ("fusermount3", "fusermount"):
            if subprocess.call(["sh", "-c", f"command -v {tool} >/dev/null 2>&1"]) == 0:
                result = run([tool, "-u", MOUNT])
                if result.returncode == 0:
                    break
    assert result.returncode == 0, f"Could not unmount test mount: {result.stderr}"
    wait_for_mount(False)


def mount_archive(path):
    result = run(["runuser", "-u", "user", "--", "squashfuse", path, MOUNT], timeout=15)
    assert result.returncode == 0, f"squashfuse failed: {result.stderr}"
    wait_for_mount(True)


def listening_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, encoding="ascii") as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].rsplit(":", 1)[1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass
    pids = set()
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
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
        except (FileNotFoundError, PermissionError):
            pass
    return pids


def fetch_alert():
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    req = urllib.request.Request("https://127.0.0.1:8443/ssh_alerts.txt")
    with urllib.request.urlopen(req, context=context, timeout=3) as response:
        assert response.status == 200, f"Expected HTTP status 200, got {response.status}."
        return response.read()


def test_mounted_logs():
    """Verify that logs.sqsh is genuinely mounted by squashfuse and readable."""
    record = mount_record()
    assert record is not None, f"{MOUNT} is not a mount point"
    filesystem, source = record
    assert "squashfuse" in filesystem.lower(), f"Expected squashfuse filesystem, got {filesystem}"
    assert os.path.basename(source) == "logs.sqsh" or os.path.realpath(source) == ARCHIVE, \
        f"Mounted source is not {ARCHIVE}: {source}"

    auth1_path = f"{MOUNT}/auth1.log"
    assert os.path.isfile(auth1_path), f"{auth1_path} does not exist. Archive might not be mounted."
    with open(auth1_path, "r", encoding="utf-8") as f:
        content = f.read()
    assert "Accepted password" in content, "Expected content not found in mounted log file."

    for name in ("auth1.log", "auth2.log"):
        extracted = subprocess.check_output(["unsquashfs", "-cat", ARCHIVE, name])
        with open(os.path.join(MOUNT, name), "rb") as f:
            assert f.read() == extracted, f"Mounted {name} differs from logs.sqsh"


def test_generate_alerts_script():
    """Verify that generate_alerts.sh exists and is executable."""
    assert os.path.isfile(GENERATE), f"{GENERATE} does not exist."
    assert os.stat(GENERATE).st_mode & stat.S_IXUSR, f"{GENERATE} is not executable."


def test_alerts_generated():
    """Verify the generated alert file exactly matches all qualifying archive lines."""
    assert os.path.isfile(ALERT), f"{ALERT} does not exist."
    lines = [line for line in read_alert_lines() if "Failed publickey" in line]
    assert len(lines) == 2, f"Expected exactly 2 lines containing 'Failed publickey', found {len(lines)}."
    content = "\n".join(lines)
    assert "Jan 14 10:05:22 server sshd[1235]: Failed publickey" in content
    assert "Jan 14 10:07:11 server sshd[1236]: Silent rejection: Failed publickey" in content
    assert collections.Counter(read_alert_lines()) == collections.Counter(expected_alert_lines())


def test_acl_permissions():
    """Verify that nobody has effective read-only access via ACL."""
    assert os.path.isfile(ALERT), f"{ALERT} does not exist."
    result = run(["getfacl", ALERT])
    assert result.returncode == 0, "Failed to run getfacl."
    acl_lines = result.stdout.splitlines()
    assert any(line.startswith("user:nobody:r") for line in acl_lines), \
        f"ACL for {ALERT} does not grant read permission to nobody."
    entry = next((line for line in acl_lines if line.startswith("user:nobody:")), None)
    assert entry is not None and entry.split("#", 1)[0].strip() == "user:nobody:r--", \
        f"nobody ACL must be read-only, got {entry}"
    access = run(["runuser", "-u", "nobody", "--", "sh", "-c", f"test -r '{ALERT}' && test ! -w '{ALERT}'"])
    assert access.returncode == 0, "nobody does not have effective read-only access"


def test_tls_certificates():
    """Verify a valid matching self-signed RSA-2048 certificate and key."""
    assert os.path.isfile(CERT), f"Certificate {CERT} does not exist."
    assert os.path.isfile(KEY), f"Private key {KEY} does not exist."

    cert_info = run(["openssl", "x509", "-in", CERT, "-noout", "-text"])
    assert cert_info.returncode == 0, f"Invalid certificate: {cert_info.stderr}"
    assert "Public-Key: (2048 bit)" in cert_info.stdout
    assert "Public Key Algorithm: rsaEncryption" in cert_info.stdout
    key_check = run(["openssl", "pkey", "-in", KEY, "-noout", "-check"])
    assert key_check.returncode == 0, f"Invalid or encrypted private key: {key_check.stderr}"
    verify = run(["openssl", "verify", "-CAfile", CERT, CERT])
    assert verify.returncode == 0, "Certificate is not self-signed or does not verify itself"

    cert_pub = subprocess.check_output(["openssl", "x509", "-in", CERT, "-pubkey", "-noout"])
    key_pub = subprocess.check_output(["openssl", "pkey", "-in", KEY, "-pubout"])
    assert cert_pub == key_pub, "Certificate and private key do not match"


def test_serve_script():
    """Verify that serve.sh exists and is executable."""
    assert os.path.isfile(SERVE), f"{SERVE} does not exist."
    assert os.stat(SERVE).st_mode & stat.S_IXUSR, f"{SERVE} is not executable."


def test_generation_script_on_unpredictable_archive():
    """Execute the script against an unpredictable squashfs to reject fixture output."""
    token = secrets.token_hex(16)
    temp_root = f"/tmp/verifier_logs_{token}"
    temp_archive = f"/tmp/verifier_{token}.sqsh"
    os.makedirs(os.path.join(temp_root, "nested"))
    wanted = [
        f"dynamic {token} Failed publickey first",
        f"prefix Failed publickey dynamic-{token}-second suffix",
        f"Failed publickey {token} third",
    ]
    with open(os.path.join(temp_root, "one.log"), "w", encoding="utf-8") as f:
        f.write("ignore this line\n" + wanted[0] + "\n")
    with open(os.path.join(temp_root, "nested", "two.log"), "w", encoding="utf-8") as f:
        f.write(wanted[1] + "\n" + wanted[2] + "\nnot a match\n")
    with open(os.path.join(temp_root, "ignored.txt"), "w", encoding="utf-8") as f:
        f.write(f"Failed publickey ignored-{token}\n")
    made = run(["mksquashfs", temp_root, temp_archive, "-noappend", "-quiet"])
    assert made.returncode == 0, f"Could not build behavioral-test archive: {made.stderr}"
    os.chmod(temp_archive, 0o644)

    try:
        unmount_logs()
        mount_archive(temp_archive)
        result = run_as_user(GENERATE)
        assert result.returncode == 0, f"generate_alerts.sh failed: {result.stderr}"
        assert os.path.isfile(ALERT), "generate_alerts.sh did not create ssh_alerts.txt"
        assert collections.Counter(read_alert_lines()) == collections.Counter(wanted), \
            "generate_alerts.sh did not extract exact matching lines from all and only .log files"
    finally:
        if mount_record() is not None:
            unmount_logs()
        mount_archive(ARCHIVE)
        restored = run_as_user(GENERATE)
        assert restored.returncode == 0, f"Could not regenerate alerts from original archive: {restored.stderr}"
        subprocess.run(["setfacl", "-m", "u:nobody:r--", ALERT], check=True)
        subprocess.run(["rm", "-rf", temp_root, temp_archive], check=False)

    assert collections.Counter(read_alert_lines()) == collections.Counter(expected_alert_lines())


def test_web_server_running_and_serve_script_works():
    """Restart serve.sh and verify its exact file and configured certificate over HTTPS."""
    for pid in listening_pids(8443):
        os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 5
    while listening_pids(8443) and time.time() < deadline:
        time.sleep(0.1)
    assert not listening_pids(8443), "Could not stop the previous listener on port 8443"

    subprocess.Popen(
        ["runuser", "-u", "user", "--", SERVE],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    deadline = time.time() + 10
    last_error = None
    body = None
    while time.time() < deadline:
        try:
            body = fetch_alert()
            break
        except Exception as exc:
            last_error = exc
            time.sleep(0.2)
    assert body is not None, f"Failed to connect to serve.sh HTTPS server: {last_error}"
    with open(ALERT, "rb") as f:
        expected = f.read()
    assert body == expected, "HTTPS endpoint is not serving the generated ssh_alerts.txt"
    assert b"Failed publickey" in body, "The served file does not contain the expected text."

    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    import socket
    with socket.create_connection(("127.0.0.1", 8443), timeout=3) as raw:
        with context.wrap_socket(raw, server_hostname="127.0.0.1") as tls:
            peer_der = tls.getpeercert(binary_form=True)
    with open(CERT, encoding="ascii") as f:
        local_der = ssl.PEM_cert_to_DER_cert(f.read())
    assert peer_der == local_der, "Port 8443 is not using /home/user/cert.pem"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
