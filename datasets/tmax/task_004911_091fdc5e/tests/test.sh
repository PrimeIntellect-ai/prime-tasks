#!/bin/bash
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_dataset.py
import inspect
import json
import math
import os
import runpy
import sys

import numpy as np
import scipy.fft
import scipy.fftpack
import scipy.integrate
import scipy.stats

SCRIPT = "/home/user/prepare_dataset.py"
OUTPUT = "/home/user/dataset_stats.json"

assert os.path.isfile(SCRIPT), f"{SCRIPT} does not exist or is not a regular file."
assert os.path.getsize(SCRIPT) > 0, f"{SCRIPT} is empty."

# Ensure the result being checked was produced by this execution.
if os.path.lexists(OUTPUT):
    os.remove(OUTPUT)

solve_calls = []
fft_signal_count = [0]
kde_calls = [0]

original_solve_ivp = scipy.integrate.solve_ivp
original_gaussian_kde = scipy.stats.gaussian_kde
original_fft_functions = {}


def tracked_solve_ivp(*args, **kwargs):
    result = original_solve_ivp(*args, **kwargs)
    try:
        bound = inspect.signature(original_solve_ivp).bind_partial(*args, **kwargs)
        bound.apply_defaults()
        t_span = bound.arguments["t_span"]
        t_eval = np.asarray(bound.arguments["t_eval"], dtype=float)
        valid = (
            len(t_span) == 2
            and math.isclose(float(t_span[0]), 0.0, abs_tol=1e-12)
            and math.isclose(float(t_span[1]), 100.0, abs_tol=1e-12)
            and t_eval.shape == (1000,)
            and np.allclose(t_eval, np.linspace(0.0, 100.0, 1000), rtol=0, atol=1e-12)
            and math.isclose(float(bound.arguments["rtol"]), 1e-6, rel_tol=0, abs_tol=1e-15)
            and np.allclose(bound.arguments["atol"], 1e-8, rtol=0, atol=1e-15)
        )
    except Exception:
        valid = False
    solve_calls.append(valid)
    return result


