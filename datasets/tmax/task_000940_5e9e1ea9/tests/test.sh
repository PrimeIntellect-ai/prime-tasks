#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import pwd
import re
import subprocess
import tempfile

HOME = "/home/user"


def expected_split():
    valid = []
    for i in range(1, 151):
        if i % 15 != 0:
            valid.append(f"{i+1},{i*2},{i*3},{i*4}")
    return valid[:100], valid[100:]


def nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def expected_predictions(train_lines, test_lines):
    train = [[float(x) for x in line.split(",")[:3]] for line in train_lines]
    test = [[float(x) for x in line.split(",")[:3]] for line in test_lines]

    means = [sum(row[j] for row in train) / len(train) for j in range(3)]
    stds = []
    for j in range(3):
        std = math.sqrt(sum((row[j] - means[j]) ** 2 for row in train) / len(train))
        stds.append(std if std != 0 else 1.0)

    weights = [0.5, -1.2, 0.8]
    result = []
    for row in test:
        pred = 2.0 + sum(((row[j] - means[j]) / stds[j]) * weights[j] for j in range(3))
        result.append(f"{pred:.4f}")
    return result


def run_pipeline(binary, train_lines, test_lines):
    nobody = pwd.getpwnam("nobody")
    with tempfile.TemporaryDirectory() as workdir:
        os.chmod(workdir, 0o755)
        for name, lines in (("train.csv", train_lines), ("test.csv", test_lines)):
            path = os.path.join(workdir, name)
            with open(path, "w") as f:
                f.write("\n".join(lines) + "\n")
            os.chmod(path, 0o644)

        def drop_privileges():
            os.setgroups([])
            os.setgid(nobody.pw_gid)
            os.setuid(nobody.pw_uid)

        completed = subprocess.run(
            [binary], cwd=workdir, text=True, capture_output=True,
            timeout=10, preexec_fn=drop_privileges
        )
        assert completed.returncode == 0, \
            f"{binary} exited with {completed.returncode}: {completed.stderr}"
        assert completed.stderr == "", f"{binary} wrote unexpected stderr: {completed.stderr}"
        return completed.stdout.splitlines()


def test_train_csv_created():
    """Verify train.csv exists and contains the first 100 valid raw rows in order."""
    path = os.path.join(HOME, "train.csv")
    assert os.path.isfile(path), "/home/user/train.csv is missing"
    lines = nonempty_lines(path)
    assert len(lines) == 100, f"Expected 100 lines in train.csv, found {len(lines)}"
    expected_train, _ = expected_split()
    assert lines == expected_train, "train.csv is not the first 100 valid data rows in raw-data order"


def test_test_csv_created():
    """Verify test.csv exists and contains all remaining valid raw rows in order."""
    path = os.path.join(HOME, "test.csv")
    assert os.path.isfile(path), "/home/user/test.csv is missing"
    lines = nonempty_lines(path)
    assert len(lines) == 40, f"Expected 40 lines in test.csv, found {len(lines)}"
    _, expected_test = expected_split()
    assert lines == expected_test, "test.csv is not the remaining valid data rows in raw-data order"


def test_executable_exists():
    """Verify the C program was compiled to an executable ELF file."""
    path = os.path.join(HOME, "pipeline")
    assert os.path.isfile(path), "/home/user/pipeline executable is missing"
    assert os.access(path, os.X_OK), "/home/user/pipeline is not executable"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/pipeline is not a compiled ELF executable"


def test_predictions_correct():
    """Verify the saved predictions match train-only normalization of the required split."""
    path = os.path.join(HOME, "test_predictions.txt")
    assert os.path.isfile(path), "/home/user/test_predictions.txt is missing"

    train_lines = nonempty_lines(os.path.join(HOME, "train.csv"))
    test_lines = nonempty_lines(os.path.join(HOME, "test.csv"))
    expected = expected_predictions(train_lines, test_lines)
    actual = nonempty_lines(path)

    assert len(actual) == len(expected), \
        f"Expected {len(expected)} predictions, found {len(actual)}"
    assert all(re.fullmatch(r"-?\d+\.\d{4}", value) for value in actual), \
        "Predictions must be float values with exactly four decimal places"
    for i, (got, want) in enumerate(zip(actual, expected), 1):
        assert got == want, \
            f"Prediction mismatch at line {i}: expected {want}, got {got}. The data leak may not be fully fixed."


def test_pipeline_source_and_executable_behavior():
    """Compile the submitted source and exercise both it and the submitted executable."""
    source = os.path.join(HOME, "pipeline.c")
    submitted_binary = os.path.join(HOME, "pipeline")
    assert os.path.isfile(source), "/home/user/pipeline.c is missing"

    with tempfile.TemporaryDirectory() as builddir:
        rebuilt = os.path.join(builddir, "pipeline_rebuilt")
        compiled = subprocess.run(
            ["gcc", source, "-O2", "-o", rebuilt, "-lm"],
            text=True, capture_output=True, timeout=20
        )
        assert compiled.returncode == 0, f"pipeline.c does not compile with gcc: {compiled.stderr}"

        cases = [
            (
                ["1,2,4,0", "2,5,8,0", "4,9,3,0", "8,1,7,0"],
                ["3,7,2,0", "10,4,9,0", "-2,6,5,0"],
            ),
            (
                ["-5,10,2,0", "0,3,11,0", "6,-4,8,0", "9,7,-3,0", "2,15,5,0"],
                ["4,1,6,0", "-7,12,10,0"],
            ),
        ]

        for case_number, (train_lines, test_lines) in enumerate(cases, 1):
            expected = expected_predictions(train_lines, test_lines)
            for binary in (submitted_binary, rebuilt):
                actual = run_pipeline(binary, train_lines, test_lines)
                assert actual == expected, \
                    f"{binary} failed behavioral normalization test case {case_number}: expected {expected}, got {actual}"

        canonical_train, canonical_test = expected_split()
        expected = expected_predictions(canonical_train, canonical_test)
        submitted_output = run_pipeline(submitted_binary, canonical_train, canonical_test)
        rebuilt_output = run_pipeline(rebuilt, canonical_train, canonical_test)
        saved_output = nonempty_lines(os.path.join(HOME, "test_predictions.txt"))
        assert submitted_output == expected, "The submitted executable produces incorrect canonical predictions"
        assert rebuilt_output == expected, "The submitted pipeline.c produces incorrect canonical predictions"
        assert saved_output == submitted_output, \
            "test_predictions.txt does not match the submitted executable's output"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
