#!/bin/bash
set -e
mkdir -p /logs/verifier

if python3 - <<'PY'
import json
import math
import os
import subprocess

import numpy as np
import pandas as pd
from scipy.signal import welch

SCRIPT = "/home/user/analyze_spectrum.py"
DATASET = "/home/user/spectroscopy_data.csv"
RESULT = "/home/user/hypothesis_result.json"


def assert_script_exists():
    assert os.path.exists(SCRIPT), f"Expected script {SCRIPT} does not exist."
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is not a file."


def run_submission():
    if os.path.exists(RESULT):
        os.remove(RESULT)
    completed = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert completed.returncode == 0, (
        f"Analysis script exited with status {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.exists(RESULT), f"Expected result file {RESULT} does not exist."
    assert os.path.isfile(RESULT), f"{RESULT} is not a file."
    try:
        with open(RESULT, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError("Result file is not valid JSON.") from exc

    expected_keys = {"power_A", "power_B", "best_model"}
    missing_keys = expected_keys - set(data.keys())
    assert not missing_keys, f"Result JSON is missing keys: {missing_keys}"
    assert isinstance(data["power_A"], (int, float)), "power_A must be a number."
    assert isinstance(data["power_B"], (int, float)), "power_B must be a number."
    assert math.isfinite(data["power_A"]), "power_A must be finite."
    assert math.isfinite(data["power_B"]), "power_B must be finite."
    return data


def independently_compute(amplitude):
    frequencies, psd = welch(
        np.asarray(amplitude, dtype=float),
        fs=200.0,
        window="hann",
        nperseg=1024,
        noverlap=512,
        detrend="constant",
        return_onesided=True,
        scaling="density",
    )

    def band_power(ranges):
        mask = np.zeros(frequencies.shape, dtype=bool)
        for low, high in ranges:
            mask |= (frequencies >= low) & (frequencies <= high)
        return float(np.sum(psd[mask]))

    power_a = band_power([(9.0, 11.0), (24.0, 26.0), (49.0, 51.0)])
    power_b = band_power([(9.0, 11.0), (19.0, 21.0), (49.0, 51.0)])
    return power_a, power_b, "A" if power_a > power_b else "B"


def assert_matches(data, amplitude, label):
    expected_a, expected_b, expected_model = independently_compute(amplitude)
    assert math.isclose(data["power_A"], expected_a, rel_tol=1e-8, abs_tol=1e-10), (
        f"{label}: power_A value {data['power_A']} is not close to expected {expected_a}."
    )
    assert math.isclose(data["power_B"], expected_b, rel_tol=1e-8, abs_tol=1e-10), (
        f"{label}: power_B value {data['power_B']} is not close to expected {expected_b}."
    )
    assert data["best_model"] == expected_model, (
        f"{label}: best_model is '{data['best_model']}', expected '{expected_model}'."
    )


assert_script_exists()
with open(DATASET, "rb") as f:
    original_dataset = f.read()

try:
    # Execute the submitted artifact on the original data and retain the original
    # verifier's known-value assertions.
    original_frame = pd.read_csv(DATASET)
    original_result = run_submission()
    assert_matches(original_result, original_frame["amplitude"].to_numpy(), "original data")

    expected_power_a = 41.05050519159955
    expected_power_b = 24.939151247065902
    expected_best_model = "A"
    assert math.isclose(original_result["power_A"], expected_power_a, rel_tol=1e-3), (
        f"power_A value {original_result['power_A']} is not close to expected {expected_power_a}."
    )
    assert math.isclose(original_result["power_B"], expected_power_b, rel_tol=1e-3), (
        f"power_B value {original_result['power_B']} is not close to expected {expected_power_b}."
    )
    assert original_result["best_model"] == expected_best_model, (
        f"best_model is '{original_result['best_model']}', expected '{expected_best_model}'."
    )

    # Exercise the script on fresh data unknown when the submission was written.
    seed = int.from_bytes(os.urandom(8), "little")
    rng = np.random.default_rng(seed)
    for index, (amp20, amp25) in enumerate(((0.4, 2.8), (3.1, 0.35)), start=1):
        n = 7000 + int(rng.integers(0, 1500))
        time = np.arange(n, dtype=float) / 200.0
        amplitude = (
            1.3 * np.sin(2 * np.pi * 10.0 * time + rng.uniform(0, 2 * np.pi))
            + amp20 * np.sin(2 * np.pi * 20.0 * time + rng.uniform(0, 2 * np.pi))
            + amp25 * np.sin(2 * np.pi * 25.0 * time + rng.uniform(0, 2 * np.pi))
            + 0.9 * np.sin(2 * np.pi * 50.0 * time + rng.uniform(0, 2 * np.pi))
            + rng.normal(0.0, 1.7, n)
        )
        pd.DataFrame({"time": time, "amplitude": amplitude}).to_csv(DATASET, index=False)
        challenge_result = run_submission()
        # Re-read exactly the decimal values made available to the submission.
        challenge_amplitude = pd.read_csv(DATASET)["amplitude"].to_numpy()
        assert_matches(challenge_result, challenge_amplitude, f"challenge {index}")
finally:
    with open(DATASET, "wb") as f:
        f.write(original_dataset)

# Leave the requested output corresponding to the original spectroscopy data.
final_result = run_submission()
final_frame = pd.read_csv(DATASET)
assert_matches(final_result, final_frame["amplitude"].to_numpy(), "restored original data")
PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
