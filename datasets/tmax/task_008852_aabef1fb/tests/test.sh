#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import subprocess
import sys

import numpy as np
import pandas as pd
from sklearn.linear_model import LinearRegression
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import MinMaxScaler

EXPERIMENT = "/home/user/experiment"


def read_predictions(path, expected_count):
    with open(path, "r") as f:
        lines = f.read().strip().split("\n")
    assert len(lines) == expected_count, f"{path} should have exactly {expected_count} rows"
    values = []
    for line in lines:
        assert "," not in line, f"{path} must contain one prediction per line with no header"
        value = float(line.strip())
        assert math.isfinite(value), f"Non-finite prediction in {path}"
        values.append(value)
    return np.asarray(values)


def expected_fixed_predictions(data_file):
    df = pd.read_csv(data_file)
    X = df[["feature1", "feature2"]]
    y = df["target"]
    X_train, X_test, y_train, _ = train_test_split(
        X, y, test_size=0.2, shuffle=False
    )
    scaler = MinMaxScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled = scaler.transform(X_test)
    model = LinearRegression()
    model.fit(X_train_scaled, y_train)
    return model.predict(X_test_scaled)


def expected_leaky_predictions(data_file):
    df = pd.read_csv(data_file)
    X = df[["feature1", "feature2"]]
    y = df["target"]
    scaler = MinMaxScaler()
    X_scaled = scaler.fit_transform(X)
    X_train, X_test, y_train, _ = train_test_split(
        X_scaled, y, test_size=0.2, shuffle=False
    )
    model = LinearRegression()
    model.fit(X_train, y_train)
    return model.predict(X_test)


def run_required_scripts():
    for output in ("fixed_predictions.csv", "metrics.txt"):
        path = os.path.join(EXPERIMENT, output)
        if os.path.exists(path):
            os.remove(path)
    subprocess.run(
        [sys.executable, os.path.join(EXPERIMENT, "fixed_train.py")],
        cwd=EXPERIMENT, check=True, timeout=60
    )
    assert os.path.isfile(os.path.join(EXPERIMENT, "fixed_predictions.csv")), (
        "fixed_train.py did not generate fixed_predictions.csv"
    )
    subprocess.run(
        ["bash", os.path.join(EXPERIMENT, "compare.sh")],
        cwd=EXPERIMENT, check=True, timeout=60
    )
    assert os.path.isfile(os.path.join(EXPERIMENT, "metrics.txt")), (
        "compare.sh did not generate metrics.txt"
    )


def test_fixed_scripts_and_outputs_exist():
    """Check that the required files have been created."""
    fixed_train = os.path.join(EXPERIMENT, "fixed_train.py")
    assert os.path.isfile(fixed_train), f"Missing {fixed_train}"

    fixed_preds = os.path.join(EXPERIMENT, "fixed_predictions.csv")
    assert os.path.isfile(fixed_preds), f"Missing {fixed_preds}"

    compare_sh = os.path.join(EXPERIMENT, "compare.sh")
    assert os.path.isfile(compare_sh), f"Missing {compare_sh}"

    metrics_txt = os.path.join(EXPERIMENT, "metrics.txt")
    assert os.path.isfile(metrics_txt), f"Missing {metrics_txt}"


def test_execute_scripts_and_predictions_and_metrics_correctness():
    """Execute both artifacts, independently verify predictions, and verify metrics.txt."""
    data_file = os.path.join(EXPERIMENT, "data.csv")
    leaky_preds_file = os.path.join(EXPERIMENT, "leaky_predictions.csv")
    fixed_preds_file = os.path.join(EXPERIMENT, "fixed_predictions.csv")
    metrics_txt = os.path.join(EXPERIMENT, "metrics.txt")

    run_required_scripts()

    with open(data_file, "r") as f:
        lines = f.read().strip().split("\n")
    data_lines = lines[1:]
    assert len(data_lines) == 100, "data.csv should have exactly 100 data rows"
    test_targets = np.asarray([float(line.split(",")[2]) for line in data_lines[-20:]])

    leaky_preds = read_predictions(leaky_preds_file, 20)
    fixed_preds = read_predictions(fixed_preds_file, 20)

    oracle_leaky = expected_leaky_predictions(data_file)
    oracle_fixed = expected_fixed_predictions(data_file)
    assert np.allclose(leaky_preds, oracle_leaky, rtol=1e-7, atol=1e-5), (
        "leaky_predictions.csv does not match the original leaky pipeline"
    )
    assert np.allclose(fixed_preds, oracle_fixed, rtol=1e-7, atol=1e-5), (
        "fixed_predictions.csv does not match a MinMaxScaler fitted only on training data"
    )

    leaky_mae = float(np.mean(np.abs(test_targets - leaky_preds)))
    fixed_mae = float(np.mean(np.abs(test_targets - fixed_preds)))
    expected_leaky_str = f"Leaky MAE: {leaky_mae:.2f}"
    expected_fixed_str = f"Fixed MAE: {fixed_mae:.2f}"

    with open(metrics_txt, "r") as f:
        metrics_content = f.read().strip().split("\n")
    assert len(metrics_content) >= 2, "metrics.txt must contain at least two lines"
    assert metrics_content[0].strip() == expected_leaky_str, (
        f"First line of metrics.txt is incorrect. Expected '{expected_leaky_str}', "
        f"got '{metrics_content[0].strip()}'"
    )
    assert metrics_content[1].strip() == expected_fixed_str, (
        f"Second line of metrics.txt is incorrect. Expected '{expected_fixed_str}', "
        f"got '{metrics_content[1].strip()}'"
    )


