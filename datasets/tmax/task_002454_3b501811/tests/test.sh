#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TRACE_EOF' > /tmp/verifier_bash_env
export PS4='+ '
set -x
TRACE_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import re
import shutil
import subprocess

import nbformat
import numpy as np
import pandas as pd
import pytest
from scipy.optimize import curve_fit

HOME = "/home/user"
LEVELS = ["0.1", "0.2", "0.3", "0.4", "0.5"]
GENERATED = [f"data_noise_{s}.csv" for s in LEVELS]
GENERATED += [f"mcmc_run_{s}.ipynb" for s in LEVELS]
GENERATED += [f"result_{s}.json" for s in LEVELS]
GENERATED += ["summary.tsv"]
RUN_TRACES = []


def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(65536), b""):
            h.update(block)
    return h.hexdigest()


def clean_outputs():
    for name in GENERATED:
        path = os.path.join(HOME, name)
        if os.path.isdir(path):
            shutil.rmtree(path)
        elif os.path.lexists(path):
            os.remove(path)


def run_submission():
    env = os.environ.copy()
    env["BASH_ENV"] = "/tmp/verifier_bash_env"
    proc = subprocess.run(
        ["/home/user/run_stability_test.sh"],
        cwd=HOME,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=300,
    )
    RUN_TRACES.append(proc.stdout + "\n" + proc.stderr)
    assert proc.returncode == 0, (
        f"run_stability_test.sh exited with {proc.returncode}\n"
        f"stdout:\n{proc.stdout[-4000:]}\nstderr:\n{proc.stderr[-4000:]}"
    )


@pytest.fixture(scope="session", autouse=True)
def execute_and_check_reproducibility():
    clean_outputs()
    run_submission()
    for name in GENERATED:
        assert os.path.isfile(os.path.join(HOME, name)), f"Missing generated artifact: {name}"

    reproducible_names = [f"data_noise_{s}.csv" for s in LEVELS]
    reproducible_names += [f"result_{s}.json" for s in LEVELS]
    reproducible_names += ["summary.tsv"]
    first = {name: digest(os.path.join(HOME, name)) for name in reproducible_names}

    clean_outputs()
    run_submission()
    second = {name: digest(os.path.join(HOME, name)) for name in reproducible_names}
    assert first == second, "Noise data, JSON results, and summary must be reproducible across clean runs"


def test_script_exists_and_executable():
    script_path = "/home/user/run_stability_test.sh"
    assert os.path.isfile(script_path), f"Script not found at {script_path}"
    assert os.access(script_path, os.X_OK), f"Script at {script_path} is not executable"


