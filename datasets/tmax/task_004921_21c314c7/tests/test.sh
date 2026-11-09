#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import secrets
import stat
import subprocess
import tempfile
import uuid

FILTER_SCRIPT = "/home/user/filter.sh"
EVIL_CORPUS_DIR = "/app/corpus/evil"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
BOM = b"\xef\xbb\xbf"
ENCODED_SECRET_PAYLOAD = base64.b64encode(b"99x-auth-secret-val\n")


def run_filter(path):
    try:
        return subprocess.run(
            [FILTER_SCRIPT, path], capture_output=True, timeout=5
        ).returncode
    except subprocess.TimeoutExpired:
        return None


def test_filter_script_exists_and_executable():
    assert os.path.isfile(FILTER_SCRIPT), f"Filter script not found at {FILTER_SCRIPT}"
    st = os.stat(FILTER_SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"Filter script at {FILTER_SCRIPT} is not executable"


def test_filter_script_behavior():
    # Preserve the original corpus assertions.
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]

    bypassed_evil = []
    modified_clean = []

    for evil_file in evil_files:
        if run_filter(evil_file) != 1:
            bypassed_evil.append(os.path.basename(evil_file))

    for clean_file in clean_files:
        if run_filter(clean_file) != 0:
            modified_clean.append(os.path.basename(clean_file))

    errors = []
    if bypassed_evil:
        errors.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_evil)}")
    if modified_clean:
        errors.append(f"{len(modified_clean)} of {len(clean_files)} clean modified (rejected): {', '.join(modified_clean)}")

    assert not errors, " | ".join(errors)


def test_generated_hidden_content_cases():
    # All cases use indistinguishable randomized paths in one private directory;
    # expected results are derived from the recovered payload signatures.
    cases = [
        b"",
        b"ordinary text\n",
        b'{"status":"ok","word":"secret"}\n',
        b"\xef",
        b"\xef\xbb",
        b"prefix\xef-middle\xbb-suffix\xbf",
        BOM,
        BOM + b'{"status":"ok"}',
        b'{"status":"ok"}' + BOM,
        b'{"before":true}' + BOM + b'{"after":true}',
        ENCODED_SECRET_PAYLOAD,
        b"prefix:" + ENCODED_SECRET_PAYLOAD + b":suffix",
        BOM + ENCODED_SECRET_PAYLOAD,
    ]

    # Add fresh random safe data and fresh payload placements on every run.
    for _ in range(12):
        blob = os.urandom(secrets.randbelow(192) + 1)
        while BOM in blob or ENCODED_SECRET_PAYLOAD in blob:
            blob = os.urandom(secrets.randbelow(192) + 1)
        cases.append(blob)

    for marker in (BOM, ENCODED_SECRET_PAYLOAD):
        for _ in range(8):
            prefix = os.urandom(secrets.randbelow(80))
            suffix = os.urandom(secrets.randbelow(80))
            cases.append(prefix + marker + suffix)

    secrets.SystemRandom().shuffle(cases)

    failures = []
    with tempfile.TemporaryDirectory(prefix="ingest-validation-") as tmpdir:
        for data in cases:
            path = os.path.join(tmpdir, uuid.uuid4().hex)
            with open(path, "wb") as f:
                f.write(data)

            expected = 1 if BOM in data or ENCODED_SECRET_PAYLOAD in data else 0
            actual = run_filter(path)
            if actual != expected:
                failures.append(
                    f"case {os.path.basename(path)} expected {expected}, got {actual}"
                )

    assert not failures, " | ".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
