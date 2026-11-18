#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/verifier_hook
cat << 'HOOK_EOF' > /tmp/verifier_hook/sitecustomize.py
import json
import os

try:
    from matplotlib.figure import Figure

    _original_savefig = Figure.savefig

    def _verified_savefig(self, fname, *args, **kwargs):
        try:
            path = os.fspath(fname)
        except TypeError:
            path = ""

        if os.path.basename(path) == "posterior_plot.png":
            axes = []
            for ax in self.axes:
                axes.append({
                    "patches": len(ax.patches),
                    "lines": len(ax.lines),
                    "collections": len(ax.collections),
                    "images": len(ax.images),
                })
            metadata = {
                "axes_count": len(self.axes),
                "axes": axes,
                "width": float(self.get_figwidth()),
                "height": float(self.get_figheight()),
            }
            with open("/tmp/posterior_plot_metadata.json", "w") as f:
                json.dump(metadata, f)

        return _original_savefig(self, fname, *args, **kwargs)

    Figure.savefig = _verified_savefig
except Exception:
    pass
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess

import matplotlib.image as mpimg
import nbformat
import numpy as np
import pytest

NOTEBOOK = "/home/user/profile_analysis.ipynb"
PLOT = "/home/user/posterior_plot.png"
RESULTS = "/home/user/results.json"
PLOT_METADATA = "/tmp/posterior_plot_metadata.json"


@pytest.fixture(scope="session", autouse=True)
def execute_submitted_notebook():
    assert os.path.isfile(NOTEBOOK), f"Notebook file {NOTEBOOK} is missing."

    try:
        with open(NOTEBOOK, "r", encoding="utf-8") as f:
            nbformat.read(f, as_version=4)
    except Exception as exc:
        pytest.fail(f"Notebook file {NOTEBOOK} is not a valid Jupyter notebook: {exc}")

    # Existing outputs cannot satisfy the verifier: the submitted notebook must
    # recreate both artifacts when it is actually executed.
    for path in (PLOT, RESULTS, PLOT_METADATA):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env["MPLBACKEND"] = "Agg"
    env["PYTHONPATH"] = "/tmp/verifier_hook" + (
        os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else ""
    )

    proc = subprocess.run(
        [
            "jupyter", "nbconvert",
            "--to", "notebook",
            "--execute",
            "--inplace",
            "--ExecutePreprocessor.timeout=300",
            NOTEBOOK,
        ],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=360,
    )
    assert proc.returncode == 0, "Notebook execution failed:\n" + proc.stdout[-6000:]

    with open(NOTEBOOK, "r", encoding="utf-8") as f:
        executed = nbformat.read(f, as_version=4)
    code_cells = [
        cell for cell in executed.cells
        if cell.cell_type == "code" and cell.source.strip()
    ]
    assert code_cells, "The notebook contains no executable code cells."
    assert all(cell.execution_count is not None for cell in code_cells), \
        "One or more non-empty notebook code cells were not executed."


def get_expected_results():
    data_a = np.loadtxt('/home/user/latency_a.txt')
    data_b = np.loadtxt('/home/user/latency_b.txt')

    # 1. Bootstrap
    np.random.seed(42)
    diffs = []
    n_a = len(data_a)
    n_b = len(data_b)
    for _ in range(10000):
        samp_a = np.random.choice(data_a, n_a, replace=True)
        samp_b = np.random.choice(data_b, n_b, replace=True)
        diffs.append(np.median(samp_b) - np.median(samp_a))

    ci_lower = np.percentile(diffs, 2.5)
    ci_upper = np.percentile(diffs, 97.5)

    # 2. MCMC
    def log_likelihood(data, mu):
        if mu <= 0 or mu > 200:
            return -np.inf
        return -len(data)*np.log(mu) - np.sum(data)/mu

    def run_mcmc(data, seed):
        np.random.seed(seed)
        mu_current = 50.0
        ll_current = log_likelihood(data, mu_current)
        samples = []

        for i in range(10000):
            mu_prop = np.random.normal(mu_current, 2.0)
            ll_prop = log_likelihood(data, mu_prop)

            if ll_prop > -np.inf:
                ratio = ll_prop - ll_current
                if np.log(np.random.uniform(0, 1)) < ratio:
                    mu_current = mu_prop
                    ll_current = ll_prop

            samples.append(mu_current)

        return np.mean(samples[2000:])

    mcmc_a = run_mcmc(data_a, 100)
    mcmc_b = run_mcmc(data_b, 200)

    return {
        "bootstrap_ci_lower": float(ci_lower),
        "bootstrap_ci_upper": float(ci_upper),
        "mcmc_mu_a": float(mcmc_a),
        "mcmc_mu_b": float(mcmc_b)
    }


