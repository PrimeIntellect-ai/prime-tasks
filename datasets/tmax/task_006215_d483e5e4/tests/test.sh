#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import shutil
import subprocess
import tempfile

import pytest

SOURCE = "/home/user/uptime_monitor.c"
BINARY = "/home/user/uptime_monitor_fixed"
STATS = "/home/user/fixed_stats.txt"
DATA = "/home/user/response_times.txt"


def run_program(path, timeout=15):
    result = subprocess.run(
        [path], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=timeout, check=False
    )
    assert result.returncode == 0, (
        f"{path} exited with status {result.returncode}; "
        f"stderr: {result.stderr.decode(errors='replace')}"
    )
    return result.stdout


def parse_output(raw):
    content = raw.decode("utf-8", errors="strict").strip()
    assert content, "Program output is empty"

    count_match = re.search(r"Count:\s*(\d+)", content)
    mean_match = re.search(r"Mean:\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)", content)
    stddev_match = re.search(r"StdDev:\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)", content)

    assert count_match, "Could not parse Count from output"
    assert mean_match, "Could not parse Mean from output"
    assert stddev_match, "Could not parse StdDev from output"

    count = int(count_match.group(1))
    mean = float(mean_match.group(1))
    stddev = float(stddev_match.group(1))
    assert math.isfinite(mean), f"Mean is not finite: {mean}"
    assert math.isfinite(stddev), f"StdDev is not finite: {stddev}"
    return count, mean, stddev


@pytest.fixture(scope="module")
def rebuilt_binary():
    fd, path = tempfile.mkstemp(prefix="rebuilt_uptime_monitor_")
    os.close(fd)
    os.unlink(path)
    result = subprocess.run(
        ["gcc", SOURCE, "-O2", "-o", path, "-lm"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False
    )
    assert result.returncode == 0, (
        "Modified source does not compile: " + result.stderr.decode(errors="replace")
    )
    yield path
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass


def test_source_code_contains_assertion():
    assert os.path.isfile(SOURCE), f"File missing: {SOURCE}"
    with open(SOURCE, "r") as f:
        content = f.read()

    # Preserve the required assertion check from the original verifier.
    pattern = r"assert\s*\(\s*variance\s*>=\s*0(\.0)?\s*\)\s*;"
    assert re.search(pattern, content), (
        "Could not find required intermediate assertion "
        f"'assert(variance >= 0.0);' in {SOURCE}"
    )


def test_compiled_binary_exists_and_executable():
    assert os.path.isfile(BINARY), f"Compiled binary missing: {BINARY}"
    assert os.access(BINARY, os.X_OK), f"File is not executable: {BINARY}"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a compiled ELF binary"
    assert os.stat(BINARY).st_mtime_ns >= os.stat(SOURCE).st_mtime_ns, (
        "Compiled binary predates the modified source"
    )


def test_fixed_stats_output():
    assert os.path.isfile(STATS), f"Output file missing: {STATS}"
    with open(STATS, "rb") as f:
        saved_output = f.read()
    assert saved_output.strip(), f"Output file is empty: {STATS}"

    # The saved file must actually be the output of the submitted executable
    # on the supplied response_times.txt input.
    actual_output = run_program(BINARY)
    assert saved_output == actual_output, (
        f"{STATS} is not the current stdout of {BINARY} on the supplied data"
    )

    count, mean, stddev = parse_output(saved_output)
    assert count == 100000, f"Expected count 100000, got {count}"
    assert 999990.0 <= mean <= 1000010.0, f"Expected mean around 1000000.00, got {mean}"
    assert 2.0 <= stddev <= 3.0, f"Expected stddev around 2.50, got {stddev}"


def test_stable_computation_on_unseen_large_baselines(rebuilt_binary):
    # Generate inputs at verification time so results cannot be self-reported
    # or hard-coded. These baselines make the naive E[x^2]-E[x]^2 formula fail.
    rng = random.SystemRandom()
    cases = []
    for baseline, n, spread in ((1.0e12, 6001, 4.0), (1.0e10, 4093, 1.75)):
        values = [baseline + rng.uniform(-spread, spread) for _ in range(n)]
        cases.append(values)

    backup = DATA + ".verifier_backup"
    shutil.copyfile(DATA, backup)
    try:
        for values in cases:
            with open(DATA, "w") as f:
                for value in values:
                    f.write(f"{value:.6f}\n")

            # Derive expected answers from the exact decimal data written.
            with open(DATA, "r") as f:
                actual_values = [float(line) for line in f]
            expected_count = len(actual_values)
            expected_mean = math.fsum(actual_values) / expected_count
            expected_variance = math.fsum(
                (x - expected_mean) ** 2 for x in actual_values
            ) / expected_count
            expected_stddev = math.sqrt(expected_variance)

            submitted = parse_output(run_program(BINARY))
            rebuilt = parse_output(run_program(rebuilt_binary))

            for label, result in (("submitted binary", submitted),
                                  ("binary rebuilt from source", rebuilt)):
                count, mean, stddev = result
                assert count == expected_count, (
                    f"{label}: expected count {expected_count}, got {count}"
                )
                assert abs(mean - expected_mean) <= 0.06, (
                    f"{label}: expected mean {expected_mean:.6f}, got {mean}"
                )
                assert abs(stddev - expected_stddev) <= 0.06, (
                    f"{label}: expected stddev {expected_stddev:.6f}, got {stddev}"
                )

            # A submitted executable built from this source must agree with a
            # fresh verifier build at the precision printed by the program.
            assert submitted == rebuilt, (
                "Submitted executable's results do not match the modified source"
            )
    finally:
        shutil.move(backup, DATA)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
