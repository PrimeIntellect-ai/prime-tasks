#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import secrets
import stat
import subprocess

import pytest

LOG_FILE = "/home/user/sec_events.log"
CERTS_FILE = "/home/user/revoked_certs.txt"
BIN_FILE = "/home/user/known_good.bin"
SOURCE_FILE = "/home/user/analyzer.c"
OUTPUT_FILE = "/home/user/compromised_ips.txt"
EXECUTABLE = "/tmp/submission_analyzer"
INPUT_FILES = (LOG_FILE, CERTS_FILE, BIN_FILE)


def get_expected_compromised_ips():
    """Dynamically calculate expected compromised IPs from the active files."""
    with open(CERTS_FILE, "r") as f:
        revoked_certs = {line.strip() for line in f if line.strip()}

    with open(BIN_FILE, "rb") as f:
        known_good_hash = hashlib.sha256(f.read()).hexdigest()

    expected_ips = set()
    with open(LOG_FILE, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split("|")
            if len(parts) != 4:
                continue
            ip, cert, csp, file_hash = parts
            if (cert in revoked_certs and
                    "default-src 'self'" not in csp and
                    file_hash != known_good_hash):
                expected_ips.add(ip)
    return expected_ips


def run_analyzer():
    if os.path.lexists(OUTPUT_FILE):
        os.unlink(OUTPUT_FILE)
    result = subprocess.run(
        [EXECUTABLE], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, (
        f"analyzer exited with status {result.returncode}: {result.stderr}"
    )
    assert os.path.isfile(OUTPUT_FILE), (
        f"The required output file {OUTPUT_FILE} was not created by analyzer."
    )


def read_actual_ips():
    with open(OUTPUT_FILE, "r") as f:
        return {line.strip() for line in f if line.strip()}


def assert_output_correct():
    expected_ips = get_expected_compromised_ips()
    actual_ips = read_actual_ips()
    missing_ips = expected_ips - actual_ips
    extra_ips = actual_ips - expected_ips
    errors = []
    if missing_ips:
        errors.append(f"Missing expected compromised IPs: {', '.join(missing_ips)}")
    if extra_ips:
        errors.append(
            "Found unexpected IPs that should not be marked compromised: "
            + ", ".join(extra_ips)
        )
    assert not missing_ips and not extra_ips, " | ".join(errors)


@pytest.fixture(scope="session", autouse=True)
def compile_and_restore_files():
    backups = {path: open(path, "rb").read() for path in INPUT_FILES}

    assert os.path.exists(SOURCE_FILE), f"Required source file {SOURCE_FILE} is missing."
    mode = os.stat(SOURCE_FILE).st_mode
    assert stat.S_ISREG(mode), f"{SOURCE_FILE} is not a regular source file."
    assert os.path.getsize(SOURCE_FILE) > 0, f"{SOURCE_FILE} is empty."

    build = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE_FILE, "-o", EXECUTABLE, "-lcrypto"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert build.returncode == 0, f"analyzer.c failed to compile:\n{build.stderr}"

    yield

    for path, data in backups.items():
        with open(path, "wb") as f:
            f.write(data)
    try:
        run_analyzer()
    except Exception:
        pass


def test_01_executable_uses_libcrypto_digest_api():
    dynamic = subprocess.check_output(["readelf", "-d", EXECUTABLE], text=True)
    assert re.search(r"Shared library: \[libcrypto(?:\.so[^]]*)?\]", dynamic), (
        "Compiled analyzer is not dynamically linked to OpenSSL libcrypto."
    )

    symbols = subprocess.check_output(["nm", "-D", EXECUTABLE], text=True)
    digest_api = re.compile(
        r"\bU\s+(?:"
        r"SHA256(?:_(?:Init|Update|Final))?|"
        r"EVP_Q_digest|EVP_Digest(?:Init(?:_ex2|_ex)?|Update|Final(?:_ex)?|$)|"
        r"BIO_f_md"
        r")(?:@|\s|$)"
    )
    assert digest_api.search(symbols), (
        "Compiled analyzer does not reference an OpenSSL SHA-256/digest operation."
    )


def test_02_output_file_exists_after_running_original_fixture():
    run_analyzer()
    assert os.path.isfile(OUTPUT_FILE), (
        f"The required output file {OUTPUT_FILE} was not created."
    )


def test_03_compromised_ips_correct_for_original_fixture():
    assert os.path.isfile(OUTPUT_FILE), (
        f"Cannot verify contents because {OUTPUT_FILE} is missing."
    )
    assert_output_correct()


def test_04_analyzer_parses_new_inputs_and_hashes_binary_dynamically():
    cert1 = secrets.token_hex(32)
    cert2 = secrets.token_hex(32)
    valid_cert = secrets.token_hex(32)
    while valid_cert in {cert1, cert2}:
        valid_cert = secrets.token_hex(32)

    payload1 = os.urandom(3073)
    payload2 = os.urandom(4099)
    hash1 = hashlib.sha256(payload1).hexdigest()
    hash2 = hashlib.sha256(payload2).hexdigest()
    bad_hash = hashlib.sha256(os.urandom(73)).hexdigest()

    ips = [f"198.51.100.{n}" for n in secrets.SystemRandom().sample(range(10, 240), 5)]

    with open(CERTS_FILE, "w") as f:
        f.write(cert1 + "\n" + cert2 + "\n")
    with open(BIN_FILE, "wb") as f:
        f.write(payload1)
    with open(LOG_FILE, "w") as f:
        f.write(f"{ips[0]}|{cert1}|script-src 'none'|{bad_hash}\n")
        f.write(f"{ips[1]}|{cert2}|default-src 'self'; img-src *|{bad_hash}\n")
        f.write(f"{ips[2]}|{valid_cert}|script-src 'unsafe-inline'|{bad_hash}\n")
        f.write(f"{ips[3]}|{cert1}|object-src 'none'|{hash1}\n")
        f.write(f"{ips[4]}|{cert2}|default-src *|{hash2}\n")
        f.write("malformed|line|only\n")

    run_analyzer()
    assert_output_correct()
    first_result = read_actual_ips()

    # Keep the logs unchanged and replace only the reference binary. The entries
    # containing hash1 and hash2 must exchange status if the binary is really hashed.
    with open(BIN_FILE, "wb") as f:
        f.write(payload2)

    run_analyzer()
    assert_output_correct()
    second_result = read_actual_ips()
    assert first_result != second_result, (
        "Output did not react to replacement of known_good.bin."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
