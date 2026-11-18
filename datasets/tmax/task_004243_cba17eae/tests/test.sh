#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_task.py
import hashlib
import importlib.util
import math
import os
import secrets
import subprocess
import sys

VENV_PYTHON = "/home/user/venv/bin/python"
SIM_DIR = "/home/user/sim"
WAVE_SIM = os.path.join(SIM_DIR, "wave_sim.py")
ENERGY = os.path.join(SIM_DIR, "energy.npy")
ANALYZE = os.path.join(SIM_DIR, "analyze.py")
PEAK = os.path.join(SIM_DIR, "peak.txt")
SPECTRUM = os.path.join(SIM_DIR, "spectrum.png")

assert os.path.isfile(VENV_PYTHON), "Virtual environment Python executable not found"
subprocess.run(
    [VENV_PYTHON, "-c", "import numpy, scipy, matplotlib; print('OK')"],
    check=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
)

import numpy as np
import matplotlib.image as mpimg

assert os.path.isfile(WAVE_SIM), f"File {WAVE_SIM} does not exist"
assert os.path.isfile(ANALYZE), f"File {ANALYZE} was not created"

with open(WAVE_SIM, "r", encoding="utf-8") as f:
    source = f.read()
if "random.shuffle(items)" in source:
    assert "sort" in source or "sorted" in source, \
        "random.shuffle is still present and no sorting was added"


def run_python(path, timeout=180):
    env = os.environ.copy()
    env["MPLBACKEND"] = "Agg"
    return subprocess.run(
        [VENV_PYTHON, path], cwd=SIM_DIR, env=env, check=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        timeout=timeout,
    )


def run_simulation():
    if os.path.exists(ENERGY):
        os.remove(ENERGY)
    run_python(WAVE_SIM)
    assert os.path.isfile(ENERGY), f"File {ENERGY} was not generated"
    data = np.load(ENERGY, allow_pickle=False)
    assert data.shape == (250,), f"energy.npy has wrong shape: {data.shape}"
    assert np.issubdtype(data.dtype, np.number), "energy.npy is not numeric"
    assert np.all(np.isfinite(data)), "energy.npy contains non-finite values"
    return np.array(data, copy=True)


# Execute the submitted simulation twice and require bit-for-bit reproducibility.
first = run_simulation()
second = run_simulation()
assert np.array_equal(first, second), "Repeated simulation runs are not deterministic"

# Independently reconstruct the ascending-id reduction from the specified simulation.
xs = [np.linspace(i, i + 1, 10000) for i in range(50)]
expected_energy = []
for step in range(250):
    t = step * 0.01
    total = 0.0
    for i in range(50):
        total += np.sum(np.sin(2 * np.pi * 7.0 * t + xs[i]) * 1e-8)
    expected_energy.append(total)
expected_energy = np.asarray(expected_energy)
assert np.array_equal(second, expected_energy), \
    "energy.npy was not produced by the required ascending-id reduction"

# Instrument run_sim() to verify every time step calls subdomains in strict id order.
spec = importlib.util.spec_from_file_location("submitted_wave_sim", WAVE_SIM)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
calls = []
original_compute = module.SubDomain.compute_val
original_save = module.np.save
original_shuffle = getattr(getattr(module, "random", None), "shuffle", None)

def fake_compute(self, t):
    calls.append(self.id)
    return float(self.id)

def reverse_shuffle(items):
    items[:] = list(reversed(items))

try:
    module.SubDomain.compute_val = fake_compute
    module.np.save = lambda *args, **kwargs: None
    if hasattr(module, "random") and original_shuffle is not None:
        module.random.shuffle = reverse_shuffle
    module.run_sim()
finally:
    module.SubDomain.compute_val = original_compute
    module.np.save = original_save
    if hasattr(module, "random") and original_shuffle is not None:
        module.random.shuffle = original_shuffle

