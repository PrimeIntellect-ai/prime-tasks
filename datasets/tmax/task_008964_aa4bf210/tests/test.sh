#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import hashlib
import http.client
import os
import re
import shlex
import ssl
import subprocess
import tarfile
import tempfile

import pytest

CERT = "/home/user/service/certs/cert.pem"
KEY = "/home/user/service/certs/key.pem"
SOURCE = "/home/user/service/backup_daemon.go"
BINARY = "/home/user/service/backup_daemon"
ARCHIVE = "/home/user/backup_verified.tar.gz"
ORIGINAL = "/home/user/important_data"
RESTORED = "/home/user/restored_data"


def run(*args, input=None):
    return subprocess.run(args, input=input, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, check=True).stdout


def test_certs_exist():
    assert os.path.isfile(CERT), f"Certificate file {CERT} is missing."
    assert os.path.isfile(KEY), f"Private key file {KEY} is missing."
    assert os.path.getsize(CERT) > 0
    assert os.path.getsize(KEY) > 0


def test_certificate_and_key_are_required_credentials():
    cert_text = run("openssl", "x509", "-in", CERT, "-noout", "-text").decode()
    assert re.search(r"Public-Key:\s*\(2048 bit\)", cert_text), "Certificate is not RSA-2048."

    key_text = run("openssl", "pkey", "-in", KEY, "-noout", "-text").decode()
    assert re.search(r"Private-Key:\s*\(2048 bit", key_text), "Private key is not RSA-2048."

    cert_pub_pem = run("openssl", "x509", "-in", CERT, "-pubkey", "-noout")
    cert_pub_der = run("openssl", "pkey", "-pubin", "-outform", "DER", input=cert_pub_pem)
    key_pub_pem = run("openssl", "pkey", "-in", KEY, "-pubout")
    key_pub_der = run("openssl", "pkey", "-pubin", "-outform", "DER", input=key_pub_pem)
    assert cert_pub_der == key_pub_der, "Certificate and private key do not match."

    subject = run("openssl", "x509", "-in", CERT, "-noout", "-subject").decode().split("=", 1)[1].strip()
    issuer = run("openssl", "x509", "-in", CERT, "-noout", "-issuer").decode().split("=", 1)[1].strip()
    assert subject == issuer, "Certificate is not self-issued."
    run("openssl", "verify", "-CAfile", CERT, CERT)

    dates = run("openssl", "x509", "-in", CERT, "-noout", "-dates").decode().splitlines()
    values = dict(line.split("=", 1) for line in dates)
    fmt = "%b %d %H:%M:%S %Y %Z"
    not_before = datetime.datetime.strptime(values["notBefore"], fmt).replace(tzinfo=datetime.timezone.utc)
    not_after = datetime.datetime.strptime(values["notAfter"], fmt).replace(tzinfo=datetime.timezone.utc)
    assert not_after - not_before == datetime.timedelta(days=365), "Certificate validity is not 365 days."
    now = datetime.datetime.now(datetime.timezone.utc)
    assert not_before <= now <= not_after, "Certificate is not currently valid."


def test_go_code_fixed():
    assert os.path.isfile(SOURCE), f"File {SOURCE} does not exist."
    with open(SOURCE, "r") as f:
        content = f.read()
    assert "ListenAndServeTLS" in content, "The Go file does not use ListenAndServeTLS as required for HTTPS."
    assert '":8443"' in content, "The Go file is not configured to listen on port 8443."
    assert "cert.pem" in content and "key.pem" in content, "The TLS certificate paths are not configured."

    with tempfile.TemporaryDirectory() as td:
        subprocess.run(["go", "build", "-o", os.path.join(td, "backup_daemon"), SOURCE],
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)


def test_binary_exists_and_is_running():
    assert os.path.isfile(BINARY), f"Compiled binary {BINARY} is missing."
    assert os.access(BINARY, os.X_OK), f"Compiled binary {BINARY} is not executable."
    version = subprocess.run(["go", "version", BINARY], stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, text=True)
    assert version.returncode == 0 and "go version" in version.stdout, "backup_daemon is not a compiled Go binary."

    wanted = os.path.realpath(BINARY)
    running = False
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            target = os.path.realpath(f"/proc/{name}/exe")
        except OSError:
            continue
        if target == wanted:
            running = True
            break
    assert running, "The backup_daemon binary is not running."


