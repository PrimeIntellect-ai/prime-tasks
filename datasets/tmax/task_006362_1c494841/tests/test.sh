#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import os
import re
import secrets
import subprocess


def extract_hash():
    proc_root = "/home/user/proc_dumps"
    for entry in sorted(os.listdir(proc_root)):
        cmdline = os.path.join(proc_root, entry, "cmdline")
        if not os.path.isfile(cmdline):
            continue
        with open(cmdline, "rb") as f:
            args = [arg for arg in f.read().split(b"\0") if arg]
        token = None
        for i, arg in enumerate(args):
            if arg == b"--auth-token" and i + 1 < len(args):
                token = args[i + 1]
                break
            if arg.startswith(b"--auth-token="):
                token = arg.split(b"=", 1)[1]
                break
        if token is not None:
            payload = base64.b64decode(token, validate=True).decode("utf-8")
            _, md5_hash = payload.split(":", 1)
            assert re.fullmatch(r"[0-9a-fA-F]{32}", md5_hash), "Extracted token does not contain a valid MD5 hash."
            return md5_hash.lower()
    raise AssertionError("No --auth-token argument was found in the process dumps.")


def pin_for_hash(md5_hash):
    for number in range(10000):
        pin = f"{number:04d}"
        if hashlib.md5(pin.encode()).hexdigest() == md5_hash:
            return pin
    raise AssertionError("The extracted MD5 hash does not correspond to a 4-digit PIN.")


def run_cracker(path, md5_hash, expected_pin):
    result = subprocess.run(
        [path, md5_hash],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, f"Cracker {path} exited with status {result.returncode}: {result.stderr}"
    assert result.stdout in (expected_pin, expected_pin + "\n"), (
        f"Cracker {path} must print only the matching PIN; got {result.stdout!r}."
    )


def test_cracker_files_exist():
    """Verify that the student created and compiled the C cracker program."""
    c_file = "/home/user/cracker.c"
    executable = "/home/user/cracker"

    assert os.path.isfile(c_file), f"The C source file is missing at {c_file}."
    assert os.path.isfile(executable), f"The compiled executable is missing at {executable}."
    assert os.access(executable, os.X_OK), f"The file at {executable} is not executable."
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"The file at {executable} is not a compiled executable."


def test_cracker_source_and_executable_work():
    """Compile the submitted C source and exercise both binaries on derived inputs."""
    rebuilt = "/tmp/rebuilt_cracker"
    compile_result = subprocess.run(
        ["gcc", "/home/user/cracker.c", "-o", rebuilt, "-lcrypto"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, f"cracker.c failed to compile: {compile_result.stderr}"

    extracted_hash = extract_hash()
    extracted_pin = pin_for_hash(extracted_hash)
    challenges = [(extracted_hash, extracted_pin)]

    chosen = {extracted_pin}
    while len(challenges) < 4:
        pin = f"{secrets.randbelow(10000):04d}"
        if pin in chosen:
            continue
        chosen.add(pin)
        challenges.append((hashlib.md5(pin.encode()).hexdigest(), pin))

    for executable in ("/home/user/cracker", rebuilt):
        for md5_hash, pin in challenges:
            run_cracker(executable, md5_hash, pin)


def test_csr_exists():
    """Verify that the CSR file was generated at the correct location."""
    csr_path = "/home/user/server.csr"
    assert os.path.isfile(csr_path), f"The Certificate Signing Request file is missing at {csr_path}."


def test_csr_subject():
    """Verify that the generated CSR contains the exact required Subject details."""
    csr_path = "/home/user/server.csr"

    result = subprocess.run(
        ["openssl", "req", "-in", csr_path, "-noout", "-subject"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Failed to read CSR subject. OpenSSL error: {result.stderr}"

    subject = result.stdout.strip()
    assert "C = US" in subject or "C=US" in subject, f"Country (C) is not 'US' in the CSR subject. Actual subject: {subject}"
    assert "O = SecCorp" in subject or "O=SecCorp" in subject, f"Organization (O) is not 'SecCorp' in the CSR subject. Actual subject: {subject}"
    assert "CN = internal.seccorp.local" in subject or "CN=internal.seccorp.local" in subject, f"Common Name (CN) is not 'internal.seccorp.local' in the CSR subject. Actual subject: {subject}"


def test_csr_signature_verification():
    """Verify that the CSR is valid and correctly signed by the private key."""
    csr_path = "/home/user/server.csr"

    result = subprocess.run(
        ["openssl", "req", "-in", csr_path, "-noout", "-verify"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"CSR signature verification failed. The CSR may be malformed or not signed properly. OpenSSL error: {result.stderr}"

    output = result.stdout + result.stderr
    assert "verify OK" in output, "CSR verification did not indicate success ('verify OK' not found in output)."


def test_csr_uses_encrypted_key():
    """Verify that the CSR public key is the one from encrypted.key."""
    pin = pin_for_hash(extract_hash())

    key_result = subprocess.run(
        ["openssl", "pkey", "-in", "/home/user/encrypted.key", "-passin", f"pass:{pin}", "-pubout", "-outform", "DER"],
        capture_output=True,
        timeout=15,
    )
    assert key_result.returncode == 0, f"Failed to unlock encrypted.key with the cracked PIN: {key_result.stderr.decode(errors='replace')}"

    csr_pub = subprocess.run(
        ["openssl", "req", "-in", "/home/user/server.csr", "-pubkey", "-noout"],
        capture_output=True,
        timeout=15,
    )
    assert csr_pub.returncode == 0, f"Failed to extract the CSR public key: {csr_pub.stderr.decode(errors='replace')}"

    csr_der = subprocess.run(
        ["openssl", "pkey", "-pubin", "-outform", "DER"],
        input=csr_pub.stdout,
        capture_output=True,
        timeout=15,
    )
    assert csr_der.returncode == 0, f"Failed to normalize the CSR public key: {csr_der.stderr.decode(errors='replace')}"
    assert csr_der.stdout == key_result.stdout, "The CSR was not generated using /home/user/encrypted.key."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
