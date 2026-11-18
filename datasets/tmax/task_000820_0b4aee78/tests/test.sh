#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import re
import secrets
import socket
import subprocess
import tempfile
import time


def run(*args, input_data=None):
    return subprocess.run(
        args,
        input=input_data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    ).stdout


def test_certificates_generated():
    """Verify a valid self-signed RSA-2048 certificate and matching key."""
    cert_path = "/home/user/vuln_app/certs/server.crt"
    key_path = "/home/user/vuln_app/certs/server.key"

    assert os.path.isfile(cert_path), f"Certificate file is missing: {cert_path}"
    assert os.path.isfile(key_path), f"Private key file is missing: {key_path}"

    with open(cert_path, "r") as f:
        cert_content = f.read()
    assert "-----BEGIN CERTIFICATE-----" in cert_content, f"File {cert_path} does not appear to be a valid PEM certificate."

    with open(key_path, "r") as f:
        key_content = f.read()
    assert "-----BEGIN PRIVATE KEY-----" in key_content or "-----BEGIN RSA PRIVATE KEY-----" in key_content, \
        f"File {key_path} does not appear to be a valid PEM private key."

    # These commands parse the files, validate the private key, and verify the
    # certificate's self-signature rather than trusting PEM header text.
    run("openssl", "x509", "-in", cert_path, "-noout")
    run("openssl", "pkey", "-in", key_path, "-check", "-noout")
    run("openssl", "verify", "-CAfile", cert_path, cert_path)

    subject = run("openssl", "x509", "-in", cert_path, "-noout", "-subject", "-nameopt", "RFC2253").decode().strip()
    issuer = run("openssl", "x509", "-in", cert_path, "-noout", "-issuer", "-nameopt", "RFC2253").decode().strip()
    assert subject.removeprefix("subject=") == issuer.removeprefix("issuer="), "Certificate is not self-issued."

    cert_pub = run("openssl", "x509", "-in", cert_path, "-pubkey", "-noout")
    key_pub = run("openssl", "pkey", "-in", key_path, "-pubout")
    cert_der = run("openssl", "pkey", "-pubin", "-outform", "DER", input_data=cert_pub)
    key_der = run("openssl", "pkey", "-pubin", "-outform", "DER", input_data=key_pub)
    assert cert_der == key_der, "Certificate and private key do not match."

    key_text = run("openssl", "pkey", "-in", key_path, "-text", "-noout").decode(errors="replace")
    assert re.search(r"(?:Private-Key|Public-Key): \(2048 bit", key_text), "The private key is not RSA-2048."
    assert "modulus:" in key_text.lower(), "The private key is not an RSA key."

    dates = run("openssl", "x509", "-in", cert_path, "-noout", "-dates").decode().splitlines()
    values = dict(line.split("=", 1) for line in dates)
    fmt = "%b %d %H:%M:%S %Y GMT"
    not_before = datetime.datetime.strptime(values["notBefore"], fmt).replace(tzinfo=datetime.timezone.utc)
    not_after = datetime.datetime.strptime(values["notAfter"], fmt).replace(tzinfo=datetime.timezone.utc)
    assert not_after - not_before == datetime.timedelta(days=365), "Certificate validity is not exactly 365 days."
    now = datetime.datetime.now(datetime.timezone.utc)
    assert not_before <= now <= not_after, "Certificate is not currently valid."


def test_hacked_txt_exists_and_content():
    """Verify that the path traversal exploit created hacked.txt with the correct content."""
    hacked_file = "/home/user/vuln_app/hacked.txt"
    assert os.path.isfile(hacked_file), f"The exploit file was not found at the expected location: {hacked_file}"
    with open(hacked_file, "r") as f:
        content = f.read().strip()
    assert content == "EXPLOIT_SUCCESS", f"The content of {hacked_file} is incorrect. Expected 'EXPLOIT_SUCCESS', got '{content}'."


