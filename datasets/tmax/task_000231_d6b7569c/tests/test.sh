#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
import pytest

EVIL_CORPUS = "/app/corpora/evil"
CLEAN_CORPUS = "/app/corpora/clean"
ENTRY_POINT = "/home/user/manifest_filter"
MAGIC_HEADER = "AQUAMARINE_WHALE"

def test_manifest_filter_exists():
    assert os.path.exists(ENTRY_POINT), f"Executable not found at {ENTRY_POINT}"
    assert os.path.isfile(ENTRY_POINT), f"{ENTRY_POINT} is not a file"
    assert os.access(ENTRY_POINT, os.X_OK), f"{ENTRY_POINT} is not executable"

def test_clean_corpus_accepted():
    clean_files = [os.path.join(CLEAN_CORPUS, f) for f in os.listdir(CLEAN_CORPUS) if os.path.isfile(os.path.join(CLEAN_CORPUS, f))]
    assert clean_files, f"No files found in clean corpus: {CLEAN_CORPUS}"

    failed_files = []
    for filepath in clean_files:
        result = subprocess.run([ENTRY_POINT, filepath], capture_output=True)
        if result.returncode != 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified/rejected. Offending files: {', '.join(failed_files)}")

def test_evil_corpus_rejected():
    evil_files = [os.path.join(EVIL_CORPUS, f) for f in os.listdir(EVIL_CORPUS) if os.path.isfile(os.path.join(EVIL_CORPUS, f))]
    assert evil_files, f"No files found in evil corpus: {EVIL_CORPUS}"

    bypassed_files = []
    for filepath in evil_files:
        result = subprocess.run([ENTRY_POINT, filepath], capture_output=True)
        if result.returncode != 1:
            bypassed_files.append(os.path.basename(filepath))

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil bypassed. Offending files: {', '.join(bypassed_files)}")

def expected_result(manifest):
    lines = manifest.splitlines()
    if not lines or lines[0] != f"HEADER {MAGIC_HEADER}":
        return 1
    for line in lines[1:]:
        if line.startswith("FILE: "):
            path = line[len("FILE: "):]
            if path.startswith("/") or "../" in path:
                return 1
    return 0

def block(path, chunks, checksum):
    return f"FILE: {path}\nCHUNKS: {chunks}\nCHECKSUM: {checksum}\n"

def test_generated_hidden_manifests():
    token = secrets.token_hex(12)
    safe_a = f"project_{token}/src_{secrets.token_hex(5)}/main_{secrets.token_hex(4)}.c"
    safe_b = f"assets_{secrets.token_hex(5)}/file..name_{secrets.token_hex(4)}.dat"
    safe_c = f"..hidden_{secrets.token_hex(5)}/notes_{secrets.token_hex(4)}.txt"
    checksum_a = secrets.token_hex(32)
    checksum_b = secrets.token_hex(32)

    valid_single = f"HEADER {MAGIC_HEADER}\n" + block(safe_a, 2, checksum_a)
    valid_multiple = (f"HEADER {MAGIC_HEADER}\n" +
                      block(safe_a, 1, checksum_a) +
                      block(safe_b, 3, checksum_b) +
                      block(safe_c, 1, secrets.token_hex(32)))

    cases = [
        valid_single,
        valid_multiple,
        f"HEADER WRONG_{secrets.token_hex(10)}\n" + block(safe_a, 2, checksum_a),
        f"HEADER {MAGIC_HEADER}_{secrets.token_hex(5)}\n" + block(safe_a, 2, checksum_a),
        f"HEADER {MAGIC_HEADER}\n" + block(f"/tmp/{secrets.token_hex(8)}/payload", 1, checksum_a),
        f"HEADER {MAGIC_HEADER}\n" + block(f"../{secrets.token_hex(8)}/payload", 1, checksum_a),
        f"HEADER {MAGIC_HEADER}\n" + block(f"safe/{secrets.token_hex(4)}/../../escape", 1, checksum_a),
        (f"HEADER {MAGIC_HEADER}\n" + block(safe_a, 1, checksum_a) +
         block(f"nested/{secrets.token_hex(4)}/../escape", 1, checksum_b)),
    ]
    secrets.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix=f"manifest-{secrets.token_hex(10)}-") as directory:
        failures = []
        for manifest in cases:
            filepath = os.path.join(directory, secrets.token_hex(16))
            with open(filepath, "w", encoding="utf-8", newline="\n") as handle:
                handle.write(manifest)

            expected = expected_result(manifest)
            result = subprocess.run([ENTRY_POINT, filepath], capture_output=True, timeout=5)
            if result.returncode != expected:
                failures.append((expected, result.returncode))

        assert not failures, f"Generated manifest results were incorrect: {failures}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
