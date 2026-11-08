#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gc
import importlib.util
import math
import os
import random
import secrets
import shutil
import subprocess
import tempfile
import tracemalloc

import pytest

SERVICE_PATH = "/home/user/stats_service.py"
DATA_PATH = "/home/user/data.txt"
OUTPUT_PATH = "/home/user/output.txt"


def compute_expected_variance(data_path):
    count = 0
    mean = 0.0
    M2 = 0.0
    with open(data_path, 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                val = float(line)
                count += 1
                delta = val - mean
                mean += delta / count
                delta2 = val - mean
                M2 += delta * delta2
    if count < 2:
        return 0.0
    return M2 / (count - 1)


def load_service():
    spec = importlib.util.spec_from_file_location("submitted_stats_service", SERVICE_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_service():
    subprocess.run(
        ["python3", SERVICE_PATH],
        check=True,
        timeout=120,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def read_output_float():
    assert os.path.isfile(OUTPUT_PATH), f"The output file {OUTPUT_PATH} is missing."
    content = open(OUTPUT_PATH, 'r').read().strip()
    assert content, f"The output file {OUTPUT_PATH} is empty."
    try:
        value = float(content)
    except ValueError:
        pytest.fail(f"The output file {OUTPUT_PATH} does not contain a valid float: '{content}'")
    assert math.isfinite(value), "The output variance must be finite."
    return value


def test_stats_service_fixed():
    path = SERVICE_PATH
    assert os.path.isfile(path), f"The file {path} is missing."

    with open(path, 'r') as f:
        content = f.read()

    assert "class StatsTracker:" in content, f"The file {path} does not contain the 'StatsTracker' class."
    assert ".append(" not in content, "The script still contains list appends, which causes memory leaks for large streams."


def test_tracker_online_and_numerically_stable():
    module = load_service()
    assert hasattr(module, "StatsTracker"), "StatsTracker is missing."

    tracker = module.StatsTracker()
    assert callable(getattr(tracker, "add_point", None)), "StatsTracker.add_point is missing."
    assert callable(getattr(tracker, "get_variance", None)), "StatsTracker.get_variance is missing."
    assert tracker.get_variance() == 0.0
    tracker.add_point(123.0)
    assert tracker.get_variance() == 0.0

    # Runtime-generated, large-magnitude data exposes catastrophic cancellation.
    seed = secrets.randbits(64)
    rng = random.Random(seed)
    tracker = module.StatsTracker()
    count = 0
    mean = 0.0
    m2 = 0.0
    for _ in range(10000):
        value = 1_000_000_000_000.0 + rng.randint(-400, 400) / 8.0
        tracker.add_point(value)
        count += 1
        delta = value - mean
        mean += delta / count
        m2 += delta * (value - mean)
    expected = m2 / (count - 1)
    actual = tracker.get_variance()
    assert math.isfinite(actual)
    assert math.isclose(actual, expected, rel_tol=1e-7, abs_tol=1e-4), \
        f"StatsTracker returned {actual}; expected approximately {expected}."

    # A genuinely online tracker must not retain memory proportional to the stream.
    tracker = module.StatsTracker()
    tracemalloc.start()
    for i in range(2000):
        tracker.add_point(1_000_000_000_000.0 + (i % 97) / 8.0)
    gc.collect()
    baseline, _ = tracemalloc.get_traced_memory()
    for i in range(120000):
        tracker.add_point(1_000_000_000_000.0 + (i % 97) / 8.0)
    gc.collect()
    current, _ = tracemalloc.get_traced_memory()
    tracemalloc.stop()
    assert current - baseline < 1_000_000, \
        f"StatsTracker retained {current - baseline} bytes as the stream grew; it appears to store history."


def test_main_executes_on_unseen_data_and_restores_provided_run():
    assert os.path.isfile(DATA_PATH), f"The dataset file {DATA_PATH} is missing."
    backup_dir = tempfile.mkdtemp(prefix="stats-verifier-")
    backup_data = os.path.join(backup_dir, "data.txt")
    shutil.copyfile(DATA_PATH, backup_data)

    try:
        rng = random.Random(secrets.randbits(64))
        with open(DATA_PATH, 'w') as f:
            for _ in range(4096):
                value = 1_000_000_000_000.0 + rng.randint(-80, 80) / 8.0
                f.write(repr(value) + "\n")

        expected = compute_expected_variance(DATA_PATH)
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
        run_service()
        actual = read_output_float()
        assert math.isclose(actual, expected, rel_tol=1e-5, abs_tol=1e-5), \
            f"Executed service returned {actual}; expected approximately {expected:.6f}."
    finally:
        shutil.copyfile(backup_data, DATA_PATH)
        shutil.rmtree(backup_dir, ignore_errors=True)
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
        # Leave output.txt produced by the submitted script for the provided data.
        run_service()


def test_output_variance_correct():
    data_path = DATA_PATH
    output_path = OUTPUT_PATH

    assert os.path.isfile(data_path), f"The dataset file {data_path} is missing."
    assert os.path.isfile(output_path), f"The output file {output_path} is missing. Did you run the script?"

    expected_variance = compute_expected_variance(data_path)

    with open(output_path, 'r') as f:
        output_content = f.read().strip()

    assert output_content, f"The output file {output_path} is empty."

    try:
        actual_variance = float(output_content)
    except ValueError:
        pytest.fail(f"The output file {output_path} does not contain a valid float: '{output_content}'")

    # The original script formats to 6 decimal places, so we check with a reasonable tolerance.
    assert math.isclose(actual_variance, expected_variance, rel_tol=1e-5), \
        f"The computed variance {actual_variance} is incorrect. Expected approximately {expected_variance:.6f}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
