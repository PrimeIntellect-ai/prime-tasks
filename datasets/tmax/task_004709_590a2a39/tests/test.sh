#!/bin/bash
set -u
mkdir -p /logs/verifier

EDGE=/home/user/edge_ml
status=0

# The requested artifacts must be executable shell/Awk scripts.
for script in 1_clean.sh 2_predict.sh 3_evaluate.sh; do
    path="$EDGE/$script"
    if [ ! -f "$path" ] || [ ! -x "$path" ]; then
        echo "Missing or non-executable script: $path" >&2
        status=1
        continue
    fi
    first_line=$(head -n 1 "$path" 2>/dev/null || true)
    if ! printf '%s\n' "$first_line" | grep -Eq '^#![[:space:]]*(/(usr/)?bin/(ba)?sh|/bin/dash|/usr/bin/awk)([[:space:]]|$)|^#![[:space:]]*/usr/bin/env[[:space:]]+(-S[[:space:]]+)?(bash|sh|dash|awk)([[:space:]]|$)'; then
        echo "Not a Bash/POSIX-shell/Awk script: $path" >&2
        status=1
    fi
done

# Remove any precomputed artifacts and execute the submitted pipeline on the
# original fixture before applying the original assertions.
if [ "$status" -eq 0 ]; then
    rm -f "$EDGE/clean_data.csv" "$EDGE/predictions.csv" "$EDGE/covariance.txt"
    for script in 1_clean.sh 2_predict.sh 3_evaluate.sh; do
        if ! (cd "$EDGE" && timeout 10s "$EDGE/$script"); then
            echo "Script failed: $script" >&2
            status=1
            break
        fi
    done
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv

EDGE_ML_DIR = "/home/user/edge_ml"
RAW_DATA_PATH = os.path.join(EDGE_ML_DIR, "raw_data.csv")
CLEAN_DATA_PATH = os.path.join(EDGE_ML_DIR, "clean_data.csv")
MODEL_WEIGHTS_PATH = os.path.join(EDGE_ML_DIR, "model_weights.txt")
PREDICTIONS_PATH = os.path.join(EDGE_ML_DIR, "predictions.csv")
COVARIANCE_PATH = os.path.join(EDGE_ML_DIR, "covariance.txt")

def is_float(value):
    try:
        float(value)
        if value.lower() in ['nan', 'inf', '-inf', 'infinity', '-infinity']:
            return False
        return True
    except ValueError:
        return False

def is_int(value):
    try:
        int(value)
        return True
    except ValueError:
        return False

def get_expected_clean_data():
    expected_rows = []
    if not os.path.exists(RAW_DATA_PATH):
        return expected_rows
    with open(RAW_DATA_PATH, 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row) != 7:
                continue
            if not is_int(row[0]):
                continue
            if not all(is_float(val) for val in row[1:]):
                continue
            expected_rows.append(row)
    return expected_rows

def get_expected_predictions(clean_data):
    if not os.path.exists(MODEL_WEIGHTS_PATH):
        return []
    with open(MODEL_WEIGHTS_PATH, 'r') as f:
        weights = [float(line.strip()) for line in f if line.strip()]
    if len(weights) != 6:
        return []
    b = weights[0]
    w = weights[1:]
    predictions = []
    for row in clean_data:
        row_id = row[0]
        features = [float(x) for x in row[1:6]]
        pred = b + sum(f * weight for f, weight in zip(features, w))
        predictions.append((row_id, f"{pred:.4f}"))
    return predictions

def get_expected_covariance(clean_data, predictions):
    if not clean_data or not predictions:
        return None
    n = len(clean_data)
    y_true = [float(row[6]) for row in clean_data]
    y_pred = [float(pred[1]) for pred in predictions]
    mean_true = sum(y_true) / n
    mean_pred = sum(y_pred) / n
    cov = sum((y_pred[i] - mean_pred) * (y_true[i] - mean_true) for i in range(n)) / n
    return f"{cov:.4f}"

def test_clean_data_csv():
    assert os.path.exists(CLEAN_DATA_PATH), f"File {CLEAN_DATA_PATH} does not exist."
    expected_clean_data = get_expected_clean_data()
    with open(CLEAN_DATA_PATH, 'r') as f:
        reader = csv.reader(f)
        actual_clean_data = [row for row in reader if row]
    assert len(actual_clean_data) == len(expected_clean_data), f"Expected {len(expected_clean_data)} valid rows in clean_data.csv, found {len(actual_clean_data)}."
    for actual, expected in zip(actual_clean_data, expected_clean_data):
        assert actual == expected, f"Row mismatch in clean_data.csv. Expected {expected}, got {actual}."

def test_predictions_csv():
    assert os.path.exists(PREDICTIONS_PATH), f"File {PREDICTIONS_PATH} does not exist."
    expected_clean_data = get_expected_clean_data()
    expected_predictions = get_expected_predictions(expected_clean_data)
    with open(PREDICTIONS_PATH, 'r') as f:
        reader = csv.reader(f)
        actual_predictions = [tuple(row) for row in reader if row]
    assert len(actual_predictions) == len(expected_predictions), f"Expected {len(expected_predictions)} predictions, found {len(actual_predictions)}."
    for actual, expected in zip(actual_predictions, expected_predictions):
        assert actual[0] == expected[0], f"ID mismatch in predictions.csv. Expected {expected[0]}, got {actual[0]}."
        assert float(actual[1]) == float(expected[1]), f"Prediction mismatch for ID {expected[0]}. Expected {expected[1]}, got {actual[1]}."
        assert actual[1] == expected[1], f"Prediction formatting mismatch for ID {expected[0]}. Expected exactly '{expected[1]}', got '{actual[1]}'."

