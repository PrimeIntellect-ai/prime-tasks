#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import time
import pickle
import secrets
import subprocess

import numpy as np
from sklearn.linear_model import LogisticRegression

WORKSPACE_DIR = "/home/user/ml_pipeline"


def load_csv(filepath):
    with open(filepath, "r") as f:
        return [line.strip().split(",") for line in f if line.strip()]


def test_files_exist():
    expected_files = [
        "train_scaled.csv",
        "test_scaled.csv",
        "model.pkl",
        "benchmark.sh",
        "avg_time.txt",
    ]
    for filename in expected_files:
        path = os.path.join(WORKSPACE_DIR, filename)
        assert os.path.isfile(path), f"Expected file {path} is missing."


def test_benchmark_script_executable():
    path = os.path.join(WORKSPACE_DIR, "benchmark.sh")
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_avg_time_format():
    path = os.path.join(WORKSPACE_DIR, "avg_time.txt")
    with open(path, "r") as f:
        content = f.read().strip()

    match = re.match(r"^Average Inference Time: [0-9.]+ ms$", content)
    assert match is not None, (
        f"avg_time.txt content '{content}' does not match expected format "
        "'Average Inference Time: <value> ms'."
    )


def test_data_leakage_fixed():
    # Recompute the expected data
    users_path = os.path.join(WORKSPACE_DIR, "users.csv")
    transactions_path = os.path.join(WORKSPACE_DIR, "transactions.csv")

    assert os.path.isfile(users_path), "users.csv is missing. Did you run generate_data.py?"
    assert os.path.isfile(transactions_path), "transactions.csv is missing. Did you run generate_data.py?"

    users = load_csv(users_path)
    transactions = load_csv(transactions_path)

    # Sort by user_id
    users.sort(key=lambda x: x[0])
    transactions.sort(key=lambda x: x[0])

    # Join on user_id
    joined = []
    t_idx = 0
    for u in users:
        while t_idx < len(transactions) and transactions[t_idx][0] < u[0]:
            t_idx += 1
        if t_idx < len(transactions) and transactions[t_idx][0] == u[0]:
            # user_id, age, amount, fraud_label
            joined.append([u[0], u[1], transactions[t_idx][1], transactions[t_idx][2]])

    assert len(joined) == 1000, f"Expected 1000 joined rows, got {len(joined)}."

    train_raw = joined[:800]
    test_raw = joined[800:]

    # Compute min/max on train_raw
    train_amounts = [float(row[2]) for row in train_raw]
    min_amt = min(train_amounts)
    max_amt = max(train_amounts)

    # Scale
    def scale_row(row):
        scaled = (float(row[2]) - min_amt) / (max_amt - min_amt)
        return f"{row[0]},{row[1]},{scaled:.4f},{row[3]}"

    expected_train = [scale_row(row) for row in train_raw]
    expected_test = [scale_row(row) for row in test_raw]

    # Load actual
    actual_train = [",".join(row) for row in load_csv(os.path.join(WORKSPACE_DIR, "train_scaled.csv"))]
    actual_test = [",".join(row) for row in load_csv(os.path.join(WORKSPACE_DIR, "test_scaled.csv"))]

    assert len(actual_train) == 800, f"train_scaled.csv should have 800 rows, got {len(actual_train)}"
    assert len(actual_test) == 200, f"test_scaled.csv should have 200 rows, got {len(actual_test)}"

    for i, (act, exp) in enumerate(zip(actual_train, expected_train)):
        assert act == exp, f"Mismatch in train_scaled.csv at row {i+1}. Expected '{exp}', got '{act}'."

    for i, (act, exp) in enumerate(zip(actual_test, expected_test)):
        assert act == exp, f"Mismatch in test_scaled.csv at row {i+1}. Expected '{exp}', got '{act}'."


