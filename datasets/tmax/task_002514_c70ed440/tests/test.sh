#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shlex
import stat
import subprocess
import tempfile


def run(command, **kwargs):
    return subprocess.run(command, capture_output=True, text=True, **kwargs)


def test_audit_runner_modified():
    path = "/home/user/audit_runner.py"
    assert os.path.exists(path), f"File {path} is missing."
    with open(path, "r") as f:
        content = f.read()
    assert '["/home/user/scanner.sh", args.token]' not in content, "The audit_runner.py script still passes the token via CLI arguments."


def test_audit_log_redacted():
    path = "/home/user/audit_log.txt"
    assert os.path.exists(path), f"File {path} is missing."
    with open(path, "r") as f:
        content = f.read()
    assert "[REDACTED]" in content, "The string [REDACTED] was not found in the audit log."
    assert "super_secret_audit_token_991" not in content, "The sensitive token was found in the audit log."


def test_audit_runner_behavior():
    runner = "/home/user/audit_runner.py"
    scanner = "/home/user/scanner.sh"
    token = "dynamic_audit_token_" + os.urandom(16).hex()

    with open(scanner, "rb") as f:
        original_scanner = f.read()
    original_mode = stat.S_IMODE(os.stat(scanner).st_mode)

    with tempfile.TemporaryDirectory() as td:
        argv_file = os.path.join(td, "argv")
        env_file = os.path.join(td, "env")
        probe = f'''#!/bin/sh
printf '%s\\n' "$#" > {shlex.quote(argv_file)}
printf '%s\\n' "$@" >> {shlex.quote(argv_file)}
printf '%s' "$SCANNER_TOKEN" > {shlex.quote(env_file)}
printf 'Scanning initiated with token: %s\\n' "$SCANNER_TOKEN"
'''
        try:
            with open(scanner, "w") as f:
                f.write(probe)
            os.chmod(scanner, 0o755)

            clean_env = os.environ.copy()
            clean_env.pop("SCANNER_TOKEN", None)
            result = subprocess.run(
                ["python3", runner, "--token", token],
                capture_output=True,
                text=True,
                env=clean_env,
                timeout=15,
            )
        finally:
            with open(scanner, "wb") as f:
                f.write(original_scanner)
            os.chmod(scanner, original_mode)

        assert result.returncode == 0, f"audit_runner.py failed: {result.stderr}"
        assert os.path.exists(argv_file), "audit_runner.py did not execute /home/user/scanner.sh."
        assert os.path.exists(env_file), "The scanner probe did not receive an environment."

        with open(argv_file) as f:
            argv_data = f.read().splitlines()
        assert argv_data == ["0"], f"The scanner received command-line arguments: {argv_data!r}"

        with open(env_file) as f:
            scanner_token = f.read()
        assert scanner_token == token, "SCANNER_TOKEN was not passed correctly to scanner.sh."

        with open("/home/user/audit_log.txt") as f:
            log = f.read()
        assert token not in log, "The dynamic sensitive token was found in the audit log."
        assert log == "Scanning initiated with token: [REDACTED]\n", "Scanner output was not correctly written and redacted."


def test_payload_decoded():
    path = "/home/user/payload.txt"
    assert os.path.exists(path), f"File {path} is missing."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "CRITICAL_VULN_FOUND:CVE-2023-12345", f"Content of {path} is incorrect."


def test_ssh_key_exists_and_perms():
    ssh_dir = "/home/user/.ssh"
    key_path = "/home/user/.ssh/audit_key"
    pub_path = key_path + ".pub"
    assert os.path.isdir(ssh_dir), f"SSH directory {ssh_dir} is missing."
    assert stat.S_IMODE(os.stat(ssh_dir).st_mode) == 0o700, f"Permissions for {ssh_dir} must be 0o700."

    assert os.path.exists(key_path), f"SSH key {key_path} is missing."
    with open(key_path, "r") as f:
        content = f.read()
    assert "OPENSSH PRIVATE KEY" in content, f"File {key_path} does not appear to be a valid OpenSSH private key."

    st = os.stat(key_path)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o600, f"Permissions for {key_path} are {oct(perms)}, expected 0o600."

    derived = run(["ssh-keygen", "-y", "-f", key_path], input="", timeout=10)
    assert derived.returncode == 0, "audit_key is not a valid unencrypted SSH private key."
    fingerprint = run(["ssh-keygen", "-lf", key_path], input="", timeout=10)
    assert fingerprint.returncode == 0, "Unable to inspect the SSH private key."
    assert "ED25519" in fingerprint.stdout.upper(), "audit_key is not an Ed25519 key."

    assert os.path.isfile(pub_path), f"SSH public key {pub_path} is missing."
    with open(pub_path) as f:
        public_fields = f.read().strip().split()
    derived_fields = derived.stdout.strip().split()
    assert len(public_fields) >= 2 and public_fields[:2] == derived_fields[:2], "audit_key.pub does not match audit_key."
    assert stat.S_IMODE(os.stat(pub_path).st_mode) & 0o022 == 0, "SSH public key is writable by group or others."


