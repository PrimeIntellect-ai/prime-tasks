#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import re
import shutil
import stat
import statistics
import subprocess
import time
import urllib.request

import joblib
import pandas as pd
from sklearn.metrics import mean_squared_error

SCRIPT = "/home/user/run_pipeline.sh"
DATA_API = "/app/services/data_api.py"
TRAIN_API = "/app/services/train_api.py"
UPLOAD = "/tmp/challenge_upload.csv"
GET_MARKER = "/tmp/challenge_raw_requested"
POST_MARKER = "/tmp/challenge_train_requested"


def stop_services():
    subprocess.run(
        ["pkill", "-f", "/app/services/(data_api|train_api)\\.py"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    time.sleep(0.5)


def run_pipeline():
    result = subprocess.run(
        [SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=90,
    )
    assert result.returncode == 0, f"Pipeline exited with {result.returncode}:\n{result.stdout}"


def build_challenge(path):
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    rows = []
    base_id = rng.randint(100000, 900000)

    # There are 63 non-missing ages, so their median is unambiguous and integral.
    for i in range(70):
        age = "" if i < 7 else rng.randint(18, 80)
        income = 300000 if i == 10 else rng.randint(20000, 150000)
        activity = rng.uniform(0.05, 9.95)
        numeric_age = 45 if age == "" else age
        target = 5.0 + 0.1 * numeric_age + 0.0001 * income + 2.0 * activity + rng.uniform(-1.0, 1.0)
        rows.append([str(base_id + i), str(age), str(income), f"{activity:.12f}", f"{target:.12f}"])

    valid_ages = [int(r[1]) for r in rows if r[1] != ""]
    median_age = int(statistics.median(valid_ages))

    # These rows exercise every required rejection. Their ages equal the median,
    # so transform ordering cannot change the expected imputation value.
    rows.extend([
        [str(base_id + 1000), str(median_age), "", "3.25", "17.5"],
        [str(base_id + 1001), str(median_age), "300001", "4.25", "48.0"],
        [str(base_id + 1002), str(median_age), "450000", "5.25", "61.0"],
        ["", str(median_age), "65000", "6.25", "30.0"],
        [str(base_id + 1004), str(median_age), "75000", "7.25", ""],
    ])
    rng.shuffle(rows)

    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "age", "income", "activity_score", "target"])
        writer.writerows(rows)

    expected = []
    for row in rows:
        rid, age, income, activity, target = row
        if not rid or not target or not income:
            continue
        if float(income) > 300000:
            continue
        expected.append({
            "id": rid,
            "age": float(median_age if age == "" else age),
            "income": float(income),
            "activity_score": float(activity),
            "target": float(target),
        })
    return expected


def pearson(xs, ys):
    mx = sum(xs) / len(xs)
    my = sum(ys) / len(ys)
    numerator = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    denominator = math.sqrt(sum((x - mx) ** 2 for x in xs) * sum((y - my) ** 2 for y in ys))
    return numerator / denominator


def test_00_pipeline_executes_real_etl_and_apis():
    assert os.path.isfile(SCRIPT), f"{SCRIPT} does not exist"
    assert os.stat(SCRIPT).st_mode & stat.S_IXUSR, f"{SCRIPT} is not executable"

    # Python may be used to launch the supplied services, but not as an Extract
    # or Transform helper.
    with open(SCRIPT, "r", errors="replace") as f:
        script_text = f.read()
    for line in script_text.splitlines():
        code = line.split("#", 1)[0]
        if re.search(r"(^|[^A-Za-z0-9_])python(?:[0-9.]+)?([^A-Za-z0-9_]|$)", code):
            assert "/app/services/data_api.py" in code or "/app/services/train_api.py" in code, \
                f"Python is not allowed for Extract/Transform: {line}"

    # First run from a stopped state against the supplied services. This checks
    # that the script autonomously starts/configures them and causes the training
    # API to save at the required path.
    stop_services()
    for path in ("/home/user/model.joblib", "/home/user/correlation.txt"):
        if os.path.exists(path):
            os.remove(path)
    run_pipeline()
    assert os.path.isfile("/home/user/model.joblib"), "Supplied training API did not save /home/user/model.joblib"
    assert os.path.isfile("/home/user/correlation.txt"), "Pipeline did not create correlation.txt"
    with urllib.request.urlopen("http://127.0.0.1:8000/raw_data", timeout=5) as response:
        assert response.status == 200
    joblib.load("/home/user/model.joblib")

    stop_services()
    backups = {}
    challenge_path = "/tmp/challenge_raw.csv"
    expected = build_challenge(challenge_path)

    data_mock = r'''from flask import Flask, Response
app = Flask(__name__)
@app.route('/raw_data', methods=['GET'])
def raw_data():
    open('/tmp/challenge_raw_requested', 'a').write('1\n')
    return Response(open('/tmp/challenge_raw.csv', 'rb').read(), mimetype='text/csv')
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000)
'''
    train_mock = r'''import os
import joblib
import pandas as pd
from flask import Flask, request, jsonify
from sklearn.linear_model import LinearRegression
from sklearn.metrics import mean_squared_error
app = Flask(__name__)
@app.route('/train', methods=['POST'])
def train():
    open('/tmp/challenge_train_requested', 'a').write('1\n')
    if 'file' not in request.files:
        return jsonify(error='No file part'), 400
    request.files['file'].save('/tmp/challenge_upload.csv')
    try:
        df = pd.read_csv('/tmp/challenge_upload.csv')
        if df.isnull().values.any():
            return jsonify(error='Data contains missing values'), 400
        X = df[['age', 'income', 'activity_score']]
        y = df['target']
        model = LinearRegression().fit(X, y)
        preds = model.predict(X)
        rmse = mean_squared_error(y, preds, squared=False)
        joblib.dump(model, '/home/user/model.joblib')
        return jsonify(message='Model trained', rmse=rmse)
    except Exception as exc:
        return jsonify(error=str(exc)), 400
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8001)
'''

    try:
        for path in (DATA_API, TRAIN_API):
            backup = path + ".verifier_backup"
            shutil.copy2(path, backup)
            backups[path] = backup
        with open(DATA_API, "w") as f:
            f.write(data_mock)
        with open(TRAIN_API, "w") as f:
            f.write(train_mock)
        for path in (UPLOAD, GET_MARKER, POST_MARKER, "/home/user/model.joblib", "/home/user/correlation.txt"):
            if os.path.exists(path):
                os.remove(path)

        # The challenge is generated only after the agent has finished. The
        # pipeline must start the APIs, fetch it, clean it, and POST the result.
        run_pipeline()
        assert os.path.isfile(GET_MARKER), "Pipeline did not fetch /raw_data from the Data Source API"
        assert os.path.isfile(POST_MARKER), "Pipeline did not POST to the Model Training API"
        assert os.path.isfile(UPLOAD), "Training API did not receive a CSV upload"

        uploaded = pd.read_csv(UPLOAD, dtype=str)
        assert list(uploaded.columns) == ["id", "age", "income", "activity_score", "target"], \
            f"Unexpected cleaned CSV columns: {list(uploaded.columns)}"
        assert len(uploaded) == len(expected), f"Expected {len(expected)} cleaned rows, got {len(uploaded)}"
        assert not uploaded.isnull().values.any(), "Cleaned CSV still contains missing values"

        actual_by_id = {str(row["id"]): row for _, row in uploaded.iterrows()}
        expected_by_id = {row["id"]: row for row in expected}
        assert set(actual_by_id) == set(expected_by_id), "Cleaned CSV retained rejected rows or dropped valid rows"
        for rid, exp in expected_by_id.items():
            got = actual_by_id[rid]
            for column in ("age", "income", "activity_score", "target"):
                assert math.isclose(float(got[column]), exp[column], rel_tol=1e-9, abs_tol=1e-7), \
                    f"Incorrect {column} for id {rid}: got {got[column]}, expected {exp[column]}"

        with open("/home/user/correlation.txt") as f:
            corr_text = f.read().strip()
        assert re.fullmatch(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", corr_text), \
            "correlation.txt must contain a single float"
        actual_corr = float(corr_text)
        expected_corr = pearson(
            [row["activity_score"] for row in expected],
            [row["target"] for row in expected],
        )
        assert math.isclose(actual_corr, expected_corr, rel_tol=2e-5, abs_tol=2e-5), \
            f"Expected Pearson correlation {expected_corr}, got {actual_corr}"
        assert os.path.isfile("/home/user/model.joblib"), "Pipeline did not trigger model creation through the API"
    finally:
        stop_services()
        for path, backup in backups.items():
            if os.path.exists(backup):
                shutil.move(backup, path)


def test_run_pipeline_script_exists_and_executable():
    script_path = "/home/user/run_pipeline.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist"
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{script_path} is not executable"


def test_correlation_file():
    corr_path = "/home/user/correlation.txt"
    assert os.path.isfile(corr_path), f"{corr_path} does not exist"
    with open(corr_path, "r") as f:
        content = f.read().strip()

    try:
        corr_value = float(content)
    except ValueError:
        assert False, f"Content of {corr_path} is not a valid float: '{content}'"

    assert -1.0 <= corr_value <= 1.0, f"Correlation value {corr_value} is out of bounds [-1.0, 1.0]"


def test_model_exists_and_meets_rmse_threshold():
    model_path = "/home/user/model.joblib"
    test_data_path = "/app/hidden_test_data.csv"

    assert os.path.isfile(model_path), f"Model file {model_path} does not exist. Did the pipeline trigger the training API?"
    assert os.path.isfile(test_data_path), f"Hidden test data {test_data_path} is missing."

    try:
        model = joblib.load(model_path)
    except Exception as e:
        assert False, f"Failed to load model from {model_path}: {e}"

    try:
        test_df = pd.read_csv(test_data_path)
        X_test = test_df[['age', 'income', 'activity_score']]
        y_test = test_df['target']
    except Exception as e:
        assert False, f"Failed to load or parse test data from {test_data_path}: {e}"

    try:
        preds = model.predict(X_test)
    except Exception as e:
        assert False, f"Model prediction failed: {e}"

    rmse = mean_squared_error(y_test, preds, squared=False)
    assert rmse <= 12.5, f"RMSE {rmse:.4f} is greater than threshold 12.5"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