def test_tunnel_cmd():
    cmd_file = "/home/user/tunnel_cmd.sh"
    assert os.path.isfile(cmd_file), f"File {cmd_file} does not exist."
    with open(cmd_file, "r") as f:
        content = f.read().strip()

    assert content.startswith("ssh") or " ssh " in content, "The command does not appear to be an SSH command."
    assert "-L" in content, "The SSH command is missing the -L flag for local port forwarding."
    mapping_pattern = r"9443:(localhost|127\.0\.0\.1):8443"
    assert re.search(mapping_pattern, content), "The SSH command does not correctly forward local port 9443 to localhost:8443."
    assert "user@localhost" in content, "The SSH command does not specify the correct user@localhost destination."

    tokens = shlex.split(content)
    assert tokens and tokens[0] == "ssh", "The file must contain one SSH command."
    assert tokens[-1] == "user@localhost", "The SSH destination must be user@localhost with no remote command."
    assert not re.search(r"[;&|`<>\n]", content), "The file contains additional shell commands or redirections."

    flags = set()
    mappings = []
    i = 1
    while i < len(tokens) - 1:
        token = tokens[i]
        if token == "-L":
            i += 1
            assert i < len(tokens) - 1, "-L is missing its forwarding specification."
            mappings.append(tokens[i])
        elif token.startswith("-L") and len(token) > 2:
            mappings.append(token[2:])
        elif token.startswith("-") and len(token) > 1 and all(c in "fN" for c in token[1:]):
            flags.update(token[1:])
        else:
            pytest.fail(f"Unexpected SSH argument or remote command: {token}")
        i += 1
    assert "f" in flags, "The SSH command must use -f to run in the background."
    assert "N" in flags, "The SSH command must use -N to execute no remote command."
    assert mappings == ["9443:localhost:8443"], "The SSH forwarding must be exactly 9443:localhost:8443."


def tree_snapshot(root):
    result = {}
    for current, dirs, files in os.walk(root, followlinks=False):
        dirs.sort()
        files.sort()
        rel_current = os.path.relpath(current, root)
        for name in dirs:
            path = os.path.join(current, name)
            rel = name if rel_current == "." else os.path.join(rel_current, name)
            assert not os.path.islink(path), f"Unexpected symlink in data tree: {rel}"
            result[rel.replace(os.sep, "/")] = ("dir", None)
        for name in files:
            path = os.path.join(current, name)
            rel = name if rel_current == "." else os.path.join(rel_current, name)
            assert not os.path.islink(path), f"Unexpected symlink in data tree: {rel}"
            with open(path, "rb") as f:
                result[rel.replace(os.sep, "/")] = ("file", f.read())
    return result


def archive_snapshot(path=None, data=None):
    result = {}
    source = path
    temp = None
    if data is not None:
        temp = tempfile.NamedTemporaryFile(delete=False)
        temp.write(data)
        temp.close()
        source = temp.name
    try:
        with tarfile.open(source, "r:gz") as tf:
            for member in tf.getmembers():
                name = member.name.rstrip("/")
                assert name and not name.startswith("/") and ".." not in name.split("/"), "Archive has an unsafe path."
                assert name not in result, "Archive contains duplicate paths."
                if member.isdir():
                    result[name] = ("dir", None)
                elif member.isfile():
                    extracted = tf.extractfile(member)
                    assert extracted is not None
                    result[name] = ("file", extracted.read())
                else:
                    pytest.fail(f"Archive contains unsupported entry type: {name}")
        return result
    finally:
        if temp is not None:
            os.unlink(temp.name)


def fetch_https_backup():
    context = ssl._create_unverified_context()
    conn = http.client.HTTPSConnection("localhost", 8443, context=context, timeout=10)
    conn.connect()
    served_der = conn.sock.getpeercert(binary_form=True)
    expected_pem = open(CERT, "r").read()
    expected_der = ssl.PEM_cert_to_DER_cert(expected_pem)
    assert served_der == expected_der, "The HTTPS service is not using cert.pem."
    conn.request("GET", "/backup")
    response = conn.getresponse()
    body = response.read()
    conn.close()
    assert response.status == 200, f"HTTPS backup endpoint returned status {response.status}."
    assert body, "HTTPS backup endpoint returned an empty response."
    return body


def test_https_archive_and_restoration():
    expected = tree_snapshot(ORIGINAL)
    served = fetch_https_backup()
    assert archive_snapshot(data=served) == expected, "The live HTTPS service did not serve the important_data archive."

    assert os.path.isfile(ARCHIVE), f"The downloaded backup archive {ARCHIVE} is missing."
    assert os.path.getsize(ARCHIVE) > 0, "The downloaded backup archive is empty."
    assert archive_snapshot(path=ARCHIVE) == expected, "backup_verified.tar.gz does not contain the original data."
    assert tree_snapshot(RESTORED) == expected, "The restored data tree does not exactly match important_data."


def test_restored_data():
    orig_secrets = "/home/user/important_data/secrets.env"
    restored_secrets = "/home/user/restored_data/secrets.env"
    orig_customers = "/home/user/important_data/customers.csv"
    restored_customers = "/home/user/restored_data/customers.csv"
    assert os.path.isfile(restored_secrets), f"Restored file {restored_secrets} is missing."
    assert os.path.isfile(restored_customers), f"Restored file {restored_customers} is missing."
    with open(orig_secrets, "r") as f:
        expected_secrets = f.read()
    with open(restored_secrets, "r") as f:
        actual_secrets = f.read()
    assert actual_secrets == expected_secrets, "The restored secrets.env does not match the original."
    with open(orig_customers, "r") as f:
        expected_customers = f.read()
    with open(restored_customers, "r") as f:
        actual_customers = f.read()
    assert actual_customers == expected_customers, "The restored customers.csv does not match the original."


def test_backup_archive_exists():
    assert os.path.isfile(ARCHIVE), f"The downloaded backup archive {ARCHIVE} is missing."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
