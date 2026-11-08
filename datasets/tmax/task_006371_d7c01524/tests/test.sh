#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import re
import subprocess

import pytest

SOURCE = '/home/user/workspace/analyze_oscillator.go'
OUTPUT = '/home/user/analysis.json'
WORKSPACE = '/home/user/workspace'
BINARY = '/tmp/analyze_oscillator_verifier_bin'


def reference_results():
    dt = 0.1
    steps = 2000
    x = y = z = 0.1
    xs = [x]

    def deriv(a, b, c):
        return (1.0 / (1.0 + c ** 10) - 0.1 * a,
                a - 0.1 * b,
                b - 0.1 * c)

    for _ in range(steps):
        k1 = deriv(x, y, z)
        k2 = deriv(x + dt * k1[0] / 2, y + dt * k1[1] / 2, z + dt * k1[2] / 2)
        k3 = deriv(x + dt * k2[0] / 2, y + dt * k2[1] / 2, z + dt * k2[2] / 2)
        k4 = deriv(x + dt * k3[0], y + dt * k3[1], z + dt * k3[2])
        x += dt * (k1[0] + 2*k2[0] + 2*k3[0] + k4[0]) / 6
        y += dt * (k1[1] + 2*k2[1] + 2*k3[1] + k4[1]) / 6
        z += dt * (k1[2] + 2*k2[2] + 2*k3[2] + k4[2]) / 6
        xs.append(x)

    integral = dt / 3.0 * (xs[0] + xs[-1] +
                           4.0 * sum(xs[1:-1:2]) +
                           2.0 * sum(xs[2:-1:2]))

    n = len(xs)
    best_k = None
    best_power = -1.0
    for k in range(1, n // 2 + 1):
        angle = -2.0 * math.pi * k / n
        step_r, step_i = math.cos(angle), math.sin(angle)
        wr, wi = 1.0, 0.0
        real = imag = 0.0
        for value in xs:
            real += value * wr
            imag += value * wi
            wr, wi = wr * step_r - wi * step_i, wr * step_i + wi * step_r
        power = real * real + imag * imag
        if power > best_power:
            best_power = power
            best_k = k

    return integral, best_k / (n * dt)


@pytest.fixture(scope='session', autouse=True)
def build_and_run_submission():
    assert os.path.isfile(SOURCE), f'{SOURCE} does not exist.'
    assert not os.path.islink(SOURCE), f'{SOURCE} must be a regular Go source file, not a symlink.'

    with open(SOURCE, 'r', encoding='utf-8') as f:
        source = f.read()

    # Require evidence of each specifically requested numerical method and reject
    # the fixed answer literals that made the old verifier trivial to bypass.
    assert re.search(r'(?i)\b(rk4|runge[_ -]?kutta)\b', source), 'No RK4 implementation is identifiable in the Go source.'
    assert re.search(r'(?i)\bsimpson', source), "No Simpson's-rule implementation is identifiable in the Go source."
    assert re.search(r'(?i)\b(fft|fourier)', source), 'No FFT/Fourier implementation is identifiable in the Go source.'
    assert re.search(r'\bfor\b', source), 'The simulation must iterate over the requested time points.'

    number_tokens = re.findall(r'(?<![A-Za-z_])(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?', source)
    for token in number_tokens:
        value = float(token)
        assert not math.isclose(value, 1635.805, rel_tol=0.01), 'The source embeds the expected integral instead of deriving it.'
        assert not math.isclose(value, 0.0249875, rel_tol=0.05), 'The source embeds the expected frequency instead of deriving it.'

    if os.path.lexists(OUTPUT):
        os.remove(OUTPUT)
    if os.path.exists(BINARY):
        os.remove(BINARY)

    subprocess.run(['go', 'build', '-o', BINARY, SOURCE], cwd=WORKSPACE,
                   check=True, timeout=120)
    subprocess.run([BINARY], cwd=WORKSPACE, check=True, timeout=120)


def load_analysis():
    with open(OUTPUT, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            assert False, '/home/user/analysis.json is not a valid JSON file.'


def test_analysis_json_exists():
    """Verify that the executed Go program created analysis.json in the correct location."""
    assert os.path.isfile(OUTPUT), '/home/user/analysis.json does not exist.'
    assert not os.path.islink(OUTPUT), '/home/user/analysis.json must be a regular file.'


def test_analysis_json_contents():
    """Retain the original output assertions."""
    data = load_analysis()
    assert 'total_mrna_integral' in data, "Missing 'total_mrna_integral' in JSON output."
    assert 'dominant_frequency_hz' in data, "Missing 'dominant_frequency_hz' in JSON output."

    integral = data['total_mrna_integral']
    freq = data['dominant_frequency_hz']
    assert isinstance(integral, (int, float)), "'total_mrna_integral' must be a number."
    assert isinstance(freq, (int, float)), "'dominant_frequency_hz' must be a number."

    expected_integral = 1635.805
    expected_freq = 0.0249875
    assert math.isclose(integral, expected_integral, rel_tol=0.01), \
        f"'total_mrna_integral' {integral} is not within 1% of expected value {expected_integral}."
    assert math.isclose(freq, expected_freq, rel_tol=0.05), \
        f"'dominant_frequency_hz' {freq} is not within 5% of expected value {expected_freq}."


def test_results_against_independent_computation():
    """Compare the program's freshly generated results with independently derived values."""
    data = load_analysis()
    expected_integral, expected_freq = reference_results()
    assert math.isclose(data['total_mrna_integral'], expected_integral, rel_tol=1e-6, abs_tol=1e-6)
    assert math.isclose(data['dominant_frequency_hz'], expected_freq, rel_tol=1e-9, abs_tol=1e-12)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
