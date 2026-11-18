#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import secrets
import subprocess
import pytest

SCRIPT_PATH = "/home/user/analyze.sh"
RESULTS_PATH = "/home/user/results.json"
TEMPS_PATH = "/home/user/temps.txt"
LOADS_PATH = "/home/user/loads.txt"


def run_analyze():
    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)
    try:
        completed = subprocess.run(
            [SCRIPT_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("analyze.sh did not finish within 15 seconds")
    assert completed.returncode == 0, (
        f"analyze.sh exited with status {completed.returncode}. "
        f"stderr: {completed.stderr}"
    )
    assert os.path.isfile(RESULTS_PATH), (
        f"Executing analyze.sh did not create {RESULTS_PATH}"
    )


def read_and_validate_results():
    with open(RESULTS_PATH, "r") as f:
        raw = f.read()

    number = r"-?(?:0|[1-9][0-9]*)\.[0-9]{4}"
    structure = re.compile(
        r"\A\s*\{\s*"
        r'"correlation"\s*:\s*(' + number + r")\s*,\s*"
        r'"slope"\s*:\s*(' + number + r")\s*,\s*"
        r'"intercept"\s*:\s*(' + number + r")\s*"
        r"\}\s*\Z"
    )
    assert structure.fullmatch(raw), (
        "results.json must contain exactly correlation, slope, and intercept in "
        "the required order, with each value written to exactly four decimal places"
    )

    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        pytest.fail(f"File {RESULTS_PATH} does not contain valid JSON.")
    return data


def expected_statistics(points):
    n = len(points)
    mean_x = sum(x for x, _ in points) / n
    mean_y = sum(y for _, y in points) / n
    sxx = sum((x - mean_x) ** 2 for x, _ in points)
    syy = sum((y - mean_y) ** 2 for _, y in points)
    sxy = sum((x - mean_x) * (y - mean_y) for x, y in points)
    slope = sxy / sxx
    intercept = mean_y - slope * mean_x
    correlation = sxy / math.sqrt(sxx * syy)
    return correlation, slope, intercept


def write_dynamic_dataset(rng):
    base = secrets.randbelow(700000) + 200000
    slope = rng.uniform(0.035, 0.16)
    intercept = rng.uniform(-3.0, 3.0)

    points = []
    temps = []
    loads = []
    xs = rng.sample(range(25, 96), 10)

    # Every timestamp is shared by A and B, ensuring the join must use both fields.
    for i, x_int in enumerate(xs):
        timestamp = base + i // 2
        server = "A" if i % 2 == 0 else "B"
        x_text = f"{x_int + (i % 3) * 0.25:.2f}"
        noise = rng.uniform(-0.22, 0.22)
        y_text = f"{slope * float(x_text) + intercept + noise:.3f}"
        points.append((float(x_text), float(y_text)))
        temps.append(f"{timestamp}|{server}|{x_text}")
        loads.append(f"{timestamp}|{server}|{y_text}")

    # Joined rows that must be discarded by each cleaning rule.
    temps.extend([
        f"{base + 20}|A|ERR",
        f"{base + 21}|A|101.5",
        f"{base + 22}|A|52.0",
        f"{base + 23}|A|49.0",
        f"{base + 24}|A|70.0",  # no matching load row
    ])
    loads.extend([
        f"{base + 20}|A|8.0",
        f"{base + 21}|A|8.5",
        f"{base + 22}|A|BAD",
        f"{base + 23}|A|",
        f"{base + 25}|A|4.0",  # no matching temperature row
    ])

    rng.shuffle(temps)
    rng.shuffle(loads)
    with open(TEMPS_PATH, "w") as f:
        f.write("\n".join(temps) + "\n")
    with open(LOADS_PATH, "w") as f:
        f.write("\n".join(loads) + "\n")
    os.chmod(TEMPS_PATH, 0o666)
    os.chmod(LOADS_PATH, 0o666)
    return expected_statistics(points)


def test_analyze_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script file missing: {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script is not executable: {SCRIPT_PATH}"


def test_results_json():
    # Execute the submitted artifact against the supplied datasets rather than
    # trusting a results.json left behind before verification.
    run_analyze()
    data = read_and_validate_results()

    expected_correlation = 0.9989
    expected_slope = 0.1060
    expected_intercept = -2.7900

    assert "correlation" in data, "Missing 'correlation' key in results.json"
    assert "slope" in data, "Missing 'slope' key in results.json"
    assert "intercept" in data, "Missing 'intercept' key in results.json"

    assert math.isclose(float(data["correlation"]), expected_correlation, abs_tol=0.00015), \
        f"Expected correlation close to {expected_correlation}, got {data['correlation']}"
    assert math.isclose(float(data["slope"]), expected_slope, abs_tol=0.00015), \
        f"Expected slope close to {expected_slope}, got {data['slope']}"
    assert math.isclose(float(data["intercept"]), expected_intercept, abs_tol=0.00015), \
        f"Expected intercept close to {expected_intercept}, got {data['intercept']}"


def test_pipeline_on_unseen_datasets():
    rng = random.Random(secrets.randbits(128))
    for _ in range(2):
        expected = write_dynamic_dataset(rng)
        run_analyze()
        data = read_and_validate_results()

        for key, value in zip(("correlation", "slope", "intercept"), expected):
            rounded_expected = float(f"{value:.4f}")
            assert math.isclose(
                float(data[key]), rounded_expected, rel_tol=0.0, abs_tol=0.00005
            ), f"Incorrect {key}: expected {rounded_expected:.4f}, got {data[key]}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
