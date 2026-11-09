#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess
import tempfile

SOURCE = '/home/user/pipeline.cpp'
RESULTS = '/home/user/model_results.txt'
TRAIN = '/home/user/train_data.txt'
TEST = '/home/user/test_data.txt'


def run_checked(cmd, timeout):
    return subprocess.run(
        cmd,
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
        check=True,
    )


def execute_pipeline(executable):
    if os.path.lexists(RESULTS):
        os.remove(RESULTS)
    run_checked([executable], 10)
    assert os.path.isfile(RESULTS), (
        'The output file /home/user/model_results.txt is missing. '
        'Did you compile and run the program?'
    )


def read_results():
    with open(RESULTS, 'r') as f:
        content = f.read().strip().split('\n')
    content = [line.strip() for line in content if line.strip()]
    assert len(content) == 3, (
        f'Expected exactly 3 lines in model_results.txt, but got {len(content)}.'
    )
    return content


def write_dataset(path, rows):
    with open(path, 'w') as f:
        f.write('ID|Sensor_A|Sensor_B|Target\n')
        for row in rows:
            f.write('|'.join(str(value) for value in row) + '\n')


def ols_and_mae(train_points, test_points):
    n = len(train_points)
    mean_x = sum(x for x, _ in train_points) / n
    mean_y = sum(y for _, y in train_points) / n
    denominator = sum((x - mean_x) ** 2 for x, _ in train_points)
    assert denominator > 0
    m = sum((x - mean_x) * (y - mean_y) for x, y in train_points) / denominator
    b = mean_y - m * mean_x
    mae = sum(abs((m * x + b) - y) for x, y in test_points) / len(test_points)
    return m, b, mae


def assert_dynamic_results(expected):
    lines = read_results()
    patterns = [
        re.compile(r'^m: (-?\d+\.\d{4})$'),
        re.compile(r'^b: (-?\d+\.\d{4})$'),
        re.compile(r'^MAE: (-?\d+\.\d{4})$'),
    ]
    actual = []
    for line, pattern in zip(lines, patterns):
        match = pattern.fullmatch(line)
        assert match is not None, (
            f'Incorrect output format: {line!r}; numeric values must have exactly 4 decimal places.'
        )
        actual.append(float(match.group(1)))

    for label, got, want in zip(('m', 'b', 'MAE'), actual, expected):
        assert math.isfinite(got), f'{label} is not finite.'
        assert abs(got - want) <= 0.000051, (
            f'{label} is incorrect: got {got:.4f}, expected {want:.4f}.'
        )


def make_random_case(rng, case_number):
    train_count = rng.randint(5, 9)
    test_count = rng.randint(3, 7)
    slope_seed = rng.randint(-700, 900) / 100.0
    intercept_seed = rng.randint(-500, 500) / 100.0

    train_points = []
    train_rows = []
    for i in range(train_count):
        x = (i + 1) * rng.randint(2, 7) / 4.0 + rng.randint(0, 30) / 100.0
        noise = rng.randint(-80, 80) / 100.0
        y = slope_seed * x + intercept_seed + noise
        x = float(f'{x:.6f}')
        y = float(f'{y:.6f}')
        train_points.append((x, y))
        train_rows.append((1000 + case_number * 100 + i, f'{x:.6f}', rng.randint(-999, 999), f'{y:.6f}'))

    # These rows must be discarded. Their extreme values make either filtering bug visible.
    train_rows.append((1900 + case_number, f'{-rng.randint(1, 20)}.500000', '999999', '888888.000000'))
    train_rows.append((1950 + case_number, '9999.000000', '-999999', 'NaN'))

    test_points = []
    test_rows = []
    for i in range(test_count):
        x = (i + 1) * rng.randint(3, 9) / 5.0 + rng.randint(0, 40) / 100.0
        deviation = rng.randint(-120, 120) / 100.0
        y = slope_seed * x + intercept_seed + deviation
        x = float(f'{x:.6f}')
        y = float(f'{y:.6f}')
        test_points.append((x, y))
        test_rows.append((2000 + case_number * 100 + i, f'{x:.6f}', rng.randint(-999, 999), f'{y:.6f}'))

    test_rows.append((2900 + case_number, f'{-rng.randint(1, 20)}.250000', '123456', '-777777.000000'))
    test_rows.append((2950 + case_number, '7777.000000', '-123456', 'NaN'))
    rng.shuffle(train_rows)
    rng.shuffle(test_rows)
    return train_rows, test_rows, ols_and_mae(train_points, test_points)


def main():
    # Preserve the original source existence assertion.
    assert os.path.isfile(SOURCE), 'The C++ source file /home/user/pipeline.cpp is missing.'

    executable = os.path.join(tempfile.gettempdir(), 'pipeline_verified_' + next(tempfile._get_candidate_names()))
    try:
        run_checked(['g++', '-std=c++17', '-O2', SOURCE, '-o', executable], 30)

        # First run against the originally supplied datasets and preserve the exact original assertions.
        with open(TRAIN, 'w') as f:
            f.write('''ID|Sensor_A|Sensor_B|Target
1|2.5|10.0|7.45
2|-1.0|5.0|4.00
3|3.0|12.0|8.70
4|4.5|8.0|NaN
5|1.5|7.0|4.95
6|5.0|9.0|13.70
7|0.0|0.0|1.20
''')
        with open(TEST, 'w') as f:
            f.write('''ID|Sensor_A|Sensor_B|Target
8|2.0|1.0|6.20
9|4.0|2.0|11.20
10|-2.5|3.0|1.00
11|3.5|4.0|9.95
12|1.0|5.0|NaN
''')
        execute_pipeline(executable)
        content = read_results()
        expected_lines = ['m: 2.5000', 'b: 1.2000', 'MAE: 0.0000']
        for i, expected in enumerate(expected_lines):
            assert content[i] == expected, (
                f"Line {i+1} mismatch. Expected '{expected}', got '{content[i]}'."
            )

        # Exercise the compiled submission on unpredictable datasets and derive each oracle independently.
        rng = random.SystemRandom()
        for case_number in range(3):
            train_rows, test_rows, expected = make_random_case(rng, case_number)
            write_dataset(TRAIN, train_rows)
            write_dataset(TEST, test_rows)
            execute_pipeline(executable)
            assert_dynamic_results(expected)
    finally:
        if os.path.exists(executable):
            os.remove(executable)


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
