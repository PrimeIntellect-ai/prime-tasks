#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import stat
import subprocess

import pytest

HOME = "/home/user"
UPLOADS = os.path.join(HOME, "uploads")


def run_checked(command, **kwargs):
    try:
        return subprocess.run(command, timeout=5, capture_output=True, **kwargs)
    except subprocess.TimeoutExpired:
        pytest.fail(f"Command timed out: {command}")


def test_forensics_report():
    report_path = "/home/user/forensics_report.json"
    assert os.path.isfile(report_path), f"Report file {report_path} is missing."

    with open(report_path, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} is not valid JSON.")

    assert isinstance(report, dict), "Forensics report must be a JSON object."
    assert set(report) == {"vulnerability_cwe", "attacker_public_key", "recovered_evidence"}, \
        "Forensics report does not have the required exact structure."

    cwe = report.get("vulnerability_cwe", "").upper()
    assert cwe in ["CWE-22", "CWE-23"], f"Incorrect CWE identified in report: {cwe}"

    attacker_key = report.get("attacker_public_key", "")
    assert "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDKX9" in attacker_key, \
        "Attacker public key not correctly identified in report."
    assert attacker_key == "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDKX9... attacker@evil.com", \
        "The complete original attacker public key was not extracted."

    evidence = report.get("recovered_evidence", "")
    assert evidence == "flag{bash_f0r3ns1cs_p4th_tr4v3rsal}", "Recovered evidence is incorrect."


def test_poc_execution_through_vulnerable_server():
    poc_path = "/home/user/poc.sh"
    server_path = "/home/user/upload_server.sh"
    target_file = "/home/user/.ssh/pwned.txt"
    assert os.path.isfile(poc_path), f"PoC script {poc_path} is missing."
    assert os.path.isfile(server_path), f"Original upload server {server_path} is missing."

    with open(server_path, "rb") as f:
        original_server = f.read()
    original_mode = stat.S_IMODE(os.stat(server_path).st_mode)

    probe_id = secrets.token_hex(16)
    marker = f"/tmp/upload_server_invocation_{probe_id}"
    instrumented_server = f'''#!/bin/bash
read -r line1
filename=$(echo "$line1" | grep "Filename:" | awk '{{print $2}}')
if [ -n "$filename" ]; then
    cat > "/home/user/uploads/$filename"
    printf '%s' "$filename" > "{marker}"
    echo "File $filename uploaded successfully."
else
    echo "Error: No filename provided."
fi
'''

    for path in (target_file, marker):
        if os.path.lexists(path):
            os.remove(path)

    try:
        with open(server_path, "w") as f:
            f.write(instrumented_server)
        os.chmod(server_path, 0o755)

        run_checked(["bash", poc_path])

        assert os.path.isfile(target_file), \
            "PoC script failed to create the target file via path traversal."
        assert os.path.isfile(marker), \
            "PoC did not invoke /home/user/upload_server.sh."
        with open(marker, "r") as f:
            submitted_filename = f.read()
        assert submitted_filename, "PoC invoked the server without a filename."
        resolved = os.path.realpath(os.path.join(UPLOADS, submitted_filename))
        assert resolved == os.path.realpath(target_file), \
            "PoC did not submit a traversal filename that resolves to .ssh/pwned.txt."
    finally:
        with open(server_path, "wb") as f:
            f.write(original_server)
        os.chmod(server_path, original_mode)
        if os.path.lexists(marker):
            os.remove(marker)


def test_ssh_keys():
    priv_key = "/home/user/.ssh/id_ed25519"
    pub_key = "/home/user/.ssh/id_ed25519.pub"
    auth_keys = "/home/user/.ssh/authorized_keys"

    assert os.path.isfile(priv_key), f"Private key {priv_key} is missing."
    assert os.path.isfile(pub_key), f"Public key {pub_key} is missing."
    assert os.path.isfile(auth_keys), f"Authorized keys file {auth_keys} is missing."

    with open(pub_key, "r") as f:
        new_pub_key_content = f.read().strip()
    with open(auth_keys, "r") as f:
        auth_keys_content = f.read()

    assert new_pub_key_content in auth_keys_content, \
        "Newly generated ed25519 public key not found in authorized_keys."
    assert "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDKX9" not in auth_keys_content, \
        "Attacker's key was not removed from authorized_keys."

    pub_lines = [line.strip() for line in new_pub_key_content.splitlines() if line.strip()]
    assert len(pub_lines) == 1, "Public-key file must contain exactly one key."
    pub_parts = pub_lines[0].split()
    assert len(pub_parts) >= 2 and pub_parts[0] == "ssh-ed25519", \
        "Generated public key is not an Ed25519 key."

    derived = run_checked(["ssh-keygen", "-y", "-P", "", "-f", priv_key])
    assert derived.returncode == 0, \
        "Private key is invalid or is protected by a passphrase."
    derived_parts = derived.stdout.decode().strip().split()
    assert len(derived_parts) >= 2 and derived_parts[0] == "ssh-ed25519", \
        "Private key is not an Ed25519 key."
    assert derived_parts[:2] == pub_parts[:2], \
        "id_ed25519.pub does not match the generated private key."

    validation = run_checked(["ssh-keygen", "-lf", pub_key])
    assert validation.returncode == 0, "Public key is not a valid SSH public key."

    active_auth = [line.strip() for line in auth_keys_content.splitlines()
                   if line.strip() and not line.lstrip().startswith("#")]
    assert len(active_auth) == 1, \
        "authorized_keys must contain only the newly generated key."
    assert active_auth[0].split()[:2] == pub_parts[:2], \
        "authorized_keys does not contain the matching Ed25519 public key."


