#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import subprocess
import math

SCRIPT_PATH = "/home/user/prepare_and_train.py"
RESULTS_PATH = "/home/user/model_results.json"

def test_script_exists():
    """Test that the required Python script exists."""
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} was not found."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."


def test_script_executes_and_creates_results():
    """Execute the submitted script and require it to regenerate the output."""
    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)

    proc = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert proc.returncode == 0, (
        f"prepare_and_train.py failed with exit code {proc.returncode}.\n"
        f"stdout:\n{proc.stdout}\n"
        f"stderr:\n{proc.stderr}"
    )
    assert os.path.isfile(RESULTS_PATH), (
        "Running prepare_and_train.py did not create model_results.json."
    )


def test_model_results():
    """Test that the model results JSON exists and contains the correct values."""
    results_path = "/home/user/model_results.json"
    assert os.path.exists(results_path), f"The output file {results_path} was not found."

    with open(results_path, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            assert False, "The file model_results.json is not valid JSON."

    assert "num_features" in results, "Key 'num_features' missing in JSON."
    assert "f1_score" in results, "Key 'f1_score' missing in JSON."

    assert results["num_features"] == 5, f"Expected num_features to be 5, got {results['num_features']}"

    # Compute expected F1 score by running a subprocess, since tests are restricted to stdlib
    script = """
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import f1_score

df = pd.read_csv('/home/user/data/sensors.csv')
df['temp_pressure_interaction'] = df['temp'] * df['pressure']
df['high_humidity'] = (df['humidity'] > 80.0).astype(int)

X = df[['temp', 'pressure', 'humidity', 'temp_pressure_interaction', 'high_humidity']]
y = df['target']

X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

clf = LogisticRegression(random_state=42)
clf.fit(X_train, y_train)
y_pred = clf.predict(X_test)
print(f1_score(y_test, y_pred))
"""
    try:
        proc = subprocess.run(['python3', '-c', script], capture_output=True, text=True, check=True)
        expected_f1 = float(proc.stdout.strip())
    except Exception as e:
        assert False, f"Failed to compute expected F1 score in test environment: {e}"

    actual_f1 = results["f1_score"]
    assert isinstance(actual_f1, float), f"Expected f1_score to be a float, got {type(actual_f1)}"

    assert math.isclose(actual_f1, expected_f1, rel_tol=1e-4), f"Expected f1_score to be close to {expected_f1}, got {actual_f1}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
