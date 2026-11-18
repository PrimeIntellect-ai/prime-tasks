#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import subprocess

import matplotlib.image as mpimg
import numpy as np
import pandas as pd
import pytest
import torch
import torch.nn as nn

SCRIPT_PATH = "/home/user/process.py"
SUMMARY_PATH = "/home/user/summary.csv"
PLOT_PATH = "/home/user/plot.png"
DATASET_PATH = "/home/user/dataset.csv"
MODEL_PATH = "/home/user/model.pth"


class SimpleMLP(nn.Module):
    def __init__(self):
        super().__init__()
        self.fc1 = nn.Linear(2, 16)
        self.relu = nn.ReLU()
        self.fc2 = nn.Linear(16, 1)

    def forward(self, x):
        return self.fc2(self.relu(self.fc1(x)))


def compute_expected_means():
    df = pd.read_csv(DATASET_PATH)
    assert list(df.columns) == ["id", "category", "f1", "f2"]

    model = SimpleMLP()
    try:
        state_dict = torch.load(MODEL_PATH, map_location="cpu", weights_only=True)
    except TypeError:
        state_dict = torch.load(MODEL_PATH, map_location="cpu")
    model.load_state_dict(state_dict)
    model.eval()

    features = torch.tensor(df[["f1", "f2"]].to_numpy(dtype=np.float32), dtype=torch.float32)
    with torch.no_grad():
        predictions = model(features).squeeze(1).cpu().numpy()

    expected_df = df.copy()
    expected_df["pred"] = predictions
    return expected_df.groupby("category")["pred"].mean().to_dict()


@pytest.fixture(scope="module")
def executed_process():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    expected = compute_expected_means()

    # Outputs must be freshly produced by the submitted script.
    for path in (SUMMARY_PATH, PLOT_PATH):
        if os.path.lexists(path):
            os.remove(path)

    result = subprocess.run(
        ["python3", SCRIPT_PATH], capture_output=True, text=True, timeout=120
    )
    return result, expected


def test_process_script_exists_and_runs(executed_process):
    result, _ = executed_process
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert result.returncode == 0, f"Script failed to run. Stderr: {result.stderr}"


def test_summary_csv(executed_process):
    result, expected = executed_process
    assert result.returncode == 0, f"Script failed to run. Stderr: {result.stderr}"
    assert os.path.isfile(SUMMARY_PATH), f"Summary CSV not found at {SUMMARY_PATH}"

    with open(SUMMARY_PATH, "r", newline="") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "Summary CSV is empty"

    header = rows[0]
    assert header == ["category", "mean_pred"], f"Unexpected header: {header}"

    data_rows = rows[1:]
    assert len(data_rows) == 4, f"Expected 4 categories, found {len(data_rows)}"

    categories = set()
    actual = {}
    for row in data_rows:
        assert len(row) == 2, f"Expected 2 columns in row, got {len(row)}"
        categories.add(row[0])
        try:
            value = float(row[1])
        except ValueError:
            pytest.fail(f"mean_pred value '{row[1]}' is not a valid float")
        assert math.isfinite(value), f"mean_pred for {row[0]} is not finite"
        actual[row[0]] = value

    assert categories == {"A", "B", "C", "D"}, f"Unexpected categories: {categories}"
    assert set(actual) == set(expected), "Summary categories do not match the dataset"
    for category, expected_value in expected.items():
        assert np.isclose(actual[category], expected_value, rtol=1e-5, atol=1e-6), (
            f"Incorrect mean_pred for {category}: got {actual[category]}, "
            f"expected {expected_value}"
        )


def test_plot_png(executed_process):
    result, _ = executed_process
    assert result.returncode == 0, f"Script failed to run. Stderr: {result.stderr}"
    assert os.path.isfile(PLOT_PATH), f"Plot image not found at {PLOT_PATH}"
    assert os.path.getsize(PLOT_PATH) > 0, "Plot image is empty (0 bytes)"

    with open(PLOT_PATH, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", "plot.png is not a PNG file"

    try:
        image = np.asarray(mpimg.imread(PLOT_PATH))
    except Exception as exc:
        pytest.fail(f"plot.png is not a readable PNG image: {exc}")

    assert image.ndim in (2, 3), f"Unexpected plot image shape: {image.shape}"
    assert image.shape[0] >= 100 and image.shape[1] >= 100, "Plot image is too small"
    assert np.isfinite(image).all(), "Plot image contains invalid pixel values"

    pixels = image[..., :3] if image.ndim == 3 else image
    assert float(np.max(pixels) - np.min(pixels)) > 0.1, "Plot image appears blank"
    assert float(np.std(pixels)) > 0.005, "Plot image has insufficient visual content"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
