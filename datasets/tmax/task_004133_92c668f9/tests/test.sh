#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import stat
import subprocess
import tempfile

FILTER_SCRIPT = "/home/user/filter.sh"
CLEAN_CORPUS_DIR = "/app/corpus/clean/"
EVIL_CORPUS_DIR = "/app/corpus/evil/"


def run_filter(path):
    try:
        return subprocess.run(
            [FILTER_SCRIPT, path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        ).returncode
    except subprocess.TimeoutExpired:
        return -999


def test_filter_script_exists_and_executable():
    assert os.path.isfile(FILTER_SCRIPT), f"Filter script not found at {FILTER_SCRIPT}"
    st = os.stat(FILTER_SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"Filter script {FILTER_SCRIPT} is not executable"
    with open(FILTER_SCRIPT, "rb") as f:
        assert f.readline().rstrip() == b"#!/bin/bash", "Filter must use #!/bin/bash"


def test_adversarial_corpus_verification():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]

    assert len(clean_files) > 0, "No files found in clean corpus"
    assert len(evil_files) > 0, "No files found in evil corpus"

    clean_failed = []
    evil_failed = []

    for clean_file in clean_files:
        if run_filter(clean_file) != 0:
            clean_failed.append(os.path.basename(clean_file))

    for evil_file in evil_files:
        if run_filter(evil_file) != 1:
            evil_failed.append(os.path.basename(evil_file))

    error_messages = []
    if clean_failed:
        error_messages.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected (expected exit code 0). Offending files: {', '.join(clean_failed[:10])}{'...' if len(clean_failed) > 10 else ''}")
    if evil_failed:
        error_messages.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed (expected exit code 1). Offending files: {', '.join(evil_failed[:10])}{'...' if len(evil_failed) > 10 else ''}")
    assert not error_messages, " | ".join(error_messages)


def test_content_based_classification_on_hidden_paths():
    cases = []
    for _ in range(40):
        n = secrets.randbelow(999999) + 1
        tail = secrets.token_hex(8).encode()
        cases.append((b"EVIL_ padding_data_" + str(n).encode() + b" DEADBEEF " + tail + b"\n", 1))

    clean_templates = [
        b"ordinary log entry DEADBEEF without exploit wrapper\n",
        b"EVIL_ harmless data without the recovered signature\n",
        b"EVIL_ padding_data_x DEADBEEF\n",
        b"EVIL_padding_data_123 DEADBEEF\n",
        b"prefix EVIL_ padding_data_123 DEADBEEF\n",
        b"EVIL_ padding_data_123 DEADBEE0\n",
        b"/app/corpus/evil/file_1.txt is only a pathname\n",
        b"Clean payload data with binary byte \x00 and DEADBEEF\n",
    ]
    for _ in range(40):
        cases.append((random.choice(clean_templates) + secrets.token_bytes(6), 0))

    random.SystemRandom().shuffle(cases)
    failures = []
    with tempfile.TemporaryDirectory(prefix="payload-check-") as td:
        for payload, expected in cases:
            path = os.path.join(td, secrets.token_hex(16))
            with open(path, "wb") as f:
                f.write(payload)
            actual = run_filter(path)
            if actual != expected:
                failures.append((expected, actual, payload[:80]))
    assert not failures, f"Hidden content tests failed: {failures[:5]}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
