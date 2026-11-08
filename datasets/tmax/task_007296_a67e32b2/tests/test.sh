#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import hashlib

import numpy as np
import pandas as pd
import pytest
import torch
import torch.nn as nn
import torch.nn.functional as F


def test_recommendations_file():
    rec_path = '/home/user/etl_pipeline/recommendations.txt'
    assert os.path.isfile(rec_path), f"Missing {rec_path}"

    with open(rec_path, 'r') as f:
        content = f.read().strip()

    assert content, f"File {rec_path} is empty."

    parts = content.split(',')
    assert len(parts) == 3, f"Expected 3 comma-separated IDs in {rec_path}, found {len(parts)}."

    for p in parts:
        assert p.strip().isdigit(), f"Expected integer IDs in {rec_path}, found '{p}'."


def test_embeddings_csv_format_and_sort():
    emb_path = '/home/user/etl_pipeline/embeddings.csv'
    assert os.path.isfile(emb_path), f"Missing {emb_path}"

    with open(emb_path, 'r') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ['id', 'e0', 'e1', 'e2'], f"Incorrect header in {emb_path}: {header}"

        rows = list(reader)
        assert len(rows) == 100, f"Expected 100 rows in {emb_path}, found {len(rows)}."

        prev_id = -1
        for i, row in enumerate(rows):
            assert len(row) == 4, f"Row {i+1} does not have 4 columns."

            curr_id = int(row[0])
            assert curr_id > prev_id, f"IDs are not sorted ascending at row {i+1}."
            prev_id = curr_id

            for j in range(1, 4):
                val_str = row[j]
                assert '.' in val_str, f"Value {val_str} not rounded to 4 decimal places."
                decimals = val_str.split('.')[1]
                assert len(decimals) <= 4, f"Value {val_str} has more than 4 decimal places."


def test_reproducibility_file_and_md5():
    emb_path = '/home/user/etl_pipeline/embeddings.csv'
    rep_path = '/home/user/etl_pipeline/reproducibility.txt'

    assert os.path.isfile(emb_path), f"Missing {emb_path}"
    assert os.path.isfile(rep_path), f"Missing {rep_path}"

    with open(emb_path, 'rb') as f:
        actual_md5 = hashlib.md5(f.read()).hexdigest()

    with open(rep_path, 'r') as f:
        saved_md5 = f.read().strip()

    assert saved_md5 == actual_md5, f"MD5 hash in {rep_path} ({saved_md5}) does not match actual MD5 of {emb_path} ({actual_md5})."
    assert len(saved_md5) == 32, f"MD5 hash string should be 32 characters, got {len(saved_md5)}."


def _load_and_validate_inputs():
    data_path = '/home/user/etl_pipeline/data.csv'
    weights_path = '/home/user/etl_pipeline/model_weights.pth'
    assert os.path.isfile(data_path), f"Missing {data_path}"
    assert os.path.isfile(weights_path), f"Missing {weights_path}"

    actual_df = pd.read_csv(data_path, float_precision='round_trip')
    expected_columns = ['id'] + [f'f{i}' for i in range(10)]
    assert list(actual_df.columns) == expected_columns
    assert len(actual_df) == 100

    np.random.seed(1337)
    expected_ids = np.arange(1, 101)
    np.random.shuffle(expected_ids)
    expected_features = np.random.randn(100, 10)
    expected_df = pd.DataFrame(expected_features, columns=[f'f{i}' for i in range(10)])
    expected_df.insert(0, 'id', expected_ids)

    actual_sorted = actual_df.sort_values('id').reset_index(drop=True)
    expected_sorted = expected_df.sort_values('id').reset_index(drop=True)
    assert np.array_equal(actual_sorted['id'].to_numpy(), expected_sorted['id'].to_numpy()), "Input IDs were altered."
    assert np.array_equal(
        actual_sorted[[f'f{i}' for i in range(10)]].to_numpy(),
        expected_sorted[[f'f{i}' for i in range(10)]].to_numpy(),
    ), "Input features were altered."

    torch.manual_seed(1337)
    expected_model = nn.Sequential(
        nn.Linear(10, 5),
        nn.ReLU(),
        nn.Linear(5, 3),
    )
    expected_state = expected_model.state_dict()
    actual_state = torch.load(weights_path, map_location='cpu', weights_only=True)
    assert list(actual_state.keys()) == list(expected_state.keys()), "Model state_dict keys do not match the required architecture."
    for key in expected_state:
        assert torch.equal(actual_state[key], expected_state[key]), f"Model weight {key} was altered."

    model = nn.Sequential(
        nn.Linear(10, 5),
        nn.ReLU(),
        nn.Linear(5, 3),
    )
    model.load_state_dict(actual_state, strict=True)
    model.eval()
    return actual_sorted, model


def test_outputs_match_model_inference_and_similarity_search():
    sorted_df, model = _load_and_validate_inputs()
    features = torch.tensor(
        sorted_df[[f'f{i}' for i in range(10)]].to_numpy(),
        dtype=torch.float32,
    )
    with torch.no_grad():
        embeddings = model(features)

    ids = sorted_df['id'].astype(int).tolist()
    target_index = ids.index(42)
    similarities = F.cosine_similarity(
        embeddings,
        embeddings[target_index].unsqueeze(0),
        dim=1,
    )
    similarities[target_index] = -float('inf')
    top_indices = torch.argsort(similarities, descending=True)[:3].tolist()
    expected_recommendations = [ids[i] for i in top_indices]

    with open('/home/user/etl_pipeline/recommendations.txt', 'r') as f:
        actual_recommendations = [int(part.strip()) for part in f.read().strip().split(',')]
    assert actual_recommendations == expected_recommendations, (
        f"Incorrect recommendations: expected {expected_recommendations}, got {actual_recommendations}."
    )

    with open('/home/user/etl_pipeline/embeddings.csv', 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader)
        rows = list(reader)
    assert header == ['id', 'e0', 'e1', 'e2']
    assert len(rows) == len(ids)

    for index, row in enumerate(rows):
        expected_row = [str(ids[index])] + [f"{float(value):.4f}" for value in embeddings[index]]
        assert row == expected_row, (
            f"Incorrect embedding row for id {ids[index]}: expected {expected_row}, got {row}."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