def test_sshd_config():
    config_path = "/home/user/sshd_config_custom"
    assert os.path.isfile(config_path), f"Config file {config_path} is missing."

    with open(config_path, "r") as f:
        lines = f.readlines()

    permit_root = False
    password_auth = False

    for line in lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) >= 2:
            key, val = parts[0].lower(), parts[1].lower()
            if key == "permitrootlogin":
                assert val == "no", f"PermitRootLogin is set to {val}, expected 'no'."
                permit_root = True
            elif key == "passwordauthentication":
                assert val == "no", f"PasswordAuthentication is set to {val}, expected 'no'."
                password_auth = True

    assert permit_root, "PermitRootLogin directive missing from sshd_config_custom."
    assert password_auth, "PasswordAuthentication directive missing from sshd_config_custom."


def test_patched_server():
    server_path = "/home/user/upload_server_patched.sh"
    assert os.path.isfile(server_path), f"Patched server script {server_path} is missing."
    assert not os.path.islink(server_path), "Patched server must be a real script, not a symlink."
    assert os.access(server_path, os.X_OK), f"Patched server script {server_path} is not executable."
    with open(server_path, "rb") as f:
        first_line = f.readline(256).lower()
    assert first_line.startswith(b"#!") and b"bash" in first_line, \
        "Patched server is not a Bash script."
    assert os.path.isdir(UPLOADS) and not os.path.islink(UPLOADS), \
        "Uploads directory must remain a real directory."

    # A patched upload service must still save valid uploads, not merely do nothing.
    for _ in range(3):
        filename = f"safe{secrets.token_hex(8)}.txt"
        content = f"upload-{secrets.token_hex(24)}\n"
        destination = os.path.join(UPLOADS, filename)
        if os.path.lexists(destination):
            os.remove(destination)
        result = run_checked(["bash", server_path],
                             input=f"Filename: {filename}\n{content}".encode())
        assert result.returncode == 0, "Patched server failed on a valid upload."
        assert os.path.isfile(destination) and not os.path.islink(destination), \
            "Patched server did not save a valid filename in the uploads directory."
        with open(destination, "rb") as f:
            assert f.read() == content.encode(), "Patched server corrupted valid upload content."

    # Exercise independently randomized traversal destinations and spellings.
    token = secrets.token_hex(12)
    attacks = [
        (f"../../.ssh/evil{token}.txt", f"/home/user/.ssh/evil{token}.txt"),
        (f"../escaped{token}.txt", f"/home/user/escaped{token}.txt"),
        (f"../../../tmp/escaped{token}.txt", f"/tmp/escaped{token}.txt"),
        (f"..//../.ssh/slash{token}.txt", f"/home/user/.ssh/slash{token}.txt"),
    ]

    for supplied_name, outside_target in attacks:
        if os.path.lexists(outside_target):
            os.remove(outside_target)
        before = set()
        for root, dirs, files in os.walk(UPLOADS):
            for name in dirs + files:
                before.add(os.path.relpath(os.path.join(root, name), UPLOADS))

        content = f"malicious-{secrets.token_hex(20)}\n"
        run_checked(["bash", server_path],
                    input=f"Filename: {supplied_name}\n{content}".encode())
        assert not os.path.exists(outside_target), \
            f"Patched server allowed path traversal using {supplied_name!r}."

        after = set()
        for root, dirs, files in os.walk(UPLOADS):
            for name in dirs + files:
                after.add(os.path.relpath(os.path.join(root, name), UPLOADS))
        for relative_path in after - before:
            assert os.sep not in relative_path, \
                "Patched server created a nested path from an unsafe filename."
            assert re.fullmatch(r"[A-Za-z0-9.]+", relative_path), \
                "Patched server saved a filename containing disallowed characters."


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
