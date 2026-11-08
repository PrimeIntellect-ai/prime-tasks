#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
import sys
import time

import pytest

SERVICE = '/home/user/sensor_service'
DATA = os.path.join(SERVICE, 'sensor_data.csv')
METRICS = os.path.join(SERVICE, 'final_metrics.txt')
BUILD = os.path.join(SERVICE, 'build_data.sh')
PROCESSOR = os.path.join(SERVICE, 'processor.py')


def run_checked(command, timeout=60):
    result = subprocess.run(
        command,
        cwd=SERVICE,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Command failed: {command}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


@pytest.fixture(scope='session', autouse=True)
def build_and_run_submission():
    for path in (DATA, METRICS):
        if os.path.exists(path):
            os.remove(path)
    run_checked([BUILD])
    run_checked([sys.executable, PROCESSOR])


def read_reported_variance():
    assert os.path.isfile(METRICS), f"{METRICS} is missing."
    with open(METRICS, 'r') as f:
        content = f.read()
    match = re.fullmatch(r'Variance: (-?\d+\.\d{4})\n?', content)
    assert match is not None, (
        f"Format incorrect in {METRICS}. Expected exactly 'Variance: <value>' "
        "with four decimal places."
    )
    return float(match.group(1))


def welford_variance(path):
    count = 0
    mean = 0.0
    m2 = 0.0
    with open(path, 'r') as f:
        for line in f:
            value = float(line.strip())
            count += 1
            delta = value - mean
            mean += delta / count
            m2 += delta * (value - mean)
    assert count > 0
    return m2 / count


def test_sensor_data_generated():
    assert os.path.isfile(DATA), f"{DATA} was not generated."
    assert os.path.getsize(DATA) > 0, f"{DATA} is empty."

    rng = random.Random(42)
    count = 0
    with open(DATA, 'r') as f:
        for count, line in enumerate(f, 1):
            assert float(line.strip()) == 1000000 + rng.uniform(-1, 1), (
                f"Unexpected generated sensor value on line {count}."
            )
    assert count == 100000, f"Expected 100000 sensor values, found {count}."


def test_final_metrics_generated():
    assert os.path.isfile(METRICS), f"{METRICS} was not generated."


def test_variance_calculation_accuracy():
    assert os.path.isfile(METRICS), f"{METRICS} is missing."

    with open(METRICS, 'r') as f:
        content = f.read().strip()

    match = re.search(r'Variance:\s*([0-9\.]+)', content)
    assert match is not None, f"Format incorrect in {METRICS}. Expected 'Variance: <value>'."

    variance = float(match.group(1))
    assert 0.3300 <= variance <= 0.3400, (
        f"Variance {variance} is out of the expected numerical stability range (approx 0.3333). "
        "Catastrophic cancellation might not be fully fixed."
    )

    expected = welford_variance(DATA)
    assert content == f"Variance: {expected:.4f}", (
        f"Reported variance does not match the variance recomputed from {DATA}."
    )
    assert read_reported_variance() == float(f"{expected:.4f}")


def write_synthetic_data(rows):
    with open(DATA, 'w') as f:
        block = '999999.5\n1000000.5\n' * 5000
        pairs, remainder = divmod(rows, 10000)
        for _ in range(pairs):
            f.write(block)
        for i in range(remainder):
            f.write('999999.5\n' if i % 2 == 0 else '1000000.5\n')


def run_and_measure_peak_rss(timeout=90):
    proc = subprocess.Popen(
        [sys.executable, PROCESSOR],
        cwd=SERVICE,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    peak_kb = 0
    deadline = time.monotonic() + timeout
    while proc.poll() is None:
        if time.monotonic() > deadline:
            proc.kill()
            proc.wait()
            pytest.fail('processor.py timed out while processing the dataset.')
        try:
            with open(f'/proc/{proc.pid}/status', 'r') as status:
                for line in status:
                    if line.startswith('VmRSS:'):
                        peak_kb = max(peak_kb, int(line.split()[1]))
                        break
        except FileNotFoundError:
            pass
        time.sleep(0.002)
    stderr = proc.stderr.read()
    assert proc.returncode == 0, f"processor.py failed: {stderr}"
    assert read_reported_variance() == 0.25, (
        'processor.py did not calculate the variance of the synthetic input.'
    )
    return peak_kb


def test_z_memory_usage_does_not_scale_with_input_history():
    try:
        write_synthetic_data(200000)
        small_peak = run_and_measure_peak_rss()

        write_synthetic_data(2000000)
        large_peak = run_and_measure_peak_rss()

        assert large_peak - small_peak < 24 * 1024, (
            f"Memory usage grew with input size ({small_peak} KiB to {large_peak} KiB), "
            "indicating that sensor history is still being retained."
        )
    finally:
        run_checked([BUILD])
        run_checked([sys.executable, PROCESSOR])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
