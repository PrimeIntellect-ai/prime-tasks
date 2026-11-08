#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import secrets
import shutil
import subprocess
import tempfile
from datetime import datetime

import pytest
from elftools.elf.elffile import ELFFile

ROGUE_CN = b"c2-backend.corp.attacker.net"


def test_rogue_cn_extracted():
    """Verify that the rogue CN was correctly extracted from the video."""
    cn_file = "/home/user/rogue_cn.txt"
    assert os.path.isfile(cn_file), f"Missing rogue CN file: {cn_file}"

    with open(cn_file, "r") as f:
        cn_value = f.read().strip()

    expected_cn = "c2-backend.corp.attacker.net"
    assert cn_value == expected_cn, f"Incorrect rogue CN. Expected '{expected_cn}', got '{cn_value}'"


def test_detector_script_against_corpus():
    """Verify the detector script classifies all corpus files correctly."""
    detector_script = "/home/user/detector.py"
    assert os.path.isfile(detector_script), f"Missing detector script: {detector_script}"

    evil_corpus = "/app/corpus/evil/"
    clean_corpus = "/app/corpus/clean/"

    evil_files = [os.path.join(evil_corpus, f) for f in os.listdir(evil_corpus) if os.path.isfile(os.path.join(evil_corpus, f))]
    clean_files = [os.path.join(clean_corpus, f) for f in os.listdir(clean_corpus) if os.path.isfile(os.path.join(clean_corpus, f))]

    evil_bypassed = []
    clean_modified = []

    for filepath in evil_files:
        try:
            result = subprocess.run(["python3", detector_script, filepath], capture_output=True, text=True, timeout=5)
            output = result.stdout.strip()
            if output != "EVIL":
                evil_bypassed.append(os.path.basename(filepath))
        except Exception:
            evil_bypassed.append(os.path.basename(filepath))

    for filepath in clean_files:
        try:
            result = subprocess.run(["python3", detector_script, filepath], capture_output=True, text=True, timeout=5)
            output = result.stdout.strip()
            if output != "CLEAN":
                clean_modified.append(os.path.basename(filepath))
        except Exception:
            clean_modified.append(os.path.basename(filepath))

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {evil_bypassed}")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {clean_modified}")

    assert not error_msgs, " | ".join(error_msgs)


def _parse_elf(data):
    return ELFFile(io.BytesIO(bytes(data)))


def _choose_base_elf():
    for path in ("/bin/true", "/usr/bin/true", "/bin/ls", "/usr/bin/env"):
        if not os.path.isfile(path):
            continue
        with open(path, "rb") as f:
            data = bytearray(f.read())
        try:
            elf = _parse_elf(data)
            rodata = elf.get_section_by_name(".rodata")
            names = [section.name for section in elf.iter_sections()]
            if (rodata is not None and rodata.data_size >= len(ROGUE_CN)
                    and ROGUE_CN not in rodata.data()
                    and ".mal_tls" not in names):
                return data
        except Exception:
            pass
    pytest.fail("Verifier could not find a suitable system ELF for detector tests")


def _put_cn_in_rodata(base):
    data = bytearray(base)
    elf = _parse_elf(data)
    rodata = elf.get_section_by_name(".rodata")
    offset = int(rodata.header["sh_offset"])
    data[offset:offset + len(ROGUE_CN)] = ROGUE_CN
    return data


def _rename_section(base, new_name):
    data = bytearray(base)
    elf = _parse_elf(data)
    shstr = elf.get_section(int(elf.header["e_shstrndx"]))
    shstr_offset = int(shstr.header["sh_offset"])

    target = None
    for section in elf.iter_sections():
        if section.name != ".rodata" and len(section.name) >= len(new_name):
            target = section
            break
    assert target is not None, "No suitable ELF section name available for test fixture"

    name_offset = int(target.header["sh_name"])
    absolute = shstr_offset + name_offset
    encoded = new_name.encode("ascii")
    data[absolute:absolute + len(encoded)] = encoded
    data[absolute + len(encoded)] = 0
    return data


def _write_random_fixture(directory, data):
    path = os.path.join(directory, secrets.token_hex(12))
    with open(path, "wb") as f:
        f.write(data)
    return path


