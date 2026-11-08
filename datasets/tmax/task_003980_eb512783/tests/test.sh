#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import secrets
import subprocess
import tempfile
import pytest
import jwt

SCRIPT_PATH = "/home/user/token_filter.py"
CLEAN_DIR = "/app/corpus/clean"
EVIL_DIR = "/app/corpus/evil"
SECRET = "bravo tango seven four niner omega"

def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."

def run_script_and_parse_output(directory):
    result = subprocess.run(
        ["python3", SCRIPT_PATH, directory],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Script failed with return code {result.returncode}\nStderr: {result.stderr}"

    accepts = set()
    rejects = set()

    for line in result.stdout.splitlines():
        line = line.strip()
        if line.startswith("ACCEPT: "):
            accepts.add(line[len("ACCEPT: "):].strip())
        elif line.startswith("REJECT: "):
            rejects.add(line[len("REJECT: "):].strip())

    return accepts, rejects

def test_clean_corpus():
    clean_files = set(os.listdir(CLEAN_DIR))
    assert len(clean_files) > 0, "Clean corpus is empty."

    accepts, rejects = run_script_and_parse_output(CLEAN_DIR)

    rejected_clean = clean_files.intersection(rejects)
    missing_clean = clean_files - accepts

    errors = []
    if rejected_clean:
        errors.append(f"{len(rejected_clean)} of {len(clean_files)} clean files were incorrectly rejected: {', '.join(rejected_clean)}")
    if missing_clean and not rejected_clean:
        errors.append(f"{len(missing_clean)} clean files were not accepted: {', '.join(missing_clean)}")

    assert not errors, "\n".join(errors)

def test_evil_corpus():
    evil_files = set(os.listdir(EVIL_DIR))
    assert len(evil_files) > 0, "Evil corpus is empty."

    accepts, rejects = run_script_and_parse_output(EVIL_DIR)

    accepted_evil = evil_files.intersection(accepts)
    missing_evil = evil_files - rejects

    errors = []
    if accepted_evil:
        errors.append(f"{len(accepted_evil)} of {len(evil_files)} evil files bypassed the filter and were accepted: {', '.join(accepted_evil)}")
    if missing_evil and not accepted_evil:
        errors.append(f"{len(missing_evil)} evil files were not rejected: {', '.join(missing_evil)}")

    assert not errors, "\n".join(errors)

def test_randomized_mixed_corpus():
    expected_accepts = set()
    expected_rejects = set()
    wrong_secret = secrets.token_urlsafe(32)

    with tempfile.TemporaryDirectory(prefix="jwt_validation_") as corpus_dir:
        for valid in ([True, False] * 12):
            filename = f"{secrets.token_hex(12)}.txt"
            payload = {
                "user": secrets.token_hex(10),
                "nonce": secrets.token_urlsafe(18),
                "admin": bool(secrets.randbits(1)),
            }
            signing_key = SECRET if valid else wrong_secret
            token = jwt.encode(payload, signing_key, algorithm="HS256")
            with open(os.path.join(corpus_dir, filename), "w") as token_file:
                token_file.write(token)

            if valid:
                expected_accepts.add(filename)
            else:
                expected_rejects.add(filename)

        accepts, rejects = run_script_and_parse_output(corpus_dir)

        assert accepts == expected_accepts, (
            f"Random mixed corpus ACCEPT results were incorrect. "
            f"Expected {sorted(expected_accepts)}, got {sorted(accepts)}"
        )
        assert rejects == expected_rejects, (
            f"Random mixed corpus REJECT results were incorrect. "
            f"Expected {sorted(expected_rejects)}, got {sorted(rejects)}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
