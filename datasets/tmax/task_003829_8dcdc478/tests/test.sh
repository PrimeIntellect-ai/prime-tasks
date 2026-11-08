#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess
import tempfile
import time

import numpy as np
import pandas as pd
import pytest

CPP_FILE = "/home/user/fast_mcmc.cpp"
NOTEBOOK = "/home/user/workflow.ipynb"
EXECUTABLE = "/tmp/fast_mcmc"
ORACLE = "/app/oracle_mcmc"
DATA = "/app/data.csv"


def test_files_exist_and_source_uses_parallel_mcmc():
    assert os.path.isfile(CPP_FILE), f"{CPP_FILE} does not exist"
    assert os.path.isfile(NOTEBOOK), f"{NOTEBOOK} does not exist"

    source = open(CPP_FILE, encoding="utf-8", errors="replace").read()
    assert re.search(r"#\s*pragma\s+omp\s+parallel", source), "C++ source does not use an OpenMP parallel region"
    assert re.search(r"\b4\b", source), "C++ source does not define four chains/threads"
    assert ("25000" in source or ("100000" in source and re.search(r"/\s*4\b", source))), \
        "C++ source does not define 25,000 samples per chain"
    assert re.search(r"mt19937|default_random_engine|random_device|normal_distribution", source), \
        "C++ source does not contain random sampling machinery"
    assert "oracle_samples" not in source and "oracle_mcmc" not in source, \
        "The fast implementation must perform sampling rather than consume or invoke the oracle"


def test_notebook_workflow():
    try:
        with open(NOTEBOOK, encoding="utf-8") as f:
            notebook = json.load(f)
    except Exception as exc:
        pytest.fail(f"workflow.ipynb is not a valid notebook JSON file: {exc}")

    code_cells = [c for c in notebook.get("cells", []) if c.get("cell_type") == "code"]
    assert code_cells, "Notebook contains no code cells"
    code = "\n".join("".join(c.get("source", [])) for c in code_cells)
    lower = code.lower()

    assert "g++" in code and "-fopenmp" in code and "fast_mcmc.cpp" in code, \
        "Notebook does not compile fast_mcmc.cpp with OpenMP"
    assert "oracle_mcmc" in code and "fast_mcmc" in code and "data.csv" in code, \
        "Notebook does not run both the oracle and fast sampler on the input data"
    assert any(token in lower for token in ("perf_counter", "time.time", "timeit", "%time", "%%time")), \
        "Notebook does not profile execution time"
    assert "read_csv" in lower and "oracle_samples" in lower and "fast_samples" in lower, \
        "Notebook does not load both sample CSV files"
    assert any(token in lower for token in ("kde", "gaussian_kde")), \
        "Notebook does not perform posterior density estimation"
    assert any(token in lower for token in ("plot(", "plt.", "seaborn", "sns.")), \
        "Notebook does not visualize the posterior comparison"
    assert ".mean(" in lower and any(token in lower for token in ("print(", "display(")), \
        "Notebook does not compute and print/display sample means"


def compile_agent():
    try:
        subprocess.run(
            ["g++", "-O3", "-fopenmp", CPP_FILE, "-o", EXECUTABLE],
            check=True, capture_output=True, text=True, timeout=120
        )
    except subprocess.CalledProcessError as exc:
        pytest.fail(f"Compilation failed:\n{exc.stderr}")
    assert os.path.isfile(EXECUTABLE), "Agent executable was not generated"


def load_and_validate_samples(path):
    assert os.path.isfile(path), f"Output file was not created: {path}"
    try:
        frame = pd.read_csv(path, names=["a", "b"], header=None)
        values = frame.to_numpy(dtype=float)
    except Exception as exc:
        pytest.fail(f"Failed to read numeric sample CSV {path}: {exc}")

    assert values.shape == (100000, 2), \
        f"Expected exactly 100,000 two-column samples, got shape {values.shape}"
    assert np.isfinite(values).all(), "Samples contain NaN or infinite values"
    assert ((values[:, 0] >= 0) & (values[:, 0] <= 10)).all(), "Parameter a violates its prior bounds"
    assert ((values[:, 1] >= 0) & (values[:, 1] <= 5)).all(), "Parameter b violates its prior bounds"

    chains = values.reshape(4, 25000, 2)
    for index, chain in enumerate(chains):
        changed = np.any(chain[1:] != chain[:-1], axis=1)
        repeats = ~changed
        assert changed.sum() >= 100, f"Chain {index} does not contain a genuine evolving trajectory"
        assert repeats.sum() >= 10, f"Chain {index} has no evidence of Metropolis-Hastings rejections"

    for left in range(4):
        for right in range(left + 1, 4):
            assert not np.array_equal(chains[left], chains[right]), \
                f"Chains {left} and {right} are identical rather than independent"
    return values


