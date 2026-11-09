#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import stat
import subprocess
import tempfile


def test_non_elf_file_unmodified():
    filepath = "/home/user/binaries/config.bin"
    assert os.path.isfile(filepath), f"File {filepath} is missing."

    with open(filepath, "rb") as f:
        data = f.read()

    assert not data.startswith(b"\x7fELF"), f"File {filepath} should not be an ELF."
    assert b"555-66-7777" in data, f"Non-ELF file {filepath} was modified; original SSN is missing."
    assert b"***-**-****" not in data, f"Non-ELF file {filepath} was modified; contains redaction string."


def test_elf_file_service_a_redacted():
    filepath = "/home/user/binaries/service_a.bin"
    assert os.path.isfile(filepath), f"File {filepath} is missing."

    with open(filepath, "rb") as f:
        data = f.read()

    assert b"123-45-6789" not in data, f"SSN '123-45-6789' was not redacted in {filepath}."
    assert b"***-**-****" in data, f"Redaction string '***-**-****' not found in {filepath}."
    assert data.count(b"***-**-****") == 1, f"Expected exactly 1 redaction in {filepath}."


def test_elf_file_service_b_redacted():
    filepath = "/home/user/binaries/service_b.bin"
    assert os.path.isfile(filepath), f"File {filepath} is missing."

    with open(filepath, "rb") as f:
        data = f.read()

    assert b"987-65-4321" not in data, f"SSN '987-65-4321' was not redacted in {filepath}."
    assert b"000-00-0000" not in data, f"SSN '000-00-0000' was not redacted in {filepath}."
    assert data.count(b"***-**-****") == 2, f"Expected exactly 2 redactions in {filepath}."


def test_audit_log_correct():
    filepath = "/home/user/audit.log"
    assert os.path.isfile(filepath), f"Audit log file {filepath} is missing."

    with open(filepath, "r") as f:
        log_data = f.read()

    expected_a = "[AUDIT] Processed service_a.bin: redacted 1 secrets."
    expected_b = "[AUDIT] Processed service_b.bin: redacted 2 secrets."

    assert expected_a in log_data, f"Audit log is missing expected entry for service_a.bin. Expected: '{expected_a}'"
    assert expected_b in log_data, f"Audit log is missing expected entry for service_b.bin. Expected: '{expected_b}'"
    assert "config.bin" not in log_data, "Audit log incorrectly contains an entry for config.bin, which is not an ELF file."


def test_headers_conf_csp_enforced():
    filepath = "/home/user/headers.conf"
    assert os.path.isfile(filepath), f"Headers config file {filepath} is missing."

    with open(filepath, "r") as f:
        headers = f.read()

    expected_csp = "Content-Security-Policy: default-src 'self';"
    assert expected_csp in headers, f"CSP header was not appended to {filepath}. Expected to find: '{expected_csp}'"