def test_trained_model_is_valid_and_matches_training_data():
    train_path = os.path.join(WORKSPACE_DIR, "train_scaled.csv")
    test_path = os.path.join(WORKSPACE_DIR, "test_scaled.csv")
    model_path = os.path.join(WORKSPACE_DIR, "model.pkl")

    train = np.loadtxt(train_path, delimiter=",")
    test = np.loadtxt(test_path, delimiter=",")
    X_train, y_train = train[:, 1:3], train[:, 3]
    X_test = test[:, 1:3]

    expected = LogisticRegression(random_state=42)
    expected.fit(X_train, y_train)

    assert os.path.getsize(model_path) > 0, "model.pkl is empty."
    with open(model_path, "rb") as f:
        actual = pickle.load(f)

    assert isinstance(actual, LogisticRegression), "model.pkl does not contain a LogisticRegression model."
    assert hasattr(actual, "coef_") and hasattr(actual, "intercept_"), "model.pkl contains an unfitted model."
    np.testing.assert_array_equal(actual.classes_, expected.classes_)
    np.testing.assert_allclose(actual.coef_, expected.coef_, rtol=1e-10, atol=1e-12)
    np.testing.assert_allclose(actual.intercept_, expected.intercept_, rtol=1e-10, atol=1e-12)
    np.testing.assert_array_equal(actual.predict(X_test), expected.predict(X_test))

    result = subprocess.run(
        ["python3", "predict.py", "test_scaled.csv"],
        cwd=WORKSPACE_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"predict.py could not use model.pkl: {result.stderr}"


def _read_reported_average():
    path = os.path.join(WORKSPACE_DIR, "avg_time.txt")
    assert os.path.isfile(path), "benchmark.sh did not create avg_time.txt."
    content = open(path, "r").read().strip()
    match = re.fullmatch(r"Average Inference Time: ([0-9]+(?:\.[0-9]+)?) ms", content)
    assert match, f"Invalid benchmark output: {content!r}"
    value = float(match.group(1))
    assert np.isfinite(value) and value >= 0
    return value


def test_benchmark_executes_prediction_50_times_sequentially_and_times_it():
    benchmark = os.path.join(WORKSPACE_DIR, "benchmark.sh")
    predict_path = os.path.join(WORKSPACE_DIR, "predict.py")
    backup_path = os.path.join(WORKSPACE_DIR, ".predict.py.verifier-backup")
    token = secrets.token_hex(8)
    log_path = f"/tmp/benchmark_calls_{token}.log"
    lock_path = f"/tmp/benchmark_lock_{token}"
    config_path = f"/tmp/benchmark_delay_{token}"

    probe = f'''import os
import sys
import time

log_path = {log_path!r}
lock_path = {lock_path!r}
config_path = {config_path!r}

with open(log_path, "a") as log:
    log.write("CALL\\n")

valid = len(sys.argv) == 2 and os.path.basename(sys.argv[0]) == "predict.py" and os.path.basename(sys.argv[1]) == "test_scaled.csv"
if not valid:
    with open(log_path, "a") as log:
        log.write("BAD_ARGUMENTS\\n")

owned = False
try:
    fd = os.open(lock_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    os.close(fd)
    owned = True
except FileExistsError:
    with open(log_path, "a") as log:
        log.write("OVERLAP\\n")

try:
    with open(config_path, "r") as f:
        delay = float(f.read().strip())
    time.sleep(delay)
finally:
    if owned:
        os.unlink(lock_path)

if not valid:
    sys.exit(2)
'''

    os.replace(predict_path, backup_path)
    try:
        with open(predict_path, "w") as f:
            f.write(probe)

        reported_values = []
        expected_values = []
        rng = secrets.SystemRandom()
        delays = [rng.uniform(0.006, 0.014), rng.uniform(0.055, 0.075)]

        for delay in delays:
            for path in (log_path, lock_path, os.path.join(WORKSPACE_DIR, "avg_time.txt")):
                try:
                    os.unlink(path)
                except FileNotFoundError:
                    pass
            with open(config_path, "w") as f:
                f.write(str(delay))

            started = time.perf_counter()
            result = subprocess.run(
                ["bash", benchmark],
                cwd=WORKSPACE_DIR,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
            )
            elapsed = time.perf_counter() - started

            assert result.returncode == 0, f"benchmark.sh failed: {result.stderr}"
            assert os.path.isfile(log_path), "benchmark.sh never invoked predict.py."
            with open(log_path, "r") as f:
                events = [line.strip() for line in f if line.strip()]

            assert events.count("CALL") == 50, f"benchmark.sh invoked predict.py {events.count('CALL')} times, expected 50."
            assert "BAD_ARGUMENTS" not in events, "benchmark.sh did not invoke predict.py with test_scaled.csv."
            assert "OVERLAP" not in events, "Prediction runs overlapped; they must run sequentially."

            reported = _read_reported_average()
            expected = elapsed * 1000.0 / 50.0
            tolerance = max(12.0, expected * 0.20)
            assert abs(reported - expected) <= tolerance, (
                f"Reported average {reported:.3f} ms is inconsistent with measured "
                f"average {expected:.3f} ms."
            )
            reported_values.append(reported)
            expected_values.append(expected)

        assert reported_values[1] > reported_values[0] + 20.0, (
            "avg_time.txt did not respond to a substantial change in actual prediction runtime."
        )
    finally:
        try:
            os.unlink(predict_path)
        except FileNotFoundError:
            pass
        os.replace(backup_path, predict_path)
        for path in (log_path, lock_path, config_path):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
