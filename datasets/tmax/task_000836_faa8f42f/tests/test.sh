#!/bin/bash
mkdir -p /logs/verifier
reward=0
trap 'printf "%s\n" "$reward" > /logs/verifier/reward.txt' EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import re
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path


def test_cwe_identification():
    cwe_path = "/home/user/evidence/cwe.txt"
    assert os.path.isfile(cwe_path), f"Missing evidence file: {cwe_path}"

    with open(cwe_path, "r") as f:
        cwe_content = f.read().strip()

    valid_cwes = {"CWE-121", "CWE-120"}
    assert cwe_content in valid_cwes, f"Expected {cwe_path} to contain CWE-121 or CWE-120, but found '{cwe_content}'"


def test_c2_domain():
    c2_path = "/home/user/evidence/c2_domain.txt"
    assert os.path.isfile(c2_path), f"Missing evidence file: {c2_path}"

    with open(c2_path, "r") as f:
        c2_content = f.read().strip()

    expected_domain = "c2-alpha.malicious.local"
    assert c2_content == expected_domain, f"Expected C2 domain to be '{expected_domain}', but found '{c2_content}'"


def decode_reference(encoded):
    xored = base64.b64decode(encoded.strip(), validate=True)
    return bytes(b ^ 0x42 for b in xored)


def test_decoder_source_compiles_runs_and_decodes():
    source = Path("/home/user/workspace/decoder.c")
    payload = Path("/home/user/forensics/payload.enc")
    implant = Path("/home/user/evidence/implant.bin")

    assert source.is_file(), f"Missing decoder source file: {source}"
    original_encoded = payload.read_bytes()
    expected_original = decode_reference(original_encoded)
    assert b"SIG_DEADC0DE" in expected_original

    build_dir = Path(tempfile.mkdtemp(prefix="decoder_build_"))
    executable = build_dir / "decoder"
    try:
        compiled = subprocess.run(
            ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", str(source), "-o", str(executable)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert compiled.returncode == 0, f"decoder.c failed to compile:\n{compiled.stderr}"
        assert executable.is_file() and os.access(executable, os.X_OK)

        random_plaintexts = [secrets.token_bytes(37), secrets.token_bytes(513)]
        cases = [
            (base64.b64encode(bytes(b ^ 0x42 for b in plain)), plain)
            for plain in random_plaintexts
        ]
        cases.append((original_encoded, expected_original))

        for encoded, expected in cases:
            payload.write_bytes(encoded)
            if implant.exists() or implant.is_symlink():
                implant.unlink()
            run = subprocess.run(
                [str(executable)],
                cwd="/home/user/workspace",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
            assert run.returncode == 0, f"Compiled decoder exited with status {run.returncode}: {run.stderr!r}"
            assert implant.is_file(), "Compiled decoder did not create /home/user/evidence/implant.bin"
            assert implant.read_bytes() == expected, "Compiled decoder output does not equal Base64 decoding followed by XOR with 0x42"
    finally:
        payload.write_bytes(original_encoded)
        shutil.rmtree(build_dir, ignore_errors=True)

    implant_data = implant.read_bytes()
    assert implant_data == expected_original, "implant.bin is not the exact decoded original payload"
    assert b"SIG_DEADC0DE" in implant_data, "The decoded implant.bin does not contain the expected signature 'SIG_DEADC0DE'. Decoding/Decryption may have failed."


def run_yara(rule_path, target):
    result = subprocess.run(
        ["yara", "-r", str(rule_path), str(target)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"YARA failed for {target}: {result.stderr}"
    matches = []
    for line in result.stdout.splitlines():
        line = line.strip()
        if line:
            parts = line.split()
            assert len(parts) >= 2, f"Unexpected YARA output: {line!r}"
            matches.append((parts[0], parts[-1]))
    return matches


def test_yara_rule_exists_is_valid_and_detects_exact_signature():
    yar_path = Path("/home/user/evidence/implant.yar")
    assert yar_path.is_file(), f"Missing YARA rule file: {yar_path}"

    yar_content = yar_path.read_text()
    assert "rule " in yar_content, "The file implant.yar does not appear to contain a valid YARA rule structure (missing 'rule' keyword)."
    assert "SIG_DEADC0DE" in yar_content, "The YARA rule does not contain the expected signature string 'SIG_DEADC0DE'."

    implant_data = Path("/home/user/evidence/implant.bin").read_bytes()
    signatures = set(re.findall(rb"SIG_[0-9A-F]{8}", implant_data))
    assert signatures == {b"SIG_DEADC0DE"}, f"Expected one unique implant signature, found {signatures}"
    signature = next(iter(signatures))

    probe_dir = Path(tempfile.mkdtemp(prefix="yara_probe_"))
    try:
        positive = probe_dir / ("positive_" + secrets.token_hex(6))
        positive.write_bytes(secrets.token_bytes(19) + signature + secrets.token_bytes(23))
        positive_matches = run_yara(yar_path, positive)
        assert positive_matches == [("Implant_Rule", str(positive))], "Implant_Rule must detect a file containing the exact ASCII signature"

        negatives = [
            signature[:-1] + (b"F" if signature[-1:] != b"F" else b"E"),
            signature.lower(),
            secrets.token_bytes(80),
        ]
        for index, data in enumerate(negatives):
            negative = probe_dir / f"negative_{index}_{secrets.token_hex(6)}"
            negative.write_bytes(data)
            assert run_yara(yar_path, negative) == [], f"Implant_Rule incorrectly matched non-signature input {negative}"
    finally:
        shutil.rmtree(probe_dir, ignore_errors=True)

    system_dir = Path("/home/user/forensics/system_files")
    expected_paths = {
        "/home/user/forensics/system_files/crond_helper",
        "/home/user/forensics/system_files/sshd_monitor",
    }
    system_matches = run_yara(yar_path, system_dir)
    assert all(name == "Implant_Rule" for name, _ in system_matches), "Matches must be produced by the rule named Implant_Rule"
    assert {path for _, path in system_matches} == expected_paths, "The YARA rule did not identify exactly the infected system files"


def test_infected_files_list():
    infected_path = "/home/user/evidence/infected.txt"
    assert os.path.isfile(infected_path), f"Missing infected files list: {infected_path}"

    with open(infected_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_files = {
        "/home/user/forensics/system_files/crond_helper",
        "/home/user/forensics/system_files/sshd_monitor"
    }
    actual_files = set(lines)
    missing = expected_files - actual_files
    extra = actual_files - expected_files

    assert not missing, f"Missing expected infected files in {infected_path}: {missing}"
    assert not extra, f"Found extra (incorrect) files in {infected_path}: {extra}"
    assert len(lines) == 2, f"Expected exactly 2 infected files, but found {len(lines)}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    reward=1
fi
exit 0
