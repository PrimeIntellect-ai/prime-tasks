#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import numpy as np
import pytest


def test_summary_file_exists_and_content():
    summary_path = "/home/user/summary.txt"
    assert os.path.isfile(summary_path), f"Summary file {summary_path} does not exist."

    with open(summary_path, "r") as f:
        content = f.read().strip()

    expected_content = "Positive: 27\nNegative: 23"
    assert content == expected_content, f"Summary file content is incorrect. Expected:\n{expected_content}\nGot:\n{content}"


def test_dataset_directory_is_empty():
    dataset_path = "/home/user/dataset"
    assert os.path.isdir(dataset_path), f"Directory {dataset_path} does not exist."
    files = os.listdir(dataset_path)
    assert len(files) == 0, f"Directory {dataset_path} is not empty. Found {len(files)} files."


def test_positive_cases_directory_contents():
    pos_path = "/home/user/positive_cases"
    assert os.path.isdir(pos_path), f"Directory {pos_path} does not exist."
    files = os.listdir(pos_path)
    npy_files = [f for f in files if f.endswith('.npy')]
    assert len(npy_files) == 27, f"Expected 27 .npy files in {pos_path}, found {len(npy_files)}."


def test_negative_cases_directory_contents():
    neg_path = "/home/user/negative_cases"
    assert os.path.isdir(neg_path), f"Directory {neg_path} does not exist."
    files = os.listdir(neg_path)
    npy_files = [f for f in files if f.endswith('.npy')]
    assert len(npy_files) == 23, f"Expected 23 .npy files in {neg_path}, found {len(npy_files)}."


def test_total_files_moved():
    pos_path = "/home/user/positive_cases"
    neg_path = "/home/user/negative_cases"

    pos_files = os.listdir(pos_path) if os.path.isdir(pos_path) else []
    neg_files = os.listdir(neg_path) if os.path.isdir(neg_path) else []

    total_files = len(pos_files) + len(neg_files)
    assert total_files == 50, f"Expected a total of 50 files moved, but found {total_files}."


def test_each_original_sample_is_in_model_selected_directory():
    pos_path = "/home/user/positive_cases"
    neg_path = "/home/user/negative_cases"
    weights_path = "/home/user/model_weights.npz"

    assert os.path.isfile(weights_path), f"Weights file {weights_path} does not exist."

    # Recreate the deterministic setup data so filenames cannot be reassigned to
    # fabricated or swapped arrays to satisfy only the aggregate counts.
    rng = np.random.RandomState(42)
    expected_weights = {
        "W1": rng.randn(10, 5).astype(np.float32),
        "b1": rng.randn(5).astype(np.float32),
        "W2": rng.randn(5, 1).astype(np.float32),
        "b2": rng.randn(1).astype(np.float32),
    }
    expected_samples = {
        f"sample_{i}.npy": rng.randn(10).astype(np.float32)
        for i in range(50)
    }

    with np.load(weights_path, allow_pickle=False) as weights:
        for key, expected in expected_weights.items():
            assert key in weights.files, f"Weights file is missing key {key}."
            actual = weights[key]
            assert actual.shape == expected.shape, f"Weight {key} has shape {actual.shape}, expected {expected.shape}."
            assert np.array_equal(actual, expected), f"Weight {key} was modified."

        W1 = weights["W1"].copy()
        b1 = weights["b1"].copy()
        W2 = weights["W2"].copy()
        b2 = weights["b2"].copy()

    actual_pos = {name for name in os.listdir(pos_path) if name.endswith(".npy")}
    actual_neg = {name for name in os.listdir(neg_path) if name.endswith(".npy")}
    expected_names = set(expected_samples)
    assert actual_pos.isdisjoint(actual_neg), "A sample filename appears in both class directories."
    assert actual_pos | actual_neg == expected_names, "The moved .npy filenames do not match the original 50 samples."

    for name, original_x in expected_samples.items():
        hidden = np.maximum(original_x @ W1 + b1, 0)
        output = (hidden @ W2 + b2).reshape(-1)[0]
        expected_dir = pos_path if output > 0 else neg_path
        wrong_dir = neg_path if output > 0 else pos_path
        sample_path = os.path.join(expected_dir, name)

        assert os.path.isfile(sample_path), f"{name} was placed in the wrong class directory."
        assert not os.path.exists(os.path.join(wrong_dir, name)), f"{name} appears in both class directories."

        moved_x = np.load(sample_path, allow_pickle=False)
        assert moved_x.shape == (10,), f"{name} has shape {moved_x.shape}, expected (10,)."
        assert np.array_equal(moved_x, original_x), f"{name} no longer contains its original sample data."

        moved_hidden = np.maximum(moved_x @ W1 + b1, 0)
        moved_output = (moved_hidden @ W2 + b2).reshape(-1)[0]
        assert (moved_output > 0) == (expected_dir == pos_path), f"Inference result for {name} does not match its directory."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
