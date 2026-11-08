#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import numpy as np
import pandas as pd
from sklearn.decomposition import PCA
from sklearn.metrics import pairwise_distances


def test_pca_components_file():
    filepath = "/home/user/pca_components.txt"
    assert os.path.isfile(filepath), f"File not found: {filepath}"

    with open(filepath, "r") as f:
        content = f.read().strip()

    assert content.isdigit(), f"Expected an integer in {filepath}, got: {content}"
    assert int(content) > 0, "PCA components must be greater than 0"


def test_removed_ids_file():
    filepath = "/home/user/removed_ids.txt"
    assert os.path.isfile(filepath), f"File not found: {filepath}"

    with open(filepath, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    removed_ids = []
    for line in lines:
        assert line.lstrip('-').isdigit(), f"Expected integer ID, got: {line}"
        removed_ids.append(int(line))

    assert removed_ids == sorted(removed_ids), "Removed IDs are not sorted in ascending order"


def test_cleaned_embeddings_and_partition():
    orig_filepath = "/home/user/data/embeddings.csv"
    cleaned_filepath = "/home/user/cleaned_embeddings.csv"
    removed_filepath = "/home/user/removed_ids.txt"

    assert os.path.isfile(orig_filepath), f"Original data not found: {orig_filepath}"
    assert os.path.isfile(cleaned_filepath), f"Cleaned data not found: {cleaned_filepath}"
    assert os.path.isfile(removed_filepath), f"Removed IDs file not found: {removed_filepath}"

    orig_data = {}
    with open(orig_filepath, "r", newline="") as f:
        reader = csv.reader(f)
        orig_header = next(reader)
        for row in reader:
            orig_data[int(row[0])] = row

    with open(removed_filepath, "r") as f:
        removed_ids = set(int(line.strip()) for line in f if line.strip())

    cleaned_ids = []
    cleaned_data = {}
    with open(cleaned_filepath, "r", newline="") as f:
        reader = csv.reader(f)
        cleaned_header = next(reader)
        assert cleaned_header == orig_header, "Header in cleaned dataset does not match original"

        for row in reader:
            row_id = int(row[0])
            cleaned_ids.append(row_id)
            cleaned_data[row_id] = row

    assert cleaned_ids == sorted(cleaned_ids), "Cleaned dataset is not sorted by id in ascending order"

    orig_id_set = set(orig_data.keys())
    cleaned_id_set = set(cleaned_ids)

    assert cleaned_id_set.isdisjoint(removed_ids), "Cleaned dataset contains IDs that were marked for removal"
    assert orig_id_set == cleaned_id_set.union(removed_ids), "Cleaned IDs and removed IDs do not exactly partition the original IDs"

    for cid in cleaned_ids:
        assert cleaned_data[cid] == orig_data[cid], f"Data for id {cid} was altered in the cleaned dataset"


def compute_expected_results():
    df = pd.read_csv("/home/user/data/embeddings.csv")
    feature_columns = [f"v{i}" for i in range(50)]
    features = df[feature_columns].to_numpy(dtype=float)
    ids = df["id"].to_numpy(dtype=int)

    pca = PCA()
    transformed = pca.fit_transform(features)
    cumulative = np.cumsum(pca.explained_variance_ratio_)
    component_count = int(np.searchsorted(cumulative, 0.90, side="left") + 1)

    reduced = transformed[:, :component_count]
    distances = pairwise_distances(reduced, metric="euclidean")

    parent = list(range(len(ids)))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[rb] = ra

    close_i, close_j = np.where(np.triu(distances < 0.25, k=1))
    for i, j in zip(close_i.tolist(), close_j.tolist()):
        union(i, j)

    component_minimum = {}
    for index, user_id in enumerate(ids):
        root = find(index)
        component_minimum[root] = min(component_minimum.get(root, int(user_id)), int(user_id))

    removed = sorted(
        int(user_id)
        for index, user_id in enumerate(ids)
        if int(user_id) != component_minimum[find(index)]
    )
    kept = sorted(set(int(x) for x in ids) - set(removed))
    return component_count, removed, kept


def test_pca_and_deduplication_are_correct():
    expected_components, expected_removed, expected_kept = compute_expected_results()

    with open("/home/user/pca_components.txt", "r") as f:
        actual_components = int(f.read().strip())
    assert actual_components == expected_components, (
        f"Expected {expected_components} PCA components, got {actual_components}"
    )

    with open("/home/user/removed_ids.txt", "r") as f:
        actual_removed = [int(line.strip()) for line in f if line.strip()]
    assert actual_removed == expected_removed, "Removed IDs do not match the near-duplicate connected components"

    with open("/home/user/cleaned_embeddings.csv", "r", newline="") as f:
        reader = csv.reader(f)
        next(reader)
        actual_kept = [int(row[0]) for row in reader]
    assert actual_kept == expected_kept, "Cleaned dataset does not contain exactly the expected retained IDs"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
