#!/bin/bash
set -e
mkdir -p /logs/verifier

MARKER=$(mktemp /tmp/c2_decoder_used.XXXXXX)
REAL_DECODER=$(mktemp /app/.c2_decoder.real.XXXXXX)
rm -f "$REAL_DECODER"

cleanup() {
    rm -f /app/c2_decoder
    if [ -e "$REAL_DECODER" ]; then
        mv "$REAL_DECODER" /app/c2_decoder
        chmod +x /app/c2_decoder
    fi
    rm -f "$MARKER"
}
trap cleanup EXIT

mv /app/c2_decoder "$REAL_DECODER"
cat > /app/c2_decoder <<EOF
#!/bin/sh
printf 'used\n' >> '$MARKER'
exec '$REAL_DECODER' "\$@"
EOF
chmod +x /app/c2_decoder
export DECODER_MARKER="$MARKER"

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import base64
import os
import random
import secrets
import subprocess
import tempfile
import pytest

CLASSIFIER_PATH = "/home/user/classifier"
CLEAN_CORPUS_DIR = "/var/test_corpus/clean"
EVIL_CORPUS_DIR = "/var/test_corpus/evil"
DECODER_MARKER = os.environ["DECODER_MARKER"]

def test_classifier_exists_and_executable():
    assert os.path.exists(CLASSIFIER_PATH), f"Classifier script not found at {CLASSIFIER_PATH}"
    assert os.path.isfile(CLASSIFIER_PATH), f"{CLASSIFIER_PATH} is not a file"
    assert os.access(CLASSIFIER_PATH, os.X_OK), f"Classifier script at {CLASSIFIER_PATH} is not executable"

def test_clean_corpus():
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, "Clean corpus is empty"

    failed_files = []
    for filename in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, filename)
        try:
            result = subprocess.run([CLASSIFIER_PATH, filepath], capture_output=True, text=True, timeout=5)
            output = result.stdout.strip()
            if output != "CLEAN":
                failed_files.append((filename, output))
        except Exception as e:
            failed_files.append((filename, str(e)))

    if failed_files:
        error_msg = f"{len(failed_files)} of {len(clean_files)} clean files failed (were not classified as CLEAN).\n"
        error_msg += "Offending files:\n"
        for f, out in failed_files[:10]:
            error_msg += f"  {f}: output '{out}'\n"
        if len(failed_files) > 10:
            error_msg += "  ...\n"
        pytest.fail(error_msg)

def test_evil_corpus():
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, "Evil corpus is empty"

    failed_files = []
    for filename in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, filename)
        try:
            result = subprocess.run([CLASSIFIER_PATH, filepath], capture_output=True, text=True, timeout=5)
            output = result.stdout.strip()
            if output != "EVIL":
                failed_files.append((filename, output))
        except Exception as e:
            failed_files.append((filename, str(e)))

    if failed_files:
        error_msg = f"{len(failed_files)} of {len(evil_files)} evil files bypassed (were not classified as EVIL).\n"
        error_msg += "Offending files:\n"
        for f, out in failed_files[:10]:
            error_msg += f"  {f}: output '{out}'\n"
        if len(failed_files) > 10:
            error_msg += "  ...\n"
        pytest.fail(error_msg)

def obfuscate(text):
    raw = text.encode("utf-8")
    return base64.b64encode(bytes(c ^ 0x5A for c in raw))

def test_randomized_paths_and_decoder_use():
    nonce = secrets.token_hex(8)
    cases = [
        ("CLEAN", f"GET /news/{nonce}.html HTTP/1.1\nHost: example.com"),
        ("CLEAN", f"POST /account HTTP/1.1\nHost: example.com\n\nname=user_{nonce}&theme=blue"),
        ("CLEAN", f"GET /assets/logo-{nonce}.png HTTP/1.1\nHost: static.example.com"),
        ("EVIL", f"GET /search?q=<script>alert('{nonce}')</script> HTTP/1.1\nHost: example.com"),
        ("EVIL", f"GET /image?name=x onerror=alert('{nonce}') HTTP/1.1\nHost: example.com"),
        ("EVIL", f"POST /login HTTP/1.1\nHost: example.com\n\nuser=admin' OR '1'='1&n={nonce}"),
        ("EVIL", f"GET /profile?id=1; DROP TABLE users HTTP/1.1\nHost: example.com\nX-Request: {nonce}"),
        ("EVIL", f"GET /lookup?q=UNION SELECT username,password FROM users HTTP/1.1\nHost: example.com\nX-Request: {nonce}"),
        ("EVIL", f"GET /redirect?url=javascript:alert('{nonce}') HTTP/1.1\nHost: example.com"),
    ]
    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="entries_") as directory:
        for expected, plaintext in cases:
            path = os.path.join(directory, secrets.token_hex(12))
            with open(path, "wb") as entry:
                entry.write(obfuscate(plaintext))

            open(DECODER_MARKER, "w").close()
            result = subprocess.run(
                [CLASSIFIER_PATH, path], capture_output=True, text=True, timeout=5
            )

            assert result.returncode == 0, f"Classifier exited with {result.returncode}: {result.stderr}"
            assert result.stdout.strip() == expected, (
                f"Randomized entry expected {expected}, got {result.stdout!r}"
            )
            assert os.path.getsize(DECODER_MARKER) > 0, (
                "Classifier did not invoke /app/c2_decoder for an input entry"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
