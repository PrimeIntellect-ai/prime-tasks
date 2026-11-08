#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
import tempfile

import pytest

HOME = "/home/user"
SOURCE = f"{HOME}/analyze.c"
BINARY = f"{HOME}/analyze"
OUTPUT = f"{HOME}/flagged.txt"


def read_flagged():
    assert os.path.isfile(OUTPUT), f"Output file missing at {OUTPUT}"
    with open(OUTPUT, "r") as f:
        return [line.strip() for line in f if line.strip()]


def run_analyzer(path):
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    try:
        result = subprocess.run(
            [path], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=20
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Analyzer {path} timed out")
    assert os.path.isfile(OUTPUT), (
        f"Analyzer {path} did not create {OUTPUT}; exit={result.returncode}, "
        f"stderr={result.stderr}"
    )
    return read_flagged()


def quiet_run(args, **kwargs):
    result = subprocess.run(
        args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs
    )
    assert result.returncode == 0, (
        f"Command failed: {' '.join(args)}\n"
        f"stdout: {result.stdout!r}\nstderr: {result.stderr!r}"
    )
    return result


def test_analyze_c_exists():
    assert os.path.isfile(SOURCE), f"Source file missing at {SOURCE}"


def test_analyze_executable_exists():
    assert os.path.isfile(BINARY), f"Executable missing at {BINARY}"
    assert os.access(BINARY, os.X_OK), f"File at {BINARY} is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File at {BINARY} is not a compiled ELF executable"


def test_flagged_txt_correct():
    expected = ["client2.crt", "client3.crt"]
    assert read_flagged() == expected, f"Expected {expected} in {OUTPUT}, but got {read_flagged()}"


def test_installed_program_recomputes_original_output():
    expected = ["client2.crt", "client3.crt"]
    actual = run_analyzer(BINARY)
    assert actual == expected, f"Expected {expected} after executing analyzer, but got {actual}"


def test_program_and_source_on_fresh_randomized_inputs():
    compiled = "/tmp/analyze_from_source"
    build = subprocess.run(
        ["gcc", SOURCE, "-o", compiled, "-lssl", "-lcrypto"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert build.returncode == 0, f"analyze.c did not compile:\n{build.stderr}"

    backup_root = tempfile.mkdtemp(prefix="analyze-backup-")
    work = tempfile.mkdtemp(prefix="analyze-fixture-")
    original_files = ["ca.crt", "secret.key", "server.log", "flagged.txt"]
    try:
        shutil.copytree(f"{HOME}/certs", f"{backup_root}/certs")
        for name in original_files:
            path = f"{HOME}/{name}"
            if os.path.exists(path):
                shutil.copy2(path, f"{backup_root}/{name}")

        ca_key = f"{work}/ca.key"
        ca_crt = f"{work}/ca.crt"
        quiet_run([
            "openssl", "req", "-x509", "-sha256", "-nodes", "-days", "30",
            "-newkey", "rsa:2048", "-keyout", ca_key, "-out", ca_crt,
            "-subj", "/CN=VerifierRandomCA"
        ])

        token = secrets.token_hex(5)
        cert_specs = [
            (f"alpha_{token}.crt", True, False),
            (f"middle_{token}.crt", True, True),
            (f"zeta_{token}.crt", False, False),
        ]

        shutil.rmtree(f"{HOME}/certs")
        os.mkdir(f"{HOME}/certs")
        shutil.copy2(ca_crt, f"{HOME}/ca.crt")

        for index, (filename, valid, malicious) in enumerate(cert_specs):
            crt = f"{work}/{filename}"
            key = f"{work}/leaf{index}.key"
            if valid:
                csr = f"{work}/leaf{index}.csr"
                quiet_run([
                    "openssl", "req", "-new", "-newkey", "rsa:2048", "-nodes",
                    "-keyout", key, "-out", csr,
                    "-subj", f"/CN=RandomClient{index}-{token}"
                ])
                quiet_run([
                    "openssl", "x509", "-req", "-in", csr, "-CA", ca_crt,
                    "-CAkey", ca_key, "-CAcreateserial", "-out", crt, "-days", "30",
                    "-sha256"
                ])
            else:
                quiet_run([
                    "openssl", "req", "-x509", "-sha256", "-nodes", "-days", "30",
                    "-newkey", "rsa:2048", "-keyout", key, "-out", crt,
                    "-subj", f"/CN=UntrustedClient{index}-{token}"
                ])
            shutil.copy2(crt, f"{HOME}/certs/{filename}")

        key_bytes = secrets.token_bytes(32)
        with open(f"{HOME}/secret.key", "wb") as f:
            f.write(key_bytes)

        entries = []
        expected = []
        for filename, _, malicious in cert_specs:
            random_text = secrets.token_hex(12)
            plaintext = (
                f"POST /{random_text} EXEC_SHELL arg={secrets.token_hex(8)}"
                if malicious else
                f"GET /{random_text} HTTP/1.1 harmless={secrets.token_hex(8)}"
            ).encode()
            iv = secrets.token_bytes(16)
            encrypted = quiet_run([
                "openssl", "enc", "-aes-256-cbc", "-K", key_bytes.hex(),
                "-iv", iv.hex()
            ], input=plaintext).stdout
            entries.append(f"{filename} {iv.hex()}:{encrypted.hex()}")

            verification = subprocess.run(
                ["openssl", "verify", "-CAfile", f"{HOME}/ca.crt",
                 f"{HOME}/certs/{filename}"],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE
            )
            if verification.returncode != 0 or b"EXEC_SHELL" in plaintext:
                expected.append(filename)

        secrets.SystemRandom().shuffle(entries)
        with open(f"{HOME}/server.log", "w") as f:
            f.write("\n".join(entries) + "\n")
        expected.sort()

        installed_result = run_analyzer(BINARY)
        assert installed_result == expected, (
            f"Installed analyzer produced {installed_result}; expected {expected} "
            "for freshly generated certificates and payloads"
        )

        source_result = run_analyzer(compiled)
        assert source_result == expected, (
            f"Freshly compiled analyze.c produced {source_result}; expected {expected} "
            "for freshly generated certificates and payloads"
        )
    finally:
        shutil.rmtree(f"{HOME}/certs", ignore_errors=True)
        if os.path.isdir(f"{backup_root}/certs"):
            shutil.copytree(f"{backup_root}/certs", f"{HOME}/certs")
        for name in original_files:
            destination = f"{HOME}/{name}"
            backup = f"{backup_root}/{name}"
            if os.path.exists(backup):
                shutil.copy2(backup, destination)
            elif os.path.exists(destination):
                os.remove(destination)
        shutil.rmtree(backup_root, ignore_errors=True)
        shutil.rmtree(work, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
