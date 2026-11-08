#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import subprocess

SOURCE = "/home/user/mcmc_pipeline.cpp"
BINARY = "/home/user/mcmc_pipeline"
RESULTS = "/home/user/results.json"


def read_results():
    with open(RESULTS, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as exc:
            raise AssertionError("results.json is not a valid JSON file.") from exc


def run_pipeline():
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    completed = subprocess.run(
        [BINARY], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert completed.returncode == 0, (
        f"mcmc_pipeline exited with status {completed.returncode}: {completed.stderr}"
    )
    assert os.path.isfile(RESULTS), "Running mcmc_pipeline did not create /home/user/results.json."
    return read_results()


def test_pipeline():
    # Preserve the original required-file assertions before rebuilding or running.
    assert os.path.isfile(SOURCE), "Source file /home/user/mcmc_pipeline.cpp is missing."
    assert os.path.isfile(BINARY), "Compiled binary /home/user/mcmc_pipeline is missing."
    assert os.path.isfile(RESULTS), "Results file /home/user/results.json is missing."

    with open(SOURCE, "r") as f:
        code = f.read()

    # Preserve the original LLT assertion and check the explicitly required RNG
    # and Box-Muller machinery outside comments and string literals.
    has_llt = "llt()" in code or "LLT" in code
    assert has_llt, "Cholesky decomposition (LLT) not found in source code. You must use Eigen's LLT."

    cleaned = re.sub(r"//.*?$|/\*.*?\*/", " ", code, flags=re.MULTILINE | re.DOTALL)
    cleaned = re.sub(r'"(?:\\.|[^"\\])*"', '""', cleaned)
    assert re.search(r"\b(?:std::)?mt19937\b", cleaned), "std::mt19937 is not used."
    assert re.search(r"\b(?:std::)?uniform_real_distribution\s*<\s*double\s*>", cleaned), \
        "uniform_real_distribution<double> is not used."
    assert re.search(r"mt19937\s+\w+\s*[({]\s*42\s*[)}]|\.seed\s*\(\s*42\s*\)", cleaned), \
        "The mt19937 generator is not initialized with seed 42."
    assert re.search(r"\b(?:std::)?sqrt\s*\(", cleaned) and re.search(r"\b(?:std::)?log\s*\(", cleaned), \
        "Box-Muller sqrt/log operations are missing."
    assert re.search(r"\b(?:std::)?(?:cos|sin)\s*\(", cleaned), "Box-Muller trigonometric operation is missing."
    assert "10000" in cleaned and "100000" in cleaned, "Required burn-in and sample counts are missing."

    # Rebuild the demanded artifact from the submitted source, preventing an
    # unrelated prebuilt executable from satisfying the behavioral checks.
    build = subprocess.run(
        ["g++", "-std=c++17", "-O2", "-I/usr/include/eigen3", SOURCE, "-o", BINARY],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
    )
    assert build.returncode == 0, f"Submitted source does not compile: {build.stderr}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), "Compiled artifact is not executable."

    first = run_pipeline()
    second = run_pipeline()
    assert first == second, "Repeated runs are not reproducible with the required fixed seed."

    data = second
    required_keys = ["empirical_mu", "empirical_cov", "kl_divergence"]
    for key in required_keys:
        assert key in data, f"Missing required key '{key}' in results.json."

    emp_mu = data["empirical_mu"]
    emp_cov = data["empirical_cov"]
    kl_div = data["kl_divergence"]

    assert isinstance(emp_mu, list) and len(emp_mu) == 2, "empirical_mu must be a list of 2 elements."
    assert isinstance(emp_cov, list) and len(emp_cov) == 2, "empirical_cov must be a 2x2 matrix."
    assert all(isinstance(row, list) and len(row) == 2 for row in emp_cov), \
        "empirical_cov must be a 2x2 matrix."
    assert isinstance(kl_div, (int, float)) and not isinstance(kl_div, bool), \
        "kl_divergence must be a number."

    values = emp_mu + emp_cov[0] + emp_cov[1] + [kl_div]
    assert all(isinstance(x, (int, float)) and not isinstance(x, bool) and math.isfinite(x) for x in values), \
        "All reported statistics must be finite numbers."

    mu_true = [1.0, 2.0]
    cov_true = [[2.0, 0.5], [0.5, 1.0]]
    for i in range(2):
        assert math.isclose(emp_mu[i], mu_true[i], abs_tol=0.1), \
            f"Empirical mean at index {i} ({emp_mu[i]}) is too far from true mean ({mu_true[i]})."
    for i in range(2):
        for j in range(2):
            assert math.isclose(emp_cov[i][j], cov_true[i][j], abs_tol=0.2), \
                f"Empirical covariance at [{i}][{j}] ({emp_cov[i][j]}) is too far from true covariance ({cov_true[i][j]})."
    assert 0 <= kl_div <= 0.05, f"KL divergence {kl_div} is out of expected bounds [0, 0.05]."

    # Independently derive KL from the produced empirical statistics rather than
    # trusting a hardcoded distance value.
    assert math.isclose(emp_cov[0][1], emp_cov[1][0], rel_tol=0.0, abs_tol=1e-8), \
        "Empirical covariance is not symmetric."
    det0 = emp_cov[0][0] * emp_cov[1][1] - emp_cov[0][1] * emp_cov[1][0]
    assert emp_cov[0][0] > 0 and det0 > 0, "Empirical covariance is not positive definite."
    det1 = 1.75
    inv1 = [[1.0 / 1.75, -0.5 / 1.75], [-0.5 / 1.75, 2.0 / 1.75]]
    trace_term = sum(inv1[i][j] * emp_cov[j][i] for i in range(2) for j in range(2))
    delta = [mu_true[i] - emp_mu[i] for i in range(2)]
    quad = sum(delta[i] * inv1[i][j] * delta[j] for i in range(2) for j in range(2))
    expected_kl = 0.5 * (math.log(det1 / det0) - 2.0 + trace_term + quad)
    assert math.isclose(kl_div, expected_kl, rel_tol=2e-4, abs_tol=2e-5), \
        f"Reported KL divergence {kl_div} is inconsistent with the empirical statistics ({expected_kl})."

    # A finite MCMC realization cannot exactly equal every target parameter;
    # reject the audit's fixed target-statistics shortcut.
    exact_target = emp_mu == mu_true and emp_cov == cov_true
    assert not exact_target, "results.json contains hardcoded target parameters rather than empirical statistics."

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