def test_covariance_txt():
    assert os.path.exists(COVARIANCE_PATH), f"File {COVARIANCE_PATH} does not exist."
    expected_clean_data = get_expected_clean_data()
    expected_predictions = get_expected_predictions(expected_clean_data)
    expected_covariance = get_expected_covariance(expected_clean_data, expected_predictions)
    with open(COVARIANCE_PATH, 'r') as f:
        actual_covariance = f.read().strip()
    assert actual_covariance == expected_covariance, f"Covariance mismatch. Expected exactly '{expected_covariance}', got '{actual_covariance}'."
TEST_EOF

if [ "$status" -eq 0 ] && ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short; then
    status=1
fi

# Exercise all three scripts on unseen inputs and derive the answers independently.
cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_pipeline.py
import csv
import math
import os
import shutil
import subprocess
import tempfile

EDGE = "/home/user/edge_ml"
FILES = ["raw_data.csv", "model_weights.txt", "clean_data.csv", "predictions.csv", "covariance.txt"]
SCRIPTS = ["1_clean.sh", "2_predict.sh", "3_evaluate.sh"]

fixtures = [
    (
        """101,-2.5,0,3.0,4.25,-1.5,8.0
102,1.25,-3.5,2,-0.75,6.0,-2.25
bad,1,2,3,4,5,6
103,1,2,3,4,5
104,1,2,3,4,5,6,7
105,1,2,null,4,5,6
106,-0.5,-1.5,-2.5,-3.5,-4.5,0
""",
        """-1.25
0.75
-2
1.5
0.25
-0.5
""",
    ),
    (
        """201,10,2,-1,0.5,4,3
202,-3,1.5,2,8,-2,-4
203,0.25,-0.5,1.25,-1.5,2.5,1
204,1,2,Infinity,4,5,6
nope,1,2,3,4,5,6
205,1,2,3,4,5,6,7
""",
        """2
-0.5
1.25
0.75
-1
2
""",
    ),
]

def valid_float(value):
    try:
        number = float(value)
    except ValueError:
        return False
    return math.isfinite(number)

def valid_int(value):
    try:
        int(value)
        return True
    except ValueError:
        return False

def expected(raw_text, weight_text):
    rows = []
    for row in csv.reader(raw_text.splitlines()):
        if len(row) == 7 and valid_int(row[0]) and all(valid_float(x) for x in row[1:]):
            rows.append(row)
    values = [float(x) for x in weight_text.splitlines() if x.strip()]
    assert len(values) == 6
    preds = []
    for row in rows:
        prediction = values[0] + sum(float(row[i + 1]) * values[i + 1] for i in range(5))
        preds.append((row[0], f"{prediction:.4f}"))
    ys = [float(row[6]) for row in rows]
    ps = [float(value) for _, value in preds]
    mean_y = sum(ys) / len(ys)
    mean_p = sum(ps) / len(ps)
    covariance = sum((p - mean_p) * (y - mean_y) for p, y in zip(ps, ys)) / len(rows)
    return rows, preds, f"{covariance:.4f}"

def read_csv(path):
    with open(path, newline="") as handle:
        return [row for row in csv.reader(handle) if row]

backup = tempfile.mkdtemp(prefix="edge_ml_verify_")
existing = {}
try:
    for name in FILES:
        src = os.path.join(EDGE, name)
        existing[name] = os.path.exists(src)
        if existing[name]:
            shutil.copy2(src, os.path.join(backup, name))

    for raw_text, weight_text in fixtures:
        with open(os.path.join(EDGE, "raw_data.csv"), "w") as handle:
            handle.write(raw_text)
        with open(os.path.join(EDGE, "model_weights.txt"), "w") as handle:
            handle.write(weight_text)
        for name in ("clean_data.csv", "predictions.csv", "covariance.txt"):
            try:
                os.remove(os.path.join(EDGE, name))
            except FileNotFoundError:
                pass

        for script in SCRIPTS:
            subprocess.run([os.path.join(EDGE, script)], cwd=EDGE, check=True, timeout=10)

        expected_rows, expected_preds, expected_cov = expected(raw_text, weight_text)
        actual_rows = read_csv(os.path.join(EDGE, "clean_data.csv"))
        assert actual_rows == expected_rows, f"dynamic clean_data mismatch: {actual_rows!r} != {expected_rows!r}"

        actual_preds = [tuple(row) for row in read_csv(os.path.join(EDGE, "predictions.csv"))]
        assert actual_preds == expected_preds, f"dynamic predictions mismatch: {actual_preds!r} != {expected_preds!r}"

        with open(os.path.join(EDGE, "covariance.txt")) as handle:
            actual_cov = handle.read().strip()
        assert actual_cov == expected_cov, f"dynamic covariance mismatch: {actual_cov!r} != {expected_cov!r}"
finally:
    for name in FILES:
        destination = os.path.join(EDGE, name)
        if existing.get(name):
            shutil.copy2(os.path.join(backup, name), destination)
        else:
            try:
                os.remove(destination)
            except FileNotFoundError:
                pass
    shutil.rmtree(backup)
DYNAMIC_EOF

if [ "$status" -eq 0 ] && ! python3 /tmp/test_dynamic_pipeline.py; then
    status=1
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