def test_required_tools_available_and_used():
    for module in ["pandas", "scipy", "papermill", "jupyter"]:
        subprocess.run(
            ["python3", "-c", f"import {module}"],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
    assert shutil.which("jq"), "jq is not installed"

    trace = "\n".join(RUN_TRACES)
    assert re.search(r"(?m)^\+ .*\bpapermill\b", trace), "The executed pipeline did not invoke papermill"
    assert re.search(r"(?m)^\+ .*\bjq\b", trace), "The executed pipeline did not invoke jq"


def test_summary_tsv_exists():
    summary_path = "/home/user/summary.tsv"
    assert os.path.isfile(summary_path), f"Summary file not found at {summary_path}"


def read_summary():
    with open("/home/user/summary.tsv", "r", encoding="utf-8") as f:
        return [line.rstrip("\n\r") for line in f if line.strip()]


def test_summary_tsv_content():
    lines = read_summary()
    assert len(lines) == 6, f"Expected 6 lines in summary.tsv (1 header + 5 data rows), found {len(lines)}"
    assert lines[0] == "NoiseLevel\tEstimatedMu", "Incorrect summary.tsv header"

    actual_noise_floats = []
    for i, line in enumerate(lines[1:], start=2):
        parts = line.split("\t")
        assert len(parts) == 2, f"Line {i} is not tab-separated properly: {line!r}"
        noise, mu_text = parts
        try:
            actual_noise_floats.append(float(noise))
            mu = float(mu_text)
        except ValueError:
            pytest.fail(f"Line {i} does not contain numeric values: {line!r}")
        assert 14.0 <= mu <= 17.0, f"EstimatedMu {mu} on line {i} is too far from expected 15.5"

    assert actual_noise_floats == [0.1, 0.2, 0.3, 0.4, 0.5], (
        f"Expected sorted noise levels [0.1, 0.2, 0.3, 0.4, 0.5], got {actual_noise_floats}"
    )


def test_output_files_exist():
    for sigma in LEVELS:
        assert os.path.isfile(f"/home/user/data_noise_{sigma}.csv"), f"Missing generated dataset for {sigma}"
        assert os.path.isfile(f"/home/user/mcmc_run_{sigma}.ipynb"), f"Missing executed notebook for {sigma}"
        assert os.path.isfile(f"/home/user/result_{sigma}.json"), f"Missing result JSON for {sigma}"


def gauss(x, a, mu, sigma):
    return a * np.exp(-0.5 * ((x - mu) / sigma) ** 2)


def test_noisy_datasets_and_results_are_real_and_consistent():
    base = pd.read_csv("/home/user/base_data.csv")
    assert list(base.columns) == ["x", "y"]
    assert len(base) == 100

    summary_values = {}
    for line in read_summary()[1:]:
        level, value = line.split("\t")
        summary_values[f"{float(level):.1f}"] = float(value)

    for sigma_text in LEVELS:
        sigma = float(sigma_text)
        data_path = f"/home/user/data_noise_{sigma_text}.csv"
        result_path = f"/home/user/result_{sigma_text}.json"
        noisy = pd.read_csv(data_path)

        assert list(noisy.columns) == ["x", "y"], f"Wrong columns in {data_path}"
        assert len(noisy) == len(base), f"Wrong row count in {data_path}"
        np.testing.assert_allclose(noisy["x"], base["x"], rtol=0, atol=1e-12)

        residual = noisy["y"].to_numpy() - base["y"].to_numpy()
        assert np.isfinite(residual).all()
        assert not np.allclose(residual, 0), f"No noise was added for sigma={sigma_text}"
        assert abs(float(residual.mean())) < max(0.05, 0.35 * sigma), (
            f"Injected noise for sigma={sigma_text} is not approximately zero-mean"
        )
        sample_std = float(residual.std(ddof=1))
        assert 0.65 * sigma < sample_std < 1.35 * sigma, (
            f"Noise standard deviation for sigma={sigma_text} is {sample_std}, expected about {sigma}"
        )
        standardized = (residual - residual.mean()) / sample_std
        assert abs(float(np.mean(standardized ** 3))) < 1.0, "Noise is implausibly skewed for Gaussian noise"
        assert abs(float(np.mean(standardized ** 4)) - 3.0) < 1.5, "Noise is implausible as Gaussian noise"

        popt, _ = curve_fit(gauss, noisy["x"], noisy["y"], p0=[10, 15, 2])
        expected_mu = round(float(popt[1]), 4)
        with open(result_path, "r", encoding="utf-8") as f:
            result = json.load(f)
        assert isinstance(result, dict) and "estimated_mu" in result
        assert isinstance(result["estimated_mu"], (int, float)) and not isinstance(result["estimated_mu"], bool)
        assert float(result["estimated_mu"]) == pytest.approx(expected_mu, abs=5e-5), (
            f"{result_path} does not contain the fit result for its noisy dataset"
        )
        assert summary_values[sigma_text] == pytest.approx(float(result["estimated_mu"]), abs=5e-10), (
            f"summary.tsv does not match {result_path}"
        )


def test_notebooks_were_executed_with_correct_parameters():
    for sigma in LEVELS:
        nb_path = f"/home/user/mcmc_run_{sigma}.ipynb"
        nb = nbformat.read(nb_path, as_version=4)
        code_cells = [cell for cell in nb.cells if cell.cell_type == "code"]
        assert code_cells, f"{nb_path} has no code cells"
        assert any(cell.get("execution_count") is not None for cell in code_cells), (
            f"{nb_path} does not appear to be an executed notebook"
        )
        assert not any(cell.get("outputs") and any(o.get("output_type") == "error" for o in cell.outputs)
                       for cell in code_cells), f"{nb_path} contains an execution error"

        injected = [cell for cell in code_cells if "injected-parameters" in cell.get("metadata", {}).get("tags", [])]
        assert injected, f"{nb_path} lacks papermill's injected parameter cell"
        injected_source = "\n".join(cell.source for cell in injected)
        assert f"/home/user/data_noise_{sigma}.csv" in injected_source, "Incorrect input_file parameter"
        assert f"/home/user/result_{sigma}.json" in injected_source, "Incorrect output_json parameter"

        pm = nb.metadata.get("papermill", {})
        assert pm, f"{nb_path} lacks papermill execution metadata"
        assert pm.get("exception") is False, f"Papermill reported an exception in {nb_path}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
