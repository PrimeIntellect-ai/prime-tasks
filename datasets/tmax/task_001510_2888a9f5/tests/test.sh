#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import pytest

MEASUREMENTS_FILE = "/home/user/measurements.csv"
PROGRAM_FILE = "/home/user/process_stream.go"
WELFORD_FILE = "/home/user/welford_stats.jsonl"
POSTERIOR_FILE = "/home/user/bayesian_posterior.json"

@pytest.fixture(scope="module")
def expected_stats():
    if not os.path.isfile(MEASUREMENTS_FILE):
        pytest.fail(f"Input file {MEASUREMENTS_FILE} is missing.")

    n = 0
    mean = 0.0
    M2 = 0.0
    sum_x = 0.0
    welford_stats = []

    with open(MEASUREMENTS_FILE, "r") as f:
        for line in f:
            val = line.strip()
            if not val:
                continue
            x = float(val)
            n += 1
            sum_x += x

            delta = x - mean
            mean += delta / n
            delta2 = x - mean
            M2 += delta * delta2

            if n % 1000 == 0:
                variance = M2 / (n - 1) if n > 1 else 0.0
                welford_stats.append({
                    "n": n,
                    "mean": round(mean, 3),
                    "variance": round(variance, 3)
                })

    post_var = 1.0 / (1.0 + n)
    post_mean = post_var * sum_x
    posterior_stats = {
        "posterior_mean": round(post_mean, 5),
        "posterior_variance": round(post_var, 5)
    }
    return welford_stats, posterior_stats

def test_go_program_exists():
    assert os.path.isfile(PROGRAM_FILE), f"The required Go program {PROGRAM_FILE} is missing."
    assert os.path.getsize(PROGRAM_FILE) > 0, f"The Go program {PROGRAM_FILE} is empty."

def test_welford_stats_file(expected_stats):
    """Test that the generated JSONL contains correct Welford statistics."""
    expected_welford, _ = expected_stats

    assert os.path.isfile(WELFORD_FILE), f"The file {WELFORD_FILE} is missing."
    with open(WELFORD_FILE, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(expected_welford), f"Expected {len(expected_welford)} lines in {WELFORD_FILE}, found {len(lines)}."

    for i, line in enumerate(lines):
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Line {i+1} in {WELFORD_FILE} is not valid JSON: {line}")

        expected = expected_welford[i]
        assert "n" in data and data["n"] == expected["n"], f"Line {i+1} missing or incorrect 'n'. Expected {expected['n']}."
        assert "mean" in data and data["mean"] == expected["mean"], f"Line {i+1} incorrect 'mean'. Expected {expected['mean']}, got {data.get('mean')}."
        assert "variance" in data and data["variance"] == expected["variance"], f"Line {i+1} incorrect 'variance'. Expected {expected['variance']}, got {data.get('variance')}."

def test_bayesian_posterior_file(expected_stats):
    """Test that the generated posterior file contains correct final statistics."""
    _, expected_posterior = expected_stats

    assert os.path.isfile(POSTERIOR_FILE), f"The file {POSTERIOR_FILE} is missing."
    with open(POSTERIOR_FILE, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {POSTERIOR_FILE} is not valid JSON.")

    assert "posterior_mean" in data, f"Key 'posterior_mean' missing in {POSTERIOR_FILE}."
    assert "posterior_variance" in data, f"Key 'posterior_variance' missing in {POSTERIOR_FILE}."
    assert data["posterior_mean"] == expected_posterior["posterior_mean"], \
        f"Incorrect posterior_mean. Expected {expected_posterior['posterior_mean']}, got {data['posterior_mean']}."
    assert data["posterior_variance"] == expected_posterior["posterior_variance"], \
        f"Incorrect posterior_variance. Expected {expected_posterior['posterior_variance']}, got {data['posterior_variance']}."
TEST_EOF

status=0

if [ ! -f /home/user/process_stream.go ] || [ ! -s /home/user/process_stream.go ]; then
    echo "Required Go source file is missing or empty."
    status=1
elif ! go build -o /tmp/process_stream /home/user/process_stream.go; then
    echo "The Go program did not compile."
    status=1
else
    # Replace the known build-time data with an unpredictable numerical-stability
    # case, then require the compiled artifact itself to generate both outputs.
    if ! python3 - << 'PY_EOF'
import random
import secrets

rng = random.Random(secrets.randbits(128))
base = rng.choice((-1.0, 1.0)) * (1_000_000.0 + rng.uniform(-5000.0, 5000.0))
with open("/home/user/measurements.csv", "w") as f:
    for _ in range(10000):
        f.write(f"{rng.gauss(base, 1.0):.6f}\n")
PY_EOF
    then
        status=1
    else
        rm -f /home/user/welford_stats.jsonl /home/user/bayesian_posterior.json
        if ! timeout 30s /tmp/process_stream; then
            echo "The compiled Go program failed while processing the stream."
            status=1
        elif ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
            status=1
        fi
    fi
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
