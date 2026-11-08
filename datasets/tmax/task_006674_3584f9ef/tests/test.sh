#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import secrets
import subprocess

import numpy as np
from scipy import stats


def test_samples_txt_exists_and_valid():
    """Test that the notebook generated the complete deterministic sample set."""
    path = "/home/user/samples.txt"
    assert os.path.isfile(path), f"File {path} does not exist. The notebook may not have been executed."

    with open(path, "r") as f:
        lines = f.readlines()

    assert len(lines) == 10000, f"Expected 10000 lines in {path}, found {len(lines)}."

    rng = np.random.default_rng(42)
    expected = rng.exponential(scale=0.5, size=10000)
    expected_lines = [f"{value:.6f}" for value in expected]
    actual_lines = [line.rstrip("\r\n") for line in lines]
    assert actual_lines == expected_lines, (
        "samples.txt does not contain the samples produced by sampler.ipynb."
    )


def test_evaluate_py_exists():
    """Test that the evaluate.py script was created."""
    path = "/home/user/evaluate.py"
    assert os.path.isfile(path), f"Script {path} was not created."


def test_evaluate_uses_kstest():
    """Check that evaluate.py contains a call to scipy's kstest API."""
    path = "/home/user/evaluate.py"
    with open(path, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=path)

    imported_names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.module == "scipy.stats":
            for alias in node.names:
                if alias.name == "kstest":
                    imported_names.add(alias.asname or alias.name)

    found_call = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Attribute) and node.func.attr == "kstest":
            found_call = True
        if isinstance(node.func, ast.Name) and node.func.id in imported_names:
            found_call = True

    assert found_call, "evaluate.py must call scipy.stats.kstest."


def test_convergence_csv_matches_expected():
    """Test that convergence.csv has the correct KS statistics."""
    path = "/home/user/convergence.csv"
    assert os.path.isfile(path), f"Output file {path} was not created."

    expected_content = (
        "N,KS\n"
        "1000,0.0154\n"
        "5000,0.0097\n"
        "10000,0.0084\n"
    )

    with open(path, "r") as f:
        content = f.read()

    content_normalized = content.strip().replace("\r\n", "\n")
    expected_normalized = expected_content.strip()

    assert content_normalized == expected_normalized, (
        f"Content of {path} does not match expected output.\n"
        f"Expected:\n{expected_normalized}\n"
        f"Got:\n{content_normalized}"
    )


def test_evaluate_script_computes_fresh_results():
    """Run evaluate.py on unpredictable samples and independently derive the answer."""
    samples_path = "/home/user/samples.txt"
    output_path = "/home/user/convergence.csv"

    with open(samples_path, "rb") as f:
        original_samples = f.read()
    with open(output_path, "rb") as f:
        original_output = f.read()

    try:
        rng = np.random.default_rng(secrets.randbits(128))
        generated = np.concatenate([
            rng.exponential(scale=0.20, size=1000),
            rng.exponential(scale=1.10, size=4000),
            rng.exponential(scale=0.50, size=5000),
        ])
        np.savetxt(samples_path, generated, fmt="%.10f")
        test_samples = np.loadtxt(samples_path)

        expected_rows = []
        for n in (1000, 5000, 10000):
            statistic = stats.kstest(test_samples[:n], "expon", args=(0, 0.5)).statistic
            expected_rows.append(f"{n},{statistic:.4f}")
        expected_content = "N,KS\n" + "\n".join(expected_rows)

        os.remove(output_path)
        result = subprocess.run(
            ["python3", "/home/user/evaluate.py"],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, (
            "evaluate.py failed when executed.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(output_path), "evaluate.py did not create convergence.csv."

        with open(output_path, "r") as f:
            actual_content = f.read().strip().replace("\r\n", "\n")
        assert actual_content == expected_content, (
            "evaluate.py did not compute KS statistics from the first N input samples.\n"
            f"Expected:\n{expected_content}\nGot:\n{actual_content}"
        )
    finally:
        with open(samples_path, "wb") as f:
            f.write(original_samples)
        with open(output_path, "wb") as f:
            f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
