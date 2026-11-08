#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import re
import subprocess

import matplotlib.image as mpimg
import numpy as np


def get_expected_metrics():
    # We use a subprocess to compute the expected metrics using the installed third-party libraries
    # since the test itself must only import standard library modules.
    script = """
import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score
from sklearn.decomposition import PCA

df = pd.read_csv('/home/user/data/dataset.csv')
X = df.drop('target', axis=1).values
y = df['target'].values

pca = PCA(n_components=2)
X_pca = pca.fit_transform(X)

model = RandomForestClassifier(random_state=42)
n_iterations = 100
n_size = int(len(X) * 0.8)

accuracies = []
np.random.seed(42)
for i in range(n_iterations):
    indices = np.random.choice(len(X), n_size, replace=True)
    X_sample = X_pca[indices]
    y_sample = y[indices]

    oob_indices = list(set(range(len(X))) - set(indices))
    if len(oob_indices) == 0: continue
    X_test = X_pca[oob_indices]
    y_test = y[oob_indices]

    model.fit(X_sample, y_sample)
    preds = model.predict(X_test)
    acc = accuracy_score(y_test, preds)
    accuracies.append(acc)

expected_lower = np.percentile(accuracies, 2.5)
expected_upper = np.percentile(accuracies, 97.5)
print(f"{expected_lower:.4f},{expected_upper:.4f}")
"""
    result = subprocess.run(["python3", "-c", script], capture_output=True, text=True, check=True)
    lower, upper = result.stdout.strip().split(',')
    return float(lower), float(upper)


def test_pca_plot_exists():
    plot_path = "/home/user/workspace/pca_plot.png"
    assert os.path.isfile(plot_path), f"The plot file {plot_path} was not generated."
    assert os.path.getsize(plot_path) > 0, f"The plot file {plot_path} is empty."

    # Check PNG magic number
    with open(plot_path, "rb") as f:
        header = f.read(8)
    assert header == b"\x89PNG\r\n\x1a\n", f"The file {plot_path} is not a valid PNG image."

    # Decode the image and ensure it is a substantive, non-blank plot.
    image = mpimg.imread(plot_path)
    assert image.ndim in (2, 3), f"The file {plot_path} could not be decoded as an image."
    assert image.shape[0] > 10 and image.shape[1] > 10, f"The plot {plot_path} has invalid dimensions."
    assert np.isfinite(image).all(), f"The plot {plot_path} contains invalid pixel data."
    assert float(np.max(image) - np.min(image)) > 0.01, f"The plot {plot_path} appears to be blank."


def test_metrics_file():
    metrics_path = "/home/user/workspace/metrics.txt"
    assert os.path.isfile(metrics_path), f"The metrics file {metrics_path} was not generated."

    with open(metrics_path, "r") as f:
        content = f.read()

    match_lower = re.search(r"Lower:\s*([0-9.]+)", content)
    match_upper = re.search(r"Upper:\s*([0-9.]+)", content)

    assert match_lower and match_upper, "The metrics.txt file does not contain properly formatted 'Lower: ...' and 'Upper: ...' values."

    actual_lower = float(match_lower.group(1))
    actual_upper = float(match_upper.group(1))

    expected_lower, expected_upper = get_expected_metrics()

    assert abs(actual_lower - expected_lower) < 1e-3, f"Expected Lower CI bound around {expected_lower:.4f}, but got {actual_lower:.4f}."
    assert abs(actual_upper - expected_upper) < 1e-3, f"Expected Upper CI bound around {expected_upper:.4f}, but got {actual_upper:.4f}."


def test_script_modifications():
    script_path = "/home/user/workspace/analyze_data.py"
    assert os.path.isfile(script_path), f"The script {script_path} is missing."

    with open(script_path, "r") as f:
        content = f.read()

    # Check headless matplotlib backend
    assert re.search(r"matplotlib\.use\(['\"]Agg['\"]\)", content) or re.search(r"plt\.switch_backend\(['\"]Agg['\"]\)", content), \
        "The script does not configure matplotlib to use the 'Agg' backend."

    # Check PCA usage
    assert "PCA" in content and "fit_transform" in content, \
        "The script does not appear to use PCA.fit_transform to reduce dimensions."

    # Check replace=True
    assert "replace=True" in content, \
        "The script does not use replace=True in np.random.choice for bootstrap sampling."

    # Check percentiles
    assert "2.5" in content and "97.5" in content, \
        "The script does not use the correct percentiles (2.5 and 97.5) for a 95% confidence interval."
TEST_EOF

# Remove any pre-created artifacts, then require the submitted script itself to
# regenerate them successfully.
rm -f /home/user/workspace/pca_plot.png /home/user/workspace/metrics.txt
if timeout 180s python3 /home/user/workspace/analyze_data.py && \
   python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
