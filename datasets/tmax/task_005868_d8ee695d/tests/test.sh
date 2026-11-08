#!/bin/bash
set -e
mkdir -p /logs/verifier

DATA_DIR=/home/user/data
BACKUP_DIR=$(mktemp -d)
cp -a "$DATA_DIR/." "$BACKUP_DIR/"
restore_data() {
    rm -rf "$DATA_DIR"
    mkdir -p "$DATA_DIR"
    cp -a "$BACKUP_DIR/." "$DATA_DIR/"
    chmod -R 777 /home/user
    rm -rf "$BACKUP_DIR"
}
trap restore_data EXIT

cat > "$DATA_DIR/sensors.csv" <<'EOF'
machine_id,temp,vibration
11,0.2,0.12
2,1.1,0.85
17,-0.7,0.22
4,1.8,0.91
23,-1.3,0.05
6,0.6,0.44
31,-0.2,0.31
8,2.2,0.97
19,-1.8,0.08
10,1.4,0.73
27,0.0,0.39
14,-0.9,0.18
35,1.0,0.66
EOF

cat > "$DATA_DIR/maintenance.csv" <<'EOF'
machine_id,days_since_last_service
11,9
17,4
4,101
6,37
8,188
19,13
14,62
35,21
EOF

cat > "$DATA_DIR/labels.csv" <<'EOF'
machine_id,failed
11,0
2,1
17,0
4,1
23,0
6,0
31,0
8,1
19,0
10,1
27,0
14,0
35,1
EOF
chmod -R 777 /home/user

rm -rf /home/user/output
rm -f /tmp/pipeline_audit.jsonl /tmp/pipeline_elapsed.txt
mkdir -p /tmp/verifier_hook
touch /tmp/pipeline_audit.jsonl
chmod 666 /tmp/pipeline_audit.jsonl

cat > /tmp/verifier_hook/sitecustomize.py <<'PYEOF'
import json
import time
import sklearn.linear_model as _linear_model

_LogisticRegression = _linear_model.LogisticRegression
_original_fit = _LogisticRegression.fit
_original_predict = _LogisticRegression.predict

def _write(event):
    with open('/tmp/pipeline_audit.jsonl', 'a', encoding='utf-8') as f:
        f.write(json.dumps(event) + '\n')

def _fit(self, X, y, *args, **kwargs):
    defaults = _LogisticRegression().get_params(deep=False)
    _write({
        'event': 'fit',
        'rows': int(getattr(X, 'shape', [0, 0])[0]),
        'cols': int(getattr(X, 'shape', [0, 0])[1]),
        'default_parameters': self.get_params(deep=False) == defaults,
    })
    return _original_fit(self, X, y, *args, **kwargs)

def _predict(self, X, *args, **kwargs):
    start = time.perf_counter()
    time.sleep(0.001)
    result = _original_predict(self, X, *args, **kwargs)
    elapsed = time.perf_counter() - start
    _write({
        'event': 'predict',
        'rows': int(getattr(X, 'shape', [0, 0])[0]),
        'cols': int(getattr(X, 'shape', [0, 0])[1]),
        'duration': elapsed,
    })
    return result

_LogisticRegression.fit = _fit
_LogisticRegression.predict = _predict
PYEOF

start_ns=$(date +%s%N)
run_status=0
if ! timeout 30s runuser -u user -- env PYTHONPATH=/tmp/verifier_hook python3 /home/user/pipeline.py; then
    run_status=$?
    if [ "$run_status" -eq 0 ]; then run_status=1; fi
fi
end_ns=$(date +%s%N)
python3 - "$start_ns" "$end_ns" "$run_status" > /tmp/pipeline_elapsed.txt <<'PYEOF'
import sys
print((int(sys.argv[2]) - int(sys.argv[1])) / 1e9)
print(sys.argv[3])
PYEOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import csv
import json
import math
import pandas as pd
import pytest
from pandas.testing import assert_frame_equal
from sklearn.linear_model import LogisticRegression

PIPELINE_PATH = "/home/user/pipeline.py"
JOINED_DATA_PATH = "/home/user/output/joined_data.csv"
METRICS_PATH = "/home/user/output/metrics.json"


def test_pipeline_exists_and_executed_successfully():
    assert os.path.isfile(PIPELINE_PATH), f"File {PIPELINE_PATH} does not exist."
    assert not os.path.islink(PIPELINE_PATH), "pipeline.py must be a regular Python script, not a symlink."
    assert stat.S_ISREG(os.stat(PIPELINE_PATH).st_mode)
    with open('/tmp/pipeline_elapsed.txt', encoding='utf-8') as f:
        elapsed = float(f.readline().strip())
        status = int(f.readline().strip())
    assert status == 0, "pipeline.py did not execute successfully."
    assert elapsed > 0