def test_compare_sh_no_python():
    """Ensure compare.sh does not use Python."""
    compare_sh = os.path.join(EXPERIMENT, "compare.sh")
    with open(compare_sh, "r") as f:
        content = f.read()
    assert "python" not in content.lower(), "compare.sh must not use Python to calculate MAE"


def test_pipeline_on_unseen_data_and_instrumented_training(tmp_path):
    """Use unseen inputs and confirm fitting occurs only after the required split."""
    data_path = os.path.join(EXPERIMENT, "data.csv")
    leaky_path = os.path.join(EXPERIMENT, "leaky_predictions.csv")
    original_data = open(data_path, "rb").read()
    original_leaky = open(leaky_path, "rb").read()

    rng = np.random.default_rng(731946)
    f1 = rng.normal(3.0, 4.0, 100)
    f2 = rng.normal(-2.0, 1.5, 100)
    target = 1.7 * f1 - 4.2 * f2 + rng.normal(0, 0.3, 100)
    f1[93] = 750.0
    probe = pd.DataFrame({"feature1": f1, "feature2": f2, "target": target})

    runner = tmp_path / "instrument_runner.py"
    events_path = tmp_path / "events.json"
    runner.write_text(r'''
import json
import os
import runpy
import sklearn.model_selection as ms
from sklearn.preprocessing import MinMaxScaler
from sklearn.linear_model import LinearRegression

events = {"split": [], "scaler_fit": [], "model_fit": []}
orig_split = ms.train_test_split
orig_scaler_fit = MinMaxScaler.fit
orig_model_fit = LinearRegression.fit

def split_wrapper(*arrays, **kwargs):
    events["split"].append({
        "test_size": kwargs.get("test_size"),
        "shuffle": kwargs.get("shuffle", True)
    })
    return orig_split(*arrays, **kwargs)

def scaler_fit_wrapper(self, X, y=None):
    events["scaler_fit"].append(len(X))
    return orig_scaler_fit(self, X, y)

def model_fit_wrapper(self, X, y, *args, **kwargs):
    events["model_fit"].append(len(X))
    return orig_model_fit(self, X, y, *args, **kwargs)

ms.train_test_split = split_wrapper
MinMaxScaler.fit = scaler_fit_wrapper
LinearRegression.fit = model_fit_wrapper
try:
    runpy.run_path(os.environ["FIXED_SCRIPT"], run_name="__main__")
finally:
    with open(os.environ["EVENTS_PATH"], "w") as f:
        json.dump(events, f)
''')

    try:
        probe.to_csv(data_path, index=False)
        probe_leaky = expected_leaky_predictions(data_path)
        np.savetxt(leaky_path, probe_leaky, fmt="%.10f")
        for output in ("fixed_predictions.csv", "metrics.txt"):
            path = os.path.join(EXPERIMENT, output)
            if os.path.exists(path):
                os.remove(path)

        env = os.environ.copy()
        env["FIXED_SCRIPT"] = os.path.join(EXPERIMENT, "fixed_train.py")
        env["EVENTS_PATH"] = str(events_path)
        subprocess.run(
            [sys.executable, str(runner)], cwd=EXPERIMENT, env=env,
            check=True, timeout=60
        )

        expected = expected_fixed_predictions(data_path)
        actual = read_predictions(os.path.join(EXPERIMENT, "fixed_predictions.csv"), 20)
        assert np.allclose(actual, expected, rtol=1e-7, atol=1e-5), (
            "fixed_train.py produced incorrect predictions on unseen data"
        )

        events = json.loads(events_path.read_text())
        assert events["split"], "fixed_train.py must use train_test_split"
        assert any(e["test_size"] == 0.2 and e["shuffle"] is False for e in events["split"]), (
            "train_test_split must use test_size=0.2 and shuffle=False"
        )
        assert events["scaler_fit"], "fixed_train.py must fit MinMaxScaler"
        assert all(n == 80 for n in events["scaler_fit"]), (
            "MinMaxScaler must only be fitted on the 80 training rows"
        )
        assert events["model_fit"], "fixed_train.py must fit LinearRegression"
        assert all(n == 80 for n in events["model_fit"]), (
            "LinearRegression must be fitted on the 80 training rows"
        )

        subprocess.run(
            ["bash", os.path.join(EXPERIMENT, "compare.sh")],
            cwd=EXPERIMENT, check=True, timeout=60
        )
        targets = probe["target"].to_numpy()[-20:]
        leaky_mae = float(np.mean(np.abs(targets - probe_leaky)))
        fixed_mae = float(np.mean(np.abs(targets - actual)))
        expected_metrics = [f"Leaky MAE: {leaky_mae:.2f}", f"Fixed MAE: {fixed_mae:.2f}"]
        with open(os.path.join(EXPERIMENT, "metrics.txt"), "r") as f:
            actual_metrics = [line.strip() for line in f.read().strip().split("\n")]
        assert actual_metrics[:2] == expected_metrics, (
            "compare.sh did not calculate metrics from the supplied unseen input files"
        )
    finally:
        with open(data_path, "wb") as f:
            f.write(original_data)
        with open(leaky_path, "wb") as f:
            f.write(original_leaky)
        run_required_scripts()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
