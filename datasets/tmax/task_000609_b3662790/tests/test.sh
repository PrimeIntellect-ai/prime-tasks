#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import pytest
import subprocess
import ctypes
import secrets
import struct
import stat


def get_expected_test_mean():
    data_path = "/home/user/data.csv"
    if not os.path.exists(data_path):
        return None

    train_vals = []
    test_vals = []

    with open(data_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            val = float(row['value'])
            if row['split'] == 'train':
                train_vals.append(val)
            elif row['split'] == 'test':
                test_vals.append(val)

    if not train_vals or not test_vals:
        return None

    train_mean = sum(train_vals) / len(train_vals)
    sq_sum = sum((x - train_mean)**2 for x in train_vals)
    train_std = math.sqrt(sq_sum / len(train_vals))

    test_norms = [(x - train_mean) / train_std for x in test_vals]
    test_mean = sum(test_norms) / len(test_norms)

    return test_mean


def test_test_mean_output():
    out_path = "/home/user/test_mean.txt"
    assert os.path.exists(out_path), f"Output file {out_path} is missing. Did you compile and run the C program?"

    with open(out_path, "r") as f:
        content = f.read().strip()

    assert content, f"{out_path} is empty."

    try:
        actual_test_mean = float(content)
    except ValueError:
        pytest.fail(f"Could not parse a float from {out_path}. Content: {content}")

    expected_test_mean = get_expected_test_mean()
    assert expected_test_mean is not None, "Could not compute expected test mean due to missing or invalid data.csv."

    assert math.isclose(actual_test_mean, expected_test_mean, abs_tol=0.001), \
        f"test_mean.txt contains {actual_test_mean:.4f}, but expected {expected_test_mean:.4f}. The data leakage bug might not be correctly fixed."


def test_bootstrap_mean_output():
    out_path = "/home/user/bootstrap_mean.txt"
    assert os.path.exists(out_path), f"Output file {out_path} is missing."

    with open(out_path, "r") as f:
        content = f.read().strip()

    assert content, f"{out_path} is empty."

    try:
        actual_bs_mean = float(content)
    except ValueError:
        pytest.fail(f"Could not parse a float from {out_path}. Content: {content}")

    assert abs(actual_bs_mean) < 0.05, \
        f"bootstrap_mean.txt contains {actual_bs_mean:.4f}, which is too far from 0.0. " \
        "If normalization was correctly computed ONLY on the train split, the train split's normalized mean should be 0."


def test_c_code_modifications():
    c_path = "/home/user/normalize_and_bootstrap.c"
    assert os.path.exists(c_path), f"C program {c_path} is missing."

    with open(c_path, "r") as f:
        code = f.read()

    assert "fopen(\"/home/user/test_mean.txt\"" in code, "Output file path for test_mean.txt was altered or removed."
    assert "fopen(\"/home/user/bootstrap_mean.txt\"" in code, "Output file path for bootstrap_mean.txt was altered or removed."
    assert "srand(42);" in code, "Random seed was altered or removed."
    assert "B = 1000;" in code or "b < 1000;" in code or "B=1000;" in code, "Number of bootstrap iterations was altered."


def f32(value):
    return struct.unpack("f", struct.pack("f", float(value)))[0]


def expected_results(train_values, test_values):
    train = [f32(x) for x in train_values]
    test = [f32(x) for x in test_values]

    total = f32(0.0)
    for value in train:
        total = f32(total + value)
    mean = f32(total / len(train))

    sq_sum = f32(0.0)
    for value in train:
        delta = f32(value - mean)
        sq_sum = f32(sq_sum + f32(delta * delta))
    stddev = f32(math.sqrt(f32(sq_sum / len(train))))

    train_norm = [f32(f32(value - mean) / stddev) for value in train]
    test_norm = [f32(f32(value - mean) / stddev) for value in test]

    test_sum = f32(0.0)
    for value in test_norm:
        test_sum = f32(test_sum + value)
    expected_test = f32(test_sum / len(test_norm))

    libc = ctypes.CDLL(None)
    libc.srand.argtypes = [ctypes.c_uint]
    libc.rand.restype = ctypes.c_int
    libc.srand(42)

    bs_means_sum = f32(0.0)
    for _ in range(1000):
        sample_sum = f32(0.0)
        for _ in range(len(train_norm)):
            idx = libc.rand() % len(train_norm)
            sample_sum = f32(sample_sum + train_norm[idx])
        bs_means_sum = f32(bs_means_sum + f32(sample_sum / len(train_norm)))
    expected_bs = f32(bs_means_sum / 1000)

    return expected_test, expected_bs


def make_hidden_case():
    rng = secrets.SystemRandom()
    best = None
    for _ in range(250):
        train_count = rng.randint(3, 8)
        test_count = rng.randint(2, 5)
        train = [round(rng.uniform(15.0, 95.0), 2) for _ in range(train_count)]
        if max(train) - min(train) < 10.0:
            continue
        test = [round(rng.uniform(145.0, 260.0), 2) for _ in range(test_count)]
        expected_test, expected_bs = expected_results(train, test)
        candidate = (abs(expected_bs), train, test, expected_test, expected_bs)
        if best is None or candidate[0] > best[0]:
            best = candidate
        if abs(expected_bs) >= 0.010:
            return train, test, expected_test, expected_bs

    assert best is not None and best[0] >= 0.004, "Could not construct a discriminating bootstrap test case"
    return best[1], best[2], best[3], best[4]


def read_single_float(path):
    assert os.path.isfile(path) and not os.path.islink(path), f"{path} was not generated as a regular file"
    content = open(path, "r").read().strip()
    assert content, f"{path} is empty"
    try:
        value = float(content)
    except ValueError:
        pytest.fail(f"Could not parse a float from {path}. Content: {content}")
    assert math.isfinite(value), f"{path} must contain a finite value"
    return value


def test_compiled_program_on_hidden_datasets():
    source = "/home/user/normalize_and_bootstrap.c"
    binary = "/tmp/run_pipeline_verified"
    data_path = "/home/user/data.csv"
    test_path = "/home/user/test_mean.txt"
    bs_path = "/home/user/bootstrap_mean.txt"

    assert os.path.isfile(source) and not os.path.islink(source), f"C program {source} must be a regular file"
    compile_result = subprocess.run(
        ["gcc", source, "-lm", "-o", binary],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, f"C program did not compile:\n{compile_result.stderr}"
    assert os.path.isfile(binary) and os.access(binary, os.X_OK), "Compilation did not produce an executable"

    saved = {}
    for path in (data_path, test_path, bs_path):
        saved[path] = open(path, "rb").read() if os.path.isfile(path) else None

    try:
        for _ in range(3):
            train, test, expected_test, expected_bs = make_hidden_case()
            if os.path.lexists(data_path):
                os.unlink(data_path)
            with open(data_path, "w") as f:
                f.write("id,value,split\n")
                row_id = 1
                for value in train:
                    f.write(f"{row_id},{value:.2f},train\n")
                    row_id += 1
                for value in test:
                    f.write(f"{row_id},{value:.2f},test\n")
                    row_id += 1

            for path in (test_path, bs_path):
                if os.path.lexists(path):
                    os.unlink(path)

            result = subprocess.run(
                [binary],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=15,
            )
            assert result.returncode == 0, \
                f"Compiled pipeline failed on a hidden dataset (exit {result.returncode}):\n{result.stderr}"

            actual_test = read_single_float(test_path)
            actual_bs = read_single_float(bs_path)
            assert math.isclose(actual_test, expected_test, abs_tol=0.002), \
                f"Hidden dataset test mean was {actual_test:.4f}, expected {expected_test:.4f}"
            assert math.isclose(actual_bs, expected_bs, abs_tol=0.002), \
                f"Hidden dataset bootstrap mean was {actual_bs:.4f}, expected {expected_bs:.4f}"
    finally:
        for path, content in saved.items():
            if os.path.lexists(path):
                os.unlink(path)
            if content is not None:
                with open(path, "wb") as f:
                    f.write(content)
        if os.path.exists(binary):
            os.unlink(binary)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
