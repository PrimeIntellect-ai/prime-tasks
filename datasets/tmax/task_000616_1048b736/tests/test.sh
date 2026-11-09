#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import ssl
import socket
import time
import subprocess
import pytest

SSH_DIR = '/home/user/.ssh'
PRIV_KEY = os.path.join(SSH_DIR, 'redteam_key')
PUB_KEY = os.path.join(SSH_DIR, 'redteam_key.pub')
PAYLOAD_FILE = '/home/user/payload.enc'
TLS_DIR = '/home/user/tls'
CERT_FILE = os.path.join(TLS_DIR, 'cert.pem')
KEY_FILE = os.path.join(TLS_DIR, 'key.pem')
SERVER_SCRIPT = '/home/user/server.py'


def run_checked(args, **kwargs):
    result = subprocess.run(
        args,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        **kwargs,
    )
    assert result.returncode == 0, (
        f"Command failed: {args}\n"
        f"stdout: {result.stdout.decode(errors='replace')}\n"
        f"stderr: {result.stderr.decode(errors='replace')}"
    )
    return result.stdout


def expected_payload():
    with open(PUB_KEY, 'r') as f:
        pub_key_content = f.read()
    command = f'echo "{pub_key_content}" >> /home/user/authorized_keys'.encode('utf-8')
    command += b'\x00' * ((-len(command)) % 4)
    key = b'\xDE\xAD\xBE\xEF'
    encrypted = bytearray()
    for offset in range(0, len(command), 4):
        xored = bytes(command[offset + i] ^ key[i] for i in range(4))
        encrypted.extend(xored[::-1])
    return bytes(encrypted)


def process_tree(root_pid):
    pids = {root_pid}
    changed = True
    while changed:
        changed = False
        for name in os.listdir('/proc'):
            if not name.isdigit():
                continue
            pid = int(name)
            if pid in pids:
                continue
            try:
                with open(f'/proc/{pid}/stat', 'r') as f:
                    stat = f.read()
                rest = stat[stat.rfind(')') + 2:].split()
                ppid = int(rest[1])
            except (OSError, ValueError, IndexError):
                continue
            if ppid in pids:
                pids.add(pid)
                changed = True
    return pids


def process_socket_inodes(root_pid):
    inodes = set()
    for pid in process_tree(root_pid):
        fd_dir = f'/proc/{pid}/fd'
        try:
            names = os.listdir(fd_dir)
        except OSError:
            continue
        for name in names:
            try:
                target = os.readlink(os.path.join(fd_dir, name))
            except OSError:
                continue
            match = re.fullmatch(r'socket:\[(\d+)\]', target)
            if match:
                inodes.add(match.group(1))
    return inodes


def listens_on_ipv4_any_8443(root_pid):
    owned = process_socket_inodes(root_pid)
    try:
        with open('/proc/net/tcp', 'r') as f:
            rows = f.readlines()[1:]
    except OSError:
        return False
    for row in rows:
        fields = row.split()
        if len(fields) < 10:
            continue
        local_address, state, inode = fields[1], fields[3], fields[9]
        address, port = local_address.split(':')
        if address == '00000000' and port.upper() == '20FB' and state == '0A' and inode in owned:
            return True
    return False


def test_ssh_keys_exist_and_are_unencrypted_ed25519_pair():
    assert os.path.isfile(PRIV_KEY), f"Private key not found at {PRIV_KEY}"
    assert os.path.isfile(PUB_KEY), f"Public key not found at {PUB_KEY}"
    assert os.path.getsize(PRIV_KEY) > 0, "Private SSH key is empty"
    assert os.path.getsize(PUB_KEY) > 0, "Public SSH key is empty"

    derived = run_checked(['ssh-keygen', '-y', '-P', '', '-f', PRIV_KEY], input=b'').decode().strip().split()
    with open(PUB_KEY, 'r') as f:
        supplied = f.read().strip().split()
    assert len(derived) >= 2 and len(supplied) >= 2, "Invalid SSH public key data"
    assert derived[:2] == supplied[:2], "SSH public key does not match the private key"
    assert supplied[0] == 'ssh-ed25519', "SSH key is not Ed25519"

    fingerprint = run_checked(['ssh-keygen', '-lf', PUB_KEY]).decode(errors='replace')
    assert re.search(r'\b256\b', fingerprint), f"Unexpected Ed25519 key size: {fingerprint}"
    assert '(ED25519)' in fingerprint.upper(), f"Public key is not reported as Ed25519: {fingerprint}"


