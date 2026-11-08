#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess
import tempfile
import pytest

MARKER = b"\xDE\xAD\xBE\xEF"


def test_bad_commit_identified():
    repo_path = "/home/user/pipeline"
    bad_commit_file = "/home/user/bad_commit.txt"

    assert os.path.isfile(bad_commit_file), f"File {bad_commit_file} not found"

    with open(bad_commit_file, "r") as f:
        student_commit = f.read().strip()

    result = subprocess.run(
        ["git", "-C", repo_path, "rev-parse", "HEAD~63"],
        capture_output=True, text=True, check=True
    )
    expected_commit = result.stdout.strip()

    assert student_commit == expected_commit, f"Expected bad commit {expected_commit}, but got {student_commit}"


def test_filter_script_adversarial_corpus():
    filter_script = "/home/user/filter.sh"
    assert os.path.isfile(filter_script), f"Filter script {filter_script} not found"

    evil_dir = "/app/corpus/evil"
    clean_dir = "/app/corpus/clean"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    assert len(evil_files) > 0, "No evil files found in corpus"
    assert len(clean_files) > 0, "No clean files found in corpus"

    evil_bypassed = []
    for ef in evil_files:
        result = subprocess.run(["bash", filter_script, ef], capture_output=True)
        if result.returncode != 1 or len(result.stdout) > 0:
            evil_bypassed.append(os.path.basename(ef))

    clean_modified = []
    for cf in clean_files:
        with open(cf, "rb") as f:
            expected_content = f.read()
        result = subprocess.run(["bash", filter_script, cf], capture_output=True)
        if result.returncode != 0 or result.stdout != expected_content:
            clean_modified.append(os.path.basename(cf))

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")

    assert not error_msgs, " | ".join(error_msgs)


def test_filter_detects_content_independent_of_path():
    filter_script = "/home/user/filter.sh"
    assert os.path.isfile(filter_script), f"Filter script {filter_script} not found"

    rng = random.SystemRandom()
    failures = []

    with tempfile.TemporaryDirectory(prefix="payload-check-") as tmpdir:
        # Reuse the exact same opaque pathname for both clean and evil contents,
        # so classification based on directory or filename cannot pass.
        candidate = os.path.join(tmpdir, os.urandom(12).hex())

        for case in range(24):
            size = rng.randint(4, 4096)
            while True:
                clean = os.urandom(size)
                if MARKER not in clean:
                    break

            if case % 3 == 0:
                offset = 0
            elif case % 3 == 1:
                offset = size - len(MARKER)
            else:
                offset = rng.randint(0, size - len(MARKER))

            evil = clean[:offset] + MARKER + clean[offset + len(MARKER):]
            variants = [(False, clean), (True, evil)]
            rng.shuffle(variants)

            for is_evil, content in variants:
                with open(candidate, "wb") as f:
                    f.write(content)

                result = subprocess.run(
                    ["bash", filter_script, candidate],
                    capture_output=True,
                    timeout=10,
                )

                if is_evil:
                    if result.returncode != 1 or result.stdout != b"":
                        failures.append(
                            f"case {case}: marker at byte {offset} was not rejected silently"
                        )
                elif result.returncode != 0 or result.stdout != content:
                    failures.append(
                        f"case {case}: clean content was rejected or modified"
                    )

    assert not failures, " | ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
