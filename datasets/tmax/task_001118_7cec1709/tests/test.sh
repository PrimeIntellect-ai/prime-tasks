#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat


def test_recovered_evidence_exists_and_permissions():
    evidence_path = "/home/user/recovered_evidence.txt"
    assert os.path.exists(evidence_path), f"Evidence file not found: {evidence_path}"
    assert os.path.isfile(evidence_path), f"Evidence path is not a file: {evidence_path}"

    file_stat = os.stat(evidence_path)
    permissions = stat.S_IMODE(file_stat.st_mode)
    assert permissions == 0o400, (
        f"Incorrect permissions on {evidence_path}. Expected 0400, got {oct(permissions)}"
    )


def test_recovered_evidence_contents():
    log_path = "/home/user/exfil.log"
    assert os.path.exists(log_path), f"Log file missing: {log_path}"

    with open(log_path, "r") as f:
        log_content = f.read()

    hex_strings = re.findall(r"auth_token=([0-9a-fA-F]+)", log_content)
    assert hex_strings, "Could not find auth_token data in log file to compute expected truth"

    combined_hex = "".join(hex_strings)
    raw_bytes = bytes.fromhex(combined_hex)
    xor_key = 0x4F
    expected_bytes = bytes([b ^ xor_key for b in raw_bytes])
    expected_text = expected_bytes.decode("utf-8", errors="replace")

    evidence_path = "/home/user/recovered_evidence.txt"
    assert os.path.exists(evidence_path), f"Evidence file not found: {evidence_path}"

    with open(evidence_path, "r") as f:
        actual_content = f.read()

    assert actual_content.strip() == expected_text.strip(), (
        f"Contents of {evidence_path} do not match the expected decrypted data. "
        f"Expected: '{expected_text}', Got: '{actual_content}'"
    )
TEST_EOF

backup_dir=""
cleanup() {
    if [ -n "$backup_dir" ] && [ -d "$backup_dir" ]; then
        rm -f /home/user/exfil.log /home/user/recovered_evidence.txt
        [ ! -e "$backup_dir/exfil.log" ] || cp -a "$backup_dir/exfil.log" /home/user/exfil.log
        [ ! -e "$backup_dir/recovered_evidence.txt" ] || cp -a "$backup_dir/recovered_evidence.txt" /home/user/recovered_evidence.txt
        rm -rf "$backup_dir"
    fi
    rm -f /tmp/submitted_decoder /tmp/decoder_expected.bin
}
trap cleanup EXIT

run_checks() {
    # Preserve the original final-state assertions.
    python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || return 1

    # The requested artifact must be an actual C source file that compiles.
    [ -f /home/user/decoder.c ] || { echo "Missing /home/user/decoder.c"; return 1; }
    [ ! -L /home/user/decoder.c ] || { echo "/home/user/decoder.c must not be a symlink"; return 1; }
    gcc -std=c11 -Wall -Wextra -O2 /home/user/decoder.c -o /tmp/submitted_decoder || return 1
    [ -x /tmp/submitted_decoder ] || return 1

    backup_dir=$(mktemp -d /tmp/decoder-verifier.XXXXXX) || return 1
    chmod 700 "$backup_dir"
    cp -a /home/user/exfil.log "$backup_dir/exfil.log" || return 1
    cp -a /home/user/recovered_evidence.txt "$backup_dir/recovered_evidence.txt" || return 1

    # Generate a fresh log so a precomputed evidence file cannot satisfy the test.
    python3 - << 'PY' || return 1
import secrets
import string

alphabet = string.ascii_letters + string.digits + " _-:/."
parts = []
for length in (19, 27, 15):
    parts.append("".join(secrets.choice(alphabet) for _ in range(length)).encode())

encoded = [bytes(b ^ 0x4F for b in part).hex() for part in parts]
log = (
    "GET /first HTTP/1.1\n"
    "Host: challenge.local\n"
    f"Cookie: session_id=noise; auth_token={encoded[0]}; theme=dark\n\n"
    "POST /second HTTP/1.1\n"
    "Host: challenge.local\n"
    f"Cookie: auth_token={encoded[1]}; other=value\n\n"
    "GET /third HTTP/1.1\n"
    "Host: challenge.local\n"
    f"Cookie: auth_token={encoded[2]}\n"
)
with open("/home/user/exfil.log", "w") as f:
    f.write(log)
with open("/tmp/decoder_expected.bin", "wb") as f:
    f.write(b"".join(parts))
PY
    chmod 644 /home/user/exfil.log || return 1
    chmod 600 /tmp/decoder_expected.bin || return 1
    rm -f /home/user/recovered_evidence.txt

    # Execute the submitted C implementation against the fresh challenge.
    timeout 10s runuser -u user -- sh -c 'cd /home/user && /tmp/submitted_decoder' || return 1
    [ -f /home/user/recovered_evidence.txt ] || return 1

    python3 - << 'PY' || return 1
with open("/tmp/decoder_expected.bin", "rb") as f:
    expected = f.read()
with open("/home/user/recovered_evidence.txt", "rb") as f:
    actual = f.read()
assert actual.strip() == expected.strip(), (
    "The compiled decoder did not extract, concatenate, and decrypt the fresh auth_token values"
)
PY
}

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