def test_payload_exists_and_is_exactly_encrypted():
    assert os.path.isfile(PAYLOAD_FILE), f"Encrypted payload not found at {PAYLOAD_FILE}"
    with open(PAYLOAD_FILE, 'rb') as f:
        actual = f.read()
    expected = expected_payload()
    assert actual, "Encrypted payload is empty"
    assert len(actual) % 4 == 0, "Encrypted payload length is not a multiple of four"
    assert actual == expected, "payload.enc does not contain the required encrypted command"


def test_tls_certs_exist_and_have_required_properties():
    assert os.path.isfile(CERT_FILE), f"Certificate not found at {CERT_FILE}"
    assert os.path.isfile(KEY_FILE), f"Private key not found at {KEY_FILE}"
    assert os.path.getsize(CERT_FILE) > 0, "TLS certificate is empty"
    assert os.path.getsize(KEY_FILE) > 0, "TLS private key is empty"

    text = run_checked(['openssl', 'x509', '-in', CERT_FILE, '-noout', '-text']).decode(errors='replace')
    assert 'Public Key Algorithm: rsaEncryption' in text, "Certificate public key is not RSA"
    assert re.search(r'Public-Key:\s*\(2048 bit\)', text), "Certificate RSA key is not exactly 2048 bits"

    cert_pub = run_checked(['openssl', 'x509', '-in', CERT_FILE, '-pubkey', '-noout'])
    key_pub = run_checked(['openssl', 'pkey', '-in', KEY_FILE, '-pubout'], input=b'')
    assert cert_pub == key_pub, "TLS certificate and private key do not match"

    subject = run_checked(['openssl', 'x509', '-in', CERT_FILE, '-noout', '-subject']).decode().strip()
    issuer = run_checked(['openssl', 'x509', '-in', CERT_FILE, '-noout', '-issuer']).decode().strip()
    assert subject.removeprefix('subject=').strip() == issuer.removeprefix('issuer=').strip(), (
        "TLS certificate is not self-issued"
    )
    run_checked(['openssl', 'verify', '-check_ss_sig', '-CAfile', CERT_FILE, CERT_FILE])


def test_server_script_exists():
    assert os.path.isfile(SERVER_SCRIPT), f"Server script not found at {SERVER_SCRIPT}"
    assert os.path.getsize(SERVER_SCRIPT) > 0, "Server script is empty"


def test_payload_delivery_and_decryption():
    """Ensure the server binds IPv4-any, uses TLS, and reads payload.enc at connection time."""
    with open(PAYLOAD_FILE, 'rb') as f:
        original_payload = f.read()
    assert original_payload == expected_payload()

    # Replace the already-validated artifact only after the server is listening. A server that
    # recomputes the expected ciphertext instead of reading payload.enc will not return this data.
    marker = b'VERIFIER_RUNTIME_PAYLOAD_\x00\xff\x10\x80_not_generated'
    assert marker != original_payload

    proc = subprocess.Popen(
        ['python3', SERVER_SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    try:
        listening = False
        for _ in range(60):
            if proc.poll() is not None:
                stdout, stderr = proc.communicate()
                pytest.fail(
                    f"Server script exited prematurely. Return code: {proc.returncode}\n"
                    f"stdout: {stdout.decode(errors='replace')}\n"
                    f"stderr: {stderr.decode(errors='replace')}"
                )
            if listens_on_ipv4_any_8443(proc.pid):
                listening = True
                break
            time.sleep(0.1)
        assert listening, "Server did not listen specifically on IPv4 0.0.0.0:8443"

        with open(PAYLOAD_FILE, 'wb') as f:
            f.write(marker)
            f.flush()
            os.fsync(f.fileno())

        context = ssl.create_default_context(cafile=CERT_FILE)
        context.check_hostname = False
        context.verify_mode = ssl.CERT_REQUIRED

        raw_sock = socket.create_connection(('127.0.0.1', 8443), timeout=3)
        data = bytearray()
        with raw_sock:
            with context.wrap_socket(raw_sock, server_hostname='127.0.0.1') as ssock:
                cert = ssock.getpeercert()
                ssock.settimeout(3)
                while True:
                    chunk = ssock.recv(4096)
                    if not chunk:
                        break
                    data.extend(chunk)

        cn_found = any(
            attr[0] == 'commonName' and attr[1] == 'redteam'
            for rdn in cert.get('subject', ())
            for attr in rdn
        )
        assert cn_found, f"Certificate Common Name (CN) is not 'redteam': {cert.get('subject')}"
        assert bytes(data) == marker, (
            "Server did not send the exact current contents of /home/user/payload.enc"
        )
    finally:
        with open(PAYLOAD_FILE, 'wb') as f:
            f.write(original_payload)
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