assert len(calls) == 250 * 50, "Simulation did not reduce all 50 subdomains at every step"
ascending = list(range(50))
for step in range(250):
    observed = calls[step * 50:(step + 1) * 50]
    assert observed == ascending, \
        f"Reduction order at step {step} is not strictly ascending by id: {observed}"


def fft_peak(data):
    freqs = np.fft.rfftfreq(len(data), d=0.01)
    amplitudes = np.abs(np.fft.rfft(data))
    amplitudes[0] = -np.inf
    return float(freqs[int(np.argmax(amplitudes))])


def run_and_validate_analysis(data):
    np.save(ENERGY, data)
    for path in (PEAK, SPECTRUM):
        if os.path.exists(path):
            os.remove(path)

    run_python(ANALYZE)
    assert os.path.isfile(PEAK), f"File {PEAK} was not created"
    assert os.path.isfile(SPECTRUM), f"File {SPECTRUM} was not generated"

    with open(PEAK, "r", encoding="utf-8") as f:
        tokens = f.read().strip().split()
    assert len(tokens) == 1, "peak.txt must contain a single standard float"
    try:
        reported = float(tokens[0])
    except ValueError as exc:
        raise AssertionError(f"peak.txt does not contain a valid float: {tokens}") from exc
    assert math.isfinite(reported), "peak.txt contains a non-finite value"

    expected = fft_peak(data)
    bin_width = 1.0 / (len(data) * 0.01)
    assert abs(reported - expected) <= bin_width / 2 + 1e-8, \
        f"Reported peak {reported} Hz does not match FFT peak {expected} Hz"

    assert os.path.getsize(SPECTRUM) > 0, "spectrum.png is empty"
    with open(SPECTRUM, "rb") as f:
        png_bytes = f.read()
    assert png_bytes.startswith(b"\x89PNG\r\n\x1a\n"), "spectrum.png is not a PNG image"
    image = mpimg.imread(SPECTRUM)
    assert image.ndim in (2, 3) and image.shape[0] > 10 and image.shape[1] > 10, \
        "spectrum.png is not a usable plot image"
    assert float(np.ptp(image)) > 0.01, "spectrum.png appears blank"
    return reported, hashlib.sha256(png_bytes).hexdigest()


# Validate analysis on the actual generated energy and retain the original peak assertion.
actual_peak, actual_plot = run_and_validate_analysis(second)
assert math.isclose(actual_peak, 7.2, abs_tol=0.3) or math.isclose(actual_peak, 7.0, abs_tol=0.3), \
    f"Peak frequency {actual_peak} is not close to the expected 7.0 or 7.2 Hz"

# Exercise analyze.py on verifier-selected signals so a hardcoded 7 Hz answer cannot pass.
choices = [k for k in range(4, 110) if k not in (16, 17, 18, 19)]
k1 = secrets.choice(choices)
choices.remove(k1)
k2 = secrets.choice(choices)
t = np.arange(250) * 0.01
signal1 = 3.7 + 2.0 * np.sin(2 * np.pi * (k1 / 2.5) * t + 0.31) \
          + 0.2 * np.sin(2 * np.pi * (k2 / 2.5) * t)
_, plot1 = run_and_validate_analysis(signal1)

choices2 = [k for k in choices if k != k2]
k3 = secrets.choice(choices2)
signal2 = -1.2 + 1.8 * np.cos(2 * np.pi * (k3 / 2.5) * t + 0.73) \
          + 0.15 * np.sin(2 * np.pi * (k1 / 2.5) * t)
_, plot2 = run_and_validate_analysis(signal2)
assert plot1 != plot2, "spectrum.png was not updated for different input spectra"

# Restore and re-analyze the genuine simulation output as the final task state.
final_peak, _ = run_and_validate_analysis(second)
assert math.isclose(final_peak, actual_peak, abs_tol=1e-8), \
    "Final analysis output is inconsistent"
PY_EOF

if /home/user/venv/bin/python /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