def test_notebook_exists():
    path = NOTEBOOK
    assert os.path.isfile(path), f"Notebook file {path} is missing."


def test_plot_exists():
    path = PLOT
    assert os.path.isfile(path), f"Plot file {path} is missing."

    with open(path, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", \
            f"Plot file {path} is not a PNG image."

    try:
        image = np.asarray(mpimg.imread(path), dtype=float)
    except Exception as exc:
        pytest.fail(f"Plot file {path} cannot be decoded: {exc}")

    assert image.ndim in (2, 3), "Plot image has an invalid shape."
    height, width = image.shape[:2]
    assert width >= 500 and height >= 250, "Plot image is too small to contain the required subplots."
    assert width > height, "Plot should have a 1-row, 2-column layout."

    if image.ndim == 3:
        rgb = image[..., :3]
        if image.shape[2] >= 4:
            alpha = image[..., 3:4]
            rgb = rgb * alpha + (1.0 - alpha)
        gray = np.mean(rgb, axis=2)
    else:
        gray = image

    left = gray[:, :width // 2]
    right = gray[:, width // 2:]
    assert np.ptp(left) > 0.1 and np.std(left) > 0.005, \
        "The left subplot appears blank or lacks plotted bootstrap data."
    assert np.ptp(right) > 0.1 and np.std(right) > 0.005, \
        "The right subplot appears blank or lacks plotted posterior data."

    assert os.path.isfile(PLOT_METADATA), \
        "The notebook did not save posterior_plot.png as a matplotlib figure during execution."
    with open(PLOT_METADATA, "r") as f:
        metadata = json.load(f)

    assert metadata.get("axes_count") == 2, \
        "posterior_plot.png must be generated from one matplotlib figure with exactly two subplots."
    axes = metadata.get("axes", [])
    assert len(axes) == 2
    left_artists = sum(axes[0].get(k, 0) for k in ("patches", "lines", "collections", "images"))
    right_artists = sum(axes[1].get(k, 0) for k in ("patches", "lines", "collections", "images"))
    assert left_artists >= 1, "The left subplot contains no plotted bootstrap distribution."
    assert right_artists >= 2, \
        "The right subplot does not contain overlaid posterior plots for both configurations."


def test_results_json():
    path = RESULTS
    assert os.path.isfile(path), f"Results file {path} is missing."

    with open(path, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} is not valid JSON.")

    expected = get_expected_results()

    assert "bootstrap_ci_lower" in results, "Missing key 'bootstrap_ci_lower' in results.json"
    assert "bootstrap_ci_upper" in results, "Missing key 'bootstrap_ci_upper' in results.json"
    assert "mcmc_mu_a" in results, "Missing key 'mcmc_mu_a' in results.json"
    assert "mcmc_mu_b" in results, "Missing key 'mcmc_mu_b' in results.json"

    assert abs(results["bootstrap_ci_lower"] - expected["bootstrap_ci_lower"]) <= 0.05, \
        f"bootstrap_ci_lower is incorrect. Expected ~{expected['bootstrap_ci_lower']}, got {results['bootstrap_ci_lower']}"

    assert abs(results["bootstrap_ci_upper"] - expected["bootstrap_ci_upper"]) <= 0.05, \
        f"bootstrap_ci_upper is incorrect. Expected ~{expected['bootstrap_ci_upper']}, got {results['bootstrap_ci_upper']}"

    assert abs(results["mcmc_mu_a"] - expected["mcmc_mu_a"]) <= 0.1, \
        f"mcmc_mu_a is incorrect. Expected ~{expected['mcmc_mu_a']}, got {results['mcmc_mu_a']}"

    assert abs(results["mcmc_mu_b"] - expected["mcmc_mu_b"]) <= 0.1, \
        f"mcmc_mu_b is incorrect. Expected ~{expected['mcmc_mu_b']}, got {results['mcmc_mu_b']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
