#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import re
import subprocess
import sys

import pytest

SCRIPT = "/home/user/process_data.py"
DATASET = "/home/user/data/articles.csv"
OUTPUT = "/home/user/output/metrics.txt"


def make_dataset(seed):
    rng = random.Random(seed)
    vocabulary = [f"term{i:03d}" for i in range(180)]
    rows = []
    for i in range(200):
        words = rng.choices(vocabulary, k=24)
        rows.append((" ".join(words), i % 2))

    from io import StringIO
    buffer = StringIO()
    writer = csv.writer(buffer, lineterminator="\n")
    writer.writerow(["text", "label"])
    writer.writerows(rows)
    return buffer.getvalue().encode("utf-8")


def expected_value():
    golden_script = r"""
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.model_selection import train_test_split
from sklearn.metrics.pairwise import cosine_similarity

df = pd.read_csv('/home/user/data/articles.csv')
text_train, text_test, y_train, y_test = train_test_split(
    df['text'], df['label'], test_size=0.2, random_state=42
)

vectorizer = TfidfVectorizer(max_features=100)
X_train = vectorizer.fit_transform(text_train)
X_test = vectorizer.transform(text_test)

sim = cosine_similarity(X_test, X_train)
max_sims = sim.max(axis=1)
avg_max_sim = max_sims.mean()
print(f"{avg_max_sim:.4f}")
"""
    result = subprocess.run(
        [sys.executable, "-c", golden_script],
        capture_output=True,
        text=True,
        check=True,
        timeout=60,
    )
    return float(result.stdout.strip())


def run_and_check():
    expected_val = expected_value()

    if os.path.lexists(OUTPUT):
        if os.path.isdir(OUTPUT):
            pytest.fail(f"Output path is a directory: {OUTPUT}")
        os.unlink(OUTPUT)

    result = subprocess.run(
        [sys.executable, SCRIPT],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"process_data.py did not run successfully (exit {result.returncode}).\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    assert os.path.exists(OUTPUT), f"Output file does not exist: {OUTPUT}"
    assert os.path.isfile(OUTPUT), f"Path is not a file: {OUTPUT}"

    with open(OUTPUT, "r") as f:
        raw = f.read()
    content = raw.strip()
    assert content, "The metrics.txt file is empty."
    assert re.fullmatch(r"[+-]?\d+\.\d{4}\n?", raw), (
        "metrics.txt must contain one number rounded to exactly 4 decimal places"
    )

    try:
        user_val = float(content)
    except ValueError:
        pytest.fail(f"The content of metrics.txt is not a valid float: {content}")

    assert abs(user_val - expected_val) < 1e-4, (
        f"The calculated mean maximum similarity is incorrect. "
        f"Expected approximately {expected_val:.4f}, but got {user_val:.4f}. "
        f"Make sure the data leakage bug is fixed correctly."
    )


def test_corrected_script_runs_and_computes_metrics():
    assert os.path.exists(SCRIPT), f"Required script does not exist: {SCRIPT}"
    assert os.path.isfile(SCRIPT), f"Script path is not a file: {SCRIPT}"

    with open(DATASET, "rb") as f:
        original_data = f.read()

    try:
        # Exercise the submitted script on verifier-generated inputs so a
        # precomputed metrics.txt or hard-coded answer cannot pass.
        for generated_data in (make_dataset(9137), make_dataset(27183)):
            with open(DATASET, "wb") as f:
                f.write(generated_data)
            run_and_check()

        # Preserve the original assertion against the task's actual dataset,
        # and leave the final output corresponding to that dataset.
        with open(DATASET, "wb") as f:
            f.write(original_data)
        run_and_check()
    finally:
        with open(DATASET, "wb") as f:
            f.write(original_data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
