#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'RUNNER_EOF' > /tmp/run_pipeline_candidate.py
import json
import os
import runpy
import sys
import traceback

import numpy as np
from sklearn.linear_model import Ridge
from sklearn.model_selection import GridSearchCV, KFold

candidate = os.path.abspath(sys.argv[1])
event_path = sys.argv[2]
original_fit = GridSearchCV.fit
events = {
    "gridsearch_fit_called": False,
    "gridsearch_fit_completed": False,
    "valid_estimator": False,
    "valid_param_grid": False,
    "valid_scoring": False,
    "valid_cv": False,
    "divide_mode": None,
}

def checked_fit(self, X, y=None, **params):
    events["gridsearch_fit_called"] = True
    events["valid_estimator"] = isinstance(self.estimator, Ridge)

    grids = self.param_grid if isinstance(self.param_grid, list) else [self.param_grid]
    try:
        events["valid_param_grid"] = (
            bool(grids)
            and all(isinstance(grid, dict) and set(grid) == {"alpha"} for grid in grids)
            and sorted({float(value) for grid in grids for value in grid["alpha"]})
                == [0.1, 1.0, 10.0, 100.0]
        )
    except Exception:
        events["valid_param_grid"] = False

    events["valid_scoring"] = self.scoring == "neg_mean_squared_error"
    events["valid_cv"] = (
        isinstance(self.cv, KFold)
        and self.cv.n_splits == 5
        and self.cv.shuffle is False
    )

    result = original_fit(self, X, y, **params)
    events["gridsearch_fit_completed"] = True
    return result

GridSearchCV.fit = checked_fit
exit_code = 0
try:
    os.chdir("/home/user")
    sys.path.insert(0, os.path.dirname(candidate))
    runpy.run_path(candidate, run_name="__main__")
except SystemExit as exc:
    if exc.code not in (None, 0):
        exit_code = 1
except BaseException:
    traceback.print_exc()
    exit_code = 1
finally:
    events["divide_mode"] = np.geterr().get("divide")
    try:
        with open(event_path, "w") as f:
            json.dump(events, f)
    except Exception:
        exit_code = 1

sys.exit(exit_code)
RUNNER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import itertools
import json
import math
import os
import subprocess

import numpy as np
import pandas as pd
import pytest
from sklearn.linear_model import Ridge
from sklearn.model_selection import GridSearchCV, KFold

RESULT_PATH = "/home/user/pipeline_results.json"
EXPECTED_FEATURES = ["sensor_A", "sensor_B", "sensor_B_roll3", "sensor_D", "sensor_E"]
VALID_ALPHAS = [0.1, 1.0, 10.0, 100.0]


def independently_compute_expected():
    sensors = pd.read_csv("/home/user/sensor_readings.csv")
    targets = pd.read_csv("/home/user/target_values.csv")
    merged = sensors.merge(targets, on="timestamp", how="inner")
    merged = merged.sort_values("timestamp").reset_index(drop=True)
    merged["sensor_A_roll3"] = merged["sensor_A"].rolling(window=3, min_periods=1).mean()
    merged["sensor_B_roll3"] = merged["sensor_B"].rolling(window=3, min_periods=1).mean()
    merged = merged.dropna()

    feature_names = [
        "sensor_A", "sensor_B", "sensor_C", "sensor_D", "sensor_E",
        "sensor_A_roll3", "sensor_B_roll3",
    ]
    correlations = merged[feature_names].corr(method="pearson")
    dropped = set()
    for first, second in itertools.combinations(feature_names, 2):
        if abs(correlations.loc[first, second]) > 0.85:
            dropped.add(max(first, second))
    selected = sorted(name for name in feature_names if name not in dropped)

    search = GridSearchCV(
        Ridge(),
        {"alpha": VALID_ALPHAS},
        scoring="neg_mean_squared_error",
        cv=KFold(n_splits=5, shuffle=False),
    )
    search.fit(merged[selected], merged["target_value"])
    return {
        "selected_features": selected,
        "best_alpha": float(search.best_params_["alpha"]),
        "best_cv_mse": round(float(-search.best_score_), 5),
    }


EXPECTED = independently_compute_expected()


