#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import pytest

ALPHA_PATH = "/home/user/system_alpha.csv"
BETA_PATH = "/home/user/system_beta.csv"
OUTPUT_PATH = "/home/user/matched_items.csv"


def load_vectors(path, id_column):
    with open(path, "r", newline="") as f:
        reader = csv.DictReader(f)
        return {
            row[id_column]: tuple(float(row[name]) for name in ("f1", "f2", "f3"))
            for row in reader
        }


def cosine(left, right):
    dot = sum(a * b for a, b in zip(left, right))
    left_norm = math.sqrt(sum(a * a for a in left))
    right_norm = math.sqrt(sum(b * b for b in right))
    assert left_norm > 0 and right_norm > 0, "Input vectors must be nonzero"
    return dot / (left_norm * right_norm)


def expected_matches():
    alphas = load_vectors(ALPHA_PATH, "item_id_alpha")
    betas = load_vectors(BETA_PATH, "item_id_beta")
    expected = {}

    for alpha_id, alpha_vector in alphas.items():
        scores = {
            beta_id: cosine(alpha_vector, beta_vector)
            for beta_id, beta_vector in betas.items()
        }
        best_score = max(scores.values())
        # The supplied data contains an exact maximum tie for A03. Either tied
        # item is a mathematically valid single highest-similarity selection.
        winners = {
            beta_id: score
            for beta_id, score in scores.items()
            if math.isclose(score, best_score, rel_tol=1e-12, abs_tol=1e-12)
        }
        expected[alpha_id] = winners

    return expected


def test_matched_items_exists():
    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."
    assert os.path.isfile(OUTPUT_PATH), f"Path {OUTPUT_PATH} is not a file."


def test_matched_items_contents():
    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."
    expected = expected_matches()

    with open(OUTPUT_PATH, "r", newline="") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail(f"File {OUTPUT_PATH} is empty.")

        assert header == ["item_id_alpha", "item_id_beta", "similarity"], \
            f"Incorrect headers in {OUTPUT_PATH}: expected ['item_id_alpha', 'item_id_beta', 'similarity'], got {header}"

        rows = list(reader)
        assert len(rows) == 5, f"Incorrect number of rows: expected 5, got {len(rows)}"

        seen_alphas = set()
        for row in rows:
            assert len(row) == 3, f"Row does not have 3 columns: {row}"
            alpha, beta, sim = row

            assert alpha in expected, f"Unexpected item_id_alpha: {alpha}"
            assert alpha not in seen_alphas, f"Duplicate item_id_alpha row: {alpha}"
            seen_alphas.add(alpha)

            valid_winners = expected[alpha]
            assert beta in valid_winners, \
                f"Mismatch for {alpha}: expected one of {sorted(valid_winners)}, got {beta}"

            try:
                sim_float = float(sim)
            except ValueError:
                pytest.fail(f"Similarity value for {alpha} is not a valid float: '{sim}'")

            formatted_sim = f"{sim_float:.4f}"
            expected_sim = f"{valid_winners[beta]:.4f}"
            assert formatted_sim == expected_sim, \
                f"Similarity mismatch for {alpha}: expected {expected_sim}, got {formatted_sim}"

        assert seen_alphas == set(expected.keys()), \
            f"Missing item_id_alpha rows: {set(expected.keys()) - seen_alphas}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
