#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_task.py
import math
import os
import re
import shutil
import subprocess
import tempfile
import numpy as np

SOURCE = '/home/user/analyzer.cpp'
SIGNAL = '/home/user/signal.txt'
OUTPUT = '/home/user/peak_params.csv'
BINARY = '/tmp/analyzer_verified'


def parse_params(path):
    assert os.path.isfile(path), f"Error: {path} not found."
    with open(path, 'r') as f:
        content = f.read().strip()
    assert len(content.splitlines()) == 1, "Error: output must contain exactly one line."
    parts = content.split(',')
    assert len(parts) == 3, f"Error: Expected 3 comma-separated values, got {len(parts)} in '{content}'"
    try:
        values = tuple(float(x) for x in parts)
    except ValueError:
        raise AssertionError(f"Error: Could not parse values as floats. Got: '{content}'")
    assert all(math.isfinite(x) for x in values), f"Error: parameters must be finite, got {values}"
    return values


def best_grid_fit(signal):
    power = np.abs(np.fft.rfft(np.asarray(signal, dtype=float)))
    xs = np.arange(80.0, 120.0)
    ys = power[80:120]
    best = None
    for mu in np.arange(95.0, 105.0001, 0.1):
        for variance in np.arange(2.0, 6.0001, 0.1):
            shape = np.exp(-((xs - mu) ** 2) / (2.0 * variance))
            amplitude = float(np.dot(ys, shape) / np.dot(shape, shape))
            residual = amplitude * shape - ys
            loss = float(np.dot(residual, residual))
            if best is None or loss < best[0]:
                best = (loss, amplitude, mu, variance)
    return power, best


def submitted_loss(params, power):
    amplitude, mu, variance = params
    assert variance > 0, f"Error: Variance must be positive, got {variance}"
    xs = np.arange(80.0, 120.0)
    model = amplitude * np.exp(-((xs - mu) ** 2) / (2.0 * variance))
    residual = model - power[80:120]
    return float(np.dot(residual, residual))


def adaptation_factor(body):
    number = r'([0-9]+(?:\.[0-9]*)?(?:[eE][+-]?[0-9]+)?)'
    patterns = [
        (rf'\blr\s*\*=\s*{number}', lambda n: n),
        (rf'\blr\s*/=\s*{number}', lambda n: 1.0 / n),
        (rf'\blr\s*=\s*lr\s*\*\s*{number}', lambda n: n),
        (rf'\blr\s*=\s*{number}\s*\*\s*lr', lambda n: n),
        (rf'\blr\s*=\s*lr\s*/\s*{number}', lambda n: 1.0 / n),
    ]
    for pattern, convert in patterns:
        match = re.search(pattern, body)
        if match:
            return convert(float(match.group(1)))
    # No learning-rate assignment means that it stays unchanged.
    if not re.search(r'\blr\s*(?:[*\/]?=|\+\+|--)', body):
        return 1.0
    raise AssertionError("Could not verify the learning-rate adjustment.")


