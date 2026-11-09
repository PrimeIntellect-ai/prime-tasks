#!/bin/bash
set -e
mkdir -p /logs/verifier
/usr/local/bin/start_services.sh >/dev/null 2>&1 || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import stat
import subprocess
import tempfile
from pathlib import Path

PIN = "61942"
TARGET_HASH = "7d5668e21a24d52e37e9092ed1a8ea649692c81fbba8364cb05db37be1e65b75"
SALT = "_T0X1C_W4ST3_"
CRACKER = Path("/home/user/cracker")
PIN_FILE = Path("/home/user/recovered_pin.txt")


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=kwargs.pop("timeout", 60),
                          **kwargs)


def test_recovered_pin():
    pin_file = "/home/user/recovered_pin.txt"
    assert os.path.isfile(pin_file), f"File {pin_file} does not exist. The PIN was not saved."

    with open(pin_file, "r") as f:
        content = f.read().strip()

    assert content == "61942", f"The recovered PIN is incorrect. Expected '61942', got '{content}'."


def test_evidence_values_are_genuinely_derived():
    validated = []
    with tempfile.TemporaryDirectory() as td:
        for port in (8443, 8888):
            result = subprocess.run(
                ["openssl", "s_client", "-connect", f"127.0.0.1:{port}",
                 "-servername", "localhost", "-showcerts"],
                input="", text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                timeout=10,
            )
            match = re.search(r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----",
                              result.stdout, re.S)
            assert match, f"No TLS certificate was retrieved from port {port}"
            cert = Path(td) / f"{port}.pem"
            cert.write_text(match.group(0) + "\n")
            verify = run(["openssl", "verify", "-CAfile", "/home/user/evidence/ca.crt", str(cert)])
            if verify.returncode == 0:
                subject = run(["openssl", "x509", "-in", str(cert), "-noout",
                               "-subject", "-nameopt", "RFC2253"])
                assert subject.returncode == 0
                org = re.search(r"(?:^|,)O=([0-9a-fA-F]{64})(?:,|$)", subject.stdout.strip())
                assert org, "The CA-validated certificate has no SHA-256 Organization field"
                validated.append((port, org.group(1).lower()))

    assert validated == [(8443, TARGET_HASH)], \
        f"Expected only port 8443 to validate with target hash {TARGET_HASH}, got {validated}"

    strings = run(["strings", "/home/user/evidence/locker"])
    assert strings.returncode == 0
    assert SALT in strings.stdout, "The required salt was not found in the compiled locker binary"


def project_text():
    pieces = []
    allowed = {".rs", ".toml", ".txt", ".json", ".yaml", ".yml", ".conf"}
    for path in CRACKER.rglob("*"):
        if not path.is_file() or "target" in path.parts or path.name == "Cargo.lock":
            continue
        if path.suffix.lower() not in allowed:
            continue
        try:
            pieces.append(path.read_text(errors="replace"))
        except OSError:
            pass
    return "\n".join(pieces)


def build_rust_program():
    rust_sources = list(CRACKER.rglob("*.rs"))
    assert rust_sources, "/home/user/cracker does not contain Rust source code"

    executables = []
    manifest = CRACKER / "Cargo.toml"
    if manifest.is_file():
        clean = run(["runuser", "-u", "user", "--", "cargo", "clean"], cwd=CRACKER)
        assert clean.returncode == 0, f"cargo clean failed: {clean.stderr}"
        build = run(["runuser", "-u", "user", "--", "cargo", "build", "--release"],
                    cwd=CRACKER, timeout=180)
        assert build.returncode == 0, f"The Rust cracker does not compile: {build.stderr}"
        release = CRACKER / "target" / "release"
        if release.is_dir():
            for path in release.iterdir():
                if path.is_file() and os.access(path, os.X_OK) and path.suffix != ".d":
                    executables.append(path)
    else:
        outdir = Path(tempfile.mkdtemp(prefix="cracker-build-"))
        os.chmod(outdir, 0o777)
        for index, source in enumerate(rust_sources):
            if "fn main" not in source.read_text(errors="replace"):
                continue
            output = outdir / f"cracker-{index}"
            build = run(["runuser", "-u", "user", "--", "rustc", "-O",
                         str(source), "-o", str(output)], cwd=CRACKER, timeout=180)
            if build.returncode == 0 and output.is_file():
                executables.append(output)

    assert executables, "No executable Rust cracker was produced"
    return executables


def test_rust_cracker_is_present_and_performs_the_recovery():
    text = project_text()
    lowered = text.lower()
    assert TARGET_HASH in lowered, "The Rust cracker does not contain the validated certificate hash"
    assert SALT.lower() in lowered, "The Rust cracker does not contain the salt extracted from locker"
    assert any(marker in lowered for marker in ("sha256", "sha-256", "sha2", "sha_256")), \
        "The cracker contains no SHA-256 implementation or use"
    assert any(marker in lowered for marker in ("for ", "while ", "loop {")), \
        "The cracker contains no candidate-iteration loop"
    assert any(bound in lowered for bound in ("100000", "100_000", "99999", "99_999")), \
        "The cracker does not cover the 00000-99999 PIN search space"
    assert PIN not in text, "The expected PIN is hardcoded in the cracker source/configuration"

    executables = build_rust_program()
    original = PIN_FILE.read_bytes()
    recovered_by_program = False
    try:
        PIN_FILE.unlink(missing_ok=True)
        for executable in executables:
            PIN_FILE.unlink(missing_ok=True)
            result = run(["runuser", "-u", "user", "--", str(executable)],
                         cwd=CRACKER, timeout=120)
            output_pins = re.findall(r"(?<!\d)\d{5}(?!\d)", result.stdout + "\n" + result.stderr)
            file_pin = None
            if PIN_FILE.is_file():
                file_pin = PIN_FILE.read_text(errors="replace").strip()
            if result.returncode == 0 and (PIN in output_pins or file_pin == PIN):
                recovered_by_program = True
                break
        assert recovered_by_program, \
            "The compiled Rust program did not recover the PIN when run without the existing answer file"
    finally:
        PIN_FILE.write_bytes(original)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