def test_timestamp_extracted_and_correlated():
    """Verify timestamp format and correlate it to the actual traversal upload log entry."""
    timestamp_file = "/home/user/vuln_app/timestamp.txt"
    log_file = "/home/user/vuln_app/access.log"
    hacked_file = "/home/user/vuln_app/hacked.txt"

    assert os.path.isfile(timestamp_file), f"The timestamp file is missing: {timestamp_file}"
    assert os.path.isfile(log_file), f"The application log is missing: {log_file}"

    with open(timestamp_file, "r") as f:
        content = f.read().strip()

    pattern = re.compile(r"^[0-9]{2}/[a-zA-Z]{3}/[0-9]{4}:[0-9]{2}:[0-9]{2}:[0-9]{2}$")
    assert pattern.match(content), f"The extracted timestamp '{content}' does not match the expected format (e.g., DD/Mon/YYYY:HH:MM:SS)."

    matched = False
    line_re = re.compile(r"^\[([^]]+)\] UPLOAD (.*) SUCCESS$")
    with open(log_file, "r") as f:
        for raw_line in f:
            match = line_re.match(raw_line.rstrip("\n"))
            if not match:
                continue
            timestamp, filename = match.groups()
            target = os.path.abspath(os.path.join("/home/user/vuln_app/uploads", filename))
            if timestamp == content and "../" in filename and target == hacked_file:
                matched = True
                break
    assert matched, "timestamp.txt does not identify a logged path-traversal upload targeting hacked.txt."


def test_privesc_user_identified():
    """Verify that the correct user was identified for the privilege escalation vector."""
    privesc_file = "/home/user/vuln_app/privesc_user.txt"
    assert os.path.isfile(privesc_file), f"The privesc user file is missing: {privesc_file}"
    with open(privesc_file, "r") as f:
        content = f.read().strip()
    assert content == "cicd_runner", f"The identified user is incorrect. Expected 'cicd_runner', got '{content}'."

    discovered = []
    config_dir = "/home/user/audit_configs/sudoers.d"
    rule = re.compile(r"^\s*([A-Za-z0-9_.-]+)\s+.*NOPASSWD:\s*/usr/bin/find(?:\s|$)")
    for name in os.listdir(config_dir):
        path = os.path.join(config_dir, name)
        if not os.path.isfile(path):
            continue
        with open(path, "r") as f:
            for line in f:
                match = rule.search(line)
                if match:
                    discovered.append(match.group(1))
    assert discovered == [content], "privesc_user.txt does not match the sudoers backup containing the NOPASSWD /usr/bin/find rule."


def test_https_application_and_traversal_endpoint_work():
    """Actually start the submitted setup and exercise the HTTPS traversal endpoint."""
    app_path = "/home/user/vuln_app/app.py"
    assert os.path.isfile(app_path), f"Application is missing: {app_path}"

    # Phase 3 requires the agent's background server to have been terminated.
    with socket.socket() as sock:
        sock.settimeout(0.3)
        assert sock.connect_ex(("127.0.0.1", 8443)) != 0, "The background Flask process was not terminated."

    token = secrets.token_hex(16)
    probe_name = f"verifier_probe_{token}.txt"
    traversal_name = f"../{probe_name}"
    probe_path = os.path.join("/home/user/vuln_app", probe_name)
    payload = f"VERIFIER_{token}".encode()
    log_path = "/home/user/vuln_app/access.log"
    old_log_size = os.path.getsize(log_path) if os.path.exists(log_path) else 0

    fd, upload_path = tempfile.mkstemp()
    os.write(fd, payload)
    os.close(fd)
    output = tempfile.TemporaryFile()
    process = subprocess.Popen(["python3", app_path], stdout=output, stderr=output)
    try:
        deadline = time.time() + 15
        while time.time() < deadline:
            if process.poll() is not None:
                output.seek(0)
                raise AssertionError("Flask application failed to start:\n" + output.read().decode(errors="replace"))
            with socket.socket() as sock:
                sock.settimeout(0.2)
                if sock.connect_ex(("127.0.0.1", 8443)) == 0:
                    break
            time.sleep(0.2)
        else:
            raise AssertionError("Flask application did not listen on HTTPS port 8443.")

        result = subprocess.run(
            ["curl", "--silent", "--show-error", "--insecure", "--output", "/dev/null", "--write-out", "%{http_code}",
             "-F", f"file=@{upload_path};filename={traversal_name}", "https://127.0.0.1:8443/upload"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert result.returncode == 0, result.stderr.decode(errors="replace")
        assert result.stdout.decode() == "200", f"Upload endpoint returned HTTP {result.stdout.decode()}."
        assert os.path.isfile(probe_path), "Traversal upload did not create the requested file outside uploads/."
        with open(probe_path, "rb") as f:
            assert f.read() == payload, "Traversal upload did not preserve the uploaded content."

        with open(log_path, "r") as f:
            f.seek(old_log_size)
            new_log = f.read()
        assert re.search(rf"^\[[^]]+\] UPLOAD {re.escape(traversal_name)} SUCCESS$", new_log, re.MULTILINE), \
            "The exercised traversal upload was not logged by the application."
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        output.close()
        for path in (upload_path, probe_path):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
