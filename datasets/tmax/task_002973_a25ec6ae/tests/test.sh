#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'REF_EOF' > /tmp/mcmc_reference.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#define N_ITERS 10000
#define N_DATA 20
unsigned long lcg_seed = 42;
double my_rand(void) {
    lcg_seed = (1103515245 * lcg_seed + 12345) % 2147483648;
    return (double)lcg_seed / 2147483648.0;
}
double my_randn(void) {
    double u1 = my_rand();
    double u2 = my_rand();
    return sqrt(-2.0 * log(u1 + 1e-15)) * cos(2.0 * M_PI * u2);
}
double log_likelihood(double mu, double sigma, double *data, int n) {
    if (sigma <= 0) return -1e9;
    double ll = 0.0;
    for (int i = 0; i < n; i++)
        ll += -log(sigma) - 0.5 * pow((data[i] - mu) / sigma, 2);
    return ll;
}
int main(void) {
    double data[N_DATA];
    FILE *f = fopen("/home/user/data.txt", "r");
    if (!f) return 1;
    for (int i = 0; i < N_DATA; i++) {
        if (fscanf(f, "%lf", &data[i]) != 1) return 1;
    }
    fclose(f);
    double current_mu = 0.0, current_sigma = 1.0;
    double current_ll = log_likelihood(current_mu, current_sigma, data, N_DATA);
    for (int i = 0; i < N_ITERS; i++) {
        double prop_mu = current_mu + my_randn() * 0.5;
        double prop_sigma = current_sigma + my_randn() * 0.5;
        double prop_ll = log_likelihood(prop_mu, prop_sigma, data, N_DATA);
        double accept_prob = exp(prop_ll - current_ll);
        if (my_rand() < accept_prob) {
            current_mu = prop_mu;
            current_sigma = prop_sigma;
            current_ll = prop_ll;
        }
        printf("%f,%f\n", current_mu, current_sigma);
    }
    return 0;
}
REF_EOF

gcc /tmp/mcmc_reference.c -lm -o /tmp/mcmc_reference
/tmp/mcmc_reference > /tmp/reference_trace.csv

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
from pathlib import Path

import matplotlib.image as mpimg
import numpy as np

HOME = Path("/home/user")


def parse_trace(path):
    lines = Path(path).read_text().strip().split("\n")
    assert len(lines) == 10000, f"Expected exactly 10,000 lines in {path}, got {len(lines)}."
    rows = []
    for number, line in enumerate(lines, 1):
        parts = line.split(',')
        assert len(parts) == 2, f"Line {number} of {path} does not contain exactly two comma-separated values."
        try:
            row = (float(parts[0]), float(parts[1]))
        except ValueError:
            raise AssertionError(f"Line {number} of {path} does not contain valid floats.")
        assert np.isfinite(row).all(), f"Line {number} of {path} contains a non-finite value."
        rows.append(row)
    return np.asarray(rows, dtype=float)


def run_program(path, output):
    with open(output, "wb") as f:
        subprocess.run([str(path)], cwd=HOME, stdout=f, stderr=subprocess.PIPE,
                       timeout=10, check=True)
    return parse_trace(output)


