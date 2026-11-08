#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import resource
import secrets
import subprocess
import tempfile

import pytest

DETECTOR_PATH = "/home/user/detector"
SOURCE_PATH = "/home/user/detector.c"
EVIL_CORPUS_DIR = "/app/hidden_corpus/evil/"
CLEAN_CORPUS_DIR = "/app/hidden_corpus/clean/"


def run_detector(binary, path, timeout=10, memory_limit=None):
    preexec_fn = None
    if memory_limit is not None:
        def apply_limit():
            resource.setrlimit(resource.RLIMIT_AS, (memory_limit, memory_limit))
        preexec_fn = apply_limit
    return subprocess.run(
        [binary, path], capture_output=True, text=True,
        timeout=timeout, preexec_fn=preexec_fn
    )


def assert_classification(binary, path, evil, **kwargs):
    result = run_detector(binary, path, **kwargs)
    expected_code = 1 if evil else 0
    expected_output = "EVIL" if evil else "CLEAN"
    assert result.returncode == expected_code, (
        f"Wrong exit status for {os.path.basename(path)}: "
        f"expected {expected_code}, got {result.returncode}"
    )
    assert result.stdout.strip() == expected_output, (
        f"Wrong output for {os.path.basename(path)}: "
        f"expected {expected_output!r}, got {result.stdout.strip()!r}"
    )


def test_detector_exists_and_executable():
    """Verify that the compiled detector binary exists and is executable."""
    assert os.path.isfile(DETECTOR_PATH), f"Detector binary not found at {DETECTOR_PATH}"
    assert os.access(DETECTOR_PATH, os.X_OK), f"Detector binary at {DETECTOR_PATH} is not executable"
    with open(DETECTOR_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Detector must be a compiled ELF binary"


def test_source_exists_compiles_and_uses_posix_regex(tmp_path):
    assert os.path.isfile(SOURCE_PATH), f"C source not found at {SOURCE_PATH}"
    source = open(SOURCE_PATH, "r", encoding="utf-8", errors="replace").read()
    assert "regex.h" in source, "detector.c must include POSIX regex support"
    assert "regcomp" in source and "regexec" in source, "detector.c must use POSIX regex functions"

    rebuilt = tmp_path / "rebuilt_detector"
    result = subprocess.run(
        ["gcc", "-O2", SOURCE_PATH, "-o", str(rebuilt)],
        capture_output=True, text=True
    )
    assert result.returncode == 0, f"detector.c does not compile: {result.stderr}"

    symbols = subprocess.run(
        ["readelf", "-Ws", DETECTOR_PATH], capture_output=True, text=True, check=True
    ).stdout
    assert "regcomp" in symbols and "regexec" in symbols, (
        "Submitted detector binary must actually link to POSIX regex functions"
    )

    sample = tmp_path / secrets.token_hex(12)
    sample.write_text(
        '{\n  "metadata": "rebuild check"\n}\n'
        '<retry_policy>infinite</retry_policy>\n'
        '"force_duplicate_on_retry": true\n'
    )
    assert_classification(str(rebuilt), str(sample), True)


def test_evil_corpus_rejection():
    """Verify that all files in the evil corpus are rejected correctly."""
    if not os.path.isfile(DETECTOR_PATH):
        pytest.skip("Detector binary not found")

    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, f"No files found in {EVIL_CORPUS_DIR}"

    bypassed = []
    for filename in evil_files:
        file_path = os.path.join(EVIL_CORPUS_DIR, filename)
        result = subprocess.run([DETECTOR_PATH, file_path], capture_output=True, text=True)
        if result.returncode != 1 or result.stdout.strip() != "EVIL":
            bypassed.append(filename)

    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil bypassed. Offending files: {bypassed}")


def test_clean_corpus_acceptance():
    """Verify that all files in the clean corpus are accepted correctly."""
    if not os.path.isfile(DETECTOR_PATH):
        pytest.skip("Detector binary not found")

    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, f"No files found in {CLEAN_CORPUS_DIR}"

    modified = []
    for filename in clean_files:
        file_path = os.path.join(CLEAN_CORPUS_DIR, filename)
        result = subprocess.run([DETECTOR_PATH, file_path], capture_output=True, text=True)
        if result.returncode != 0 or result.stdout.strip() != "CLEAN":
            modified.append(filename)

    if modified:
        pytest.fail(f"{len(modified)} of {len(clean_files)} clean modified (incorrectly flagged). Offending files: {modified}")


def test_content_derived_cases_at_unlabelled_random_paths(tmp_path):
    rng = random.SystemRandom()
    cases = []
    for has_xml in (False, True):
        for has_json in (False, True):
            for _ in range(4):
                lines = [
                    '{',
                    f'  "metadata": "{secrets.token_hex(10)}"',
                    '}',
                    '<retry_policy>normal</retry_policy>',
                    '"force_duplicate_on_retry": false',
                    '<retry_policy>infinite </retry_policy>',
                    '"force_duplicate_on_retry" : true',
                ]
                if has_xml:
                    lines.append('<retry_policy>infinite</retry_policy>')
                if has_json:
                    lines.append('"force_duplicate_on_retry": true')
                rng.shuffle(lines)
                path = tmp_path / secrets.token_hex(16)
                path.write_text("\n".join(lines) + "\n")
                cases.append((path, has_xml and has_json))

    rng.shuffle(cases)
    for path, expected_evil in cases:
        assert_classification(DETECTOR_PATH, str(path), expected_evil)


def test_large_files_are_processed_under_bounded_memory(tmp_path):
    path = tmp_path / secrets.token_hex(16)
    target_size = 48 * 1024 * 1024
    block = (b'<stage id="ordinary">normal</stage>\n' * 2048)

    def create_large(include_second_marker):
        with open(path, "wb") as f:
            f.write(b'<retry_policy>infinite</retry_policy>\n')
            while f.tell() < target_size:
                f.write(block)
            if include_second_marker:
                f.write(b'"force_duplicate_on_retry": true\n')
            else:
                f.write(b'"force_duplicate_on_retry": false\n')

    limit = 32 * 1024 * 1024
    create_large(False)
    assert_classification(DETECTOR_PATH, str(path), False, timeout=30, memory_limit=limit)
    create_large(True)
    assert_classification(DETECTOR_PATH, str(path), True, timeout=30, memory_limit=limit)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
