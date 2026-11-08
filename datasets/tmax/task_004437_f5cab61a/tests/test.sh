#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import datetime
import io
import os
import pwd
import re
import secrets
import subprocess
import sys
import time

import paramiko
import pytest
from cryptography import x509
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.x509.oid import NameOID

HOME = "/home/user"
CONFIG = HOME + "/sshd_config"
RUNNER = HOME + "/secure_runner.py"
AUTHORIZED_KEYS = HOME + "/.ssh/authorized_keys"
PAYLOAD = HOME + "/payload.b64"
SERVER_CERT = HOME + "/server.crt"
CA_CERT = HOME + "/ca.crt"
LOOT = HOME + "/loot.txt"


def payload_key():
    encoded = b"".join(open(PAYLOAD, "rb").read().split())
    private_data = base64.b64decode(encoded, validate=True)
    key = paramiko.Ed25519Key.from_private_key(
        io.StringIO(private_data.decode("ascii"))
    )
    return encoded, private_data, key


def test_sshd_config_exists_and_configured():
    assert os.path.isfile(CONFIG), f"{CONFIG} does not exist"
    with open(CONFIG, "r") as f:
        content = f.read()

    assert re.search(r'(?i)^\s*Port\s+2222\b', content, re.MULTILINE), "Port 2222 not configured in sshd_config"
    assert re.search(r'(?i)^\s*PasswordAuthentication\s+no\b', content, re.MULTILINE), "PasswordAuthentication no not configured in sshd_config"
    assert re.search(r'(?i)^\s*PubkeyAuthentication\s+yes\b', content, re.MULTILINE), "PubkeyAuthentication yes not configured in sshd_config"
    assert re.search(r'(?i)^\s*HostKey\s+/home/user/ssh_host_ed25519_key\b', content, re.MULTILINE), "HostKey /home/user/ssh_host_ed25519_key not configured in sshd_config"

    result = subprocess.run(
        ["/usr/sbin/sshd", "-T", "-C", "user=user,host=127.0.0.1,addr=127.0.0.1", "-f", CONFIG],
        text=True, capture_output=True
    )
    assert result.returncode == 0, f"sshd rejects the configuration: {result.stderr}"
    effective = result.stdout.lower().splitlines()
    assert "port 2222" in effective
    assert "passwordauthentication no" in effective
    assert "pubkeyauthentication yes" in effective
    assert "hostkey /home/user/ssh_host_ed25519_key" in effective

    host_key = HOME + "/ssh_host_ed25519_key"
    assert os.path.isfile(host_key), "Configured host private key does not exist"
    checked = subprocess.run(["ssh-keygen", "-y", "-f", host_key], capture_output=True, text=True)
    assert checked.returncode == 0 and checked.stdout.startswith("ssh-ed25519 "), "Host key is not a valid Ed25519 private key"


def test_sshd_running():
    try:
        output = subprocess.check_output(["ps", "aux"], text=True)
    except subprocess.CalledProcessError:
        pytest.fail("Failed to run ps aux")
    assert CONFIG in output, "sshd is not running with -f /home/user/sshd_config"

    real_daemon = False
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            exe = os.path.realpath(f"/proc/{name}/exe")
            cmd = open(f"/proc/{name}/cmdline", "rb").read().replace(b"\0", b" ").decode("utf-8", "replace").strip()
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if exe == "/usr/sbin/sshd" and cmd.startswith("/usr/sbin/sshd") and re.search(r"(?:^|\s)-f\s+/home/user/sshd_config(?:\s|$)", cmd):
            real_daemon = True
            break
    assert real_daemon, "No real /usr/sbin/sshd process is using the requested configuration"


def test_loot_txt_exists_and_correct():
    assert os.path.isfile(LOOT), f"{LOOT} does not exist"
    with open(LOOT, "r") as f:
        content = f.read()
    assert content.strip() == "ACCESS_GRANTED", f"{LOOT} does not contain the expected text 'ACCESS_GRANTED'"


def test_secure_runner_exists():
    assert os.path.isfile(RUNNER), f"{RUNNER} does not exist"


def test_authorized_keys_exists_and_matches_payload():
    assert os.path.isfile(AUTHORIZED_KEYS), f"{AUTHORIZED_KEYS} does not exist"
    _, _, key = payload_key()
    expected_type = key.get_name()
    expected_blob = key.get_base64()
    found = False
    with open(AUTHORIZED_KEYS, "r") as f:
        for line in f:
            fields = line.strip().split()
            for i in range(len(fields) - 1):
                if fields[i] == expected_type and fields[i + 1] == expected_blob:
                    found = True
    assert found, "authorized_keys does not contain the public key corresponding to payload.b64"