def make_tracked_fft(fn):
    def tracked(*args, **kwargs):
        if args:
            try:
                arr = np.asarray(args[0])
                axis = kwargs.get("axis", -1)
                if len(args) >= 3 and isinstance(args[2], (int, np.integer)):
                    axis = int(args[2])
                axis = int(axis) % arr.ndim
                if arr.shape[axis] >= 1000:
                    fft_signal_count[0] += int(arr.size // arr.shape[axis])
            except Exception:
                pass
        return fn(*args, **kwargs)
    return tracked


def tracked_gaussian_kde(*args, **kwargs):
    kde_calls[0] += 1
    return original_gaussian_kde(*args, **kwargs)


scipy.integrate.solve_ivp = tracked_solve_ivp
scipy.stats.gaussian_kde = tracked_gaussian_kde

for module, names in (
    (np.fft, ("fft", "rfft")),
    (scipy.fft, ("fft", "rfft")),
    (scipy.fftpack, ("fft", "rfft")),
):
    for name in names:
        if hasattr(module, name):
            key = (module, name)
            original_fft_functions[key] = getattr(module, name)
            setattr(module, name, make_tracked_fft(getattr(module, name)))

try:
    old_argv = sys.argv
    sys.argv = [SCRIPT]
    runpy.run_path(SCRIPT, run_name="__main__")
finally:
    sys.argv = old_argv
    scipy.integrate.solve_ivp = original_solve_ivp
    scipy.stats.gaussian_kde = original_gaussian_kde
    for (module, name), fn in original_fft_functions.items():
        setattr(module, name, fn)

assert len(solve_calls) >= 51 and sum(solve_calls) >= 51, (
    "prepare_dataset.py must perform the validation and 50 dataset simulations "
    "with solve_ivp, 1000 evaluation points, rtol=1e-6, and atol=1e-8."
)
assert fft_signal_count[0] >= 50, "prepare_dataset.py did not perform FFT analysis on all 50 signals."
assert kde_calls[0] >= 1, "prepare_dataset.py did not perform scipy.stats.gaussian_kde density estimation."

# Preserve the original output assertions.
assert os.path.exists(OUTPUT), f"{OUTPUT} does not exist. Did you run your script and save the output?"
with open(OUTPUT, "r") as f:
    try:
        data = json.load(f)
    except json.JSONDecodeError:
        raise AssertionError(f"{OUTPUT} is not a valid JSON file.")

expected_keys = {"max_error_validation", "mean_dominant_freq", "kde_at_target"}
missing_keys = expected_keys - set(data.keys())
assert not missing_keys, f"Missing keys in JSON output: {missing_keys}"
assert set(data.keys()) == expected_keys, f"JSON output must contain exactly these keys: {expected_keys}"

max_err = data["max_error_validation"]
mean_dom = data["mean_dominant_freq"]
kde_val = data["kde_at_target"]

assert isinstance(max_err, (int, float)), "max_error_validation must be a number."
assert isinstance(mean_dom, (int, float)), "mean_dominant_freq must be a number."
assert isinstance(kde_val, (int, float)), "kde_at_target must be a number."
assert 0 <= max_err < 1e-3, f"max_error_validation ({max_err}) is too large. Check your analytical solution and solver tolerances."
assert math.isclose(mean_dom, 0.77, abs_tol=0.05), f"mean_dominant_freq ({mean_dom}) is not close to the expected value (~0.77 Hz)."
assert math.isclose(kde_val, 1.05, abs_tol=0.1), f"kde_at_target ({kde_val}) is not close to the expected value (~1.05)."

# Independently regenerate the requested simulations and statistics rather than
# trusting values reported by the submission.
t_eval = np.linspace(0.0, 100.0, 1000)


def simulate(omega):
    def rhs(t, state):
        return (state[1], -0.1 * state[1] - omega * omega * state[0])

    return original_solve_ivp(
        rhs, (0.0, 100.0), (1.0, 0.0), t_eval=t_eval,
        rtol=1e-6, atol=1e-8
    ).y[0]


validation_y = simulate(5.0)
damped_frequency = math.sqrt(5.0 ** 2 - 0.05 ** 2)
exact_y = np.exp(-0.05 * t_eval) * (
    np.cos(damped_frequency * t_eval)
    + (0.05 / damped_frequency) * np.sin(damped_frequency * t_eval)
)
expected_max_error = float(np.max(np.abs(validation_y - exact_y)))

np.random.seed(42)
omegas = np.random.uniform(2.0, 8.0, 50)
sample_spacing = float(t_eval[1] - t_eval[0])
frequencies = np.fft.fftfreq(t_eval.size, d=sample_spacing)
positive = frequencies > 0
dominant = []
for omega in omegas:
    signal = simulate(float(omega))
    magnitude = np.abs(np.fft.fft(signal))
    dominant.append(float(frequencies[positive][np.argmax(magnitude[positive])]))

dominant = np.asarray(dominant)
expected_mean = float(np.mean(dominant))
expected_kde = float(original_gaussian_kde(dominant)([5.0 / (2.0 * math.pi)])[0])

assert math.isclose(float(max_err), expected_max_error, rel_tol=0.05, abs_tol=1e-8), (
    f"max_error_validation ({max_err}) does not match the independently recomputed value ({expected_max_error})."
)
assert math.isclose(float(mean_dom), expected_mean, rel_tol=0, abs_tol=1e-6), (
    f"mean_dominant_freq ({mean_dom}) does not match the independently recomputed value ({expected_mean})."
)
assert math.isclose(float(kde_val), expected_kde, rel_tol=0, abs_tol=1e-6), (
    f"kde_at_target ({kde_val}) does not match the independently recomputed value ({expected_kde})."
)
PY_EOF

if timeout 300s python3 /tmp/verify_dataset.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
