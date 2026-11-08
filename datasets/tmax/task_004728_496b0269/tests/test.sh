#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import math
import os
import random
import subprocess
import pytest

HOME = "/home/user"
MAKEFILE = os.path.join(HOME, "Makefile")
INPUT = os.path.join(HOME, "raw_telemetry.txt")
OUTPUT = os.path.join(HOME, "output_metrics.json")
EXECUTABLE = os.path.join(HOME, "telemetry_processor")


def run(cmd, timeout=30):
    return subprocess.run(cmd, cwd=HOME, check=True, timeout=timeout,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          text=True)


def load_output():
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} is missing."
    with open(OUTPUT, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT} does not contain valid JSON.")


def assert_metrics(data, points):
    assert set(data.keys()) == {"unique_points", "centroid", "max_distance"}, \
        "JSON must contain exactly unique_points, centroid, and max_distance."
    assert data["unique_points"] == len(points), \
        f"Expected {len(points)} unique points, got {data['unique_points']}."

    centroid = data["centroid"]
    assert isinstance(centroid, list) and len(centroid) == 3, \
        "Centroid must be a list of 3 floats."
    expected_centroid = [sum(p[i] for p in points) / len(points) for i in range(3)]
    expected_centroid = [round(v, 2) for v in expected_centroid]
    for i in range(3):
        assert isinstance(centroid[i], (int, float)) and not isinstance(centroid[i], bool)
        assert math.isfinite(centroid[i])
        assert math.isclose(centroid[i], expected_centroid[i], abs_tol=0.011), \
            f"Centroid coordinate {i} expected {expected_centroid[i]}, got {centroid[i]}."

    raw_centroid = [sum(p[i] for p in points) / len(points) for i in range(3)]
    expected_distance = max(math.sqrt(sum((p[i] - raw_centroid[i]) ** 2 for i in range(3)))
                            for p in points)
    expected_distance = round(expected_distance, 2)
    assert isinstance(data["max_distance"], (int, float)) and not isinstance(data["max_distance"], bool)
    assert math.isfinite(data["max_distance"])
    assert math.isclose(data["max_distance"], expected_distance, abs_tol=0.011), \
        f"Expected max_distance {expected_distance}, got {data['max_distance']}."


def test_makefile_exists():
    """Test that the Makefile exists in the correct location."""
    assert os.path.isfile(MAKEFILE), f"Makefile is missing at {MAKEFILE}."

    with open(MAKEFILE, "r") as f:
        content = f.read()

    assert "build:" in content, "Makefile is missing the 'build' target."
    assert "run:" in content, "Makefile is missing the 'run' target."
    assert "clean:" in content, "Makefile is missing the 'clean' target."


def test_pipeline_rebuilds_and_runs():
    sources = [p for p in glob.glob(os.path.join(HOME, "**", "*.cpp"), recursive=True)
               if os.path.isfile(p)]
    assert sources, "No C++ source file was found under /home/user."

    run(["make", "clean"])
    assert not os.path.exists(EXECUTABLE), "The clean target did not remove telemetry_processor."
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)

    run(["make", "run"])
    assert os.path.isfile(EXECUTABLE), "The run target did not build telemetry_processor."
    assert os.access(EXECUTABLE, os.X_OK), "telemetry_processor is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "telemetry_processor is not a compiled native executable."
    assert os.path.isfile(OUTPUT), "The run target did not generate output_metrics.json."


def test_output_metrics_json():
    """Test that output_metrics.json contains the correct values for the supplied fixture."""
    data = load_output()

    assert "unique_points" in data, "JSON is missing the 'unique_points' key."
    assert "centroid" in data, "JSON is missing the 'centroid' key."
    assert "max_distance" in data, "JSON is missing the 'max_distance' key."

    assert data["unique_points"] == 3, f"Expected 3 unique points, got {data['unique_points']}."

    centroid = data["centroid"]
    assert isinstance(centroid, list) and len(centroid) == 3, "Centroid must be a list of 3 floats."

    expected_centroid = [4.0, 5.0, 6.0]
    for i in range(3):
        assert math.isclose(centroid[i], expected_centroid[i], abs_tol=0.01), \
            f"Centroid coordinate {i} expected to be {expected_centroid[i]}, got {centroid[i]}."

    expected_max_distance = 5.20
    assert math.isclose(data["max_distance"], expected_max_distance, abs_tol=0.01), \
        f"Expected max_distance to be {expected_max_distance}, got {data['max_distance']}."


def test_processor_on_unseen_inputs():
    with open(INPUT, "rb") as f:
        original_input = f.read()

    rng = random.SystemRandom()
    try:
        for _ in range(3):
            count = rng.randint(4, 8)
            points = []
            used = set()
            while len(points) < count:
                point = tuple(rng.randint(-200, 200) / 10.0 for _ in range(3))
                if point not in used:
                    used.add(point)
                    points.append(point)

            lines = ["noise before telemetry", "malformed [12.0, nope, -4.0] ignored"]
            for index, point in enumerate(points):
                deltas = [rng.choice([-0.019, -0.011, 0.011, 0.019]) for _ in range(3)]
                raw = [point[i] + deltas[i] for i in range(3)]
                lines.append(f"sensor {index}: [{raw[0]:.3f}, {raw[1]:.3f}, {raw[2]:.3f}] end")
                if index % 2 == 0:
                    deltas2 = [rng.choice([-0.018, -0.012, 0.012, 0.018]) for _ in range(3)]
                    duplicate = [point[i] + deltas2[i] for i in range(3)]
                    lines.append(f"duplicate text [{duplicate[0]:.3f}, {duplicate[1]:.3f}, {duplicate[2]:.3f}]")
            rng.shuffle(lines)

            with open(INPUT, "w") as f:
                f.write("\n".join(lines) + "\n")
            if os.path.exists(OUTPUT):
                os.remove(OUTPUT)

            run([EXECUTABLE])
            assert_metrics(load_output(), points)
    finally:
        with open(INPUT, "wb") as f:
            f.write(original_input)
        try:
            run(["make", "run"])
        except Exception:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
