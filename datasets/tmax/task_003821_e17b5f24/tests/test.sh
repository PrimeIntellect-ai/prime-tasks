#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import stat
import subprocess
import tempfile
import zipfile

WORKSPACE_DIR = "/home/user/workspace"
EXTRACTED_DIR = os.path.join(WORKSPACE_DIR, "extracted")
REPORT_PATH = os.path.join(WORKSPACE_DIR, "report.txt")
SSH_KEY_PATH = "/home/user/.ssh/id_rsa"
SSHD_CONFIG_PATH = os.path.join(EXTRACTED_DIR, "sshd_config")
REDACTED_LOG_PATH = os.path.join(WORKSPACE_DIR, "db_backup_redacted.log")
ORACLE_ARCHIVE = "/tests/secret_backup.zip"
ORACLE_WORDLIST = "/tests/wordlist.txt"


def load_archive_oracle():
    assert os.path.isfile(ORACLE_ARCHIVE), f"Trusted archive is missing at {ORACLE_ARCHIVE}."
    assert os.path.isfile(ORACLE_WORDLIST), f"Trusted wordlist is missing at {ORACLE_WORDLIST}."

    with open(ORACLE_WORDLIST, "rb") as f:
        candidates = [line.strip() for line in f if line.strip()]

    with zipfile.ZipFile(ORACLE_ARCHIVE, "r") as zf:
        members = [info for info in zf.infolist() if not info.is_dir()]
        assert members, "Trusted archive contains no files."
        password = None
        contents = None
        for candidate in candidates:
            try:
                trial = {os.path.basename(info.filename): zf.read(info, pwd=candidate) for info in members}
            except (RuntimeError, zipfile.BadZipFile):
                continue
            password = candidate.decode("utf-8")
            contents = trial
            break

    assert password is not None, "No wordlist password decrypts the trusted archive."
    required = {"chain.pem", "sshd_config", "db_backup.log", "id_rsa"}
    assert required.issubset(contents), f"Trusted archive is missing: {required - set(contents)}"
    return password, contents


PASSWORD, ARCHIVE_CONTENTS = load_archive_oracle()


def expected_hardened_config():
    source = ARCHIVE_CONTENTS["sshd_config"]
    pattern = rb"(?m)^([ \t]*PermitEmptyPasswords[ \t]+)yes([ \t]*(?:#.*?)?)$"
    result, count = re.subn(pattern, rb"\1no\2", source)
    assert count == 1, f"Expected one PermitEmptyPasswords yes directive in source, found {count}."
    return result


