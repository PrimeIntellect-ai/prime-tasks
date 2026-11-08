#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import math
import subprocess
import pytest


@pytest.fixture(scope='session', autouse=True)
def run_analyze_artifacts():
    """Require the submitted script itself to generate all artifacts."""
    script_path = '/home/user/analyze_artifacts.py'
    assert os.path.exists(script_path), f"File {script_path} is missing."
    assert os.path.isfile(script_path), f"Path {script_path} is not a file."

    outputs = [
        '/home/user/pca_plot.png',
        '/home/user/centroid_distance.txt',
        '/home/user/p_value.txt',
    ]
    for path in outputs:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env['MPLBACKEND'] = 'Agg'
    result = subprocess.run(
        ['python3', script_path],
        cwd='/home/user',
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"{script_path} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_pca_plot_exists():
    """Verify that the PCA plot was generated and is a real scatter-plot PNG."""
    plot_path = '/home/user/pca_plot.png'
    assert os.path.exists(plot_path), f"File {plot_path} is missing. The script did not generate the plot."
    assert os.path.isfile(plot_path), f"Path {plot_path} is not a file."
    assert os.path.getsize(plot_path) > 0, f"File {plot_path} is empty."

    with open(plot_path, 'rb') as f:
        assert f.read(8) == b'\x89PNG\r\n\x1a\n', f"File {plot_path} is not a PNG image."

    import numpy as np
    import matplotlib.image as mpimg
    try:
        image = mpimg.imread(plot_path)
    except Exception as exc:
        pytest.fail(f"File {plot_path} is not a readable PNG image: {exc}")

    assert image.ndim == 3 and image.shape[0] >= 100 and image.shape[1] >= 100, \
        f"File {plot_path} does not have plausible plot dimensions."
    assert image.shape[2] in (3, 4), f"File {plot_path} is not an RGB/RGBA plot."
    assert np.isfinite(image).all(), f"File {plot_path} contains invalid pixels."
    rgb = image[:, :, :3]
    assert len(np.unique(rgb.reshape(-1, 3), axis=0)) > 10, \
        f"File {plot_path} does not contain rendered plot content."

    # The retained plotting code uses Matplotlib's first two default scatter colors.
    blue = np.array([31, 119, 180]) / 255.0
    orange = np.array([255, 127, 14]) / 255.0
    blue_pixels = np.sum(np.all(np.isclose(rgb, blue, atol=0.03), axis=2))
    orange_pixels = np.sum(np.all(np.isclose(rgb, orange, atol=0.03), axis=2))
    assert blue_pixels > 50 and orange_pixels > 50, \
        "The PNG does not contain both Model A and Model B scatter series."


def test_centroid_distance_correctness():
    """Verify that the centroid distance is calculated correctly and saved."""
    dist_path = '/home/user/centroid_distance.txt'
    assert os.path.exists(dist_path), f"File {dist_path} is missing."

    with open(dist_path, 'r') as f:
        content = f.read().strip()

    try:
        actual_dist = float(content)
    except ValueError:
        pytest.fail(f"Content of {dist_path} is not a valid float: '{content}'")

    # The expected distance is ~3.3087 based on the truth logic
    # We will compute it exactly from the npz to be robust
    import numpy as np
    data = np.load('/home/user/embeddings.npz')
    A, B = data['A'], data['B']
    X = np.vstack((A, B))
    X_centered = X - np.mean(X, axis=0)
    U, S, Vt = np.linalg.svd(X_centered, full_matrices=False)
    X_pca = X_centered @ Vt.T[:, :2]
    A_pca, B_pca = X_pca[:len(A)], X_pca[len(A):]

    c_A = np.mean(A_pca, axis=0)
    c_B = np.mean(B_pca, axis=0)
    expected_dist = np.linalg.norm(c_A - c_B)

    assert math.isclose(actual_dist, expected_dist, rel_tol=1e-3, abs_tol=1e-3), \
        f"Expected centroid distance ~{expected_dist:.4f}, but got {actual_dist}. Did you mean-center the data before SVD?"


def test_p_value_correctness():
    """Verify that the p-value is calculated correctly and saved."""
    pval_path = '/home/user/p_value.txt'
    assert os.path.exists(pval_path), f"File {pval_path} is missing."

    with open(pval_path, 'r') as f:
        content = f.read().strip()

    try:
        actual_p = float(content)
    except ValueError:
        pytest.fail(f"Content of {pval_path} is not a valid float: '{content}'")

    import numpy as np
    from scipy import stats
    data = np.load('/home/user/embeddings.npz')
    A, B = data['A'], data['B']
    X = np.vstack((A, B))
    X_centered = X - np.mean(X, axis=0)
    U, S, Vt = np.linalg.svd(X_centered, full_matrices=False)
    X_pca = X_centered @ Vt.T[:, :2]
    A_pca, B_pca = X_pca[:len(A)], X_pca[len(A):]

    _, expected_p = stats.ttest_ind(A_pca[:, 0], B_pca[:, 0])

    # SVD signs can be flipped, but t-test p-value is invariant to sign flips
    assert math.isclose(actual_p, expected_p, rel_tol=1e-2, abs_tol=1e-25), \
        f"Expected p-value ~{expected_p:.4e}, but got {actual_p:.4e}. Did you use PC1 and mean-center the data?"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