def test_server_certificate_is_signed_by_ca():
    ca = x509.load_pem_x509_certificate(open(CA_CERT, "rb").read())
    server = x509.load_pem_x509_certificate(open(SERVER_CERT, "rb").read())
    assert server.issuer == ca.subject
    ca.public_key().verify(
        server.signature,
        server.tbs_certificate_bytes,
        padding.PKCS1v15(),
        server.signature_hash_algorithm,
    )


def run_as_user_and_scan(argv, forbidden, timeout=15):
    account = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    proc = subprocess.Popen(
        argv, cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        preexec_fn=demote
    )
    leaked = False
    deadline = time.time() + timeout
    while proc.poll() is None and time.time() < deadline:
        for pid in os.listdir("/proc"):
            if not pid.isdigit():
                continue
            try:
                cmdline = open(f"/proc/{pid}/cmdline", "rb").read()
            except (FileNotFoundError, PermissionError, ProcessLookupError):
                continue
            if any(secret and secret in cmdline for secret in forbidden):
                leaked = True
        time.sleep(0.005)
    if proc.poll() is None:
        proc.kill()
        proc.wait()
        pytest.fail("secure_runner.py timed out")
    stdout, stderr = proc.communicate()
    return proc.returncode, stdout, stderr, leaked


def test_secure_runner_rejects_bad_certificate_and_really_uses_ssh():
    encoded, private_data, key = payload_key()
    auth_backup = open(AUTHORIZED_KEYS, "rb").read()
    auth_stat = os.stat(AUTHORIZED_KEYS)
    cert_backup = open(SERVER_CERT, "rb").read()

    nonce = secrets.token_hex(16)
    marker = f"/tmp/secure_runner_ssh_marker_{nonce}"
    wrapper = f"/tmp/secure_runner_force_{nonce}.sh"
    wrapper_body = f'''#!/bin/sh
if [ "$SSH_ORIGINAL_COMMAND" != 'echo "ACCESS_GRANTED" > /home/user/loot.txt' ]; then
    exit 42
fi
printf '%s\\n' '{nonce}' > '{marker}'
sleep 1
exec /bin/sh -c "$SSH_ORIGINAL_COMMAND"
'''

    now = datetime.datetime.now(datetime.timezone.utc)
    foreign_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    foreign_name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Foreign Test CA")])
    foreign_cert = (
        x509.CertificateBuilder()
        .subject_name(foreign_name)
        .issuer_name(foreign_name)
        .public_key(foreign_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(days=1))
        .not_valid_after(now + datetime.timedelta(days=1))
        .sign(foreign_key, hashes.SHA256())
    )

    try:
        with open(wrapper, "w") as f:
            f.write(wrapper_body)
        os.chown(wrapper, 0, 0)
        os.chmod(wrapper, 0o755)

        forced_line = (
            f'command="{wrapper}",no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty '
            f'{key.get_name()} {key.get_base64()} verifier-forced-key\n'
        )
        with open(AUTHORIZED_KEYS, "w") as f:
            f.write(forced_line)
        os.chown(AUTHORIZED_KEYS, pwd.getpwnam("user").pw_uid, pwd.getpwnam("user").pw_gid)
        os.chmod(AUTHORIZED_KEYS, 0o600)

        for path in (LOOT, marker):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass

        with open(SERVER_CERT, "wb") as f:
            f.write(foreign_cert.public_bytes(serialization.Encoding.PEM))
        bad_rc, bad_out, bad_err, _ = run_as_user_and_scan([sys.executable, RUNNER], [], timeout=10)
        assert bad_rc == 1, f"Runner must exit 1 for a certificate not signed by ca.crt; got {bad_rc}: {bad_err.decode(errors='replace')}"
        assert not os.path.exists(marker), "Runner connected over SSH despite an invalid server certificate"
        assert not os.path.exists(LOOT), "Runner created loot despite an invalid server certificate"

        with open(SERVER_CERT, "wb") as f:
            f.write(cert_backup)
        good_rc, good_out, good_err, leaked = run_as_user_and_scan(
            [sys.executable, RUNNER], [encoded, private_data], timeout=15
        )
        assert good_rc == 0, f"Runner failed with valid inputs: {good_err.decode(errors='replace')}"
        assert not leaked, "The encoded or decoded SSH private key appeared in a process command line"
        assert os.path.isfile(marker) and open(marker).read().strip() == nonce, "Runner did not authenticate and execute the exact requested command through SSH"
        assert os.path.isfile(LOOT) and open(LOOT).read().strip() == "ACCESS_GRANTED"
    finally:
        with open(SERVER_CERT, "wb") as f:
            f.write(cert_backup)
        with open(AUTHORIZED_KEYS, "wb") as f:
            f.write(auth_backup)
        os.chown(AUTHORIZED_KEYS, auth_stat.st_uid, auth_stat.st_gid)
        os.chmod(AUTHORIZED_KEYS, auth_stat.st_mode & 0o7777)
        for path in (wrapper, marker):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass


from cryptography.hazmat.primitives import serialization
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
