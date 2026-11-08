#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import subprocess

HOME = "/home/user"
DATA = os.path.join(HOME, "data.csv")
SOURCE = os.path.join(HOME, "pipeline.c")
BINARY = os.path.join(HOME, "pipeline")
FINAL = os.path.join(HOME, "final_mse.txt")
REBUILT = "/tmp/pipeline_from_source"


def read_dataset(path):
    X, y = [], []
    with open(path, "r") as f:
        lines = f.read().strip().split("\n")
    for line in lines:
        if not line.strip():
            continue
        parts = line.split(",")
        X.append(float(parts[0]))
        y.append(float(parts[1]))
    return X, y


def expected_mse(X, y):
    assert len(X) == 100 and len(y) == 100

    X_train = X[:80]
    y_train = y[:80]
    X_test = X[80:]
    y_test = y[80:]

    train_valid = [x for x in X_train if x != -999.0]
    train_mean = sum(train_valid) / len(train_valid)
    train_var = sum((x - train_mean) ** 2 for x in train_valid) / len(train_valid)
    train_std = math.sqrt(train_var)

    X_train_norm = [
        ((x if x != -999.0 else train_mean) - train_mean) / train_std
        for x in X_train
    ]
    X_test_norm = [
        ((x if x != -999.0 else train_mean) - train_mean) / train_std
        for x in X_test
    ]

    n = len(X_train_norm)
    sum_x = sum(X_train_norm)
    sum_y = sum(y_train)
    sum_xy = sum(x * y_val for x, y_val in zip(X_train_norm, y_train))
    sum_xx = sum(x * x for x in X_train_norm)

    weight = (n * sum_xy - sum_x * sum_y) / (n * sum_xx - sum_x * sum_x)
    bias = (sum_y - weight * sum_x) / n

    mse = 0.0
    for x, y_true in zip(X_test_norm, y_test):
        pred = weight * x + bias
        mse += (pred - y_true) ** 2
    return mse / len(X_test_norm)


def run_pipeline(executable):
    result = subprocess.run(
        [executable],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
        check=False,
    )
    assert result.returncode == 0, (
        f"{executable} exited with {result.returncode}. stderr: {result.stderr}"
    )
    output = result.stdout.strip()
    assert len(output.split()) == 1, f"Unexpected program output: {result.stdout!r}"
    try:
        value = float(output)
    except ValueError:
        assert False, f"Program output is not a float: {result.stdout!r}"
    assert math.isfinite(value), f"Program output is not finite: {value}"
    return output, value


def make_challenge(rng, trial):
    rows = []
    train_latent = []
    for i in range(80):
        x = rng.uniform(-9.0, 9.0) + trial * 0.17
        train_latent.append(x)

    missing_train = set(rng.sample(range(80), 7))
    for i, latent_x in enumerate(train_latent):
        observed_x = -999.0 if i in missing_train else latent_x
        target = 4.25 * latent_x - 6.0 + rng.uniform(-0.35, 0.35)
        rows.append((observed_x, target))

    valid_train = [train_latent[i] for i in range(80) if i not in missing_train]
    train_mean = sum(valid_train) / len(valid_train)
    missing_test = set(rng.sample(range(20), 9))
    for i in range(20):
        if i in missing_test:
            observed_x = -999.0
            target = 4.25 * train_mean - 6.0 + rng.uniform(-0.35, 0.35)
        else:
            observed_x = rng.uniform(35.0 + trial, 60.0 + trial)
            target = 4.25 * observed_x - 6.0 + rng.uniform(-0.35, 0.35)
        rows.append((observed_x, target))

    payload = "".join(f"{x:.9f},{target:.9f}\n" for x, target in rows)
    parsed_x = [float(line.split(",")[0]) for line in payload.strip().splitlines()]
    parsed_y = [float(line.split(",")[1]) for line in payload.strip().splitlines()]
    return payload.encode(), expected_mse(parsed_x, parsed_y)


def test_final_state_and_pipeline():
    assert os.path.isfile(FINAL), f"{FINAL} does not exist. Did you save the output?"
    assert os.path.isfile(DATA), f"{DATA} does not exist."
    assert os.path.isfile(SOURCE), f"{SOURCE} does not exist."
    assert os.path.isfile(BINARY), f"{BINARY} does not exist. Did you compile the program?"
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable."

    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a compiled ELF executable."

    # Preserve the original verifier's independent check of the submitted MSE.
    X, y = read_dataset(DATA)
    expected = expected_mse(X, y)
    with open(FINAL, "r") as f:
        actual_mse_str = f.read().strip()
    try:
        actual_mse = float(actual_mse_str)
    except ValueError:
        assert False, f"Could not parse the content of {FINAL} as a float. Content: {actual_mse_str!r}"
    assert math.isclose(actual_mse, expected, rel_tol=1e-3), (
        f"The computed MSE ({actual_mse}) does not match the expected MSE "
        f"without data leakage (~{expected:.6f})."
    )

    # Compile the submitted source independently so both source and submitted binary
    # must implement the repair.
    if os.path.lexists(REBUILT):
        os.remove(REBUILT)
    compiled = subprocess.run(
        ["gcc", "-O2", SOURCE, "-lm", "-o", REBUILT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
        check=False,
    )
    assert compiled.returncode == 0, f"pipeline.c does not compile: {compiled.stderr}"

    with open(DATA, "rb") as f:
        original_data = f.read()

    try:
        # The saved result must be the output of the submitted executable on the
        # provided dataset, rather than a separately calculated number.
        binary_output, binary_value = run_pipeline(BINARY)
        assert binary_output == actual_mse_str, (
            f"{FINAL} does not contain the output of {BINARY}: "
            f"file={actual_mse_str!r}, program={binary_output!r}"
        )
        assert math.isclose(binary_value, expected, rel_tol=1e-3), (
            f"Submitted executable produced {binary_value}, expected about {expected:.6f}."
        )
        with open(DATA, "rb") as f:
            assert f.read() == original_data, "The pipeline unexpectedly modified data.csv."

        # Exercise both artifacts on fresh, unpredictable datasets. These cases
        # contain train/test distribution shifts and missing values, making use of
        # whole-dataset preprocessing statistics produce a substantially wrong MSE.
        rng = random.SystemRandom()
        for trial in range(2):
            payload, challenge_expected = make_challenge(rng, trial)
            for executable in (BINARY, REBUILT):
                with open(DATA, "wb") as f:
                    f.write(payload)
                _, observed = run_pipeline(executable)
                assert math.isclose(
                    observed, challenge_expected, rel_tol=2e-3, abs_tol=2e-3
                ), (
                    f"{executable} produced {observed} on challenge {trial}, but "
                    f"training-only preprocessing gives about {challenge_expected:.6f}."
                )
    finally:
        with open(DATA, "wb") as f:
            f.write(original_data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