def test_detector_script_generated_elf_cases():
    """Exercise both detection rules and negative controls on generated ELF files."""
    detector_script = "/home/user/detector.py"
    assert os.path.isfile(detector_script), f"Missing detector script: {detector_script}"

    base = _choose_base_elf()
    fixture_dir = tempfile.mkdtemp(prefix="elf-evaluation-")
    try:
        cases = []
        cases.append((_write_random_fixture(fixture_dir, base), "CLEAN"))
        cases.append((_write_random_fixture(fixture_dir, base + b"\x00" + ROGUE_CN), "CLEAN"))
        cases.append((_write_random_fixture(fixture_dir, _rename_section(base, ".mal_tlsX")), "CLEAN"))
        cases.append((_write_random_fixture(fixture_dir, _put_cn_in_rodata(base)), "EVIL"))
        cases.append((_write_random_fixture(fixture_dir, _rename_section(base, ".mal_tls")), "EVIL"))
        secrets.SystemRandom().shuffle(cases)

        failures = []
        for filepath, expected in cases:
            try:
                result = subprocess.run(
                    ["python3", detector_script, filepath],
                    capture_output=True,
                    text=True,
                    timeout=5,
                )
                valid_stdout = result.stdout in (expected, expected + "\n")
                if result.returncode != 0 or not valid_stdout:
                    failures.append(
                        f"expected {expected}, return code {result.returncode}, stdout={result.stdout!r}"
                    )
            except Exception as exc:
                failures.append(f"expected {expected}, execution failed: {exc}")

        assert not failures, "Detector failed generated ELF cases: " + " | ".join(failures)
    finally:
        shutil.rmtree(fixture_dir, ignore_errors=True)


def test_credential_rotation():
    """Verify the newly generated credentials."""
    key_file = "/home/user/new_key.pem"
    cert_file = "/home/user/new_cert.pem"

    assert os.path.isfile(key_file), f"Missing private key: {key_file}"
    assert os.path.isfile(cert_file), f"Missing certificate: {cert_file}"

    # Check if key is RSA
    key_check = subprocess.run(["openssl", "rsa", "-in", key_file, "-check", "-noout"], capture_output=True, text=True)
    assert key_check.returncode == 0, "new_key.pem is not a valid RSA private key"

    # Check certificate subject
    cert_subj = subprocess.run(["openssl", "x509", "-in", cert_file, "-noout", "-subject"], capture_output=True, text=True)
    assert cert_subj.returncode == 0, "new_cert.pem is not a valid certificate"
    assert "CN = legit-update.local" in cert_subj.stdout or "CN=legit-update.local" in cert_subj.stdout, "Certificate does not have the correct Subject CN"

    # Check certificate validity dates
    cert_dates = subprocess.run(["openssl", "x509", "-in", cert_file, "-noout", "-dates"], capture_output=True, text=True)
    assert cert_dates.returncode == 0, "Failed to read certificate dates"

    dates = {}
    for line in cert_dates.stdout.strip().split('\n'):
        if '=' in line:
            key, val = line.split('=', 1)
            dates[key] = val

    assert "notBefore" in dates and "notAfter" in dates, "Certificate dates missing"

    not_before = datetime.strptime(dates["notBefore"], "%b %d %H:%M:%S %Y %Z")
    not_after = datetime.strptime(dates["notAfter"], "%b %d %H:%M:%S %Y %Z")

    diff_days = (not_after - not_before).days
    assert diff_days == 365, f"Certificate validity is {diff_days} days, expected 365 days"

    # Verify the RSA modulus is exactly 2048 bits.
    key_modulus = subprocess.run(
        ["openssl", "rsa", "-in", key_file, "-noout", "-modulus"],
        capture_output=True, text=True
    )
    assert key_modulus.returncode == 0 and key_modulus.stdout.startswith("Modulus="), "Failed to read RSA key modulus"
    modulus_hex = key_modulus.stdout.strip().split("=", 1)[1]
    assert int(modulus_hex, 16).bit_length() == 2048, "RSA private key is not 2048-bit"

    # Verify the certificate contains the public key corresponding to the private key.
    cert_modulus = subprocess.run(
        ["openssl", "x509", "-in", cert_file, "-noout", "-modulus"],
        capture_output=True, text=True
    )
    assert cert_modulus.returncode == 0, "Certificate does not contain an RSA public key"
    assert cert_modulus.stdout.strip() == key_modulus.stdout.strip(), "Certificate does not correspond to new_key.pem"

    # Verify subject and issuer are equal and that the certificate validates its own signature.
    identity = subprocess.run(
        ["openssl", "x509", "-in", cert_file, "-noout", "-subject", "-issuer", "-nameopt", "RFC2253"],
        capture_output=True, text=True
    )
    assert identity.returncode == 0, "Failed to read certificate subject and issuer"
    identity_lines = [line.strip() for line in identity.stdout.splitlines() if "=" in line]
    assert len(identity_lines) == 2, "Certificate subject or issuer is missing"
    subject = identity_lines[0].split("=", 1)[1]
    issuer = identity_lines[1].split("=", 1)[1]
    assert subject == issuer, "Certificate is not self-issued"

    self_verify = subprocess.run(
        ["openssl", "verify", "-CAfile", cert_file, cert_file],
        capture_output=True, text=True
    )
    assert self_verify.returncode == 0, "Certificate is not validly self-signed"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
