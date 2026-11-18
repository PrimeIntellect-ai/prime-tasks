#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess

PROJECT = "/home/user/nlp_tools"
MAIN_RS = os.path.join(PROJECT, "src/main.rs")
CORPUS = "/home/user/data/corpus.txt"
TOP_OUT = "/home/user/output/top_tokens.txt"
COV_OUT = "/home/user/output/covariance.csv"

ORIGINAL_CORPUS = """The quick brown fox jumps over the lazy dog.
The dog barks at the fox, but the fox is quick.
A quick brown dog is a happy dog.
Foxes are quick, but dogs are lazy.
The quick brown fox is quick and the lazy dog is lazy.
"""


def write_corpus(text):
    with open(CORPUS, "w", encoding="utf-8") as f:
        f.write(text)


def run_project(build=False):
    for path in (TOP_OUT, COV_OUT):
        if os.path.exists(path):
            os.remove(path)

    if build:
        subprocess.run(
            ["cargo", "build", "--quiet"], cwd=PROJECT,
            check=True, timeout=120, capture_output=True, text=True
        )

    subprocess.run(
        ["cargo", "run", "--quiet"], cwd=PROJECT,
        check=True, timeout=120, capture_output=True, text=True
    )

    assert os.path.isfile(TOP_OUT), f"Output file missing at {TOP_OUT}"
    assert os.path.isfile(COV_OUT), f"Output file missing at {COV_OUT}"


def read_outputs():
    with open(TOP_OUT, encoding="utf-8") as f:
        tokens = [line.strip() for line in f if line.strip()]
    with open(COV_OUT, encoding="utf-8") as f:
        matrix = [line.strip() for line in f if line.strip()]
    return tokens, matrix


def expected_covariance(counts, order):
    n = len(counts)
    columns = [[float(row[index]) for row in counts] for index in order]
    means = [sum(column) / n for column in columns]
    rows = []
    for i in range(3):
        values = []
        for j in range(3):
            covariance = sum(
                (columns[i][k] - means[i]) * (columns[j][k] - means[j])
                for k in range(n)
            ) / (n - 1)
            values.append(f"{covariance:.4f}")
        rows.append(",".join(values))
    return rows


def random_word(rng, used):
    while True:
        word = "w" + "".join(rng.choice(string.ascii_lowercase) for _ in range(9))
        if word not in used:
            used.add(word)
            return word


def test_project_behavior():
    assert os.path.isfile(MAIN_RS), f"main.rs is missing at {MAIN_RS}."

    # Build and execute against the supplied corpus. Outputs are removed first so
    # stale or pre-written files cannot satisfy these assertions.
    write_corpus(ORIGINAL_CORPUS)
    run_project(build=True)
    tokens, matrix = read_outputs()

    expected_tokens = ["the", "quick", "dog"]
    expected_matrix = [
        "1.8000,0.1500,0.0000",
        "0.1500,0.2000,0.0000",
        "0.0000,0.0000,0.5000",
    ]
    assert tokens == expected_tokens, f"Expected {expected_tokens}, got {tokens}"
    assert matrix == expected_matrix, f"Expected {expected_matrix}, got {matrix}"

    # Exercise the submitted program on an unpredictable corpus. The expected
    # tokens and sample covariance are independently derived here.
    rng = random.SystemRandom()
    used = set()
    words = [random_word(rng, used) for _ in range(3)]
    n_docs = rng.randint(5, 8)

    while True:
        counts = [[rng.randint(0, 4) for _ in range(3)] for _ in range(n_docs)]
        totals = [sum(row[i] for row in counts) for i in range(3)]
        if min(totals) > 2 and len(set(totals)) == 3:
            break

    order = sorted(range(3), key=lambda i: -totals[i])
    expected_tokens = [words[i] for i in order]
    expected_matrix = expected_covariance(counts, order)

    suffixes = ["!", "123,", "É.", "--"]
    docs = []
    for doc_index, row in enumerate(counts):
        encoded = []
        for word_index, count in enumerate(row):
            for occurrence in range(count):
                token = words[word_index]
                if (doc_index + occurrence + word_index) % 2 == 0:
                    token = token.upper()
                encoded.append(token + rng.choice(suffixes))

        # Each noise word occurs only once and cannot enter the top three.
        encoded.append(random_word(rng, used).upper() + "99É!")
        rng.shuffle(encoded)
        docs.append(" ".join(encoded))

    write_corpus("\n".join(docs) + "\n")
    run_project()
    tokens, matrix = read_outputs()

    assert tokens == expected_tokens, f"Dynamic top tokens: expected {expected_tokens}, got {tokens}"
    assert len(matrix) == 3, f"Covariance matrix should have 3 rows, got {len(matrix)}"
    for index, row in enumerate(matrix):
        assert len(row.split(",")) == 3, f"Covariance row {index} does not have 3 columns: {row}"
    assert matrix == expected_matrix, f"Dynamic covariance: expected {expected_matrix}, got {matrix}"


if __name__ == "__main__":
    test_project_behavior()
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
