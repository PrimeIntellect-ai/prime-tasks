#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import re
import pandas as pd
from scipy.sparse import hstack
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import GridSearchCV


def test_cleaned_logs_exists():
    assert os.path.exists("/home/user/data/cleaned_logs.csv"), "Cleaned logs file is missing."


def test_cleaned_logs_content():
    original_file = "/home/user/data/logs.csv"
    cleaned_file = "/home/user/data/cleaned_logs.csv"

    assert os.path.exists(original_file), "Original logs file is missing."
    assert os.path.exists(cleaned_file), "Cleaned logs file is missing."

    expected_rows = []
    with open(original_file, 'r', newline='') as f:
        reader = csv.DictReader(f)
        expected_rows.append(reader.fieldnames)
        for row in reader:
            rt_str = row['response_time']
            if rt_str == 'NA':
                rt_val = 250.0
                row['response_time'] = '250'
            else:
                rt_val = float(rt_str)
                if rt_val < 0 or rt_val > 5000:
                    continue
            expected_rows.append(row)

    actual_rows = []
    with open(cleaned_file, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader)
        actual_rows.append(header)
        for row_list in reader:
            row_dict = dict(zip(header, row_list))
            actual_rows.append(row_dict)

    assert actual_rows[0] == expected_rows[0], "Header of cleaned_logs.csv is incorrect."
    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, got {len(actual_rows)}."

    for i in range(1, len(expected_rows)):
        expected = expected_rows[i]
        actual = actual_rows[i]

        assert actual['id'] == expected['id'], f"Row {i}: ID mismatch."
        assert actual['message'] == expected['message'], f"Row {i}: Message mismatch."
        assert actual['is_anomaly'] == expected['is_anomaly'], f"Row {i}: is_anomaly mismatch."
        assert float(actual['response_time']) == float(expected['response_time']), f"Row {i}: response_time mismatch."


def test_metrics_file_format_and_values():
    metrics_file = "/home/user/metrics.txt"
    assert os.path.exists(metrics_file), "Metrics file is missing."

    with open(metrics_file, 'r') as f:
        raw_content = f.read()
    content = raw_content.strip().split('\n')

    assert len(content) >= 2, "Metrics file should contain at least two lines."

    c_match = re.search(r"Best C:\s*([0-9.]+)", content[0])
    assert c_match, "First line must match 'Best C: <value>'."
    c_val = float(c_match.group(1))
    assert c_val in [0.01, 0.1, 1.0, 10.0], f"Best C value {c_val} is not in the expected grid."

    score_match = re.search(r"Best CV Score:\s*([0-9.]+)", content[1])
    assert score_match, "Second line must match 'Best CV Score: <score>'."
    score_str = score_match.group(1)

    if '.' in score_str:
        decimals = len(score_str.split('.')[1])
        assert decimals <= 4, "CV Score should be rounded to 4 decimal places."

    data = pd.read_csv("/home/user/data/cleaned_logs.csv")
    vectorizer = TfidfVectorizer(max_features=50, stop_words='english')
    text_features = vectorizer.fit_transform(data['message'].astype(str).str.lower())
    response_time = data['response_time'].astype(float).to_numpy().reshape(-1, 1)
    features = hstack([text_features, response_time])
    target = data['is_anomaly']

    model = LogisticRegression(random_state=42, max_iter=1000)
    search = GridSearchCV(model, {'C': [0.01, 0.1, 1.0, 10.0]}, cv=5)
    search.fit(features, target)

    expected = (
        f"Best C: {search.best_params_['C']}\n"
        f"Best CV Score: {search.best_score_:.4f}"
    )
    assert raw_content in (expected, expected + "\n"), (
        "metrics.txt does not contain the GridSearchCV result produced by the "
        "required feature construction and model configuration."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
