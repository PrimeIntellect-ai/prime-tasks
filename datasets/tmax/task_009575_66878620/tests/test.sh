#!/bin/bash
set -u
mkdir -p /logs/verifier

SCRIPT_PATH=/home/user/process_and_train.py
RESULTS_PATH=/home/user/results.json
BACKUP_DIR=$(mktemp -d)
ok=1

cat > /tmp/compute_expected.py <<'PY_EOF'
import json
import sys
import pandas as pd
from sklearn.utils import resample
from sklearn.feature_selection import SelectKBest, f_classif
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import GridSearchCV

data_dir, output_path = sys.argv[1:3]
frames = [pd.read_csv(f"{data_dir}/server_{i}.csv") for i in (1, 2, 3)]
data = pd.concat(frames, ignore_index=True)
data["cpu_mem_ratio"] = data["cpu_usage"] / data["memory_usage"]

X = data.drop(columns=["crash"])
y = data["crash"]
X_majority = X[y == 0]
y_majority = y[y == 0]
X_minority = X[y == 1]
y_minority = y[y == 1]
X_minority_up, y_minority_up = resample(
    X_minority,
    y_minority,
    replace=True,
    n_samples=len(X_majority),
    random_state=42,
)
X_balanced = pd.concat([X_majority, X_minority_up], ignore_index=True)
y_balanced = pd.concat([y_majority, y_minority_up], ignore_index=True)

selector = SelectKBest(score_func=f_classif, k=3)
X_selected = selector.fit_transform(X_balanced, y_balanced)
selected_features = sorted(X.columns[selector.get_support()].tolist())

search = GridSearchCV(
    RandomForestClassifier(random_state=42),
    {"max_depth": [3, 5, None], "n_estimators": [10, 50]},
    cv=3,
)
search.fit(X_selected, y_balanced)

expected = {
    "selected_features": selected_features,
    "best_max_depth": search.best_params_["max_depth"],
    "best_n_estimators": search.best_params_["n_estimators"],
    "best_cv_score": round(float(search.best_score_), 4),
}
with open(output_path, "w") as f:
    json.dump(expected, f)
PY_EOF

cp /home/user/data/server_1.csv /home/user/data/server_2.csv /home/user/data/server_3.csv "$BACKUP_DIR"/
restore_data() {
    cp "$BACKUP_DIR"/server_1.csv "$BACKUP_DIR"/server_2.csv "$BACKUP_DIR"/server_3.csv /home/user/data/ 2>/dev/null || true
}
trap restore_data EXIT

# Derive the required answer for the supplied telemetry before executing the submission.
if ! python3 /tmp/compute_expected.py /home/user/data /tmp/expected_original.json; then
    ok=0
fi

# Exercise the script on a second valid dataset so a hard-coded results file cannot pass.
python3 - <<'PY_EOF'
import numpy as np
import pandas as pd

rng = np.random.default_rng(2025)
for server, n in ((1, 120), (2, 135), (3, 105)):
    crash = np.zeros(n, dtype=int)
    crash[rng.choice(n, size=max(12, n // 5), replace=False)] = 1
    df = pd.DataFrame({
        "cpu_usage": 28 + 38 * crash + rng.normal(0, 5, n),
        "memory_usage": 70 - 24 * crash + rng.normal(0, 6, n),
        "disk_io": 95 + 30 * crash + rng.normal(0, 12, n),
        "network_in": rng.exponential(42, n),
        "network_out": rng.exponential(55, n),
        "crash": crash,
    })
    df.to_csv(f"/home/user/data/server_{server}.csv", index=False)
PY_EOF

if ! python3 /tmp/compute_expected.py /home/user/data /tmp/expected_alternate.json; then
    ok=0
fi
rm -f "$RESULTS_PATH" /tmp/actual_alternate.json
if [ -f "$SCRIPT_PATH" ] && timeout 240s python3 "$SCRIPT_PATH"; then
    if [ -f "$RESULTS_PATH" ]; then
        cp "$RESULTS_PATH" /tmp/actual_alternate.json
    else
        ok=0
    fi
else
    ok=0
fi

# Restore the supplied data and require the final artifact to be produced from it.
restore_data
rm -f "$RESULTS_PATH"
if [ -f "$SCRIPT_PATH" ] && timeout 240s python3 "$SCRIPT_PATH"; then
    [ -f "$RESULTS_PATH" ] || ok=0
else
    ok=0
fi

cat > /tmp/test_final_state.py <<'TEST_EOF'
import json
import os
import pytest

RESULTS_PATH = '/home/user/results.json'
SCRIPT_PATH = '/home/user/process_and_train.py'


def load_json(path):
    with open(path, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {path} does not contain valid JSON.")


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."


def test_results_file_exists():
    assert os.path.isfile(RESULTS_PATH), f"The results file {RESULTS_PATH} does not exist."


def test_results_format_and_types():
    results = load_json(RESULTS_PATH)
    expected_keys = {
        "selected_features",
        "best_max_depth",
        "best_n_estimators",
        "best_cv_score"
    }
    actual_keys = set(results.keys())
    assert actual_keys == expected_keys, f"Expected keys {expected_keys}, but got {actual_keys}."

    assert isinstance(results["selected_features"], list), "selected_features must be a list."
    assert len(results["selected_features"]) == 3, "selected_features must contain exactly 3 features."
    assert results["selected_features"] == sorted(results["selected_features"]), "selected_features must be sorted alphabetically."

    valid_features = {
        "cpu_usage", "memory_usage", "disk_io",
        "network_in", "network_out", "cpu_mem_ratio"
    }
    for feature in results["selected_features"]:
        assert feature in valid_features, f"Unknown feature '{feature}' in selected_features."

    assert results["best_max_depth"] in [3, 5, None], "best_max_depth must be 3, 5, or null."
    assert results["best_n_estimators"] in [10, 50], "best_n_estimators must be 10 or 50."
    assert isinstance(results["best_cv_score"], (int, float)), "best_cv_score must be a number."

    score_str = str(results["best_cv_score"])
    if '.' in score_str:
        decimals = len(score_str.split('.')[1])
        assert decimals <= 4, f"best_cv_score must be rounded to 4 decimal places, got {decimals} decimal places."


def test_results_match_pipeline_on_supplied_data():
    actual = load_json(RESULTS_PATH)
    expected = load_json('/tmp/expected_original.json')
    assert actual == expected, f"Reported results do not match the required pipeline: expected {expected}, got {actual}."


def test_script_generalizes_to_exercised_data():
    assert os.path.isfile('/tmp/actual_alternate.json'), "The script did not create results.json on the alternate telemetry data."
    actual = load_json('/tmp/actual_alternate.json')
    expected = load_json('/tmp/expected_alternate.json')
    assert actual == expected, f"The script's alternate-data results are incorrect: expected {expected}, got {actual}."
TEST_EOF

if [ "$ok" -eq 1 ] && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

rm -rf "$BACKUP_DIR"
trap - EXIT
