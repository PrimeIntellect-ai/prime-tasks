#!/bin/bash
set -e
mkdir -p /logs/verifier
export OMP_NUM_THREADS=1

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
from functools import lru_cache

import pytest

CLEANED_DATASET_PATH = "/home/user/cleaned_dataset.csv"
REMOVED_DUPLICATES_PATH = "/home/user/removed_duplicates.txt"

CANONICAL_ROWS = [
    {"id": 1, "description": "This is a high quality mechanical keyboard with red switches.", "confidence": 0.95},
    {"id": 2, "description": "This is a high quality mechanical keyboard with red switches.", "confidence": 0.90},
    {"id": 3, "description": "Short desc", "confidence": 0.99},
    {"id": 4, "description": "A premium ergonomic wireless mouse for gaming and productivity.", "confidence": 0.40},
    {"id": 5, "description": "A premium ergonomic wireless mouse for gaming and productivity.", "confidence": 0.88},
    {"id": 6, "description": "An ergonomic wireless mouse designed for premium gaming and work.", "confidence": 0.82},
    {"id": 7, "description": "A high-resolution 4K monitor perfect for video editing.", "confidence": 0.92},
    {"id": 8, "description": "High quality mechanical keyboard with blue switches.", "confidence": 0.85},
    {"id": 9, "description": "Standard office chair with lumbar support and adjustable armrests.", "confidence": 0.91},
    {"id": 10, "description": "Office chair with lumbar support and armrests.", "confidence": 0.91},
]


@lru_cache(maxsize=1)
def expected_result():
    # Compute the oracle independently from the canonical task input using the
    # exact model and similarity operation required by the instruction.
    import pandas as pd
    from sentence_transformers import SentenceTransformer
    from sklearn.metrics.pairwise import cosine_similarity

    frame = pd.DataFrame(CANONICAL_ROWS)
    valid = frame[
        (frame["confidence"] >= 0.80)
        & (frame["description"].str.len() > 15)
    ].copy()
    records = valid.to_dict("records")

    model = SentenceTransformer("all-MiniLM-L6-v2")
    embeddings = model.encode([row["description"] for row in records])
    similarities = cosine_similarity(embeddings)
    index_by_id = {int(row["id"]): i for i, row in enumerate(records)}

    # Process strongest candidates first. A lower-priority item is removed if
    # it duplicates an already retained higher-confidence (or lower-ID tie)
    # item. This leaves no retained pair above the threshold.
    priority = sorted(records, key=lambda row: (-float(row["confidence"]), int(row["id"])))
    kept_ids = []
    removed_ids = []
    for row in priority:
        row_id = int(row["id"])
        row_index = index_by_id[row_id]
        if any(similarities[row_index, index_by_id[kept_id]] > 0.85 for kept_id in kept_ids):
            removed_ids.append(row_id)
        else:
            kept_ids.append(row_id)

    expected_rows = {int(row["id"]): row for row in records if int(row["id"]) in kept_ids}
    return expected_rows, sorted(removed_ids), similarities, index_by_id


def read_cleaned_rows():
    with open(CLEANED_DATASET_PATH, "r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["id", "description", "confidence"], "Cleaned dataset header is incorrect."
        rows = list(reader)

    parsed = []
    for row in rows:
        assert None not in row, "A cleaned dataset row has extra columns."
        assert all(row[column] is not None for column in ["id", "description", "confidence"]), "A cleaned dataset row is malformed."
        try:
            parsed.append({
                "id": int(row["id"]),
                "description": row["description"],
                "confidence": float(row["confidence"]),
            })
        except (TypeError, ValueError):
            pytest.fail("Cleaned dataset IDs and confidence values must be numeric.")
    return parsed


def read_removed_ids():
    with open(REMOVED_DUPLICATES_PATH, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    try:
        return [int(line) for line in lines]
    except ValueError:
        pytest.fail("removed_duplicates.txt should contain only integer IDs.")


def test_cleaned_dataset_exists():
    assert os.path.exists(CLEANED_DATASET_PATH), f"The file {CLEANED_DATASET_PATH} is missing."
    assert os.path.isfile(CLEANED_DATASET_PATH), f"The path {CLEANED_DATASET_PATH} is not a file."


def test_removed_duplicates_exists():
    assert os.path.exists(REMOVED_DUPLICATES_PATH), f"The file {REMOVED_DUPLICATES_PATH} is missing."
    assert os.path.isfile(REMOVED_DUPLICATES_PATH), f"The path {REMOVED_DUPLICATES_PATH} is not a file."


def test_cleaned_dataset_content():
    rows = read_cleaned_rows()
    ids = [row["id"] for row in rows]

    # Phase 2 dropped IDs should definitely not be here
    assert 3 not in ids, "ID 3 should have been dropped in Phase 2 (length <= 15)."
    assert 4 not in ids, "ID 4 should have been dropped in Phase 2 (confidence < 0.80)."

    # Phase 4 dropped IDs (identical or obvious duplicates)
    assert 2 not in ids, "ID 2 should have been dropped in Phase 4 (identical to ID 1 with lower confidence)."
    assert 10 not in ids, "ID 10 should have been dropped in Phase 4 (duplicate of 9, equal confidence, higher ID)."


def test_removed_duplicates_content():
    removed_ids = read_removed_ids()

    assert removed_ids == sorted(removed_ids), "The IDs in removed_duplicates.txt must be sorted in ascending order."

    # Phase 2 drops should NOT be in this file
    assert 3 not in removed_ids, "ID 3 was dropped in Phase 2 and should NOT be in removed_duplicates.txt."
    assert 4 not in removed_ids, "ID 4 was dropped in Phase 2 and should NOT be in removed_duplicates.txt."

    # Obvious Phase 4 drops MUST be in this file
    assert 2 in removed_ids, "ID 2 was a duplicate dropped in Phase 4 and should be in removed_duplicates.txt."
    assert 10 in removed_ids, "ID 10 was a duplicate dropped in Phase 4 and should be in removed_duplicates.txt."


def test_complete_cleaned_dataset_matches_model_result():
    rows = read_cleaned_rows()
    expected_rows, _, similarities, index_by_id = expected_result()

    ids = [row["id"] for row in rows]
    assert len(ids) == len(set(ids)), "The cleaned dataset contains duplicate IDs."
    assert set(ids) == set(expected_rows), "The cleaned dataset omits retained rows or contains rows that should have been removed."

    for row in rows:
        expected = expected_rows[row["id"]]
        assert row["description"] == expected["description"], f"Description for ID {row['id']} was altered."
        assert row["confidence"] == pytest.approx(float(expected["confidence"]), abs=1e-12), f"Confidence for ID {row['id']} was altered."

    for position, left_id in enumerate(ids):
        for right_id in ids[position + 1:]:
            similarity = similarities[index_by_id[left_id], index_by_id[right_id]]
            assert similarity <= 0.85, f"Retained IDs {left_id} and {right_id} have cosine similarity greater than 0.85."


def test_complete_removal_log_matches_model_result():
    _, expected_removed_ids, _, _ = expected_result()
    removed_ids = read_removed_ids()
    assert removed_ids == expected_removed_ids, "The removal log must contain exactly all Phase 4 removals, sorted ascending."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
