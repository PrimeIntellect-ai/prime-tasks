#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile

import pytest
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

SCRIPT_PATH = "/home/user/spam_filter.py"
EVIL_CORPUS_DIR = "/app/eval_evil/"
CLEAN_CORPUS_DIR = "/app/eval_clean/"
THRESHOLD = 0.82
TEMPLATES = [
    "Earn money fast working from home",
    "Click the link to claim your prize",
    "Buy cheap luxury watches today",
]


def reference_result(review):
    matrix = TfidfVectorizer(stop_words="english").fit_transform([review] + TEMPLATES)
    similarities = cosine_similarity(matrix[0:1], matrix[1:]).ravel()
    return "EVIL" if float(similarities.max()) >= THRESHOLD else "CLEAN"


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"


def test_evil_corpus():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory not found at {EVIL_CORPUS_DIR}"
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, "No files found in evil corpus"

    failed_files = []
    for filename in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, filename)
        result = subprocess.run(["python", SCRIPT_PATH, filepath], capture_output=True, text=True)
        output = result.stdout.strip()
        if output != "EVIL":
            failed_files.append((filename, output))

    if failed_files:
        details = ", ".join([f"{f} (output: {out})" for f, out in failed_files])
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed. Failed files: {details}")


def test_clean_corpus():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory not found at {CLEAN_CORPUS_DIR}"
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, "No files found in clean corpus"

    failed_files = []
    for filename in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, filename)
        result = subprocess.run(["python", SCRIPT_PATH, filepath], capture_output=True, text=True)
        output = result.stdout.strip()
        if output != "CLEAN":
            failed_files.append((filename, output))

    if failed_files:
        details = ", ".join([f"{f} (output: {out})" for f, out in failed_files])
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files modified/flagged. Failed files: {details}")


def test_reference_derived_cases_at_unlabeled_paths():
    def noise(count):
        return " ".join("q" + secrets.token_hex(5) for _ in range(count))

    cases = []
    for template in TEMPLATES:
        cases.append(template)
        cases.append(noise(1) + " " + template + " " + noise(1))
        cases.append(template + " " + noise(secrets.choice(range(3, 8))))

    cases.extend([
        "The packaging was sturdy and delivery was prompt " + noise(2),
        "I have used this product for several months and it works reliably " + noise(1),
        "The color differs slightly from the photograph but the quality is good",
        "Customer support replaced the damaged item without any trouble " + noise(3),
        "This ordinary review discusses comfort durability and sizing " + noise(2),
    ])

    expected = [reference_result(review) for review in cases]
    assert "EVIL" in expected and "CLEAN" in expected

    failures = []
    with tempfile.TemporaryDirectory(prefix="review-cases-") as case_dir:
        for review, wanted in zip(cases, expected):
            filename = secrets.token_hex(12) + ".txt"
            path = os.path.join(case_dir, filename)
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(review + "\n")

            try:
                result = subprocess.run(
                    ["python", SCRIPT_PATH, path],
                    capture_output=True,
                    text=True,
                    timeout=15,
                )
            except subprocess.TimeoutExpired:
                failures.append((filename, wanted, "timed out"))
                continue

            if result.returncode != 0:
                failures.append((filename, wanted, f"exit {result.returncode}: {result.stderr!r}"))
            elif result.stdout != wanted + "\n":
                failures.append((filename, wanted, repr(result.stdout)))
            elif result.stderr != "":
                failures.append((filename, wanted, f"unexpected stderr: {result.stderr!r}"))

    if failures:
        pytest.fail(f"Reference-derived TF-IDF cases failed: {failures}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
