#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import shutil
import subprocess
import tempfile
import uuid

import pytest

SCRIPT_PATH = "/home/user/filter.py"


def oracle(path):
    with open(path, newline="") as f:
        rows = list(csv.DictReader(f))
    t = [float(row["time"]) for row in rows]
    x = [float(row["x"]) for row in rows]
    assert len(t) >= 3

    v = [0.0] * len(t)
    v[0] = (x[1] - x[0]) / (t[1] - t[0])
    for i in range(1, len(t) - 1):
        v[i] = (x[i + 1] - x[i - 1]) / (t[i + 1] - t[i - 1])
    v[-1] = (x[-1] - x[-2]) / (t[-1] - t[-2])

    energy = [0.5 * vel * vel + 2.5 * pos * pos for vel, pos in zip(v, x)]
    evil = any(e > 50.0 for e in energy)
    evil = evil or any(abs(energy[i] - energy[i - 1]) > 10.0 for i in range(1, len(energy)))
    return 1 if evil else 0


def write_case(directory, t, x):
    path = os.path.join(directory, uuid.uuid4().hex + ".csv")
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["time", "x"])
        writer.writerows(zip(t, x))
    return path


def test_filter_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."


def test_validation_corpora_present():
    for directory in ("/app/data/clean", "/app/data/evil"):
        assert os.path.exists(directory), f"Dataset directory {directory} is missing."
        assert any(name.endswith(".csv") for name in os.listdir(directory)), \
            f"No CSV files found in {directory}."


def test_filter_follows_energy_rules_on_neutral_paths():
    rng = random.SystemRandom()
    cases = []

    with tempfile.TemporaryDirectory(prefix="trajectory_checks_") as directory:
        # Random smooth low-energy trajectories.
        for _ in range(12):
            n = rng.randint(61, 181)
            dt = rng.uniform(0.006, 0.025)
            amplitude = rng.uniform(0.1, 0.8)
            omega = rng.uniform(0.4, 1.8)
            phase = rng.uniform(-math.pi, math.pi)
            damping = rng.uniform(0.0, 0.08)
            t = [i * dt for i in range(n)]
            x = [amplitude * math.exp(-damping * ti) * math.cos(omega * ti + phase) for ti in t]
            cases.append(write_case(directory, t, x))

        # High potential energy without an energy jump.
        for _ in range(5):
            n = rng.randint(30, 90)
            dt = rng.uniform(0.01, 0.04)
            level = rng.uniform(4.6, 6.0)
            t = [i * dt for i in range(n)]
            x = [level] * n
            cases.append(write_case(directory, t, x))

        # High kinetic energy from an otherwise small, linear trajectory.
        for _ in range(5):
            n = rng.randint(15, 35)
            dt = rng.uniform(0.0005, 0.0015)
            slope = rng.uniform(10.5, 14.0)
            t = [i * dt for i in range(n)]
            midpoint = t[-1] / 2.0
            x = [slope * (ti - midpoint) for ti in t]
            cases.append(write_case(directory, t, x))

        # A jump-rule violation whose energy remains below 50.
        for _ in range(5):
            n = rng.randrange(21, 50, 2)
            dt = 0.1
            t = [i * dt for i in range(n)]
            x = [0.0] * n
            x[n // 2] = rng.uniform(0.95, 1.15)
            cases.append(write_case(directory, t, x))

        # Spiked trajectories at unpredictable positions and time steps.
        for _ in range(10):
            n = rng.randint(50, 140)
            dt = rng.uniform(0.005, 0.03)
            t = [i * dt for i in range(n)]
            x = [0.3 * math.cos(1.2 * ti) for ti in t]
            x[rng.randint(3, n - 4)] += rng.uniform(3.0, 12.0)
            cases.append(write_case(directory, t, x))

        # Exercise real corpus formatting, but remove label-bearing paths and
        # derive the expected result from the instructed numerical rules.
        for source_dir in ("/app/data/clean", "/app/data/evil"):
            sources = [os.path.join(source_dir, name) for name in os.listdir(source_dir)
                       if name.endswith(".csv")]
            for source in rng.sample(sources, min(6, len(sources))):
                destination = os.path.join(directory, uuid.uuid4().hex + ".csv")
                shutil.copyfile(source, destination)
                cases.append(destination)

        rng.shuffle(cases)
        failures = []
        observed = set()
        for path in cases:
            expected = oracle(path)
            observed.add(expected)
            try:
                result = subprocess.run(
                    ["python3", SCRIPT_PATH, path],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=5,
                )
                actual = result.returncode
            except subprocess.TimeoutExpired:
                failures.append(f"{os.path.basename(path)} timed out")
                continue
            if actual != expected:
                failures.append(
                    f"{os.path.basename(path)}: expected exit {expected}, got {actual}"
                )

        assert observed == {0, 1}, "Generated tests did not cover both classifications."
        if failures:
            pytest.fail("Classification failures: " + "; ".join(failures[:12]))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
