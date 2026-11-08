#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pandas as pd
import pytest
import matplotlib.image as mpimg
import numpy as np


def calculate_wer(reference, hypothesis):
    """Computes Word Error Rate using Levenshtein distance."""
    r = reference.strip().split()
    h = hypothesis.strip().split()

    d = [[0] * (len(h) + 1) for _ in range(len(r) + 1)]
    for i in range(len(r) + 1):
        d[i][0] = i
    for j in range(len(h) + 1):
        d[0][j] = j

    for i in range(1, len(r) + 1):
        for j in range(1, len(h) + 1):
            if r[i - 1].lower() == h[j - 1].lower():
                d[i][j] = d[i - 1][j - 1]
            else:
                substitution = d[i - 1][j - 1] + 1
                insertion = d[i][j - 1] + 1
                deletion = d[i - 1][j] + 1
                d[i][j] = min(substitution, insertion, deletion)

    return d[len(r)][len(h)] / float(len(r)) if len(r) > 0 else 1.0


def test_pipeline_script_exists():
    assert os.path.isfile('/home/user/pipeline.sh'), "/home/user/pipeline.sh is missing."


def test_word_freq_png_exists_and_valid():
    png_path = '/home/user/word_freq.png'
    assert os.path.isfile(png_path), f"{png_path} is missing. The plot_words.py script may have failed."
    assert os.path.getsize(png_path) >= 1000, f"{png_path} is too small, likely an empty or invalid plot."

    with open(png_path, 'rb') as f:
        assert f.read(8) == b'\x89PNG\r\n\x1a\n', f"{png_path} is not a PNG file."

    try:
        image = mpimg.imread(png_path)
    except Exception as e:
        pytest.fail(f"Failed to decode {png_path} as a PNG image: {e}")

    assert image.ndim in (2, 3) and image.shape[0] > 10 and image.shape[1] > 10, \
        f"{png_path} has invalid image dimensions."
    assert np.isfinite(image).all(), f"{png_path} contains invalid pixel values."
    assert float(np.std(image)) > 0.01, f"{png_path} appears to be blank."


def test_dataset_csv_and_wer():
    csv_path = '/home/user/dataset.csv'
    gt_path = '/tests/ground_truth.txt'

    assert os.path.isfile(csv_path), f"{csv_path} is missing."
    assert os.path.isfile(gt_path), f"Ground truth file {gt_path} is missing."

    try:
        df = pd.read_csv(csv_path, names=['filename', 'text'])
    except Exception as e:
        pytest.fail(f"Failed to read {csv_path} as CSV: {e}")

    assert len(df.columns) == 2, f"Expected 2 columns in {csv_path}, found {len(df.columns)}."

    hypothesis = " ".join(df['text'].dropna().astype(str).tolist())

    with open(gt_path, 'r') as f:
        reference = f.read().strip()

    wer_score = calculate_wer(reference, hypothesis)
    threshold = 0.3

    assert wer_score <= threshold, f"Word Error Rate (WER) is {wer_score:.4f}, which is greater than the threshold of {threshold}. The transcriptions are not accurate enough."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
