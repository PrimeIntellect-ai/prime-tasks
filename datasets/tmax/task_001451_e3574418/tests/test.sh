#!/bin/bash
mkdir -p /logs/verifier
prep_ok=1

cat << 'WRAP_EOF' > /tmp/decode_payload_wrapper.c
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>

int main(int argc, char **argv) {
    int fd = open("/tmp/decode_payload_calls.log", O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd >= 0) {
        if (argc >= 3) {
            dprintf(fd, "%s\t%s\n", argv[1], argv[2]);
        } else {
            dprintf(fd, "INVALID\n");
        }
        close(fd);
    }
    execv("/app/decode_payload.verifier-real", argv);
    return 127;
}
WRAP_EOF

if [ ! -f /app/decode_payload ]; then
    prep_ok=0
elif ! mv /app/decode_payload /app/decode_payload.verifier-real; then
    prep_ok=0
elif ! chmod 700 /app/decode_payload.verifier-real; then
    prep_ok=0
elif ! gcc -O2 /tmp/decode_payload_wrapper.c -o /app/decode_payload; then
    prep_ok=0
elif ! chmod 755 /app/decode_payload; then
    prep_ok=0
fi

: > /tmp/decode_payload_calls.log
chmod 600 /tmp/decode_payload_calls.log 2>/dev/null || prep_ok=0

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import secrets
import subprocess
import pytest

SCRIPT_PATH = "/home/user/filter_uploads.sh"
EVIL_DIR = "/app/corpus/evil"
CLEAN_DIR = "/app/corpus/clean"
CALL_LOG = "/tmp/decode_payload_calls.log"

def run_script(payload: str) -> str:
    result = subprocess.run(
        ["bash", SCRIPT_PATH],
        input=payload,
        text=True,
        capture_output=True
    )
    return result.stdout.strip()

def test_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"

def test_evil_corpus():
    assert os.path.exists(EVIL_DIR), f"Missing evil corpus directory at {EVIL_DIR}"

    files = sorted(os.listdir(EVIL_DIR))
    assert len(files) > 0, f"No files found in {EVIL_DIR}"

    bypassed = []
    for f in files:
        file_path = os.path.join(EVIL_DIR, f)
        with open(file_path, "r") as fp:
            payload = fp.read().strip()

        output = run_script(payload)
        if output != "REJECT":
            bypassed.append(f)

    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(files)} evil bypassed. Offending files: {', '.join(bypassed)}")

def test_clean_corpus():
    assert os.path.exists(CLEAN_DIR), f"Missing clean corpus directory at {CLEAN_DIR}"

    files = sorted(os.listdir(CLEAN_DIR))
    assert len(files) > 0, f"No files found in {CLEAN_DIR}"

    modified = []
    for f in files:
        file_path = os.path.join(CLEAN_DIR, f)
        with open(file_path, "r") as fp:
            payload = fp.read().strip()

        output = run_script(payload)
        if output != "ACCEPT":
            modified.append(f)

    if modified:
        pytest.fail(f"{len(modified)} of {len(files)} clean modified. Offending files: {', '.join(modified)}")

def encode_payload(plaintext: str) -> str:
    raw = bytes(c ^ 0x42 for c in plaintext.encode())
    return base64.b64encode(raw).decode()

def run_unseen_case(plaintext: str, expected: str):
    payload = encode_payload(plaintext)
    with open(CALL_LOG, "w"):
        pass

    result = subprocess.run(
        ["bash", SCRIPT_PATH],
        input=payload,
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert result.stdout.strip() == expected, (
        f"Unseen payload was classified incorrectly; expected {expected}, "
        f"got {result.stdout!r}"
    )

    with open(CALL_LOG, "r") as fp:
        calls = [line.rstrip("\n").split("\t", 1) for line in fp]
    assert ["7391", payload] in calls, (
        "The submitted filter did not decode this input by invoking "
        "/app/decode_payload with the correct PIN and supplied payload"
    )

def test_randomized_unseen_payloads():
    token = secrets.token_hex(12)
    cases = [
        (f"uploads/{token}/../../../etc/passwd", "REJECT"),
        (f"images/..%2f..%2f{token}.php", "REJECT"),
        (f"assets/%2e%2e%2f{token}.txt", "REJECT"),
        (f"<script>alert({token!r})</script>", "REJECT"),
        (f'uploads/{token}.png\"><img src=x onerror=alert(1)>', "REJECT"),
        (f"javascript:alert('{token}')", "REJECT"),
        (f"images/{token}/avatar.png", "ACCEPT"),
        (f"documents/report_{token}.pdf", "ACCEPT"),
        (f"static/{token}/index.html", "ACCEPT"),
    ]
    for plaintext, expected in cases:
        run_unseen_case(plaintext, expected)
TEST_EOF

if [ "$prep_ok" -eq 1 ] && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
