#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import subprocess
import sys

SCRIPT_PATH = "/home/user/etl_pipeline.py"
CSV_PATH = "/home/user/recommendation_stability.csv"
EMBEDDINGS_PATH = "/home/user/word_embeddings.json"
SENTENCES_PATH = "/home/user/sentences.txt"


def run_submission():
    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"etl_pipeline.py failed with exit code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(CSV_PATH), f"Output file {CSV_PATH} does not exist."


def read_csv():
    with open(CSV_PATH, "r", encoding="utf-8", newline="") as f:
        return list(csv.reader(f))


def reference_rows(embeddings, sentences, include_margins=False):
    def sentence_embedding(words):
        vectors = [embeddings[word] for word in words if word in embeddings]
        assert vectors, "Generated test sentence unexpectedly has no known words"
        return [sum(values) / len(vectors) for values in zip(*vectors)]

    def cosine(a, b):
        denominator = math.sqrt(sum(x * x for x in a)) * math.sqrt(sum(x * x for x in b))
        assert denominator != 0.0, "Generated test case unexpectedly has a zero vector"
        return sum(x * y for x, y in zip(a, b)) / denominator

    assert len(sentences) == 10
    baselines = {i: sentence_embedding(sentences[i].split(" ")) for i in range(1, 10)}
    target_words = sentences[0].split(" ")
    rng = random.Random(42)
    counts = {i: 0 for i in range(1, 10)}
    margins = []

    for _ in range(100):
        sampled = rng.choices(target_words, k=len(target_words))
        target = sentence_embedding(sampled)
        scores = [(cosine(target, baselines[i]), i) for i in range(1, 10)]
        winner = max(scores, key=lambda item: (item[0], -item[1]))[1]
        counts[winner] += 1
        ordered_scores = sorted((score for score, _ in scores), reverse=True)
        margins.append(ordered_scores[0] - ordered_scores[1])

    rows = [[str(i), str(count)] for i, count in counts.items() if count]
    rows.sort(key=lambda row: (-int(row[1]), int(row[0])))
    result = [["neighbor_id", "count"]] + rows
    return (result, margins) if include_margins else result


def write_inputs(embeddings, sentences):
    with open(EMBEDDINGS_PATH, "w", encoding="utf-8") as f:
        json.dump(embeddings, f)
    with open(SENTENCES_PATH, "w", encoding="utf-8") as f:
        f.write("\n".join(sentences) + "\n")


def make_random_case():
    system_rng = random.SystemRandom()
    original_expected = [
        ["neighbor_id", "count"],
        ["5", "50"],
        ["1", "21"],
        ["8", "19"],
        ["9", "10"],
    ]

    for _ in range(1000):
        words = [f"token_{i}" for i in range(14)]
        embeddings = {
            word: [system_rng.uniform(-2.0, 2.0) for _ in range(5)]
            for word in words
        }
        target = [system_rng.choice(words) for _ in range(8)] + ["unknown_token"]
        system_rng.shuffle(target)
        sentences = [" ".join(target)]
        for _neighbor in range(9):
            length = system_rng.randint(2, 6)
            sentences.append(" ".join(system_rng.choice(words) for _ in range(length)))

        try:
            expected, margins = reference_rows(embeddings, sentences, include_margins=True)
        except AssertionError:
            continue
        if min(margins) > 1e-7 and expected != original_expected:
            return embeddings, sentences, expected

    raise AssertionError("Could not generate a numerically stable randomized test case")


def test_recommendation_stability_csv():
    assert os.path.isfile(SCRIPT_PATH), f"Required script {SCRIPT_PATH} does not exist."
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        compile(f.read(), SCRIPT_PATH, "exec")

    with open(EMBEDDINGS_PATH, "rb") as f:
        original_embeddings = f.read()
    with open(SENTENCES_PATH, "rb") as f:
        original_sentences = f.read()

    try:
        # Execute the submitted artifact on the supplied inputs before retaining
        # the original verifier's exact output assertion.
        run_submission()

        csv_path = "/home/user/recommendation_stability.csv"
        assert os.path.isfile(csv_path), f"Output file {csv_path} does not exist."

        expected_rows = [
            ["neighbor_id", "count"],
            ["5", "50"],
            ["1", "21"],
            ["8", "19"],
            ["9", "10"]
        ]

        with open(csv_path, 'r', encoding='utf-8') as f:
            reader = csv.reader(f)
            actual_rows = list(reader)

        assert actual_rows == expected_rows, f"CSV content does not match expected output. Got {actual_rows}, expected {expected_rows}"

        # Exercise the pipeline on an unpredictable input and independently
        # derive the expected recommendations from the specified algorithm.
        embeddings, sentences, expected = make_random_case()
        write_inputs(embeddings, sentences)
        run_submission()
        assert read_csv() == expected, (
            f"CSV content is incorrect for randomized inputs. Got {read_csv()}, expected {expected}"
        )

        # Explicitly check the smaller-ID tie-breaking rule.
        tie_embeddings = {
            "same": [1.0, 2.0, 3.0, 4.0, 5.0],
            "other": [2.0, 1.0, 0.5, 3.0, 4.0],
        }
        tie_sentences = ["same other same"] + ["same other" for _ in range(9)]
        tie_expected = reference_rows(tie_embeddings, tie_sentences)
        write_inputs(tie_embeddings, tie_sentences)
        run_submission()
        assert read_csv() == tie_expected, (
            f"CSV content is incorrect for tied similarities. Got {read_csv()}, expected {tie_expected}"
        )
    finally:
        with open(EMBEDDINGS_PATH, "wb") as f:
            f.write(original_embeddings)
        with open(SENTENCES_PATH, "wb") as f:
            f.write(original_sentences)
        try:
            run_submission()
        except Exception:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
