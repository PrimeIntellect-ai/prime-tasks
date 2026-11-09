#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "sklearn:scikit-learn"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import math
import os
import stat
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

import pandas as pd
import pytest
from pandas.testing import assert_frame_equal
from sklearn.decomposition import PCA
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score
from sklearn.model_selection import train_test_split

BASE_URL = "http://127.0.0.1:5000/api/2.0/mlflow"
EXP_NAME = "Data_Cleaning_Exp"
EXECUTION = {}


def get_experiment():
    params = urllib.parse.urlencode({'experiment_name': EXP_NAME})
    url = f"{BASE_URL}/experiments/get-by-name?{params}"
    try:
        with urllib.request.urlopen(url, timeout=10) as response:
            return json.loads(response.read().decode('utf-8')).get('experiment')
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            return None
        raise


def search_runs(exp_id):
    payload = json.dumps({'experiment_ids': [str(exp_id)], 'max_results': 1000}).encode('utf-8')
    req = urllib.request.Request(
        f"{BASE_URL}/runs/search",
        data=payload,
        headers={'Content-Type': 'application/json'},
    )
    with urllib.request.urlopen(req, timeout=10) as response:
        return json.loads(response.read().decode('utf-8')).get('runs', [])


def run_id(run):
    info = run.get('info', {})
    return info.get('run_id') or info.get('run_uuid')


@pytest.fixture(scope='session', autouse=True)
def execute_pipeline():
    path = "/home/user/pipeline.py"
    assert os.path.exists(path), f"File {path} does not exist."
    mode = os.lstat(path).st_mode
    assert stat.S_ISREG(mode), f"{path} must be a regular Python file."

    before_ids = set()
    try:
        exp = get_experiment()
        if exp is not None:
            before_ids = {run_id(r) for r in search_runs(exp['experiment_id'])}
    except urllib.error.URLError as exc:
        pytest.fail(f"MLflow server was not running before pipeline execution: {exc}")

    started_ms = int(time.time() * 1000)
    try:
        result = subprocess.run(
            ['python3', path],
            cwd='/home/user',
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=180,
        )
    except subprocess.TimeoutExpired as exc:
        pytest.fail(f"pipeline.py did not finish within 180 seconds. Output: {exc.stdout}")

    assert result.returncode == 0, f"pipeline.py failed with exit code {result.returncode}:\n{result.stdout}"
    EXECUTION['before_ids'] = before_ids
    EXECUTION['started_ms'] = started_ms
    EXECUTION['output'] = result.stdout


def test_pipeline_uses_required_ml_operations():
    path = "/home/user/pipeline.py"
    with open(path, 'r', encoding='utf-8') as handle:
        source = handle.read()
    try:
        tree = ast.parse(source, filename=path)
    except SyntaxError as exc:
        pytest.fail(f"pipeline.py is not valid Python: {exc}")

    calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)]

    def call_name(call):
        func = call.func
        if isinstance(func, ast.Name):
            return func.id
        if isinstance(func, ast.Attribute):
            return func.attr
        return None

    def keyword_value(call, key):
        for kw in call.keywords:
            if kw.arg == key and isinstance(kw.value, ast.Constant):
                return kw.value.value
        return None

    pca_calls = [c for c in calls if call_name(c) == 'PCA']
    assert pca_calls, "pipeline.py must instantiate sklearn.decomposition.PCA."
    assert any(
        keyword_value(c, 'n_components') == 2
        or (c.args and isinstance(c.args[0], ast.Constant) and c.args[0].value == 2)
        for c in pca_calls
    ), "PCA must be configured with n_components=2."

    split_calls = [c for c in calls if call_name(c) == 'train_test_split']
    assert split_calls, "pipeline.py must call train_test_split."
    assert any(
        keyword_value(c, 'random_state') == 42
        and (keyword_value(c, 'test_size') == 0.2 or keyword_value(c, 'train_size') == 0.8)
        for c in split_calls
    ), "train_test_split must use an 80/20 split and random_state=42."

    forest_calls = [c for c in calls if call_name(c) == 'RandomForestClassifier']
    assert forest_calls, "pipeline.py must instantiate RandomForestClassifier."
    assert any(keyword_value(c, 'random_state') == 42 for c in forest_calls), \
        "RandomForestClassifier must use random_state=42."

    called_names = {call_name(c) for c in calls}
    assert 'fit_transform' in called_names or ({'fit', 'transform'} <= called_names), \
        "The PCA object must be fit and used to transform the features."
    assert 'fit' in called_names, "The classifier must be trained with fit()."
    assert 'predict' in called_names, "The trained classifier must be used to predict the test set."
    for feature in ('age', 'amount', 'group_hash'):
        assert feature in source, f"pipeline.py does not reference required feature {feature!r}."


def expected_cleaned_data():
    users = pd.read_csv('/home/user/data/users.csv')
    transactions = pd.read_csv('/home/user/data/transactions.csv')
    expected = users.merge(transactions, on='user_id', how='left')
    expected['amount'] = expected['amount'].fillna(0.0)
    expected['group_id'] = expected['group_id'].fillna(0).astype('int64')
    expected['group_hash'] = expected['group_id'] << 1
    return expected