def run_program():
    if os.path.exists(OUTPUT):
        os.unlink(OUTPUT)
    result = subprocess.run([BINARY], cwd='/home/user', stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, timeout=30)
    assert result.returncode == 0, (
        f"Compiled analyzer exited with {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return parse_params(OUTPUT)


assert os.path.isfile(SOURCE), f"Error: {SOURCE} not found."
assert os.path.isfile(SIGNAL), f"Error: {SIGNAL} not found."
with open(SOURCE, 'r') as f:
    source = f.read()

# Ensure the requested algorithm and protected portions were retained.
without_comments = re.sub(r'/\*.*?\*/|//[^\n]*', '', source, flags=re.S)
compact = re.sub(r'\s+', '', without_comments)
for required in (
    'doubleA=10.0;', 'doublemu=90.0;', 'doublesigma_sq=1.0;',
    'loss+=err*err;', 'A-=lr*grad_A;', 'mu-=lr*grad_mu;',
    'sigma_sq-=lr*grad_sigma_sq;', 'fftw_plan_dft_r2c_1d(',
    'fftw_execute(', 'outfile<<A<<","<<mu<<","<<sigma_sq'
):
    assert required in compact, f"Required analyzer logic is missing or was changed: {required}"

adapt = re.search(
    r'if\s*\(\s*loss\s*>\s*prev_loss\s*\)\s*\{([^{}]*)\}\s*else\s*\{([^{}]*)\}',
    without_comments, flags=re.S)
assert adapt, "Could not find the loss-based learning-rate adaptation block."
up_loss_factor = adaptation_factor(adapt.group(1))
down_loss_factor = adaptation_factor(adapt.group(2))
assert 0.0 < up_loss_factor < 1.0, "Learning rate must decrease when loss increases."
assert 1.0 <= down_loss_factor <= 1.1, "Learning rate must stay the same or increase slightly when loss decreases."

# Compile the submitted source ourselves and require FFTW3 linkage.
compile_result = subprocess.run(
    ['/usr/bin/g++', '-std=c++11', '-O2', SOURCE, '-o', BINARY, '-lfftw3', '-lm'],
    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60)
assert compile_result.returncode == 0, f"Compilation failed:\n{compile_result.stderr}"
ldd = subprocess.run(['/usr/bin/ldd', BINARY], stdout=subprocess.PIPE,
                     stderr=subprocess.STDOUT, text=True, timeout=10)
assert ldd.returncode == 0 and 'libfftw3' in ldd.stdout, "Compiled analyzer is not linked against FFTW3."

with open(SIGNAL, 'rb') as f:
    original_signal_bytes = f.read()
original_signal = np.fromstring(original_signal_bytes.decode(), sep='\n')
assert original_signal.size > 0, "signal.txt is empty or invalid."

try:
    # Delete any prewritten CSV, execute the submitted analyzer, and retain all
    # original output assertions.
    original_params = run_program()
    a, mu, sigma_sq = original_params
    assert not math.isnan(a), "Error: Amplitude (A) is NaN."
    assert not math.isnan(mu), "Error: Mean_Frequency (mu) is NaN."
    assert not math.isnan(sigma_sq), "Error: Variance (sigma_sq) is NaN."
    assert 45.0 < a < 55.0, f"Error: Amplitude (A) out of bounds. Expected 45.0 < A < 55.0, got {a}"
    assert 95.0 < mu < 105.0, f"Error: Mean_Frequency (mu) out of bounds. Expected 95.0 < mu < 105.0, got {mu}"
    assert 2.0 < sigma_sq < 6.0, f"Error: Variance (sigma_sq) out of bounds. Expected 2.0 < sigma_sq < 6.0, got {sigma_sq}"

    power, best = best_grid_fit(original_signal)
    loss = submitted_loss(original_params, power)
    assert loss <= best[0] * 3.0 + 1e-6, (
        f"Reported parameters do not fit signal.txt: loss {loss}, reference grid loss {best[0]}"
    )

    # Exercise the compiled artifact on a derived signal. Scaling a signal must
    # scale the fitted amplitude while preserving its peak location and width.
    scale = 0.73
    with open(SIGNAL, 'w') as f:
        for value in original_signal * scale:
            f.write(f'{value:.17g}\n')
    scaled_params = run_program()
    scaled_power, scaled_best = best_grid_fit(original_signal * scale)
    scaled_loss = submitted_loss(scaled_params, scaled_power)
    assert scaled_loss <= scaled_best[0] * 3.0 + 1e-6, (
        f"Analyzer output does not fit the derived signal: loss {scaled_loss}, "
        f"reference grid loss {scaled_best[0]}"
    )
    assert abs(scaled_params[0] / original_params[0] - scale) < 0.08, (
        "Amplitude did not respond correctly when the input signal was scaled."
    )
    assert abs(scaled_params[1] - original_params[1]) < 1.0, (
        "Mean frequency changed unexpectedly for a scaled copy of the signal."
    )
    assert abs(scaled_params[2] - original_params[2]) < 1.0, (
        "Variance changed unexpectedly for a scaled copy of the signal."
    )
finally:
    with open(SIGNAL, 'wb') as f:
        f.write(original_signal_bytes)

# Leave peak_params.csv as the output of a final run on the required signal.
final_params = run_program()
assert all(math.isfinite(x) for x in final_params)
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
