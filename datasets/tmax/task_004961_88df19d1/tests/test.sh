#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib
import math
import os
import random
import secrets
import sys

PROCESSOR_PATH = "/home/user/app/processor.py"


def load_compute_statistics():
    assert os.path.isfile(PROCESSOR_PATH), f"Missing {PROCESSOR_PATH}"
    sys.path.insert(0, "/home/user/app")
    try:
        sys.modules.pop("processor", None)
        module = importlib.import_module("processor")
    except Exception as exc:
        raise AssertionError(f"Could not import {PROCESSOR_PATH}: {exc}") from exc
    finally:
        sys.path.pop(0)

    assert os.path.realpath(module.__file__) == PROCESSOR_PATH
    assert callable(getattr(module, "compute_statistics", None)), "compute_statistics is missing or not callable"
    return module.compute_statistics


def reference_statistics(data):
    if not data:
        return 0.0, 0.0
    mean = math.fsum(data) / len(data)
    variance = math.fsum((x - mean) ** 2 for x in data) / len(data)
    return mean, math.sqrt(variance)


def assert_statistics(compute_statistics, data, *, std_rel_tol=1e-10):
    expected_mean, expected_stddev = reference_statistics(data)
    try:
        mean, stddev = compute_statistics(list(data))
    except Exception as exc:
        raise AssertionError(f"compute_statistics failed for {data!r}: {exc}") from exc

    assert math.isfinite(mean), f"Mean is not finite for {data!r}: {mean}"
    assert math.isfinite(stddev), f"Standard deviation is not finite for {data!r}: {stddev}"
    assert stddev >= 0.0, f"Standard deviation is negative for {data!r}: {stddev}"

    mean_abs_tol = max(1e-12, 2.0 * math.ulp(expected_mean))
    assert math.isclose(mean, expected_mean, rel_tol=1e-12, abs_tol=mean_abs_tol), (
        f"Expected mean {expected_mean}, got {mean} for {data!r}"
    )
    std_abs_tol = max(1e-15, expected_stddev * std_rel_tol)
    assert math.isclose(stddev, expected_stddev, rel_tol=std_rel_tol, abs_tol=std_abs_tol), (
        f"Expected standard deviation {expected_stddev}, got {stddev} for {data!r}"
    )


def test_success_log_exists_and_correct():
    """Keep the required proof that verify.py was run successfully."""
    log_path = "/home/user/app/success.log"
    assert os.path.isfile(log_path), "The file /home/user/app/success.log does not exist. Did you run verify.py?"
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert content == "Fixed: 100000000.0, 0.0", f"success.log contains incorrect output: {content}"


def test_original_cases():
    """Retain the verifier's original mathematical assertions."""
    compute_statistics = load_compute_statistics()

    data = [100000000.0, 100000000.0, 100000000.0]
    try:
        mean, stddev = compute_statistics(data)
    except ValueError as exc:
        raise AssertionError(f"compute_statistics still crashes with ValueError: {exc}") from exc
    assert mean == 100000000.0, f"Expected mean 100000000.0, got {mean}"
    assert stddev == 0.0, f"Expected stddev 0.0, got {stddev}"

    normal_data = [1.0, 2.0, 3.0, 4.0, 5.0]
    mean, stddev = compute_statistics(normal_data)
    assert mean == 3.0, f"Expected mean 3.0, got {mean}"
    assert abs(stddev - 1.41421356) < 1e-5, f"Expected stddev ~1.414, got {stddev}"


def test_general_and_numerically_sensitive_inputs():
    """Exercise fresh inputs and derive their answers independently."""
    compute_statistics = load_compute_statistics()
    rng = random.Random(secrets.randbits(128))

    assert_statistics(compute_statistics, [])
    assert_statistics(compute_statistics, [rng.uniform(-1e6, 1e6)])

    # General datasets prevent implementations tailored to the two public cases.
    for _ in range(12):
        center = rng.uniform(-1e5, 1e5)
        scale = 10.0 ** rng.uniform(-3.0, 4.0)
        data = [center + rng.uniform(-scale, scale) for _ in range(rng.randint(6, 35))]
        assert_statistics(compute_statistics, data)

    # Large translated datasets with small, nonzero variance expose cancellation
    # and also reject fixes that simply clamp every sensitive variance to zero.
    for _ in range(12):
        base = rng.choice([1e8, -1e8, 1e10, -1e10, 1e12, -1e12])
        unit = math.ulp(base)
        data = [base]
        for _ in range(rng.randint(4, 12)):
            offset = rng.randint(200, 5000) * unit
            data.extend([base - offset, base + offset])
        rng.shuffle(data)
        expected_stddev = reference_statistics(data)[1]
        assert expected_stddev > 0.0
        assert_statistics(compute_statistics, data, std_rel_tol=2e-3)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
