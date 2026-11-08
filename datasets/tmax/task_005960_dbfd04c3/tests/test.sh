#!/bin/bash
set +e
mkdir -p /logs/verifier

BACKUP_DIR=$(mktemp -d)
TEST_DIR=$(mktemp -d)
SWAPPED=0

cleanup() {
    if [ "$SWAPPED" -eq 1 ]; then
        cp "$BACKUP_DIR/ca.crt" /home/user/evidence/ca.crt 2>/dev/null || true
        cp "$BACKUP_DIR/cert_A.crt" /home/user/evidence/cert_A.crt 2>/dev/null || true
    fi
    rm -rf "$BACKUP_DIR" "$TEST_DIR" /tmp/recover_verifier_bin
}
trap cleanup EXIT

run_behavior_checks() {
    test -f /home/user/recover.rs || return 1

    rustc /home/user/recover.rs -o /tmp/recover_verifier_bin || return 1

    # Run the submitted program itself against the original evidence.
    rm -f /home/user/payload.bin
    (cd /home/user && /tmp/recover_verifier_bin) || return 1
    test -f /home/user/payload.bin || return 1

    cp /home/user/evidence/ca.crt "$BACKUP_DIR/ca.crt" || return 1
    cp /home/user/evidence/cert_A.crt "$BACKUP_DIR/cert_A.crt" || return 1

    # Build a fresh valid certificate containing an unpredictable OU payload.
    python3 - "$TEST_DIR" <<'PY' || return 1
import os, secrets, sys
path = sys.argv[1]
payload = secrets.token_bytes(31)
open(os.path.join(path, "expected.bin"), "wb").write(payload)
open(os.path.join(path, "payload.hex"), "w").write(payload.hex())
PY
    HEX_PAYLOAD=$(cat "$TEST_DIR/payload.hex") || return 1

    openssl req -x509 -newkey rsa:2048 -keyout "$TEST_DIR/ca.key" \
        -out "$TEST_DIR/ca.crt" -days 1 -nodes \
        -subj "/C=US/O=Verifier CA/CN=VerifierRoot" >/dev/null 2>&1 || return 1
    openssl req -newkey rsa:2048 -keyout "$TEST_DIR/leaf.key" \
        -out "$TEST_DIR/leaf.csr" -nodes \
        -subj "/C=US/O=Verifier/OU=${HEX_PAYLOAD}/CN=VerifierLeaf" >/dev/null 2>&1 || return 1
    openssl x509 -req -in "$TEST_DIR/leaf.csr" -CA "$TEST_DIR/ca.crt" \
        -CAkey "$TEST_DIR/ca.key" -CAcreateserial -out "$TEST_DIR/cert_A.crt" \
        -days 1 >/dev/null 2>&1 || return 1

    SWAPPED=1
    cp "$TEST_DIR/ca.crt" /home/user/evidence/ca.crt || return 1
    cp "$TEST_DIR/cert_A.crt" /home/user/evidence/cert_A.crt || return 1

    rm -f /home/user/payload.bin
    (cd /home/user && /tmp/recover_verifier_bin) || return 1
    cmp -s /home/user/payload.bin "$TEST_DIR/expected.bin" || return 1

    # Restore the original evidence and regenerate the required final artifact.
    cp "$BACKUP_DIR/ca.crt" /home/user/evidence/ca.crt || return 1
    cp "$BACKUP_DIR/cert_A.crt" /home/user/evidence/cert_A.crt || return 1
    SWAPPED=0
    rm -f /home/user/payload.bin
    (cd /home/user && /tmp/recover_verifier_bin) || return 1
}

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import hashlib
import pytest

def test_valid_cert_txt():
    """Test that /home/user/valid_cert.txt contains the correct valid certificate filename."""
    file_path = "/home/user/valid_cert.txt"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content == "cert_A.crt", f"Expected 'cert_A.crt' in {file_path}, but got '{content}'."

def test_recover_rs_exists():
    """Test that /home/user/recover.rs exists."""
    file_path = "/home/user/recover.rs"
    assert os.path.isfile(file_path), f"File {file_path} does not exist. You must write the Rust code here."

def test_payload_bin():
    """Test that /home/user/payload.bin exists and contains the correct decoded binary payload."""
    file_path = "/home/user/payload.bin"
    assert os.path.isfile(file_path), f"File {file_path} does not exist. Did you run your Rust program?"

    with open(file_path, "rb") as f:
        content = f.read()

    expected_bytes = b"#!/bin/bash\necho 'pwned'"
    assert content == expected_bytes, f"Payload content in {file_path} does not match the expected binary data."

    # Also verify the checksum just to be absolutely sure
    sha256_hash = hashlib.sha256(content).hexdigest()
    expected_hash = "568371353f868c2f2ce47754b5dfd4e68e0a81665a5d123e42fecfc32f41b315"
    assert sha256_hash == expected_hash, f"Expected SHA256 {expected_hash}, but got {sha256_hash}."
TEST_EOF

if run_behavior_checks && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
