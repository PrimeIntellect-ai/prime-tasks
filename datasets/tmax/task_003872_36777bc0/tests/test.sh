#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import pytest

RESULTS_FILE = "/home/user/results.json"

def test_results_json_exists():
    """Test that the results.json file exists."""
    assert os.path.exists(RESULTS_FILE), f"The file {RESULTS_FILE} was not created."
    assert os.path.isfile(RESULTS_FILE), f"The path {RESULTS_FILE} is not a file."

def test_results_json_values():
    """Test that the results.json file contains the correct computed values."""
    with open(RESULTS_FILE, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {RESULTS_FILE} does not contain valid JSON.")

    expected_keys = {"covariance", "posterior_mean", "posterior_variance"}
    actual_keys = set(data.keys())

    missing_keys = expected_keys - actual_keys
    assert not missing_keys, f"The JSON file is missing keys: {missing_keys}"

    # Expected values derived from the valid dataset
    expected_covariance = 0.648
    expected_post_mean = 50.51764705882353
    expected_post_var = 2.9411764705882355

    assert math.isclose(data["covariance"], expected_covariance, rel_tol=1e-3, abs_tol=1e-3), \
        f"Covariance is incorrect. Expected ~{expected_covariance}, got {data['covariance']}"

    assert math.isclose(data["posterior_mean"], expected_post_mean, rel_tol=1e-3, abs_tol=1e-3), \
        f"Posterior mean is incorrect. Expected ~{expected_post_mean}, got {data['posterior_mean']}"

    assert math.isclose(data["posterior_variance"], expected_post_var, rel_tol=1e-3, abs_tol=1e-3), \
        f"Posterior variance is incorrect. Expected ~{expected_post_var}, got {data['posterior_variance']}"
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_rust_program.py
import csv
import json
import math
import os
import random
import subprocess

HOME = "/home/user"
CSV_PATH = os.path.join(HOME, "sensor_data.csv")
RESULTS_PATH = os.path.join(HOME, "results.json")
EXPECTED_KEYS = {"covariance", "posterior_mean", "posterior_variance"}


def find_rust_binary():
    manifests = []
    preferred = os.path.join(HOME, "cleaner", "Cargo.toml")
    if os.path.isfile(preferred):
        manifests.append(preferred)

    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if d not in {".cargo", ".rustup", "target", ".git"}]
        manifest = os.path.join(root, "Cargo.toml")
        if "Cargo.toml" in files and manifest not in manifests:
            manifests.append(manifest)

    assert manifests, "No Rust Cargo project was found under /home/user."

    env = os.environ.copy()
    env["HOME"] = HOME
    env["CARGO_HOME"] = os.path.join(HOME, ".cargo")
    env["CARGO_NET_OFFLINE"] = "true"

    errors = []
    for manifest in manifests:
        try:
            proc = subprocess.run(
                ["/usr/bin/cargo", "metadata", "--no-deps", "--format-version", "1", "--manifest-path", manifest],
                text=True, capture_output=True, timeout=60, env=env,
            )
            if proc.returncode != 0:
                errors.append(f"{manifest}: {proc.stderr.strip()}")
                continue
            metadata = json.loads(proc.stdout)
            for package in metadata.get("packages", []):
                binary_targets = [t for t in package.get("targets", []) if "bin" in t.get("kind", [])]
                if not binary_targets:
                    continue
                default_name = package.get("default_run")
                target = next((t for t in binary_targets if t.get("name") == default_name), binary_targets[0])
                source = target.get("src_path", "")
                assert source.endswith(".rs") and os.path.isfile(source), \
                    f"Cargo binary target does not point to an existing Rust source file: {source}"
                command = [
                    "/usr/bin/cargo", "run", "--quiet", "--manifest-path", manifest,
                    "-p", package["name"], "--bin", target["name"],
                ]
                return command, os.path.dirname(manifest), env
        except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
            errors.append(f"{manifest}: {exc}")

    raise AssertionError("No runnable Rust binary target was found. " + " | ".join(errors))


def expected_values(valid):
    n = len(valid)
    mean_a = sum(a for a, _ in valid) / n
    mean_b = sum(b for _, b in valid) / n
    covariance = sum((a - mean_a) * (b - mean_b) for a, b in valid) / (n - 1)
    posterior_variance = 1.0 / (1.0 / 10.0 + n / 25.0)
    posterior_mean = posterior_variance * (50.0 / 10.0 + n * mean_a / 25.0)
    return {
        "covariance": covariance,
        "posterior_mean": posterior_mean,
        "posterior_variance": posterior_variance,
    }


def make_case(rng, case_number):
    valid = []
    rows = []
    for i in range(7 + case_number):
        a = round(rng.uniform(31.0, 79.0), 3)
        b = round(rng.uniform(-18.0, 42.0) + 0.17 * a, 3)
        valid.append((a, b))
        rows.append([f"v{case_number}_{i}", str(a), str(b), "0"])

    rows.extend([
        [f"bad{case_number}_1", "NaN", "12.5", "0"],
        [f"bad{case_number}_2", "44.1", "NaN", "0"],
        [f"bad{case_number}_3", "", "9.2", "0"],
        [f"bad{case_number}_4", "46.0", "", "0"],
        [f"bad{case_number}_5", "not-a-number", "8.1", "0"],
        [f"bad{case_number}_6", "47.0", "broken", "0"],
        [f"bad{case_number}_7", "999.0", "-999.0", "1"],
    ])
    rng.shuffle(rows)
    return rows, valid


def check_output(expected):
    assert os.path.isfile(RESULTS_PATH), "The Rust program did not create /home/user/results.json."
    with open(RESULTS_PATH, "r") as handle:
        data = json.load(handle)
    assert isinstance(data, dict), "results.json must contain a JSON object."
    assert set(data.keys()) == EXPECTED_KEYS, \
        f"results.json must contain exactly {EXPECTED_KEYS}; got {set(data.keys())}."
    for key, wanted in expected.items():
        value = data[key]
        assert isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value), \
            f"{key} must be a finite numeric JSON value."
        assert math.isclose(value, wanted, rel_tol=1e-3, abs_tol=1e-3), \
            f"{key} is incorrect for a verifier-generated dataset: expected {wanted}, got {value}."


def main():
    command, cwd, env = find_rust_binary()
    rng = random.SystemRandom()

    for case_number in range(2):
        rows, valid = make_case(rng, case_number)
        with open(CSV_PATH, "w", newline="") as handle:
            writer = csv.writer(handle, lineterminator="\n")
            writer.writerow(["timestamp", "sensor_a", "sensor_b", "error_flag"])
            writer.writerows(rows)

        try:
            os.unlink(RESULTS_PATH)
        except FileNotFoundError:
            pass

        proc = subprocess.run(command, cwd=cwd, env=env, text=True, capture_output=True, timeout=120)
        assert proc.returncode == 0, \
            f"The Rust project failed to compile or run.\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
        check_output(expected_values(valid))


if __name__ == "__main__":
    main()
DYNAMIC_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 && \
   python3 /tmp/test_rust_program.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