def candidate_output_is_correct(data):
    return (
        isinstance(data, dict)
        and set(data.keys()) == {"selected_features", "best_alpha", "best_cv_mse"}
        and data.get("selected_features") == EXPECTED["selected_features"]
        and data.get("best_alpha") == EXPECTED["best_alpha"]
        and type(data.get("best_cv_mse")) is float
        and math.isfinite(data["best_cv_mse"])
        and data["best_cv_mse"] == EXPECTED["best_cv_mse"]
    )


@pytest.fixture(scope="session", autouse=True)
def execute_submitted_pipeline():
    candidates = []
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d not in {"__pycache__", ".cache", ".local"}]
        for name in files:
            if name.endswith(".py"):
                candidates.append(os.path.join(root, name))

    assert candidates, "No Python pipeline script was found under /home/user."

    failures = []
    for index, candidate in enumerate(sorted(candidates)):
        if os.path.exists(RESULT_PATH):
            os.remove(RESULT_PATH)
        event_path = f"/tmp/pipeline_events_{index}.json"
        if os.path.exists(event_path):
            os.remove(event_path)

        completed = subprocess.run(
            ["python3", "/tmp/run_pipeline_candidate.py", candidate, event_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=120,
        )
        if completed.returncode != 0 or not os.path.isfile(event_path) or not os.path.isfile(RESULT_PATH):
            failures.append(f"{candidate}: did not execute successfully and generate the result")
            continue

        try:
            with open(event_path) as f:
                events = json.load(f)
            with open(RESULT_PATH) as f:
                data = json.load(f)
        except Exception as exc:
            failures.append(f"{candidate}: invalid execution evidence or JSON ({exc})")
            continue

        required_events = (
            events.get("gridsearch_fit_called") is True
            and events.get("gridsearch_fit_completed") is True
            and events.get("valid_estimator") is True
            and events.get("valid_param_grid") is True
            and events.get("valid_scoring") is True
            and events.get("valid_cv") is True
            and events.get("divide_mode") == "raise"
        )
        if required_events and candidate_output_is_correct(data):
            return
        failures.append(f"{candidate}: pipeline behavior or computed output was incorrect")

    pytest.fail("No submitted Python script performed the required pipeline. " + "; ".join(failures))


def test_pipeline_results_json_exists():
    """Check if the pipeline_results.json file was generated."""
    assert os.path.isfile(RESULT_PATH), f"Expected results file not found at {RESULT_PATH}"


def test_pipeline_results_content():
    """Validate the structure and content of the JSON results."""
    with open(RESULT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {RESULT_PATH} is not valid JSON."

    required_keys = {"selected_features", "best_alpha", "best_cv_mse"}
    assert required_keys.issubset(data.keys()), f"JSON missing required keys. Found: {list(data.keys())}"
    assert set(data.keys()) == required_keys, f"JSON must contain exactly {sorted(required_keys)}"

    expected_features = ["sensor_A", "sensor_B", "sensor_B_roll3", "sensor_D", "sensor_E"]
    actual_features = data["selected_features"]
    assert isinstance(actual_features, list), "'selected_features' must be a list."
    assert actual_features == expected_features, (
        f"Expected selected_features to be exactly {expected_features} (alphabetical order), "
        f"but got {actual_features}."
    )
    assert actual_features == EXPECTED["selected_features"]

    best_alpha = data["best_alpha"]
    assert best_alpha in VALID_ALPHAS, f"'best_alpha' must be one of {VALID_ALPHAS}, got {best_alpha}"
    assert best_alpha == EXPECTED["best_alpha"], (
        f"Expected GridSearchCV best alpha {EXPECTED['best_alpha']}, got {best_alpha}"
    )

    best_cv_mse = data["best_cv_mse"]
    assert isinstance(best_cv_mse, float), f"'best_cv_mse' must be a float, got {type(best_cv_mse).__name__}"
    assert best_cv_mse > 0, f"'best_cv_mse' should be a positive mean squared error, got {best_cv_mse}"
    assert math.isfinite(best_cv_mse)
    assert best_cv_mse == EXPECTED["best_cv_mse"], (
        f"Expected rounded cross-validation MSE {EXPECTED['best_cv_mse']}, got {best_cv_mse}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
