#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import numpy as np
import pandas as pd
import pytest
from scipy.io import wavfile
from sklearn.decomposition import PCA

CSV_PATH = '/home/user/top5.csv'
AUDIO_PATH = '/app/research_audio.wav'


def load_submission():
    assert os.path.exists(CSV_PATH), f"Expected output file not found at {CSV_PATH}"
    try:
        return pd.read_csv(CSV_PATH)
    except Exception as e:
        pytest.fail(f"Failed to read {CSV_PATH} as CSV: {e}")


def compute_expected():
    sample_rate, audio = wavfile.read(AUDIO_PATH)
    assert sample_rate == 16000, f"Unexpected sample rate: {sample_rate}"
    assert audio.ndim == 1, "Expected mono audio"
    assert len(audio) == 60 * 16000, f"Unexpected audio length: {len(audio)}"

    chunks = np.asarray(audio).reshape(60, 16000)
    features = np.asarray([
        [bucket.mean() for bucket in np.array_split(np.abs(np.fft.rfft(chunk)), 32)]
        for chunk in chunks
    ])
    centered = features - features.mean(axis=0)
    reduced = PCA(n_components=4).fit_transform(centered)

    reference = reduced[0]
    others = reduced[1:]
    similarities = (others @ reference) / (
        np.linalg.norm(others, axis=1) * np.linalg.norm(reference)
    )
    chunk_ids = np.arange(1, 60)
    order = np.argsort(-similarities, kind='stable')[:5]
    return chunk_ids[order], similarities[order]


def test_top5_csv_exists_and_format():
    df = load_submission()

    # Preserve the original format assertions.
    assert 'chunk_id' in df.columns, "CSV must contain a 'chunk_id' column"
    assert 'similarity' in df.columns, "CSV must contain a 'similarity' column"
    assert len(df) >= 5, f"CSV must contain at least 5 rows, found {len(df)}"

    # The instruction requires exactly these two columns and exactly five rows.
    assert list(df.columns) == ['chunk_id', 'similarity'], (
        f"CSV columns must be exactly ['chunk_id', 'similarity'], found {list(df.columns)}"
    )
    assert len(df) == 5, f"CSV must contain exactly 5 rows, found {len(df)}"


def test_similarity_metric_and_values():
    df = load_submission()
    if len(df) < 5:
        pytest.fail("CSV has fewer than 5 rows.")

    try:
        ids_numeric = pd.to_numeric(df['chunk_id'], errors='raise').to_numpy(dtype=float)
        submitted_similarities = pd.to_numeric(
            df['similarity'], errors='raise'
        ).to_numpy(dtype=float)
    except Exception as e:
        pytest.fail(f"Could not parse output columns as numeric values: {e}")

    assert np.all(np.isfinite(ids_numeric)), "chunk_id values must be finite"
    assert np.all(ids_numeric == np.floor(ids_numeric)), "chunk_id values must be integers"
    submitted_ids = ids_numeric.astype(int)
    assert np.all((submitted_ids >= 1) & (submitted_ids <= 59)), (
        "Recommended chunk IDs must be between 1 and 59"
    )
    assert len(set(submitted_ids.tolist())) == 5, "Recommended chunk IDs must be unique"
    assert np.all(np.isfinite(submitted_similarities)), "similarity values must be finite"

    # Preserve the original ground-truth metric assertion.
    ground_truth = {10, 20, 30, 40, 50}
    top_5_ids = set(submitted_ids[:5].tolist())
    metric = len(ground_truth.intersection(top_5_ids)) / 5.0
    assert metric >= 0.8, (
        f"Metric value {metric} is below the threshold of 0.8. "
        f"Top 5 IDs found: {top_5_ids}, Expected subset of: {ground_truth}"
    )

    expected_ids, expected_similarities = compute_expected()
    assert np.array_equal(submitted_ids, expected_ids), (
        f"Rows are not the correct top five chunks in descending similarity order. "
        f"Found {submitted_ids.tolist()}, expected {expected_ids.tolist()}"
    )
    assert np.all(submitted_similarities[:-1] >= submitted_similarities[1:]), (
        "Rows must be sorted in descending order of similarity"
    )
    assert np.allclose(
        submitted_similarities, expected_similarities, rtol=1e-5, atol=1e-5
    ), (
        f"Incorrect similarity values. Found {submitted_similarities.tolist()}, "
        f"expected {expected_similarities.tolist()}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
