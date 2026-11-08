#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import secrets
import subprocess

PROJECT = "/home/user/paper_recommender"
PAPERS = "/home/user/papers.json"
OUTPUT = "/home/user/recommendations.csv"
CARGO = "/root/.cargo/bin/cargo"


def compute_recommendations(docs):
    doc_tokens = [text.lower().split() for _, text in docs]
    vocab = list({term for tokens in doc_tokens for term in tokens})
    n_docs = len(docs)

    idf = {}
    for term in vocab:
        df = sum(1 for tokens in doc_tokens if term in tokens)
        idf[term] = math.log(n_docs / df)

    matrix = []
    for tokens in doc_tokens:
        counts = {term: tokens.count(term) for term in set(tokens)}
        total_terms = len(tokens)
        matrix.append([
            (counts.get(term, 0) / total_terms) * idf[term]
            for term in vocab
        ])

    def cosine(v1, v2):
        dot = sum(a * b for a, b in zip(v1, v2))
        norm1 = math.sqrt(sum(a * a for a in v1))
        norm2 = math.sqrt(sum(b * b for b in v2))
        if norm1 == 0 or norm2 == 0:
            return 0.0
        return dot / (norm1 * norm2)

    expected = {}
    score_lists = {}
    for i, (doc_id, _) in enumerate(docs):
        scores = []
        for j in range(n_docs):
            if i != j:
                scores.append((j, cosine(matrix[i], matrix[j])))
        scores.sort(key=lambda item: item[1], reverse=True)
        expected[doc_id] = [docs[scores[0][0]][0], docs[scores[1][0]][0]]
        score_lists[doc_id] = scores
    return expected, score_lists


def compute_expected_recommendations():
    docs = [
        ("doc1", "deep learning for computer vision"),
        ("doc2", "natural language processing with deep learning"),
        ("doc3", "computer vision applications in robotics"),
        ("doc4", "robotics and control systems"),
        ("doc5", "natural language processing and text mining"),
    ]
    return compute_recommendations(docs)[0]


def read_and_check_csv(expected):
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} does not exist. Did the program run successfully?"
    with open(OUTPUT, newline="") as handle:
        rows = list(csv.reader(handle))

    assert len(rows) == len(expected), f"Expected {len(expected)} rows in {OUTPUT}, found {len(rows)}"
    actual = {}
    for row in rows:
        assert len(row) == 3, f"Expected 3 columns per row, found {len(row)} in row: {row}"
        assert row[0] not in actual, f"Duplicate document {row[0]} in output"
        actual[row[0]] = [row[1], row[2]]

    assert set(actual) == set(expected), "Output document IDs do not match the input document IDs"
    for doc_id, expected_sims in expected.items():
        assert actual[doc_id] == expected_sims, (
            f"For {doc_id}, expected similar docs {expected_sims}, but got {actual[doc_id]}"
        )


def test_recommendations_csv_exists_and_correct():
    read_and_check_csv(compute_expected_recommendations())


def test_rust_code_fixed():
    main_rs_path = "/home/user/paper_recommender/src/main.rs"
    assert os.path.isfile(main_rs_path), "main.rs is missing."

    with open(main_rs_path, "r") as handle:
        content = handle.read()

    assert "let tf = (count / total_terms) as f64;" not in content, \
        "The intentional bug (integer division) is still present in main.rs"
    assert "as f64" in content, \
        "The fix should cast count and total_terms to f64 for proper division."


def make_random_case(rng, case_number):
    for _ in range(5000):
        n_docs = rng.choice([6, 7, 8])
        words = [f"term{case_number}_{i}_{rng.getrandbits(48):012x}" for i in range(n_docs * 6)]
        docs = []
        for i in range(n_docs):
            tokens = [f"unique{case_number}_{i}_{rng.getrandbits(40):010x}"]
            for word in words:
                if rng.random() < 0.30:
                    tokens.extend([word] * rng.randint(1, 3))
            if len(tokens) < 4:
                tokens.extend(rng.sample(words, 4))
            rng.shuffle(tokens)
            docs.append((f"case{case_number}_doc{i}_{rng.getrandbits(40):010x}", " ".join(tokens)))

        expected, score_lists = compute_recommendations(docs)
        # Avoid ambiguous rankings and make floating-point tie behavior irrelevant.
        if all(
            len(scores) >= 3
            and scores[0][1] - scores[1][1] > 1e-6
            and scores[1][1] - scores[2][1] > 1e-6
            for scores in score_lists.values()
        ):
            return docs, expected
    raise AssertionError("Could not generate a non-ambiguous recommendation dataset")


def run_project():
    result = subprocess.run(
        [CARGO, "run", "--quiet"],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, f"cargo run failed:\n{result.stdout}\n{result.stderr}"


def test_project_computes_unseen_inputs_when_executed():
    assert os.path.isfile(os.path.join(PROJECT, "Cargo.toml")), "Cargo.toml is missing"
    assert os.path.isfile(os.path.join(PROJECT, "src", "main.rs")), "src/main.rs is missing"

    with open(PAPERS, "rb") as handle:
        original_papers = handle.read()

    rng = random.Random(secrets.randbits(256))
    try:
        for case_number in range(3):
            docs, expected = make_random_case(rng, case_number)
            payload = [{"id": doc_id, "text": text} for doc_id, text in docs]
            with open(PAPERS, "w") as handle:
                json.dump(payload, handle)
            if os.path.exists(OUTPUT):
                os.remove(OUTPUT)
            run_project()
            read_and_check_csv(expected)
    finally:
        with open(PAPERS, "wb") as handle:
            handle.write(original_papers)
        # Restore the required final CSV for the provided dataset.
        subprocess.run(
            [CARGO, "run", "--quiet"],
            cwd=PROJECT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=180,
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
