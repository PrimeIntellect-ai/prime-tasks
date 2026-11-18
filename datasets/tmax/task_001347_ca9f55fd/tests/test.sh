#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import subprocess
import tempfile
import textwrap
import pytest

WORKING_DIR = "/home/user/bio_mcmc"
LIKELIHOOD = os.path.join(WORKING_DIR, "likelihood.cpp")


def run(cmd, **kwargs):
    return subprocess.run(cmd, timeout=30, **kwargs)


def test_eigen3_installed():
    assert os.path.exists("/usr/include/eigen3/Eigen/Dense"), \
        "Eigen3 library does not appear to be installed at /usr/include/eigen3."


def test_likelihood_cpp_uses_svd():
    assert os.path.isfile(LIKELIHOOD), f"File missing: {LIKELIHOOD}"
    with open(LIKELIHOOD, "r") as f:
        content = f.read()

    assert "JacobiSVD" in content, "likelihood.cpp does not use JacobiSVD as instructed."
    assert "LLT" not in content, "likelihood.cpp still contains LLT logic, which should have been replaced."
    assert "ComputeThinU" in content and "ComputeThinV" in content, \
        "JacobiSVD must request ComputeThinU and ComputeThinV."


def expected_log_likelihood(eigenvalues, projections):
    retained = [(s, p) for s, p in zip(eigenvalues, projections) if s >= 1e-6]
    rank = len(retained)
    log_pseudo_det = sum(math.log(s) for s, _ in retained)
    quadratic = sum((p * p) / s for s, p in retained)
    return -0.5 * (rank * math.log(2.0 * math.pi) + log_pseudo_det + quadratic)


