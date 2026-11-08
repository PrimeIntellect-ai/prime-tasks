#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import subprocess
import pytest

PROJECT = "/home/user/etl_pipeline"
MANIFEST = os.path.join(PROJECT, "Cargo.toml")
DATA_PATH = "/home/user/sensor_data.csv"
RESULTS_PATH = "/home/user/results.json"


def get_expected_results(data_path=DATA_PATH):
    assert os.path.isfile(data_path), f"Input file {data_path} is missing."

    rows = []
    with open(data_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(row)

    valid_h = [float(r["Humidity"]) for r in rows if r["Humidity"].strip() != ""]
    mean_h = sum(valid_h) / len(valid_h) if valid_h else 0.0

    cleaned_data = []
    for r in rows:
        h_str = r["Humidity"].strip()
        h_val = float(h_str) if h_str != "" else mean_h

        t_str = r["Temperature"].strip()
        p_str = r["Pressure"].strip()
        if t_str == "" or p_str == "":
            continue

        try:
            t_val = float(t_str)
            p_val = float(p_str)
        except ValueError:
            continue

        if t_val < -50.0 or t_val > 50.0:
            continue
        if p_val < 800.0 or p_val > 1200.0:
            continue

        cleaned_data.append({"t": t_val, "p": p_val, "h": h_val})

    n = len(cleaned_data)
    assert n > 0, "Cleaned dataset is empty, cannot compute statistics."

    sum_t = sum(d["t"] for d in cleaned_data)
    sum_p = sum(d["p"] for d in cleaned_data)
    sum_t2 = sum(d["t"] ** 2 for d in cleaned_data)
    sum_p2 = sum(d["p"] ** 2 for d in cleaned_data)
    sum_tp = sum(d["t"] * d["p"] for d in cleaned_data)

    numerator = n * sum_tp - sum_t * sum_p
    denominator = math.sqrt((n * sum_t2 - sum_t ** 2) * (n * sum_p2 - sum_p ** 2))
    correlation = numerator / denominator if denominator != 0 else 0.0

    mu_0 = 20.0
    var_0 = 25.0
    var_pop = 16.0
    post_var = 1.0 / (1.0 / var_0 + n / var_pop)
    post_mean = post_var * (mu_0 / var_0 + sum_t / var_pop)

    return {
        "cleaned_row_count": n,
        "correlation_temp_pressure": correlation,
        "posterior_mean_temp": post_mean,
        "posterior_variance_temp": post_var,
    }


def assert_results(expected):
    assert os.path.isfile(RESULTS_PATH), f"Results file {RESULTS_PATH} is missing."
    with open(RESULTS_PATH, "r", encoding="utf-8") as f:
        try:
            agent_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS_PATH} does not contain valid JSON.")

    assert "cleaned_row_count" in agent_data, "Missing 'cleaned_row_count' in results.json"
    assert "correlation_temp_pressure" in agent_data, "Missing 'correlation_temp_pressure' in results.json"
    assert "posterior_mean_temp" in agent_data, "Missing 'posterior_mean_temp' in results.json"
    assert "posterior_variance_temp" in agent_data, "Missing 'posterior_variance_temp' in results.json"

    assert int(agent_data["cleaned_row_count"]) == expected["cleaned_row_count"], \
        f"Expected cleaned_row_count {expected['cleaned_row_count']}, got {agent_data['cleaned_row_count']}"
    assert math.isclose(agent_data["correlation_temp_pressure"], expected["correlation_temp_pressure"], rel_tol=1e-3), \
        f"Expected correlation_temp_pressure {expected['correlation_temp_pressure']}, got {agent_data['correlation_temp_pressure']}"
    assert math.isclose(agent_data["posterior_mean_temp"], expected["posterior_mean_temp"], rel_tol=1e-3), \
        f"Expected posterior_mean_temp {expected['posterior_mean_temp']}, got {agent_data['posterior_mean_temp']}"
    assert math.isclose(agent_data["posterior_variance_temp"], expected["posterior_variance_temp"], rel_tol=1e-3), \
        f"Expected posterior_variance_temp {expected['posterior_variance_temp']}, got {agent_data['posterior_variance_temp']}"


