#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import stat
import subprocess
import tempfile
import pytest

ORIG_ELF = "/app/malware.elf"
SANITIZED_ELF = "/home/user/sanitized.elf"
ANALYZER = "/home/user/analyze.go"


def run_analyzer(timeout=180):
    return subprocess.run(
        ["runuser", "-u", "user", "--", "env", "HOME=/home/user", "go", "run", ANALYZER],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def get_section_data(elf_path, section_name):
    """Extracts the raw binary data of a specific ELF section using objcopy."""
    fd, out_path = tempfile.mkstemp(prefix="extracted_", suffix=".bin")
    os.close(fd)
    os.unlink(out_path)
    try:
        result = subprocess.run(
            ["objcopy", "-O", "binary", f"--only-section={section_name}", elf_path, out_path],
            capture_output=True,
        )
        if result.returncode != 0 or not os.path.exists(out_path):
            return None
        with open(out_path, "rb") as f:
            return f.read()
    finally:
        if os.path.exists(out_path):
            os.remove(out_path)


def sensitive_mask(data):
    mask = [False] * len(data)
    cc_pattern = re.compile(br'(?<!\d)\d{4}-\d{4}-\d{4}-\d{4}(?!\d)')
    email_pattern = re.compile(br'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}')
    for pattern in (cc_pattern, email_pattern):
        for match in pattern.finditer(data):
            for i in range(match.start(), match.end()):
                mask[i] = True
    return mask


def setup_module(module):
    assert os.path.isfile(ANALYZER), "The required Go source /home/user/analyze.go is missing."
    assert not os.path.islink(ANALYZER), "/home/user/analyze.go must be a regular source file."
    if os.path.exists(SANITIZED_ELF):
        os.remove(SANITIZED_ELF)
    result = run_analyzer()
    assert result.returncode == 0, (
        "Running /home/user/analyze.go failed.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_sanitized_elf_exists():
    assert os.path.isfile(SANITIZED_ELF), "The sanitized ELF binary /home/user/sanitized.elf is missing."


def test_redaction_f1_score():
    orig_elf = ORIG_ELF
    sanitized_elf = SANITIZED_ELF

    assert os.path.isfile(orig_elf), f"Original ELF {orig_elf} is missing."
    assert os.path.isfile(sanitized_elf), f"Sanitized ELF {sanitized_elf} is missing."

    orig_data = get_section_data(orig_elf, ".exfil_data")
    sanitized_data = get_section_data(sanitized_elf, ".exfil_data")

    assert orig_data is not None, "Failed to extract .exfil_data from original ELF."
    assert sanitized_data is not None, "Failed to extract .exfil_data from sanitized ELF."
    assert len(orig_data) == len(sanitized_data), "The length of the .exfil_data section was altered."

    # Ground truth masks
    is_sensitive = [False] * len(orig_data)

    # Regex patterns for sensitive data
    cc_pattern = re.compile(br'(?<!\d)\d{4}-\d{4}-\d{4}-\d{4}(?!\d)')
    email_pattern = re.compile(br'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}')

    for match in cc_pattern.finditer(orig_data):
        for i in range(match.start(), match.end()):
            is_sensitive[i] = True

    for match in email_pattern.finditer(orig_data):
        for i in range(match.start(), match.end()):
            is_sensitive[i] = True

    tp = 0
    fp = 0
    fn = 0

    for i in range(len(orig_data)):
        orig_byte = orig_data[i]
        sanitized_byte = sanitized_data[i]
        was_redacted = (sanitized_byte == ord('*')) and (orig_byte != ord('*'))

        if is_sensitive[i]:
            if was_redacted:
                tp += 1
            else:
                fn += 1
        elif was_redacted:
            fp += 1

    precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
    f1 = 2 * (precision * recall) / (precision + recall) if (precision + recall) > 0 else 0.0

    threshold = 0.95
    assert f1 >= threshold, f"F1 score for redaction is {f1:.4f}, which is below the threshold of {threshold}. TP={tp}, FP={fp}, FN={fn}."


def test_only_sensitive_section_bytes_were_changed():
    with open(ORIG_ELF, "rb") as f:
        original_file = f.read()
    with open(SANITIZED_ELF, "rb") as f:
        sanitized_file = f.read()

    assert len(sanitized_file) == len(original_file), "The ELF file length was changed."
    assert sanitized_file.startswith(b"\x7fELF"), "The output is not an ELF file."

    exfil = get_section_data(ORIG_ELF, ".exfil_data")
    assert exfil is not None and exfil, "Original .exfil_data is missing or empty."
    assert original_file.count(exfil) == 1, "Could not uniquely locate .exfil_data in the original ELF."
    section_offset = original_file.find(exfil)
    mask = sensitive_mask(exfil)

    expected = bytearray(original_file)
    for i, sensitive in enumerate(mask):
        if sensitive:
            expected[section_offset + i] = ord('*')

    assert sanitized_file == bytes(expected), (
        "The output must differ from the original only by replacing sensitive "
        ".exfil_data bytes with asterisks; another ELF byte was altered."
    )

    orig_cert = get_section_data(ORIG_ELF, ".tls_cert")
    sanitized_cert = get_section_data(SANITIZED_ELF, ".tls_cert")
    assert orig_cert is not None and sanitized_cert == orig_cert, ".tls_cert was altered."


def test_sanitized_binary_is_executable_and_runs():
    mode = stat.S_IMODE(os.stat(SANITIZED_ELF).st_mode)
    assert mode & 0o111, "/home/user/sanitized.elf does not have an executable mode bit."
    readelf = subprocess.run(["readelf", "-h", SANITIZED_ELF], capture_output=True)
    assert readelf.returncode == 0, "The sanitized output is not a structurally valid ELF."

    original_run = subprocess.run([ORIG_ELF], capture_output=True, timeout=10)
    sanitized_run = subprocess.run([SANITIZED_ELF], capture_output=True, timeout=10)
    assert sanitized_run.returncode == original_run.returncode, "The sanitized ELF no longer executes like the original."
    assert sanitized_run.stdout == original_run.stdout and sanitized_run.stderr == original_run.stderr, (
        "The sanitized ELF's observable output differs from the original."
    )


def test_redaction_is_conditional_on_certificate_key_match():
    with tempfile.TemporaryDirectory() as td:
        backup = os.path.join(td, "malware.original")
        mismatch = os.path.join(td, "malware.mismatch")
        key = os.path.join(td, "wrong-key.pem")
        cert = os.path.join(td, "wrong-cert.pem")
        shutil.copy2(ORIG_ELF, backup)
        shutil.copy2(ORIG_ELF, mismatch)

        generated = subprocess.run([
            "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-keyout", key, "-out", cert, "-days", "1", "-subj", "/CN=verifier-mismatch"
        ], capture_output=True)
        assert generated.returncode == 0, "Verifier failed to generate a mismatching certificate."

        updated = subprocess.run(
            ["objcopy", f"--update-section", f".tls_cert={cert}", mismatch],
            capture_output=True,
        )
        assert updated.returncode == 0, "Verifier failed to construct the certificate-mismatch ELF."
        os.chmod(mismatch, os.stat(mismatch).st_mode | 0o111)

        try:
            shutil.copy2(mismatch, ORIG_ELF)
            if os.path.exists(SANITIZED_ELF):
                os.remove(SANITIZED_ELF)
            result = run_analyzer()
            assert result.returncode == 0, (
                "The analyzer failed to produce its output for a nonmatching certificate.\n"
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )
            assert os.path.isfile(SANITIZED_ELF), "Analyzer produced no output for the mismatch case."
            with open(mismatch, "rb") as f:
                mismatch_bytes = f.read()
            with open(SANITIZED_ELF, "rb") as f:
                output_bytes = f.read()
            assert output_bytes == mismatch_bytes, (
                "The analyzer modified the binary even though its embedded certificate did not "
                "match the private key recovered from the supplied video."
            )
        finally:
            shutil.copy2(backup, ORIG_ELF)
            if os.path.exists(SANITIZED_ELF):
                os.remove(SANITIZED_ELF)
            restored = run_analyzer()
            assert restored.returncode == 0, "Analyzer failed after restoring the original evidence."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
