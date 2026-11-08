#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess

SCRIPT = '/home/user/bootstrap_corr.sh'
DATASET = '/home/user/dataset.csv'
RESULT = '/home/user/result.txt'


def test_script_exists_and_executable():
    script_path = '/home/user/bootstrap_corr.sh'
    assert os.path.exists(script_path), f"Script missing: {script_path}"
    assert os.path.isfile(script_path), f"Path is not a file: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"


def test_result_file_exists():
    result_path = '/home/user/result.txt'
    assert os.path.exists(result_path), f"Result file missing: {result_path}"
    assert os.path.isfile(result_path), f"Path is not a file: {result_path}"


def test_result_format_and_values():
    result_path = '/home/user/result.txt'
    with open(result_path, 'r') as f:
        text = f.read()

    match = re.search(r'Mean:\s+([0-9\.]+)\nSD:\s+([0-9\.]+)', text.strip())
    assert match is not None, "Output format incorrect. Expected 'Mean: 0.XXXX\\nSD: 0.XXXX'"

    mean_val = float(match.group(1))
    sd_val = float(match.group(2))

    assert 0.9600 <= mean_val <= 0.9999, f"Mean {mean_val} out of expected bounds [0.9600, 0.9999]"
    assert 0.0010 <= sd_val <= 0.0400, f"SD {sd_val} out of expected bounds [0.0010, 0.0400]"


def write_dataset(rows):
    with open(DATASET, 'w') as f:
        f.write('id,feature_A,feature_B\n')
        for i, (x, y) in enumerate(rows, 1):
            f.write(f'{i},{x},{y}\n')


def run_script(iterations):
    proc = subprocess.run(
        [SCRIPT, str(iterations)],
        cwd='/home/user',
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert proc.returncode == 0, f'Script failed for N={iterations}: {proc.stderr}'
    assert os.path.isfile(RESULT), 'Script did not create /home/user/result.txt'


def read_exact_result():
    with open(RESULT, 'r') as f:
        text = f.read()
    match = re.fullmatch(r'Mean: (-?(?:\d+)\.\d{4})\nSD: (-?(?:\d+)\.\d{4})\n?', text)
    assert match is not None, 'Result must contain exactly two labels and values rounded to 4 decimal places'
    return float(match.group(1)), float(match.group(2))


def bootstrap_moments(rows):
    n = len(rows)
    fact_n = math.factorial(n)
    weighted = []

    def visit(prefix, remaining, slots):
        if slots == 1:
            counts = prefix + [remaining]
            weight = fact_n
            for count in counts:
                weight //= math.factorial(count)

            sx = sy = sxx = syy = sxy = 0.0
            for count, (x, y) in zip(counts, rows):
                sx += count * x
                sy += count * y
                sxx += count * x * x
                syy += count * y * y
                sxy += count * x * y
            vx = sxx - sx * sx / n
            vy = syy - sy * sy / n
            if vx > 1e-14 and vy > 1e-14:
                corr = (sxy - sx * sy / n) / math.sqrt(vx * vy)
                weighted.append((weight, corr))
            return
        for count in range(remaining + 1):
            visit(prefix + [count], remaining - count, slots - 1)

    visit([], n, n)
    total = sum(weight for weight, _ in weighted)
    mean = sum(weight * value for weight, value in weighted) / total
    variance = sum(weight * (value - mean) ** 2 for weight, value in weighted) / total
    fourth = sum(weight * (value - mean) ** 4 for weight, value in weighted) / total
    return mean, math.sqrt(variance), fourth


def test_script_executes_pearson_and_bootstrap_algorithm():
    with open(DATASET, 'rb') as f:
        original_dataset = f.read()

    try:
        negative_rows = [(float(i), float(20 - 3 * i)) for i in range(1, 9)]
        write_dataset(negative_rows)
        run_script(40)
        mean, sd = read_exact_result()
        assert abs(mean + 1.0) <= 0.0002, f'Incorrect Pearson correlation on a perfect negative line: {mean}'
        assert abs(sd) <= 0.0002, f'Unexpected bootstrap SD on a perfect negative line: {sd}'

        rows = [
            (1.0, 1.0), (2.0, 4.0), (3.0, 2.0), (4.0, 8.0),
            (5.0, 3.0), (6.0, 9.0), (7.0, 5.0), (8.0, 7.0),
        ]
        expected_mean, expected_sd, fourth = bootstrap_moments(rows)
        iterations = 500
        write_dataset(rows)
        run_script(iterations)
        mean, sd = read_exact_result()

        mean_tol = max(0.03, 7.0 * expected_sd / math.sqrt(iterations))
        variance = expected_sd ** 2
        sd_se = math.sqrt(max(fourth - variance ** 2, 0.0) / (4.0 * variance * iterations))
        sd_tol = max(0.03, 7.0 * sd_se)
        assert abs(mean - expected_mean) <= mean_tol, (
            f'Bootstrap mean {mean} differs from derived expectation {expected_mean:.6f}'
        )
        assert abs(sd - expected_sd) <= sd_tol, (
            f'Bootstrap SD {sd} differs from derived expectation {expected_sd:.6f}'
        )
    finally:
        with open(DATASET, 'wb') as f:
            f.write(original_dataset)

    run_script(500)
    test_result_format_and_values()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