def test_joined_data_exists():
    """Verify that the joined_data.csv file was created."""
    assert os.path.isfile(JOINED_DATA_PATH), f"File {JOINED_DATA_PATH} does not exist."


def test_joined_data_content():
    """Verify the complete joined content and type handling."""
    assert os.path.isfile(JOINED_DATA_PATH), f"File {JOINED_DATA_PATH} does not exist."

    with open(JOINED_DATA_PATH, 'r', encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    assert len(rows) > 0, f"File {JOINED_DATA_PATH} is empty."
    expected_headers = {"machine_id", "temp", "vibration", "days_since_last_service", "failed"}
    actual_headers = set(reader.fieldnames or [])
    assert expected_headers.issubset(actual_headers), f"Missing expected columns. Found: {actual_headers}"
    assert reader.fieldnames == ["machine_id", "temp", "vibration", "days_since_last_service", "failed"]

    machine_2_row = next((row for row in rows if row["machine_id"] == "2"), None)
    assert machine_2_row is not None, "Row for machine_id=2 is missing."
    days_val = machine_2_row["days_since_last_service"]
    assert days_val == "-1", f"Expected '-1' for missing maintenance, got '{days_val}'."

    for row in rows:
        val = row["days_since_last_service"]
        assert "." not in val, f"Found float representation '{val}' in days_since_last_service, expected integer."
        int(val)

    sensors = pd.read_csv('/home/user/data/sensors.csv')
    maintenance = pd.read_csv('/home/user/data/maintenance.csv')
    labels = pd.read_csv('/home/user/data/labels.csv')
    expected = sensors.merge(maintenance, on='machine_id', how='left').merge(labels, on='machine_id', how='left')
    expected['days_since_last_service'] = expected['days_since_last_service'].fillna(-1).astype('int64')
    actual = pd.read_csv(JOINED_DATA_PATH)
    assert len(actual) == len(sensors)
    assert_frame_equal(actual, expected, check_dtype=True, check_like=False)
    assert actual['days_since_last_service'].dtype == 'int64'


def test_metrics_json_exists():
    """Verify that the metrics.json file was created."""
    assert os.path.isfile(METRICS_PATH), f"File {METRICS_PATH} does not exist."


def test_metrics_json_content():
    """Verify metrics against an independently trained default model."""
    assert os.path.isfile(METRICS_PATH), f"File {METRICS_PATH} does not exist."
    with open(METRICS_PATH, 'r', encoding='utf-8') as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {METRICS_PATH} is not valid JSON.")

    assert "accuracy" in metrics, "Key 'accuracy' missing in metrics.json."
    assert "inference_micros_per_row" in metrics, "Key 'inference_micros_per_row' missing in metrics.json."
    assert set(metrics) == {"accuracy", "inference_micros_per_row"}

    accuracy = metrics["accuracy"]
    inference_time = metrics["inference_micros_per_row"]
    assert isinstance(accuracy, float), f"Expected 'accuracy' to be a float, got {type(accuracy).__name__}."
    assert isinstance(inference_time, float), f"Expected 'inference_micros_per_row' to be a float, got {type(inference_time).__name__}."
    assert math.isfinite(accuracy) and 0.0 <= accuracy <= 1.0
    assert math.isfinite(inference_time) and inference_time > 0.0

    joined = pd.read_csv(JOINED_DATA_PATH)
    X = joined[["temp", "vibration", "days_since_last_service"]]
    y = joined["failed"]
    reference = LogisticRegression()
    reference.fit(X, y)
    expected_accuracy = float(reference.score(X, y))
    assert accuracy == pytest.approx(expected_accuracy, abs=1e-12)

    with open('/tmp/pipeline_audit.jsonl', encoding='utf-8') as f:
        events = [json.loads(line) for line in f if line.strip()]
    fits = [e for e in events if e.get('event') == 'fit']
    predicts = [e for e in events if e.get('event') == 'predict' and e.get('rows') == len(X) and e.get('cols') == 3]
    assert fits, "No LogisticRegression model was fitted."
    assert any(e['rows'] == len(X) and e['cols'] == 3 and e['default_parameters'] for e in fits), \
        "The full feature set was not fitted with default LogisticRegression parameters."
    assert len(predicts) >= 500, "model.predict() was not run on the full dataset 500 times."

    # Every audited prediction includes a known delay. A genuinely measured benchmark
    # must include at least the duration of 500 such calls.
    fastest_500 = sorted(e['duration'] for e in predicts)[:500]
    measured_floor = sum(fastest_500) * 1_000_000.0 / (500 * len(X))
    assert inference_time >= measured_floor * 0.80, "Reported inference time was not measured around the prediction loop."

    with open('/tmp/pipeline_elapsed.txt', encoding='utf-8') as f:
        total_runtime = float(f.readline().strip())
    assert inference_time <= total_runtime * 1_000_000.0 / (500 * len(X)), \
        "Reported inference time is inconsistent with the pipeline runtime."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
