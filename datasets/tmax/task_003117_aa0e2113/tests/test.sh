#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import base64
import json
import os
import random
import secrets
import subprocess
import tempfile
import pytest


def test_audit_filter_binary_exists():
    binary_path = "/home/user/audit_filter"
    source_path = "/home/user/audit_filter.c"
    assert os.path.isfile(source_path), f"Missing C source code at {source_path}"
    assert os.path.isfile(binary_path), f"Missing compiled binary at {binary_path}"
    assert os.access(binary_path, os.X_OK), f"Binary at {binary_path} is not executable"


def run_filter_on_corpus(binary_path, corpus_dir, expected_exit_code):
    if not os.path.isdir(corpus_dir):
        return  # Skip if holdout doesn't exist in this environment

    files = [f for f in os.listdir(corpus_dir) if os.path.isfile(os.path.join(corpus_dir, f))]
    assert len(files) > 0, f"Corpus directory {corpus_dir} is empty"

    failed_files = []
    for f in files:
        file_path = os.path.join(corpus_dir, f)
        result = subprocess.run([binary_path, file_path], capture_output=True)
        if result.returncode != expected_exit_code:
            failed_files.append(f)

    return len(files), failed_files


def test_adversarial_corpus_clean():
    binary_path = "/home/user/audit_filter"
    clean_dirs = ["/app/corpus/clean", "/app/corpus/holdout_clean"]

    total_clean = 0
    all_failed = []

    for d in clean_dirs:
        if os.path.isdir(d):
            total, failed = run_filter_on_corpus(binary_path, d, 0)
            total_clean += total
            all_failed.extend([f"{d}/{f}" for f in failed])

    assert len(all_failed) == 0, f"{len(all_failed)} of {total_clean} clean modified/rejected. Offending files: {', '.join(all_failed[:10])}"


def test_adversarial_corpus_evil():
    binary_path = "/home/user/audit_filter"
    evil_dirs = ["/app/corpus/evil", "/app/corpus/holdout_evil"]

    total_evil = 0
    all_failed = []

    for d in evil_dirs:
        if os.path.isdir(d):
            total, failed = run_filter_on_corpus(binary_path, d, 1)
            total_evil += total
            all_failed.extend([f"{d}/{f}" for f in failed])

    assert len(all_failed) == 0, f"{len(all_failed)} of {total_evil} evil bypassed/accepted. Offending files: {', '.join(all_failed[:10])}"


def test_audit_trail_log():
    log_path = "/home/user/audit_trail.log"
    assert os.path.isfile(log_path), f"Missing audit log at {log_path}"

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 100, f"Expected 100 entries in audit log, found {len(lines)}"

    clean_count = 0
    evil_count = 0

    for line in lines:
        if line.startswith("[CLEAN] /app/corpus/clean/"):
            clean_count += 1
        elif line.startswith("[EVIL] /app/corpus/evil/"):
            evil_count += 1
        else:
            pytest.fail(f"Invalid log entry format: {line}")

    assert clean_count == 50, f"Expected 50 [CLEAN] entries, found {clean_count}"
    assert evil_count == 50, f"Expected 50 [EVIL] entries, found {evil_count}"


def test_audit_trail_has_each_exact_evaluation_once():
    expected = []
    for label, directory in (("CLEAN", "/app/corpus/clean"), ("EVIL", "/app/corpus/evil")):
        for name in os.listdir(directory):
            path = os.path.join(directory, name)
            if os.path.isfile(path):
                expected.append(f"[{label}] {path}")

    assert len(expected) == 100, f"Expected exactly 100 corpus files, found {len(expected)}"
    with open("/home/user/audit_trail.log", "r") as f:
        actual = [line.strip() for line in f if line.strip()]

    assert len(actual) == len(set(actual)), "Audit log contains duplicate entries"
    assert set(actual) == set(expected), "Audit log does not contain each corpus file with its correct classification exactly once"


def encode_payload(text, password="trace"):
    raw = text.encode("utf-8")
    encoded = bytes(b ^ ord(password[i % len(password)]) for i, b in enumerate(raw))
    return base64.b64encode(encoded)


def test_randomized_neutral_path_payloads_and_rebuilt_source():
    signatures = ["<script>evil()</script>", "' OR 1=1 --", "\\x90\\x90\\x90\\x90\\x90"]
    cases = [None] * 10
    for signature in signatures:
        cases.extend([signature] * 5)
    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="audit_verify_") as workdir:
        rebuilt = os.path.join(workdir, secrets.token_hex(12))
        compile_result = subprocess.run(
            ["gcc", "/home/user/audit_filter.c", "-o", rebuilt],
            capture_output=True,
            text=True,
        )
        assert compile_result.returncode == 0, f"C source failed to compile: {compile_result.stderr}"

        generated = []
        for i, signature in enumerate(cases):
            record = {
                "id": secrets.randbelow(1000000000),
                "status": "ok",
                "val": secrets.randbelow(900000) + 100000,
                "nonce": secrets.token_hex(16),
            }
            decoded = "AUDIT_ENTRY:" + json.dumps(record, separators=(",", ":"))
            expected_code = 0
            if signature is not None:
                decoded += signature
                expected_code = 1

            path = os.path.join(workdir, secrets.token_hex(16) + ".dat")
            with open(path, "wb") as f:
                f.write(encode_payload(decoded))
            generated.append((path, expected_code))

        random.SystemRandom().shuffle(generated)
        for executable in ("/home/user/audit_filter", rebuilt):
            for path, expected_code in generated:
                result = subprocess.run([executable, path], capture_output=True, timeout=10)
                assert result.returncode == expected_code, (
                    f"{executable} misclassified a generated payload at a neutral randomized path"
                )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