def test_likelihood_formula_and_threshold():
    harness = r'''
#include <Eigen/Dense>
#include <iomanip>
#include <iostream>
#include "likelihood.h"

int main() {
    std::cout << std::setprecision(17);

    {
        Eigen::VectorXd x(3), mu(3);
        Eigen::MatrixXd cov = Eigen::MatrixXd::Zero(3, 3);
        x << 2.0, 3.0, 5.0;
        mu.setZero();
        cov(0,0) = 4.0;
        cov(1,1) = 1.0;
        cov(2,2) = 1e-7;
        std::cout << compute_log_likelihood(x, mu, cov) << "\n";
    }

    {
        Eigen::VectorXd x(3), mu(3);
        Eigen::MatrixXd cov = Eigen::MatrixXd::Zero(3, 3);
        x << 0.5, 0.002, 100.0;
        mu.setZero();
        cov(0,0) = 2.0;
        cov(1,1) = 1.1e-6;
        cov(2,2) = 0.9e-6;
        std::cout << compute_log_likelihood(x, mu, cov) << "\n";
    }

    {
        Eigen::VectorXd x(2), mu(2);
        Eigen::MatrixXd cov(2,2);
        x << 2.0, -1.0;
        mu << 1.0, -3.0;
        cov << 2.0, 2.0,
               2.0, 2.0;
        std::cout << compute_log_likelihood(x, mu, cov) << "\n";
    }

    {
        Eigen::VectorXd x(3), mu(3);
        Eigen::MatrixXd cov = Eigen::MatrixXd::Zero(3, 3);
        x << 8.0, -2.0, 4.0;
        mu << 1.0, 1.0, 1.0;
        std::cout << compute_log_likelihood(x, mu, cov) << "\n";
    }
    return 0;
}
'''

    with tempfile.TemporaryDirectory() as td:
        harness_path = os.path.join(td, "likelihood_harness.cpp")
        binary_path = os.path.join(td, "likelihood_harness")
        with open(harness_path, "w") as f:
            f.write(harness)

        compile_res = run([
            "g++", "-O2", "-std=c++14", "-I/usr/include/eigen3",
            f"-I{WORKING_DIR}", harness_path, LIKELIHOOD, "-o", binary_path
        ], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert compile_res.returncode == 0, \
            f"Could not compile likelihood test harness:\n{compile_res.stderr.decode()}"

        result = run([binary_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert result.returncode == 0, \
            f"Likelihood harness failed:\n{result.stderr.decode()}"

        lines = result.stdout.decode().strip().splitlines()
        assert len(lines) == 4, f"Expected four likelihood results, got: {result.stdout.decode()!r}"
        try:
            actual = [float(line) for line in lines]
        except ValueError:
            pytest.fail(f"Likelihood returned non-numeric output: {lines!r}")
        assert all(math.isfinite(v) for v in actual), f"Likelihood returned non-finite values: {actual!r}"

        expected = [
            expected_log_likelihood([4.0, 1.0, 1e-7], [2.0, 3.0, 5.0]),
            expected_log_likelihood([2.0, 1.1e-6, 0.9e-6], [0.5, 0.002, 100.0]),
            expected_log_likelihood([4.0, 0.0], [3.0 / math.sqrt(2.0), -1.0 / math.sqrt(2.0)]),
            expected_log_likelihood([0.0, 0.0, 0.0], [7.0, -3.0, 3.0]),
        ]
        for i, (got, want) in enumerate(zip(actual, expected)):
            assert math.isclose(got, want, rel_tol=1e-9, abs_tol=1e-9), \
                f"Likelihood case {i} is incorrect: got {got}, expected {want}"


def build_reference_sampler(directory):
    source = r'''
#include <Eigen/Dense>
#include <cmath>
#include <iostream>
#include <random>

static double reference_ll(const Eigen::VectorXd& x, const Eigen::VectorXd& mu,
                           const Eigen::MatrixXd& cov) {
    const double PI = 3.14159265358979323846;
    Eigen::JacobiSVD<Eigen::MatrixXd> svd(
        cov, Eigen::ComputeThinU | Eigen::ComputeThinV);
    const Eigen::VectorXd values = svd.singularValues();
    Eigen::VectorXd inverse_values = Eigen::VectorXd::Zero(values.size());
    double log_pseudo_det = 0.0;
    int rank = 0;
    for (int i = 0; i < values.size(); ++i) {
        if (values(i) >= 1e-6) {
            inverse_values(i) = 1.0 / values(i);
            log_pseudo_det += std::log(values(i));
            ++rank;
        }
    }
    Eigen::MatrixXd pseudo_inverse =
        svd.matrixV() * inverse_values.asDiagonal() * svd.matrixU().transpose();
    Eigen::VectorXd diff = x - mu;
    return -0.5 * (rank * std::log(2.0 * PI) + log_pseudo_det
                   + diff.dot(pseudo_inverse * diff));
}

int main() {
    const int n_dim = 5;
    Eigen::VectorXd x = Eigen::VectorXd::Zero(n_dim);
    Eigen::VectorXd mu = Eigen::VectorXd::Zero(n_dim);
    Eigen::MatrixXd cov = Eigen::MatrixXd::Ones(n_dim, n_dim);
    for (int i = 0; i < n_dim; ++i) cov(i,i) += 1e-10;

    std::mt19937 gen(42);
    std::normal_distribution<double> prop_dist(0.0, 0.1);
    std::uniform_real_distribution<double> uni_dist(0.0, 1.0);
    Eigen::VectorXd current_theta = Eigen::VectorXd::Zero(3);
    double current_ll = reference_ll(x, mu, cov);
    Eigen::VectorXd sum_theta = Eigen::VectorXd::Zero(3);

    for (int i = 0; i < 5000; ++i) {
        Eigen::VectorXd prop_theta = current_theta;
        for (int j = 0; j < 3; ++j) prop_theta(j) += prop_dist(gen);
        for (int j = 0; j < n_dim; ++j) mu(j) = prop_theta(0) * 0.1;
        double prop_ll = reference_ll(x, mu, cov);
        double current_prior = -0.5 * current_theta.squaredNorm();
        double prop_prior = -0.5 * prop_theta.squaredNorm();
        double log_alpha = (prop_ll + prop_prior) - (current_ll + current_prior);
        if (std::log(uni_dist(gen)) < log_alpha || current_ll == -INFINITY) {
            current_theta = prop_theta;
            current_ll = prop_ll;
        }
        sum_theta += current_theta;
    }

    Eigen::VectorXd mean_theta = sum_theta / 5000.0;
    std::cout << mean_theta(0) << "," << mean_theta(1) << "," << mean_theta(2) << std::endl;
    return 0;
}
'''
    source_path = os.path.join(directory, "reference_sampler.cpp")
    binary_path = os.path.join(directory, "reference_sampler")
    with open(source_path, "w") as f:
        f.write(source)
    result = run([
        "g++", "-O3", "-std=c++14", "-I/usr/include/eigen3",
        source_path, "-o", binary_path
    ], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert result.returncode == 0, f"Reference sampler compilation failed:\n{result.stderr.decode()}"
    return binary_path


def parse_output(output, label):
    parts = output.split(",")
    assert len(parts) == 3, f"Expected 3 comma-separated values from {label}, got: {output}"
    try:
        values = [float(part) for part in parts]
    except ValueError:
        pytest.fail(f"Output values from {label} are not valid floats: {output}")
    assert all(math.isfinite(value) for value in values), \
        f"Output from {label} contains NaN or infinity: {output}"
    return values


def test_build_and_run_mcmc():
    run(["make", "clean"], cwd=WORKING_DIR, stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL)
    build_res = run(["make"], cwd=WORKING_DIR, stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE)
    assert build_res.returncode == 0, f"Compilation failed:\n{build_res.stderr.decode()}"

    executable = os.path.join(WORKING_DIR, "mcmc_sampler")
    assert os.path.isfile(executable), "Executable mcmc_sampler was not created."
    assert os.access(executable, os.X_OK), "mcmc_sampler is not executable."
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", "mcmc_sampler is not a compiled ELF executable."

    run_res = run([executable, "/home/user/bio_mcmc/data.csv"], cwd=WORKING_DIR,
                  stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert run_res.returncode == 0, f"Execution failed:\n{run_res.stderr.decode()}"
    output = run_res.stdout.decode().strip()
    actual_values = parse_output(output, "mcmc_sampler")

    with tempfile.TemporaryDirectory() as td:
        reference_binary = build_reference_sampler(td)
        reference_res = run([reference_binary], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE)
        assert reference_res.returncode == 0, \
            f"Reference sampler failed:\n{reference_res.stderr.decode()}"
        reference_output = reference_res.stdout.decode().strip()
        expected_values = parse_output(reference_output, "reference sampler")

    for got, want in zip(actual_values, expected_values):
        assert math.isclose(got, want, rel_tol=1e-6, abs_tol=2e-5), \
            f"Sampler posterior mean is incorrect: got {output}, expected {reference_output}"

    final_txt_path = os.path.join(WORKING_DIR, "final_mean.txt")
    assert os.path.isfile(final_txt_path), f"File missing: {final_txt_path}"
    with open(final_txt_path, "r") as f:
        final_txt_content = f.read().strip()
    assert final_txt_content == output, \
        f"Contents of final_mean.txt ('{final_txt_content}') do not match the program output ('{output}')."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
