#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import secrets
import string
import subprocess
from pathlib import Path

FILTER_PATH = "/home/user/filter"


def run_filter(data):
    result = subprocess.run(
        [FILTER_PATH], input=data, capture_output=True, timeout=3
    )
    return result.returncode


def test_filter_exists_and_executable():
    filter_path = Path("/home/user/filter")
    assert filter_path.exists(), f"Filter binary not found at {filter_path}"
    assert filter_path.is_file(), f"{filter_path} is not a file"
    assert os.access(filter_path, os.X_OK), f"Filter binary at {filter_path} is not executable"


def test_filter_against_adversarial_corpus():
    filter_path = "/home/user/filter"
    clean_corpus_dir = Path("/app/corpus/clean")
    evil_corpus_dir = Path("/app/corpus/evil")

    assert clean_corpus_dir.exists() and clean_corpus_dir.is_dir(), f"Clean corpus dir missing: {clean_corpus_dir}"
    assert evil_corpus_dir.exists() and evil_corpus_dir.is_dir(), f"Evil corpus dir missing: {evil_corpus_dir}"

    clean_files = list(clean_corpus_dir.iterdir())
    evil_files = list(evil_corpus_dir.iterdir())

    assert len(clean_files) > 0, "No files found in clean corpus"
    assert len(evil_files) > 0, "No files found in evil corpus"

    clean_failed = []
    evil_failed = []

    # Test clean corpus (expected exit code 0)
    for f in clean_files:
        if not f.is_file():
            continue
        with open(f, "rb") as stdin_file:
            result = subprocess.run([filter_path], stdin=stdin_file, capture_output=True)
            if result.returncode != 0:
                clean_failed.append(f.name)

    # Test evil corpus (expected exit code 1)
    for f in evil_files:
        if not f.is_file():
            continue
        with open(f, "rb") as stdin_file:
            result = subprocess.run([filter_path], stdin=stdin_file, capture_output=True)
            if result.returncode != 1:
                evil_failed.append(f.name)

    error_messages = []
    if evil_failed:
        error_messages.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")
    if clean_failed:
        error_messages.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/blocked: {', '.join(clean_failed)}")

    if error_messages:
        assert False, " | ".join(error_messages)


def test_generated_hidden_requests_and_protocol_validation():
    alphabet = string.ascii_letters + string.digits

    def token(min_len=4, max_len=40):
        n = min_len + secrets.randbelow(max_len - min_len + 1)
        return "".join(secrets.choice(alphabet) for _ in range(n))

    clean_cases = []
    evil_cases = []

    # Generated after the agent has finished. Pairs have matching total lengths,
    # preventing length- and known-corpus-based classifiers from succeeding.
    payloads = [
        "x';id;#",
        "x'&&id;#",
        "x'|id;#",
        "x'$(id)'",
        "x'`id`'",
        "x';echo${IFS}pwned;#",
    ]
    actions = ["READ", "WRITE", "UPDATE", "PING", "ARCHIVE"]

    for i in range(48):
        user = token()
        action = secrets.choice(actions)
        payload = secrets.choice(payloads)
        prefix = token(1, 30)
        suffix = token(1, 30)
        bad_data = prefix + payload + suffix
        good_data = token(len(bad_data), len(bad_data))
        clean_cases.append(f"USER: {user}\nACTION: {action}\nDATA: {good_data}\n".encode())
        evil_cases.append(f"USER: {user}\nACTION: {action}\nDATA: {bad_data}\n".encode())

    # Semicolons, pipes, dollar signs, backticks, redirects and ampersands are
    # harmless while they remain within the binary's single-quoted argument.
    safe_punctuation = [
        "notes; continue normally",
        "price=$25 and status=ok",
        "literal `text` marker",
        "left | right & center",
        "comparison a<b and c>d",
        "parentheses (ordinary data)",
    ]
    for text in safe_punctuation:
        clean_cases.append(
            f"USER: {token()}\nACTION: {secrets.choice(actions)}\nDATA: {text} {token()}\n".encode()
        )

    # The username is interpolated into the same shell command and is therefore
    # another injection point.
    for payload in payloads:
        bad_user = token(2, 10) + payload + token(2, 10)
        data = token(20, 60)
        evil_cases.append(
            f"USER: {bad_user}\nACTION: READ\nDATA: {data}\n".encode()
        )

    nonce = token(12, 20)
    malformed_cases = [
        f"ACTION: READ\nUSER: {nonce}\nDATA: value\n".encode(),
        f"USER: {nonce}\nDATA: value\n".encode(),
        f"USER: {nonce}\nACTION: READ\n".encode(),
        f"USER {nonce}\nACTION: READ\nDATA: value\n".encode(),
        f"USER: {nonce}\nACTION READ\nDATA: value\n".encode(),
        f"USER: {nonce}\nACTION: READ\nDATA value\n".encode(),
        f"USER: \nACTION: READ\nDATA: value\n".encode(),
        f"USER: {nonce}\nACTION: \nDATA: value\n".encode(),
        f"USER: {nonce}\nACTION: READ\nDATA: \n".encode(),
        f"USER: {nonce}\nACTION: READ\nDATA: value\nEXTRA: {token()}\n".encode(),
        f"USER: {'u' * 256}\nACTION: READ\nDATA: value\n".encode(),
        f"USER: {nonce}\nACTION: {'a' * 256}\nDATA: value\n".encode(),
        f"USER: {nonce}\nACTION: READ\nDATA: {'d' * 1024}\n".encode(),
    ]

    failures = []
    for idx, case in enumerate(clean_cases):
        rc = run_filter(case)
        if rc != 0:
            failures.append(f"generated clean case {idx} returned {rc}")

    for idx, case in enumerate(evil_cases):
        rc = run_filter(case)
        if rc != 1:
            failures.append(f"generated injection case {idx} returned {rc}")

    for idx, case in enumerate(malformed_cases):
        rc = run_filter(case)
        if rc != 1:
            failures.append(f"malformed protocol case {idx} returned {rc}")

    assert not failures, " | ".join(failures[:20])
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