def test_ssh_config():
    config_path = "/home/user/.ssh/config"
    assert os.path.exists(config_path), f"SSH config {config_path} is missing."
    with open(config_path, "r") as f:
        original_content = f.read()
    content = original_content.lower()

    assert re.search(r"passwordauthentication\s+no", content), "PasswordAuthentication no is missing or incorrectly configured in SSH config."
    assert re.search(r"identityfile\s+/home/user/\.ssh/audit_key", content), "IdentityFile is missing or incorrectly configured in SSH config."
    assert stat.S_IMODE(os.stat(config_path).st_mode) == 0o600, "SSH config permissions must be 0o600."

    blocks = []
    current = None
    for raw_line in original_content.splitlines():
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split(None, 1)
        key = parts[0].lower()
        value = parts[1].strip() if len(parts) == 2 else ""
        if key == "host":
            current = {"patterns": value.split(), "directives": {}}
            blocks.append(current)
        elif key == "match":
            current = None
        elif current is not None:
            current["directives"].setdefault(key, []).append(value)

    matching = [b for b in blocks if "audit-target" in b["patterns"]]
    assert matching, "A Host audit-target configuration block is missing."
    assert any(
        b["directives"].get("hostname", [""])[0].lower() == "127.0.0.1"
        and b["directives"].get("user", [""])[0].lower() == "audituser"
        and b["directives"].get("identityfile", [""])[0] == "/home/user/.ssh/audit_key"
        and b["directives"].get("passwordauthentication", [""])[0].lower() == "no"
        for b in matching
    ), "Host audit-target does not contain all required directives."

    effective = run(["ssh", "-G", "-F", config_path, "audit-target"], timeout=10)
    assert effective.returncode == 0, f"SSH config is invalid: {effective.stderr}"
    values = {}
    for line in effective.stdout.splitlines():
        parts = line.split(None, 1)
        if len(parts) == 2:
            values.setdefault(parts[0].lower(), []).append(parts[1].strip())
    assert values.get("hostname", [None])[0] == "127.0.0.1", "Effective HostName is not 127.0.0.1."
    assert values.get("user", [None])[0] == "audituser", "Effective SSH User is not audituser."
    assert values.get("passwordauthentication", [None])[0].lower() == "no", "Password authentication is effectively enabled."
    assert "/home/user/.ssh/audit_key" in values.get("identityfile", []), "Required IdentityFile is not effective."


def test_tls_certs():
    crt_path = "/home/user/certs/audit_server.crt"
    key_path = "/home/user/certs/audit_server.key"
    assert os.path.exists(crt_path), f"Certificate {crt_path} is missing."
    assert os.path.exists(key_path), f"Private key {key_path} is missing."

    result = subprocess.run(
        ["openssl", "x509", "-in", crt_path, "-noout", "-subject"],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, "Failed to read certificate with openssl."
    assert "CN = audit.local" in result.stdout or "CN=audit.local" in result.stdout, "The Common Name (CN) of the certificate is not set to audit.local."

    subject = run(["openssl", "x509", "-in", crt_path, "-noout", "-subject", "-nameopt", "RFC2253"])
    assert subject.returncode == 0
    assert re.findall(r"(?:^|,)CN=([^,]+)", subject.stdout.removeprefix("subject=").strip()) == ["audit.local"], "Certificate CN is not exactly audit.local."

    rsa_check = run(["openssl", "rsa", "-in", key_path, "-check", "-noout"], timeout=10)
    assert rsa_check.returncode == 0, "audit_server.key is not a valid RSA private key."
    rsa_text = run(["openssl", "rsa", "-in", key_path, "-text", "-noout"], timeout=10)
    assert rsa_text.returncode == 0 and re.search(r"Private-Key:\s*\(2048 bit", rsa_text.stdout), "TLS private key is not 2048-bit RSA."

    key_pub = subprocess.run(["openssl", "pkey", "-in", key_path, "-pubout", "-outform", "DER"], capture_output=True)
    cert_pub_pem = subprocess.run(["openssl", "x509", "-in", crt_path, "-pubkey", "-noout"], capture_output=True)
    cert_pub = subprocess.run(["openssl", "pkey", "-pubin", "-outform", "DER"], input=cert_pub_pem.stdout, capture_output=True)
    assert key_pub.returncode == 0 and cert_pub_pem.returncode == 0 and cert_pub.returncode == 0, "Unable to extract TLS public keys."
    assert key_pub.stdout == cert_pub.stdout, "Certificate does not match audit_server.key."

    verify = run(["openssl", "verify", "-CAfile", crt_path, crt_path], timeout=10)
    assert verify.returncode == 0, "Certificate is not validly self-signed."

    issuer_subject = run(["openssl", "x509", "-in", crt_path, "-noout", "-issuer", "-subject", "-nameopt", "RFC2253"])
    lines = [line.split("=", 1)[1].strip() for line in issuer_subject.stdout.splitlines() if "=" in line]
    assert issuer_subject.returncode == 0 and len(lines) == 2 and lines[0] == lines[1], "Certificate issuer and subject differ; it is not self-signed."
    assert stat.S_IMODE(os.stat(key_path).st_mode) == 0o600, "TLS private key permissions must be 0o600."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
