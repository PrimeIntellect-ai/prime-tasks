#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import stat
import subprocess
import sys

WORKSPACE = "/home/user/workspace"
STATS_PATH = os.path.join(WORKSPACE, "stats_buffer.py")
TEST_PATH = os.path.join(WORKSPACE, "test_stats.py")
LOG_PATH = os.path.join(WORKSPACE, "verification.log")

RING_MUTANT = '''class SlidingWindowStats:
    def __init__(self, max_size):
        self.max_size = max_size
        self.buffer = []
        self.head = 0

    def add(self, value):
        if len(self.buffer) < self.max_size:
            self.buffer.append(value)
        else:
            self.head = (self.head + 1) % self.max_size
            self.buffer[self.head] = value

    def get_percentile(self, p):
        if not self.buffer:
            return None
        sorted_buf = sorted(self.buffer)
        k = (len(sorted_buf) - 1) * (p / 100.0)
        f = int(k)
        c = k - f
        if f + 1 < len(sorted_buf):
            return sorted_buf[f] * (1.0 - c) + sorted_buf[f + 1] * c
        return sorted_buf[-1]
'''

PERCENTILE_MUTANT = '''class SlidingWindowStats:
    def __init__(self, max_size):
        self.max_size = max_size
        self.buffer = []
        self.head = 0

    def add(self, value):
        if len(self.buffer) < self.max_size:
            self.buffer.append(value)
        else:
            self.buffer[self.head] = value
            self.head = (self.head + 1) % self.max_size

    def get_percentile(self, p):
        if not self.buffer:
            return None
        sorted_buf = sorted(self.buffer)
        k = len(sorted_buf) * (p / 100.0)
        f = int(k)
        c = k - f
        if f + 1 < len(sorted_buf):
            return sorted_buf[f] * (1.0 - c) + sorted_buf[f + 1] * c
        return sorted_buf[-1]
'''


def run_agent_test():
    try:
        os.unlink(LOG_PATH)
    except FileNotFoundError:
        pass
    result = subprocess.run(
        [sys.executable, TEST_PATH],
        cwd=WORKSPACE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    content = None
    if os.path.isfile(LOG_PATH):
        with open(LOG_PATH, "r") as f:
            content = f.read().strip()
    return result, content


def test_00_agent_regression_script():
    assert os.path.lexists(TEST_PATH), f"Regression test script not found at {TEST_PATH}"
    mode = os.lstat(TEST_PATH).st_mode
    assert stat.S_ISREG(mode), "test_stats.py must be a regular file"

    with open(STATS_PATH, "r") as f:
        submitted_stats = f.read()

    try:
        result, content = run_agent_test()
        assert result.returncode == 0, (
            "test_stats.py failed against the submitted implementation:\n"
            + result.stdout + result.stderr
        )
        assert content == "SUCCESS", "test_stats.py did not produce SUCCESS when executed"

        with open(STATS_PATH, "w") as f:
            f.write(RING_MUTANT)
        result, content = run_agent_test()
        assert content == "FAILED", (
            "test_stats.py must detect the ring-buffer off-by-one regression; "
            f"exit={result.returncode}, log={content!r}"
        )

        with open(STATS_PATH, "w") as f:
            f.write(PERCENTILE_MUTANT)
        result, content = run_agent_test()
        assert content == "FAILED", (
            "test_stats.py must detect the incorrect percentile formula; "
            f"exit={result.returncode}, log={content!r}"
        )
    finally:
        with open(STATS_PATH, "w") as f:
            f.write(submitted_stats)

    result, content = run_agent_test()
    assert result.returncode == 0 and content == "SUCCESS", (
        "test_stats.py did not produce SUCCESS after restoring the submitted implementation"
    )


def test_verification_log():
    log_path = "/home/user/workspace/verification.log"
    assert os.path.isfile(log_path), f"Verification log not found at {log_path}"
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert content == "SUCCESS", f"Expected verification.log to contain SUCCESS, but got '{content}'"


def test_stats_buffer_fixed():
    sys.path.append("/home/user/workspace")
    try:
        from stats_buffer import SlidingWindowStats
    except ImportError:
        assert False, "Could not import SlidingWindowStats from stats_buffer.py"

    # Original fixed ring-buffer checks.
    stats = SlidingWindowStats(3)
    stats.add(10)
    stats.add(20)
    stats.add(30)
    stats.add(40)
    assert sorted(stats.buffer) == [20, 30, 40], f"Ring buffer overwrite failed, got {sorted(stats.buffer)}"
    stats.add(50)
    assert sorted(stats.buffer) == [30, 40, 50], f"Ring buffer overwrite failed, got {sorted(stats.buffer)}"

    # Original fixed percentile checks.
    stats2 = SlidingWindowStats(5)
    for v in [15, 20, 35, 40, 50]:
        stats2.add(v)

    p50 = stats2.get_percentile(50)
    assert p50 == 35.0, f"Percentile formula failed. Expected 35.0, got {p50}"

    p75 = stats2.get_percentile(75)
    assert p75 == 40.0, f"Percentile formula failed. Expected 40.0, got {p75}"


def expected_percentile(values, p):
    if not values:
        return None
    ordered = sorted(values)
    k = (len(ordered) - 1) * (p / 100.0)
    lower = int(k)
    fraction = k - lower
    if lower + 1 < len(ordered):
        return ordered[lower] * (1.0 - fraction) + ordered[lower + 1] * fraction
    return ordered[-1]


def test_randomized_general_behavior():
    from stats_buffer import SlidingWindowStats

    rng = secrets.SystemRandom()
    for _ in range(24):
        max_size = rng.randint(1, 12)
        count = rng.randint(max_size + 1, max_size * 5 + 3)
        values = [rng.randint(-100000, 100000) for _ in range(count)]
        stats = SlidingWindowStats(max_size)
        model = []

        assert stats.get_percentile(rng.uniform(0, 100)) is None

        for index, value in enumerate(values):
            stats.add(value)
            model.append(value)
            if len(model) > max_size:
                model.pop(0)

            assert len(stats.buffer) == len(model)
            assert sorted(stats.buffer) == sorted(model), (
                f"Incorrect window after append {index} for size {max_size}: "
                f"got {stats.buffer}, expected elements {model}"
            )
            expected_head = max(0, index + 1 - max_size) % max_size
            assert stats.head == expected_head, (
                f"Oldest-element pointer is incorrect: got {stats.head}, expected {expected_head}"
            )

            percentiles = [0, 1, 10, 25, 33.3, 50, 66.7, 75, 90, 99, 100]
            percentiles.extend(rng.uniform(0, 100) for _ in range(3))
            before = list(stats.buffer)
            for p in percentiles:
                actual = stats.get_percentile(p)
                expected = expected_percentile(model, p)
                assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-9), (
                    f"Percentile {p} incorrect for {model}: got {actual}, expected {expected}"
                )
            assert stats.buffer == before, "get_percentile must not modify the buffer"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
