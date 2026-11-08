#!/bin/bash
mkdir -p /logs/verifier
status=0

if [[ ! -f /home/user/etl_processor.c || -L /home/user/etl_processor.c ]]; then
    echo "Missing regular C source file: /home/user/etl_processor.c"
    status=1
elif ! /usr/bin/gcc -std=c11 -O2 -Wall -Wextra -o /tmp/verified_etl /home/user/etl_processor.c -lm; then
    echo "Failed to compile /home/user/etl_processor.c"
    status=1
else
cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess

TRAIN = "/home/user/train.csv"
TEST = "/home/user/test.csv"
TRAIN_OUT = "/home/user/train_processed.csv"
TEST_OUT = "/home/user/test_processed.csv"
PROGRAM = "/tmp/verified_etl"
MISSING = -9999.0


def write_csv(path, rows):
    with open(path, "w") as f:
        for row in rows:
            f.write(f"{row[0]}, {row[1]}\n")


def run_program(train_rows, test_rows):
    write_csv(TRAIN, train_rows)
    write_csv(TEST, test_rows)
    for path in (TRAIN_OUT, TEST_OUT):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        [PROGRAM], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"Compiled ETL program exited with {result.returncode}. "
        f"stderr: {result.stderr}"
    )


original_train = [
    (1.0, 2.0),
    (3.0, -9999.0),
    (5.0, 6.0),
    (-9999.0, 8.0),
    (9.0, 10.0),
]
original_test = [
    (2.0, 4.0),
    (-9999.0, 5.0),
    (8.0, -9999.0),
]

# Run the compiled submission on the task's original inputs before checking the
# original expected-output assertions.
run_program(original_train, original_test)


def test_train_processed():
    path = "/home/user/train_processed.csv"
    assert os.path.exists(path), f"{path} does not exist. The C program may not have run successfully or written the file."

    with open(path, 'r') as f:
        content = [line.strip() for line in f.read().strip().split('\n') if line.strip()]

    expected = [
        "-1.3229,-1.7008",
        "-0.5669,0.0000",
        "0.1890,-0.1890",
        "0.0000,0.5669",
        "1.7008,1.3229"
    ]

    assert len(content) == len(expected), f"Output line count mismatch in {path}: expected {len(expected)}, got {len(content)}"
    for i, (act, exp) in enumerate(zip(content, expected)):
        # Allow optional spaces after comma
        act_clean = act.replace(" ", "")
        exp_clean = exp.replace(" ", "")
        assert act_clean == exp_clean, f"Mismatch on line {i+1} in {path}: expected {exp}, got {act}"


def test_test_processed():
    path = "/home/user/test_processed.csv"
    assert os.path.exists(path), f"{path} does not exist. The C program may not have run successfully or written the file."

    with open(path, 'r') as f:
        content = [line.strip() for line in f.read().strip().split('\n') if line.strip()]

    expected = [
        "-0.9449,-0.9449",
        "0.0000,-0.5669",
        "1.3229,0.0000"
    ]

    assert len(content) == len(expected), f"Output line count mismatch in {path}: expected {len(expected)}, got {len(content)}"
    for i, (act, exp) in enumerate(zip(content, expected)):
        # Allow optional spaces after comma
        act_clean = act.replace(" ", "")
        exp_clean = exp.replace(" ", "")
        assert act_clean == exp_clean, f"Mismatch on line {i+1} in {path}: expected {exp}, got {act}"


def expected_outputs(train_rows, test_rows):
    means = []
    for col in range(2):
        valid = [row[col] for row in train_rows if row[col] != MISSING]
        assert valid
        means.append(sum(valid) / len(valid))

    imputed_train = [
        tuple(means[c] if row[c] == MISSING else row[c] for c in range(2))
        for row in train_rows
    ]
    stds = []
    for col in range(2):
        variance = sum((row[col] - means[col]) ** 2 for row in imputed_train) / len(imputed_train)
        stds.append(math.sqrt(variance))
        assert stds[-1] > 0

    def transform(rows):
        result = []
        for row in rows:
            values = []
            for col in range(2):
                value = means[col] if row[col] == MISSING else row[col]
                values.append(f"{(value - means[col]) / stds[col]:.4f}")
            result.append(values)
        return result

    return transform(train_rows), transform(test_rows)


def assert_generated_csv(path, expected):
    assert os.path.isfile(path), f"{path} was not produced by the compiled program"
    with open(path, "r") as f:
        lines = [line.strip() for line in f.read().strip().split("\n") if line.strip()]
    assert len(lines) == len(expected), (
        f"Output line count mismatch in {path}: expected {len(expected)}, got {len(lines)}"
    )

    number = re.compile(r"^-?\d+\.\d{4}$")
    for i, (line, wanted) in enumerate(zip(lines, expected), 1):
        fields = [field.strip() for field in line.split(",")]
        assert len(fields) == 2, f"Line {i} in {path} does not contain exactly two columns"
        assert all(number.fullmatch(field) for field in fields), (
            f"Line {i} in {path} is not formatted with exactly four decimal places: {line}"
        )
        assert fields == wanted, (
            f"Mismatch on line {i} in {path}: expected {','.join(wanted)}, got {line}"
        )


def test_compiled_program_on_generated_inputs():
    rng = random.SystemRandom()

    for _ in range(2):
        a = rng.randint(-40, 40)
        b = rng.randint(-40, 40)
        step1 = rng.randint(2, 8)
        step2 = rng.randint(2, 8)

        train_rows = [
            (float(a), float(b)),
            (float(a + step1), MISSING),
            (MISSING, float(b + 4 * step2)),
            (float(a + 3 * step1), float(b - 2 * step2)),
            (float(a + 5 * step1), float(b + 7 * step2)),
            (float(a - step1), float(b + step2)),
        ]
        # Large and missing test values ensure test-set statistics cannot be used.
        test_rows = [
            (float(a + 2 * step1), float(b + 30 * step2)),
            (MISSING, float(b - 20 * step2)),
            (float(a + 25 * step1), MISSING),
            (float(a - 12 * step1), float(b + 3 * step2)),
        ]

        expected_train, expected_test = expected_outputs(train_rows, test_rows)
        run_program(train_rows, test_rows)
        assert_generated_csv(TRAIN_OUT, expected_train)
        assert_generated_csv(TEST_OUT, expected_test)
TEST_EOF

    if ! python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
        status=1
    fi
fi

if [[ "$status" -eq 0 ]]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