def test_mcmc_artifacts_and_behavior():
    binary = HOME / "mcmc_opt"
    source = HOME / "mcmc.c"
    trace_path = HOME / "trace.csv"

    assert binary.is_file(), f"File {binary} does not exist. Did you compile the C code?"
    assert os.access(binary, os.X_OK), f"File {binary} is not executable."
    assert binary.read_bytes()[:4] == b"\x7fELF", "mcmc_opt is not a gcc-produced native executable."
    assert source.is_file(), f"File {source} does not exist."
    assert trace_path.is_file(), f"File {trace_path} does not exist."

    content = source.read_text()
    fopen_count = content.count("fopen")
    assert fopen_count <= 1, "The C code still seems to call fopen multiple times. The bottleneck in log_likelihood might not be fixed."

    subprocess.run(["gcc", str(source), "-lm", "-o", "/tmp/mcmc_from_source"],
                   timeout=20, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    expected = parse_trace("/tmp/reference_trace.csv")
    submitted_trace = parse_trace(trace_path)
    binary_trace = run_program(binary, "/tmp/submitted_binary_trace.csv")
    source_trace = run_program(Path("/tmp/mcmc_from_source"), "/tmp/submitted_source_trace.csv")

    for label, observed in (("trace.csv", submitted_trace),
                            ("mcmc_opt output", binary_trace),
                            ("compiled mcmc.c output", source_trace)):
        assert np.allclose(observed, expected, rtol=0, atol=1e-6), \
            f"{label} does not implement the required reproducible Metropolis-Hastings sequence."
    assert trace_path.read_bytes() == Path("/tmp/submitted_binary_trace.csv").read_bytes(), \
        "trace.csv is not the output produced by the submitted mcmc_opt executable."


def test_results_txt():
    path = HOME / "results.txt"
    assert path.is_file(), f"File {path} does not exist."
    content = path.read_text().strip()
    match = re.fullmatch(r"mu=([0-9]+\.[0-9]{2})\nsigma=([0-9]+\.[0-9]{2})", content)
    assert match, f"{path} must contain exactly mu=X.XX and sigma=Y.YY on separate lines."
    mu_val, sigma_val = map(float, match.groups())
    assert 5.5 <= mu_val <= 5.7, f"mu value {mu_val} is out of expected range (5.5 - 5.7)."
    assert 1.0 <= sigma_val <= 1.3, f"sigma value {sigma_val} is out of expected range (1.0 - 1.3)."

    samples = parse_trace(HOME / "trace.csv")[1000:]
    expected_mu = f"{samples[:, 0].mean():.2f}"
    expected_sigma = f"{samples[:, 1].mean():.2f}"
    assert match.group(1) == expected_mu, "mu is not the rounded mean of the 9,000 post-burn-in samples."
    assert match.group(2) == expected_sigma, "sigma is not the rounded mean of the 9,000 post-burn-in samples."


def synthetic_trace(burn_value, mode):
    lines = [f"{burn_value},{burn_value}\n" for _ in range(1000)]
    for i in range(9000):
        if mode == 0:
            mu = 4.0 + (i % 90) / 30.0
            sigma = 0.7 + ((i * 17) % 70) / 70.0
        else:
            mu = 3.0 if i % 2 else 8.0
            sigma = 0.5 + (i % 5) * 0.5
        lines.append(f"{mu},{sigma}\n")
    return ''.join(lines).encode()


def run_plot_script(script, trace_bytes):
    (HOME / "trace.csv").write_bytes(trace_bytes)
    plot = HOME / "trace_plot.png"
    if plot.exists():
        plot.unlink()
    env = os.environ.copy()
    env["MPLBACKEND"] = "Agg"
    subprocess.run(["python3", str(script)], cwd=HOME, env=env, timeout=20,
                   check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert plot.is_file(), f"Visualization script {script} did not create trace_plot.png."
    assert plot.read_bytes().startswith(b"\x89PNG\r\n\x1a\n"), "trace_plot.png is not a PNG file."
    image = mpimg.imread(plot)
    assert image.ndim in (2, 3) and image.shape[0] >= 100 and image.shape[1] >= 100
    assert float(np.nanstd(image)) > 0.01, "trace_plot.png appears blank."
    return image.copy()


def test_visualization_script_and_plot():
    trace_path = HOME / "trace.csv"
    plot_path = HOME / "trace_plot.png"
    assert plot_path.is_file(), f"File {plot_path} does not exist. Did you generate the plot?"

    scripts = []
    for script in HOME.rglob("*.py"):
        try:
            text = script.read_text(errors="ignore")
        except OSError:
            continue
        if "trace.csv" in text and "trace_plot.png" in text:
            scripts.append(script)
    assert scripts, "No Python visualization script reading trace.csv and writing trace_plot.png was found."

    original_trace = trace_path.read_bytes()
    valid_script = None
    try:
        a = synthetic_trace(100.0, 0)
        b = synthetic_trace(-100.0, 0)
        c = synthetic_trace(100.0, 1)
        for script in scripts:
            try:
                image_a = run_plot_script(script, a)
                image_b = run_plot_script(script, b)
                image_c = run_plot_script(script, c)
                same_burn_ignored = image_a.shape == image_b.shape and np.array_equal(image_a, image_b)
                post_samples_used = image_a.shape != image_c.shape or not np.array_equal(image_a, image_c)
                if same_burn_ignored and post_samples_used:
                    valid_script = script
                    break
            except Exception:
                continue
        assert valid_script is not None, \
            "The visualization script must discard the first 1,000 rows and plot the post-burn-in trace data."
    finally:
        trace_path.write_bytes(original_trace)

    final_image = run_plot_script(valid_script, original_trace)
    assert final_image.size > 0

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