def test_cleaned_data_csv():
    path = "/home/user/cleaned_data.csv"
    assert os.path.exists(path), f"File {path} does not exist."
    assert os.path.isfile(path), f"{path} is not a file."

    with open(path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        headers = reader.fieldnames
        assert headers is not None, "cleaned_data.csv is empty or missing headers."
        assert 'group_id' in headers, "Missing group_id column in cleaned_data.csv"
        assert 'group_hash' in headers, "Missing group_hash column in cleaned_data.csv"

        for row_idx, row in enumerate(reader):
            group_id_str = row['group_id']
            group_hash_str = row['group_hash']

            assert group_id_str != "", f"Row {row_idx} has missing group_id."
            assert group_hash_str != "", f"Row {row_idx} has missing group_hash."

            try:
                group_id_val = int(float(group_id_str))
                group_hash_val = int(float(group_hash_str))
            except ValueError:
                pytest.fail(f"Row {row_idx} has non-numeric group_id or group_hash.")

            assert group_hash_val == (group_id_val << 1), \
                f"Row {row_idx}: group_hash ({group_hash_val}) != group_id ({group_id_val}) << 1"

    actual = pd.read_csv(path)
    expected = expected_cleaned_data()
    assert len(actual) == len(expected) == 100, \
        "cleaned_data.csv must preserve every user from the left join."
    required = list(expected.columns)
    assert all(col in actual.columns for col in required), \
        f"cleaned_data.csv must contain all joined columns: {required}"
    assert actual['user_id'].is_unique, "cleaned_data.csv contains duplicate users."
    assert pd.api.types.is_integer_dtype(actual['group_id']), \
        "group_id must be saved with an integer dtype, not as floats."
    assert not actual[['amount', 'group_id', 'group_hash']].isna().any().any(), \
        "Imputed and engineered columns must not contain missing values."

    actual_cmp = actual[required].sort_values('user_id').reset_index(drop=True)
    expected_cmp = expected[required].sort_values('user_id').reset_index(drop=True)
    assert_frame_equal(actual_cmp, expected_cmp, check_dtype=True, check_exact=True)


def recompute_expected_accuracy():
    cleaned = expected_cleaned_data()
    features = cleaned[['age', 'amount', 'group_hash']]
    target = cleaned['target']
    components = PCA(n_components=2).fit_transform(features)
    x_train, x_test, y_train, y_test = train_test_split(
        components, target, test_size=0.2, random_state=42
    )
    model = RandomForestClassifier(random_state=42)
    model.fit(x_train, y_train)
    return float(accuracy_score(y_test, model.predict(x_test)))


def test_mlflow_experiment_and_run():
    params = urllib.parse.urlencode({'experiment_name': EXP_NAME})
    get_exp_url = f"{BASE_URL}/experiments/get-by-name?{params}"

    try:
        req = urllib.request.Request(get_exp_url)
        with urllib.request.urlopen(req) as response:
            res_data = json.loads(response.read().decode('utf-8'))
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to MLflow server or experiment not found: {e}")

    assert 'experiment' in res_data, "MLflow response missing 'experiment' data."
    exp_id = res_data['experiment']['experiment_id']

    search_url = f"{BASE_URL}/runs/search"
    search_payload = json.dumps({'experiment_ids': [exp_id]}).encode('utf-8')
    req = urllib.request.Request(search_url, data=search_payload, headers={'Content-Type': 'application/json'})

    try:
        with urllib.request.urlopen(req) as response:
            runs_data = json.loads(response.read().decode('utf-8'))
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to search MLflow runs: {e}")

    runs = runs_data.get('runs', [])
    assert len(runs) > 0, "No runs found in the MLflow experiment."

    run = runs[0]
    run_data = run.get('data', {})

    metrics = {m['key']: m['value'] for m in run_data.get('metrics', [])}
    params = {p['key']: p['value'] for p in run_data.get('params', [])}

    assert 'accuracy' in metrics, "Metric 'accuracy' was not logged to MLflow."
    assert 'n_components' in params, "Parameter 'n_components' was not logged to MLflow."
    assert params['n_components'] in ('2', 2), f"Expected n_components to be 2, got {params['n_components']}"

    before_ids = EXECUTION['before_ids']
    started_ms = EXECUTION['started_ms']
    fresh_runs = []
    for candidate in runs:
        info = candidate.get('info', {})
        candidate_id = run_id(candidate)
        start_time = info.get('start_time') or 0
        if candidate_id not in before_ids and start_time >= started_ms - 2000:
            fresh_runs.append(candidate)

    assert fresh_runs, "Executing pipeline.py did not create a new MLflow run."
    expected_accuracy = recompute_expected_accuracy()
    matching = []
    for candidate in fresh_runs:
        data = candidate.get('data', {})
        candidate_metrics = {m['key']: m['value'] for m in data.get('metrics', [])}
        candidate_params = {p['key']: p['value'] for p in data.get('params', [])}
        if 'accuracy' not in candidate_metrics or 'n_components' not in candidate_params:
            continue
        value = float(candidate_metrics['accuracy'])
        if (candidate_params['n_components'] in ('2', 2)
                and math.isfinite(value)
                and value == pytest.approx(expected_accuracy, abs=1e-12)):
            matching.append(candidate)

    assert matching, \
        f"The newly executed pipeline did not log the recomputed accuracy {expected_accuracy} with n_components=2."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
