#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
from pathlib import Path

RECOVER_SOURCE = Path("/home/user/recover.go")
RECOVER_BINARY = Path("/tmp/recover_submission")
EVIDENCE = Path("/home/user/forensics/evidence.enc")
RECOVERED = Path("/home/user/recovered_evidence.txt")
EXPECTED_ORIGINAL = b'EVIDENCE_DATA:{user:"admin_root",stolen_hash:"f8b9a1c2d3e4f5a6b7c8d9e0f1a2b3c4"}'
KEY = b"A1B2C3D4E5F67890exfil.malware.local"


def run_recovery():
    if RECOVERED.exists() or RECOVERED.is_symlink():
        RECOVERED.unlink()
    subprocess.run(
        [str(RECOVER_BINARY)],
        cwd="/home/user",
        check=True,
        timeout=20,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert RECOVERED.is_file(), "/home/user/recovered_evidence.txt was not produced."
    return RECOVERED.read_bytes()


def test_recover_go_exists_and_builds():
    assert os.path.isfile(RECOVER_SOURCE), "/home/user/recover.go does not exist."
    mode = os.lstat(RECOVER_SOURCE).st_mode
    assert stat.S_ISREG(mode), "/home/user/recover.go must be a regular file."
    assert RECOVER_SOURCE.stat().st_size > 0, "/home/user/recover.go is empty."
    subprocess.run(
        ["go", "build", "-o", str(RECOVER_BINARY), str(RECOVER_SOURCE)],
        cwd="/home/user",
        check=True,
        timeout=60,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def test_recovered_evidence():
    content = run_recovery()
    assert EXPECTED_ORIGINAL in content, f"The decrypted evidence is incorrect. Found: {content!r}"


def test_recovery_program_processes_evidence_input():
    original_evidence = EVIDENCE.read_bytes()
    had_output = RECOVERED.exists()
    original_output = RECOVERED.read_bytes() if had_output else None
    try:
        for length in (73, 257):
            plaintext = os.urandom(length)
            ciphertext = bytes(b ^ KEY[i % len(KEY)] for i, b in enumerate(plaintext))
            EVIDENCE.write_bytes(ciphertext)
            assert run_recovery() == plaintext, "recover.go did not correctly decrypt a test evidence file."
    finally:
        EVIDENCE.write_bytes(original_evidence)
        if had_output:
            RECOVERED.write_bytes(original_output)
        elif RECOVERED.exists() or RECOVERED.is_symlink():
            RECOVERED.unlink()


def test_audit_report():
    report_path = "/home/user/audit_report.txt"
    assert os.path.isfile(report_path), f"File {report_path} does not exist."

    with open(report_path, "r") as f:
        raw_content = f.read()
    content = raw_content.upper()

    # Preserve the original checks.
    has_cwe_22 = "CWE-22" in content
    has_cwe_327 = "CWE-327" in content
    assert has_cwe_22 and has_cwe_327, f"The audit report must contain both CWE-22 and CWE-327. Content found: {content}"

    # Require exactly the requested comma-separated report (apart from a final newline).
    assert re.fullmatch(r"CWE-22, CWE-327\n?", raw_content) is not None, \
        f"The audit report must be exactly 'CWE-22, CWE-327'. Content found: {raw_content!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
