#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import sys

import pytest


def test_bug_report_exists_and_correct():
    report_path = "/home/user/bug_report.json"
    assert os.path.isfile(report_path), f"File {report_path} does not exist."

    with open(report_path, "r") as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} is not valid JSON.")

    assert "problematic_packet_index" in report_data, "Missing 'problematic_packet_index' in bug_report.json"
    assert report_data["problematic_packet_index"] == 2, f"Expected problematic_packet_index to be 2, got {report_data['problematic_packet_index']}"

    assert "problematic_payload" in report_data, "Missing 'problematic_payload' in bug_report.json"
    payload = report_data["problematic_payload"]
    assert payload.get("x") == 3.0, f"Expected problematic_payload.x to be 3.0, got {payload.get('x')}"
    assert payload.get("y") == 4.0, f"Expected problematic_payload.y to be 4.0, got {payload.get('y')}"
    assert payload.get("z") == 5.0, f"Expected problematic_payload.z to be 5.0, got {payload.get('z')}"


def test_math_engine_fixed():
    engine_dir = "/home/user/simulation_build"
    engine_path = os.path.join(engine_dir, "math_engine.py")
    assert os.path.isdir(engine_dir), f"Directory {engine_dir} does not exist."
    assert os.path.isfile(engine_path), f"File {engine_path} does not exist."

    sys.path.insert(0, engine_dir)
    try:
        import math_engine
    except ImportError:
        pytest.fail("Could not import math_engine from /home/user/simulation_build")

    assert os.path.realpath(math_engine.__file__) == os.path.realpath(engine_path), \
        "Imported math_engine is not /home/user/simulation_build/math_engine.py"
    assert callable(getattr(math_engine, "compute_trajectory", None)), \
        "math_engine.compute_trajectory is not callable"

    problematic_payload = {"x": 3.0, "y": 4.0, "z": 5.0}

    try:
        result = math_engine.compute_trajectory(problematic_payload)
    except ZeroDivisionError:
        pytest.fail("math_engine.compute_trajectory still raises ZeroDivisionError for the problematic payload.")
    except Exception as e:
        pytest.fail(f"math_engine.compute_trajectory raised an unexpected exception: {e}")

    assert isinstance(result, float), f"Expected compute_trajectory to return a float, got {type(result)}"

    rng = secrets.SystemRandom()
    scale = rng.randint(2, 1000)
    positive_n = rng.randint(1, 20)
    negative_n = rng.randint(1, 20)
    payloads = [
        {"x": float(3 * scale), "y": float(4 * scale), "z": float(5 * scale)},
        {"x": float(positive_n + 1), "y": 0.0, "z": float(positive_n)},
        {"x": float(negative_n), "y": 0.0, "z": float(negative_n + 1)},
    ]

    while len(payloads) < 19:
        payload = {
            "x": rng.randint(-32, 32) / 4.0,
            "y": rng.randint(-32, 32) / 4.0,
            "z": rng.randint(-32, 32) / 4.0,
        }
        denominator = payload["x"] ** 2 + payload["y"] ** 2 - payload["z"] ** 2
        if abs(denominator) >= 0.25:
            payloads.append(payload)

    for payload in payloads:
        denominator = payload["x"] ** 2 + payload["y"] ** 2 - payload["z"] ** 2
        expected = 100.0 / (denominator + 1e-9)
        try:
            actual = math_engine.compute_trajectory(payload)
        except Exception as e:
            pytest.fail(f"compute_trajectory raised {type(e).__name__} for {payload}: {e}")
        assert isinstance(actual, float), f"Expected a float for {payload}, got {type(actual)}"
        assert math.isfinite(actual), f"Expected a finite result for {payload}, got {actual}"
        assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12), \
            f"Incorrect trajectory for {payload}: expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