def expired_certificate_cn():
    blocks = re.findall(
        rb"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----",
        ARCHIVE_CONTENTS["chain.pem"],
        flags=re.DOTALL,
    )
    assert blocks, "No certificates found in trusted chain.pem."
    expired = []
    for block in blocks:
        with tempfile.NamedTemporaryFile() as cert_file:
            cert_file.write(block + b"\n")
            cert_file.flush()
            check = subprocess.run(
                ["openssl", "x509", "-in", cert_file.name, "-noout", "-checkend", "0"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            subject = subprocess.run(
                ["openssl", "x509", "-in", cert_file.name, "-noout", "-subject", "-nameopt", "multiline"],
                check=True,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            ).stdout
        if check.returncode != 0:
            match = re.search(r"^\s*commonName\s*=\s*(.+?)\s*$", subject, flags=re.MULTILINE)
            assert match, f"Could not determine CN from expired certificate subject: {subject!r}"
            expired.append(match.group(1))
    assert len(expired) == 1, f"Expected exactly one expired certificate, found {len(expired)}."
    return expired[0]


def test_report_exists_and_content():
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."

    with open(REPORT_PATH, "r") as f:
        lines = [line.strip() for line in f.read().strip().split('\n')]

    assert len(lines) == 3, f"Report should have exactly 3 lines, found {len(lines)}."

    assert lines[0] == "dragonfly2023", f"Line 1 of report should be 'dragonfly2023', got '{lines[0]}'."
    assert lines[1] == "legacy.internal.corp", f"Line 2 of report should be 'legacy.internal.corp', got '{lines[1]}'."
    assert lines[0] == PASSWORD, f"Line 1 does not match the password derived from the trusted archive: {PASSWORD}."
    assert lines[1] == expired_certificate_cn(), "Line 2 does not match the CN derived from the expired certificate."

    assert os.path.isfile(SSHD_CONFIG_PATH), f"Extracted sshd_config does not exist at {SSHD_CONFIG_PATH}."

    with open(SSHD_CONFIG_PATH, "rb") as f:
        sshd_config_content = f.read()
    expected_hash = hashlib.sha256(sshd_config_content).hexdigest()

    assert lines[2] == expected_hash, f"Line 3 of report should be the SHA256 sum of sshd_config ({expected_hash}), got '{lines[2]}'."


def test_extracted_contents_are_faithful():
    for name in ("chain.pem", "db_backup.log", "id_rsa"):
        path = os.path.join(EXTRACTED_DIR, name)
        assert os.path.isfile(path), f"Extracted file does not exist at {path}."
        with open(path, "rb") as f:
            actual = f.read()
        assert actual == ARCHIVE_CONTENTS[name], f"{path} does not match the file in the trusted archive."

    with open(SSHD_CONFIG_PATH, "rb") as f:
        actual_config = f.read()
    assert actual_config == expected_hardened_config(), "Extracted sshd_config is not the faithful source configuration with only the required hardening change."


def test_ssh_key_permissions():
    assert os.path.isfile(SSH_KEY_PATH), f"SSH key {SSH_KEY_PATH} does not exist."
    assert stat.S_ISREG(os.lstat(SSH_KEY_PATH).st_mode), f"SSH key {SSH_KEY_PATH} must be a regular file."
    st = os.stat(SSH_KEY_PATH)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o600, f"SSH key {SSH_KEY_PATH} must have 600 permissions, got {oct(perms)}."
    with open(SSH_KEY_PATH, "rb") as f:
        key_content = f.read()
    assert key_content == ARCHIVE_CONTENTS["id_rsa"], "Installed SSH key does not match the private key from the trusted archive."
    validation = subprocess.run(
        ["ssh-keygen", "-y", "-f", SSH_KEY_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert validation.returncode == 0 and validation.stdout.strip(), "Installed SSH private key is not valid."


def test_sshd_config_hardened():
    assert os.path.isfile(SSHD_CONFIG_PATH), f"Extracted sshd_config does not exist at {SSHD_CONFIG_PATH}."
    with open(SSHD_CONFIG_PATH, "r") as f:
        content = f.read()

    assert "PermitEmptyPasswords no" in content, "sshd_config does not contain 'PermitEmptyPasswords no'."
    assert "PermitEmptyPasswords yes" not in content, "sshd_config still contains 'PermitEmptyPasswords yes'."
    assert content.encode() == expected_hardened_config(), "sshd_config does not exactly match the archived configuration after the required directive change."


def test_db_backup_redacted():
    assert os.path.isfile(REDACTED_LOG_PATH), f"Redacted log file {REDACTED_LOG_PATH} does not exist."
    with open(REDACTED_LOG_PATH, "r") as f:
        content = f.read()

    matches = re.findall(r"AKIA[A-Z0-9]{16}", content)
    assert len(matches) == 0, f"Found unredacted API keys in {REDACTED_LOG_PATH}: {matches}"
    assert "[REDACTED]" in content, f"Redaction string '[REDACTED]' not found in {REDACTED_LOG_PATH}."

    expected = re.sub(rb"AKIA[A-Z0-9]{16}", b"[REDACTED]", ARCHIVE_CONTENTS["db_backup.log"])
    with open(REDACTED_LOG_PATH, "rb") as f:
        actual = f.read()
    assert actual == expected, "Redacted log does not faithfully preserve the archived log while replacing every matching API key."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