def verify_rust_project():
    assert os.path.isdir(PROJECT), f"Rust project directory {PROJECT} is missing."
    assert os.path.isfile(MANIFEST), f"Cargo manifest {MANIFEST} is missing."

    proc = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1", "--manifest-path", MANIFEST],
        cwd=PROJECT, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60
    )
    assert proc.returncode == 0, f"Cargo metadata failed:\n{proc.stderr}"
    try:
        metadata = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        pytest.fail(f"Cargo metadata did not return valid JSON: {exc}")

    root = os.path.realpath(PROJECT)
    packages = []
    rust_bin_sources = []
    for package in metadata.get("packages", []):
        manifest_path = os.path.realpath(package.get("manifest_path", ""))
        try:
            inside = os.path.commonpath([root, manifest_path]) == root
        except ValueError:
            inside = False
        if not inside:
            continue
        packages.append(package)
        for target in package.get("targets", []):
            if "bin" in target.get("kind", []):
                src = os.path.realpath(target.get("src_path", ""))
                try:
                    src_inside = os.path.commonpath([root, src]) == root
                except ValueError:
                    src_inside = False
                if src_inside and src.endswith(".rs") and os.path.isfile(src):
                    rust_bin_sources.append(src)

    assert packages, "Cargo metadata contains no package in /home/user/etl_pipeline."
    assert rust_bin_sources, "The Cargo project has no executable Rust source target."


def write_challenge_dataset(valid_count):
    rng = random.SystemRandom()
    rows = [["Temperature", "Pressure", "Humidity"]]
    for i in range(valid_count):
        t = round(rng.uniform(-42.0, 47.0), 2)
        p = round(rng.uniform(815.0, 1185.0), 2)
        h = "" if i % 5 == 0 else round(rng.uniform(30.0, 70.0), 2)
        rows.append([t, p, h])

    # Inclusive boundary rows are valid; the remaining rows must be filtered.
    rows.extend([
        [-50.0, 800.0, ""],
        [50.0, 1200.0, 55.0],
        ["", 950.0, 45.0],
        [20.0, "", 45.0],
        [50.01, 1000.0, 45.0],
        [-50.01, 1000.0, 45.0],
        [20.0, 799.99, 45.0],
        [20.0, 1200.01, 45.0],
    ])
    with open(DATA_PATH, "w", newline="", encoding="utf-8") as f:
        csv.writer(f).writerows(rows)


def run_pipeline(preferred_env=None):
    envs = []
    if preferred_env is not None:
        envs.append(preferred_env)
    else:
        envs.append(os.environ.copy())
        user_env = os.environ.copy()
        user_env["HOME"] = "/home/user"
        user_env.pop("CARGO_HOME", None)
        if user_env.get("HOME") != envs[0].get("HOME"):
            envs.append(user_env)

    failures = []
    for env in envs:
        proc = subprocess.run(
            ["cargo", "run", "--offline", "--quiet", "--manifest-path", MANIFEST],
            cwd=PROJECT, env=env, text=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=180
        )
        if proc.returncode == 0:
            return env
        failures.append(proc.stderr)
    pytest.fail("Rust pipeline failed to build or run:\n" + "\n--- retry ---\n".join(failures))


def test_results_and_rust_pipeline():
    # Preserve all original numerical checks against the supplied dataset/output.
    assert_results(get_expected_results())
    verify_rust_project()

    with open(DATA_PATH, "rb") as f:
        original_data = f.read()
    with open(RESULTS_PATH, "rb") as f:
        original_results = f.read()

    selected_env = None
    try:
        for valid_count in (17, 29):
            write_challenge_dataset(valid_count)
            expected = get_expected_results()
            if os.path.exists(RESULTS_PATH):
                os.remove(RESULTS_PATH)
            selected_env = run_pipeline(selected_env)
            assert_results(expected)
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)
        with open(RESULTS_PATH, "wb") as f:
            f.write(original_results)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
