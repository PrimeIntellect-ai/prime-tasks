#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import subprocess
import pytest


def test_00_scripts_and_pipeline_actually_work():
    """Execute each required artifact and verify that it produces its required output."""
    process_script = '/home/user/process_data.sh'
    train_script = '/home/user/train.py'
    pipeline_script = '/home/user/run_pipeline.sh'
    features_path = '/home/user/features.csv'
    metrics_path = '/home/user/metrics.txt'

    for script in (process_script, train_script, pipeline_script):
        assert os.path.exists(script), f"Script {script} is missing"
        assert os.access(script, os.X_OK), f"Script {script} is not executable"

    # process_data.sh must independently regenerate a correct features.csv.
    for path in (features_path, metrics_path):
        if os.path.lexists(path):
            os.remove(path)
    subprocess.run([process_script], cwd='/home/user', check=True, timeout=60)
    test_features_csv()

    # train.py must independently regenerate a correct metrics.txt when run with
    # the virtual environment's Python.
    if os.path.lexists(metrics_path):
        os.remove(metrics_path)
    subprocess.run(
        ['/home/user/venv/bin/python', train_script],
        cwd='/home/user', check=True, timeout=120
    )
    test_metrics_txt()

    # The master pipeline must regenerate both artifacts from a clean state.
    for path in (features_path, metrics_path):
        if os.path.lexists(path):
            os.remove(path)
    subprocess.run([pipeline_script], cwd='/home/user', check=True, timeout=180)
    assert os.path.exists(features_path), "run_pipeline.sh did not create features.csv"
    assert os.path.exists(metrics_path), "run_pipeline.sh did not create metrics.txt"


def test_venv_exists():
    """Check that the Python virtual environment is created."""
    python_path = '/home/user/venv/bin/python'
    assert os.path.exists(python_path), f"Virtual environment python not found at {python_path}"


def test_features_csv():
    """Check that features.csv is generated correctly with aggregated data."""
    raw_path = '/home/user/raw_transactions.csv'
    features_path = '/home/user/features.csv'
    assert os.path.exists(features_path), f"{features_path} does not exist"

    # Compute expected aggregation
    users = {}
    with open(raw_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            uid = int(row['user_id'])
            amt = float(row['amount'])
            tgt = int(row['target'])
            if uid not in users:
                users[uid] = {'amount': 0.0, 'count': 0, 'target': tgt}
            users[uid]['amount'] += amt
            users[uid]['count'] += 1

    expected_rows = []
    for uid in sorted(users.keys()):
        total = round(users[uid]['amount'], 2)
        count = users[uid]['count']
        avg = round(users[uid]['amount'] / count, 2)
        tgt = users[uid]['target']
        expected_rows.append([str(uid), f"{total:.2f}", str(count), f"{avg:.2f}", str(tgt)])

    with open(features_path, 'r') as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header == ['user_id', 'total_amount', 'tx_count', 'avg_amount', 'target'], \
            "Incorrect header in features.csv"

        agent_rows = list(reader)

    assert len(agent_rows) == len(expected_rows), "Incorrect number of rows in features.csv"

    for expected, agent in zip(expected_rows, agent_rows):
        assert agent[0] == expected[0], f"user_id mismatch: expected {expected[0]}, got {agent[0]}"
        assert abs(float(agent[1]) - float(expected[1])) < 1e-5, f"total_amount mismatch for user {expected[0]}"
        assert agent[2] == expected[2], f"tx_count mismatch for user {expected[0]}"
        assert abs(float(agent[3]) - float(expected[3])) < 1e-5, f"avg_amount mismatch for user {expected[0]}"
        assert agent[4] == expected[4], f"target mismatch for user {expected[0]}"


def test_metrics_txt():
    """Check that metrics.txt contains the correct accuracy score."""
    metrics_path = '/home/user/metrics.txt'
    assert os.path.exists(metrics_path), f"{metrics_path} does not exist"

    # Compute expected accuracy using the agent's venv to ensure sklearn is available
    script = """
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score

df_raw = pd.read_csv('/home/user/raw_transactions.csv')
agg = df_raw.groupby('user_id').agg(
    total_amount=('amount', 'sum'),
    tx_count=('amount', 'count'),
    avg_amount=('amount', 'mean'),
    target=('target', 'first')
).reset_index()
agg['total_amount'] = agg['total_amount'].round(2)
agg['avg_amount'] = agg['avg_amount'].round(2)

X = agg[['total_amount', 'tx_count', 'avg_amount']]
y = agg['target']
clf = LogisticRegression(random_state=42, solver='lbfgs')
clf.fit(X, y)
acc = accuracy_score(y, clf.predict(X))
print(f"Accuracy: {acc:.4f}")
"""
    try:
        result = subprocess.run(['/home/user/venv/bin/python', '-c', script], capture_output=True, text=True, check=True)
        expected_str = result.stdout.strip()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Could not compute expected accuracy using the agent's virtual environment: {e.stderr}")
    except Exception as e:
        pytest.fail(f"Could not compute expected accuracy: {e}")

    with open(metrics_path, 'r') as f:
        agent_metrics = f.read().strip()

    assert expected_str in agent_metrics, f"Expected '{expected_str}' in {metrics_path}, got '{agent_metrics}'"


def test_scripts_exist_and_executable():
    """Check that the required scripts exist and are executable."""
    scripts = ['/home/user/process_data.sh', '/home/user/train.py', '/home/user/run_pipeline.sh']
    for script in scripts:
        assert os.path.exists(script), f"Script {script} is missing"
        assert os.access(script, os.X_OK), f"Script {script} is not executable"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