def test_remediation_script_general_behavior():
    script = "/home/user/remediate.py"
    assert os.path.lexists(script), f"Required script {script} is missing."
    mode = os.lstat(script).st_mode
    assert stat.S_ISREG(mode), f"Required artifact {script} must be a regular file."
    assert os.path.getsize(script) > 0, f"Required script {script} is empty."

    binaries = "/home/user/binaries"
    headers = "/home/user/headers.conf"
    audit = "/home/user/audit.log"
    backup_root = tempfile.mkdtemp(prefix="remediation-verifier-")
    backup_binaries = os.path.join(backup_root, "binaries")
    shutil.copytree(binaries, backup_binaries)
    with open(headers, "rb") as f:
        original_headers = f.read()
    audit_existed = os.path.exists(audit)
    original_audit = b""
    if audit_existed:
        with open(audit, "rb") as f:
            original_audit = f.read()

    token = secrets.token_hex(8)
    elf_name = f"probe_{token}_many.bin"
    empty_name = f"probe_{token}_clean.bin"
    nonelf_name = f"probe_{token}_nonelf.bin"
    elf_path = os.path.join(binaries, elf_name)
    empty_path = os.path.join(binaries, empty_name)
    nonelf_path = os.path.join(binaries, nonelf_name)

    def random_ssn():
        digits = ''.join(str(secrets.randbelow(10)) for _ in range(9))
        return f"{digits[:3]}-{digits[3:5]}-{digits[5:]}".encode()

    ssns = [random_ssn() for _ in range(3)]
    original_elf = b"\x7fELF" + b"prefix:" + ssns[0] + b"|middle:" + ssns[1] + b"|tail:" + ssns[2] + b"\x00END"
    expected_elf = re.sub(rb"\d{3}-\d{2}-\d{4}", b"***-**-****", original_elf)
    original_empty = b"\x7fELF\x02\x01clean binary without a secret\x00"
    original_nonelf = b"NOTELF contains " + random_ssn() + b" and must remain unchanged"
    header_base = b"X-Remediation-Probe: enabled\n"
    csp = b"Content-Security-Policy: default-src 'self';"
    marker = f"preexisting-audit-marker-{token}\n".encode()

    try:
        with open(elf_path, "wb") as f:
            f.write(original_elf)
        with open(empty_path, "wb") as f:
            f.write(original_empty)
        with open(nonelf_path, "wb") as f:
            f.write(original_nonelf)
        with open(headers, "wb") as f:
            f.write(header_base)
        with open(audit, "wb") as f:
            f.write(marker)

        subprocess.run(["python3", script], check=True, timeout=15)

        with open(elf_path, "rb") as f:
            actual_elf = f.read()
        with open(empty_path, "rb") as f:
            actual_empty = f.read()
        with open(nonelf_path, "rb") as f:
            actual_nonelf = f.read()
        assert actual_elf == expected_elf, "The script did not redact all dynamically generated SSNs in-place without changing other bytes."
        assert len(actual_elf) == len(original_elf), "Redaction changed the ELF file size."
        assert actual_empty == original_empty, "A valid ELF with no SSNs was unexpectedly modified."
        assert actual_nonelf == original_nonelf, "A dynamically generated non-ELF file was modified."

        with open(headers, "rb") as f:
            first_headers = f.read()
        assert first_headers.startswith(header_base), "Existing header configuration was modified."
        assert first_headers[len(header_base):] in (csp, csp + b"\n"), "The exact required CSP line was not appended."
        assert first_headers.count(csp) == 1, "The CSP directive was appended more than once."

        with open(audit, "r") as f:
            first_log_lines = f.read().splitlines()
        many_entry = f"[AUDIT] Processed {elf_name}: redacted 3 secrets."
        clean_entry = f"[AUDIT] Processed {empty_name}: redacted 0 secrets."
        assert marker.decode().strip() in first_log_lines, "The script overwrote the existing audit log instead of appending."
        assert first_log_lines.count(many_entry) == 1, "Missing or incorrect audit entry for the generated ELF."
        assert first_log_lines.count(clean_entry) == 1, "A valid ELF with zero matches was not audited correctly."
        assert not any(nonelf_name in line for line in first_log_lines), "The generated non-ELF file was incorrectly audited."

        subprocess.run(["python3", script], check=True, timeout=15)
        with open(headers, "rb") as f:
            second_headers = f.read()
        assert second_headers == first_headers, "Running the script again duplicated or altered the existing CSP directive."
        with open(elf_path, "rb") as f:
            assert f.read() == expected_elf, "A second run unexpectedly altered the already-redacted ELF."
        with open(audit, "r") as f:
            second_log_lines = f.read().splitlines()
        zero_entry = f"[AUDIT] Processed {elf_name}: redacted 0 secrets."
        assert second_log_lines.count(many_entry) == 1, "The original redaction count was not logged exactly once."
        assert second_log_lines.count(zero_entry) == 1, "The second processing pass was not audited with zero redactions."
        assert second_log_lines.count(clean_entry) == 2, "The clean valid ELF was not audited on every run."
    finally:
        if os.path.exists(binaries):
            shutil.rmtree(binaries)
        shutil.copytree(backup_binaries, binaries)
        with open(headers, "wb") as f:
            f.write(original_headers)
        if audit_existed:
            with open(audit, "wb") as f:
                f.write(original_audit)
        elif os.path.exists(audit):
            os.remove(audit)
        shutil.rmtree(backup_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