def run_agent(data_path, output_path):
    env = os.environ.copy()
    env["OMP_NUM_THREADS"] = "4"
    start = time.perf_counter()
    try:
        subprocess.run(
            [EXECUTABLE, data_path, output_path], check=True,
            capture_output=True, text=True, timeout=120, env=env
        )
    except subprocess.CalledProcessError as exc:
        pytest.fail(f"Agent binary failed to run:\n{exc.stderr}")
    return time.perf_counter() - start


def test_performance_accuracy_and_behavior():
    compile_agent()

    with tempfile.TemporaryDirectory(prefix="mcmc_verify_") as work:
        agent_output = os.path.join(work, "fast_samples.csv")
        oracle_output = os.path.join(work, "oracle_samples.csv")

        # Run the submitted program before creating any oracle CSV, preventing it
        # from copying or averaging a verifier-created oracle result.
        agent_time = run_agent(DATA, agent_output)
        agent_values = load_and_validate_samples(agent_output)

        start_oracle = time.perf_counter()
        try:
            subprocess.run([ORACLE, DATA, oracle_output], check=True, capture_output=True, timeout=300)
        except subprocess.CalledProcessError as exc:
            pytest.fail(f"Oracle binary failed to run:\n{exc.stderr}")
        oracle_time = time.perf_counter() - start_oracle
        assert os.path.isfile(oracle_output), "Oracle output file was not created"

        speedup = oracle_time / agent_time
        assert speedup >= 3.0, f"Speedup is {speedup:.2f}x, which is less than the required 3.0x threshold"

        try:
            oracle_df = pd.read_csv(oracle_output, names=["a", "b"], header=None)
            oracle_values = oracle_df.to_numpy(dtype=float)
        except Exception as exc:
            pytest.fail(f"Failed to read oracle output CSV: {exc}")
        assert oracle_values.shape == (100000, 2), "Oracle did not produce 100,000 two-column samples"

        oracle_means = oracle_values.mean(axis=0)
        agent_means = agent_values.mean(axis=0)
        max_err = float(np.max(np.abs(oracle_means - agent_means)))
        assert max_err <= 0.05, (
            f"Maximum absolute error of parameter means is {max_err:.4f}, which exceeds 0.05. "
            f"Oracle means: a={oracle_means[0]:.4f}, b={oracle_means[1]:.4f}. "
            f"Agent means: a={agent_means[0]:.4f}, b={agent_means[1]:.4f}."
        )

        # Exercise the implementation on data unavailable when the submission was
        # authored. Correct model-based sampling must follow this different posterior.
        challenge_data = os.path.join(work, "challenge.csv")
        challenge_output = os.path.join(work, "challenge_samples.csv")
        xs = np.linspace(0.0, 8.0, 100)
        expected_a, expected_b = 6.2, 0.65
        ys = expected_a * np.exp(-expected_b * xs)
        np.savetxt(challenge_data, np.column_stack((xs, ys)), delimiter=",", fmt="%.12g")
        run_agent(challenge_data, challenge_output)
        challenge_values = load_and_validate_samples(challenge_output)
        challenge_means = challenge_values.mean(axis=0)
        assert abs(challenge_means[0] - expected_a) <= 0.12, \
            f"Sampler did not recover parameter a on held-out model data: {challenge_means[0]:.4f}"
        assert abs(challenge_means[1] - expected_b) <= 0.08, \
            f"Sampler did not recover parameter b on held-out model data: {challenge_means[1]:.4f}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
