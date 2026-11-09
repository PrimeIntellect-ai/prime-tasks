#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
from decimal import Decimal, ROUND_FLOOR, ROUND_HALF_UP, localcontext

SCRIPT_PATH = "/home/user/monitor/calc_stats.sh"
INPUT_PATH = "/home/user/monitor/latencies.txt"
OUTPUT_PATH = "/home/user/monitor/stats_output.txt"


def run_script(input_path):
    result = subprocess.run(
        [SCRIPT_PATH, input_path],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Script failed with return code {result.returncode}. Error: {result.stderr}"
    )
    return result.stdout.strip()


def expected_output(values):
    with localcontext() as ctx:
        ctx.prec = 60
        numbers = [Decimal(value) for value in values]
        count = Decimal(len(numbers))
        mean = sum(numbers) / count
        variance = sum((value - mean) ** 2 for value in numbers) / Decimal(len(numbers) - 1)
        stddev = variance.sqrt()
        quantum = Decimal("0.001")
        mean_text = format(mean.quantize(quantum, rounding=ROUND_HALF_UP), ".3f")
        stddev_text = format(stddev.quantize(quantum, rounding=ROUND_HALF_UP), ".3f")
        return f"Mean: {mean_text}\nStdDev: {stddev_text}", mean, stddev


def safely_away_from_rounding_boundary(value):
    scaled = value * Decimal(1000)
    fraction = scaled - scaled.to_integral_value(rounding=ROUND_FLOOR)
    return abs(fraction - Decimal("0.5")) > Decimal("0.20")


def test_stats_output_file_content():
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."

    with open(OUTPUT_PATH, "r") as f:
        raw_content = f.read()
        content = raw_content.strip().split('\n')

    assert len(content) >= 2, f"Output file {OUTPUT_PATH} does not contain enough lines."
    assert "Mean: 100000000.004" in content[0], f"Expected Mean: 100000000.004, but got {content[0]}"
    assert "StdDev: 0.003" in content[1], f"Expected StdDev: 0.003, but got {content[1]}"

    # The saved artifact must be exactly the output produced by the submitted script.
    actual_stdout = run_script(INPUT_PATH)
    assert raw_content.strip() == actual_stdout, (
        "stats_output.txt does not match the script's output on latencies.txt"
    )
    assert actual_stdout == "Mean: 100000000.004\nStdDev: 0.003"


def test_script_robustness_on_new_data():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

    # Retain the original fixed robustness assertion.
    test_data = [
        "10000000000.001",
        "10000000000.005",
        "10000000000.002",
        "10000000000.008",
        "10000000000.004",
        "10000000000.006"
    ]

    with tempfile.NamedTemporaryFile(mode='w', delete=False) as tmp:
        tmp.write("\n".join(test_data) + "\n")
        tmp_path = tmp.name

    try:
        result = subprocess.run([SCRIPT_PATH, tmp_path], capture_output=True, text=True)
        assert result.returncode == 0, f"Script failed with return code {result.returncode}. Error: {result.stderr}"

        output = result.stdout.strip().split('\n')
        assert len(output) >= 2, "Script did not output both Mean and StdDev."
        assert "Mean: 10000000000.004" in output[0], f"Expected Mean: 10000000000.004, but got {output[0]}"
        assert "StdDev: 0.003" in output[1], f"Expected StdDev: 0.003, but got {output[1]}"
    finally:
        os.remove(tmp_path)


def test_script_computes_unpredictable_datasets():
    rng = secrets.SystemRandom()
    cases = []

    # Generate varied, previously unknown datasets and independently derive their
    # sample statistics with high-precision decimal arithmetic.
    while len(cases) < 8:
        count = rng.randrange(5, 18)
        base = rng.randrange(100_000_000, 20_000_000_000)
        offsets = [rng.randrange(0, 251) for _ in range(count)]
        if len(set(offsets)) < 3:
            continue

        values = [f"{base + offset // 1000}.{offset % 1000:03d}" for offset in offsets]
        expected, mean, stddev = expected_output(values)
        if stddev == 0:
            continue
        if not safely_away_from_rounding_boundary(mean):
            continue
        if not safely_away_from_rounding_boundary(stddev):
            continue
        cases.append((values, expected))

    for values, expected in cases:
        with tempfile.NamedTemporaryFile(mode="w", delete=False) as tmp:
            tmp.write("\n".join(values) + "\n")
            tmp_path = tmp.name
        try:
            actual = run_script(tmp_path)
            assert actual == expected, (
                f"Incorrect statistics for input {values}.\n"
                f"Expected:\n{expected}\nGot:\n{actual}"
            )
        finally:
            os.remove(tmp_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
