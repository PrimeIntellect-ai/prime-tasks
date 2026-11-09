#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import ast
import collections
import csv
import importlib.metadata
import json
import os
import re
import subprocess
import sys

VENV = '/home/user/venv'
PIPELINE = '/home/user/model_pipeline.py'
EVALUATE = '/home/user/evaluate.sh'
PREDS = '/home/user/predictions.csv'
METRICS = '/home/user/metrics.txt'
REVIEWS = '/home/user/reviews.csv'
AUDIT_DIR = '/tmp/vectorizer_monitor'
AUDIT_LOG = '/tmp/vectorizer_audit.json'


def run(cmd, **kwargs):
    result = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {cmd}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def read_metric():
    assert os.path.isfile(METRICS), f"{METRICS} does not exist. Did you run evaluate.sh?"
    with open(METRICS) as f:
        content = f.read().strip()
    match = re.match(r'^Accuracy:\s*([0-9]*\.?[0-9]+)$', content)
    assert match, f"{METRICS} must contain exactly 'Accuracy: 0.XXXX'. Got: {content}"
    return float(match.group(1))


# Preserve the original environment assertions and verify the requested versions.
assert os.path.isdir(VENV), "Virtual environment at /home/user/venv does not exist."
assert os.path.isfile(f'{VENV}/bin/python'), "Python executable not found in /home/user/venv/bin/."
assert importlib.metadata.version('scikit-learn') == '1.3.0', "scikit-learn==1.3.0 is not installed in the virtual environment."
assert importlib.metadata.version('pandas') == '2.0.3', "pandas==2.0.3 is not installed in the virtual environment."

assert os.path.isfile(EVALUATE), f"{EVALUATE} does not exist."
with open(EVALUATE) as f:
    evaluate_content = f.read()
assert not re.search(r'\bpython\b', evaluate_content, re.IGNORECASE), "evaluate.sh must not use Python."

assert os.path.isfile(PIPELINE), f"{PIPELINE} does not exist."
with open(PIPELINE) as f:
    pipeline_content = f.read()
assert "vectorizer.fit_transform(df['review_text'])" not in pipeline_content, "The pipeline still contains the leaky code."

# Check required constructor/split settings without replacing the behavioral checks below.
tree = ast.parse(pipeline_content, filename=PIPELINE)

def call_name(node):
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        return node.attr
    return None


def literal_keyword(call, name, expected):
    for kw in call.keywords:
        if kw.arg == name:
            try:
                return ast.literal_eval(kw.value) == expected
            except Exception:
                return False
    return False

calls = [n for n in ast.walk(tree) if isinstance(n, ast.Call)]
split_calls = [c for c in calls if call_name(c.func) == 'train_test_split']
assert any(literal_keyword(c, 'test_size', 0.2) and literal_keyword(c, 'random_state', 42) for c in split_calls), \
    "train_test_split must use test_size=0.2 and random_state=42."
lr_calls = [c for c in calls if call_name(c.func) == 'LogisticRegression']
assert any(literal_keyword(c, 'random_state', 42) for c in lr_calls), \
    "LogisticRegression must use random_state=42."

# Install a verification-only monitor that records exactly which documents are used
# to fit and transform TfidfVectorizer. This detects equivalent spellings of leakage.
os.makedirs(AUDIT_DIR, exist_ok=True)
with open(os.path.join(AUDIT_DIR, 'sitecustomize.py'), 'w') as f:
    f.write(r'''
import atexit
import json
import os
from sklearn.feature_extraction.text import TfidfVectorizer

_events = []
_log = os.environ.get('VECTORIZER_AUDIT_LOG')
_orig_fit = TfidfVectorizer.fit
_orig_fit_transform = TfidfVectorizer.fit_transform
_orig_transform = TfidfVectorizer.transform

def _materialize(values):
    return [str(x) for x in list(values)]

def fit(self, raw_documents, y=None):
    docs = _materialize(raw_documents)
    _events.append({'kind': 'fit', 'documents': docs})
    return _orig_fit(self, docs, y)

def fit_transform(self, raw_documents, y=None):
    docs = _materialize(raw_documents)
    _events.append({'kind': 'fit_transform', 'documents': docs})
    return _orig_fit_transform(self, docs, y)

def transform(self, raw_documents):
    docs = _materialize(raw_documents)
    _events.append({'kind': 'transform', 'documents': docs})
    return _orig_transform(self, docs)

TfidfVectorizer.fit = fit
TfidfVectorizer.fit_transform = fit_transform
TfidfVectorizer.transform = transform

@atexit.register
def _save():
    if _log:
        with open(_log, 'w') as out:
            json.dump(_events, out)
''')

import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import train_test_split

# Independently derive the required split and model outputs from reviews.csv.
df = pd.read_csv(REVIEWS)
X_train, X_test, y_train, y_test, id_train, id_test = train_test_split(
    df['review_text'], df['sentiment'], df['id'], test_size=0.2, random_state=42
)
reference_vectorizer = TfidfVectorizer()
reference_vectorizer.fit(X_train)
reference_X_train = reference_vectorizer.transform(X_train)
reference_X_test = reference_vectorizer.transform(X_test)
reference_model = LogisticRegression(random_state=42)
reference_model.fit(reference_X_train, y_train)
expected_predictions = list(reference_model.predict(reference_X_test))
expected_ids = [str(x) for x in id_test.tolist()]
expected_true = [str(x) for x in y_test.tolist()]

for path in (PREDS, METRICS, AUDIT_LOG):
    try:
        os.remove(path)
    except FileNotFoundError:
        pass

env = os.environ.copy()
env['PYTHONPATH'] = AUDIT_DIR
env['VECTORIZER_AUDIT_LOG'] = AUDIT_LOG
run([f'{VENV}/bin/python', PIPELINE], cwd='/home/user', env=env)

assert os.path.isfile(AUDIT_LOG), "The pipeline did not exercise TfidfVectorizer."
with open(AUDIT_LOG) as f:
    events = json.load(f)
fit_events = [e for e in events if e.get('kind') in ('fit', 'fit_transform')]
assert fit_events, "The pipeline never fitted a TfidfVectorizer."
expected_train_counter = collections.Counter(str(x) for x in X_train.tolist())
for event in fit_events:
    assert collections.Counter(event['documents']) == expected_train_counter, \
        "TfidfVectorizer was fitted on data other than the training split (data leakage detected)."
transform_events = [e for e in events if e.get('kind') == 'transform']
expected_test_counter = collections.Counter(str(x) for x in X_test.tolist())
assert any(collections.Counter(e['documents']) == expected_test_counter for e in transform_events), \
    "The fitted vectorizer was not used to transform the test split."
assert (any(e.get('kind') == 'fit_transform' for e in fit_events) or
        any(collections.Counter(e['documents']) == expected_train_counter for e in transform_events)), \
    "The training split was not transformed with the training-fitted vectorizer."

# Validate every prediction row against the independently derived split and model.
assert os.path.isfile(PREDS), f"{PREDS} does not exist. Did you run the pipeline?"
with open(PREDS, newline='') as f:
    reader = csv.reader(f)
    header = next(reader)
    assert header == ['id', 'predicted_sentiment', 'true_sentiment'], "predictions.csv header is incorrect."
    rows = [row for row in reader if row]
assert len(rows) == 200, f"Expected 200 test samples (20% of 1000), got {len(rows)}."
assert all(len(row) == 3 for row in rows), "predictions.csv must have exactly 3 columns."
assert [row[0] for row in rows] == expected_ids, "Prediction IDs do not match the random_state=42 test split."
assert [row[2] for row in rows] == expected_true, "true_sentiment values do not match the dataset test split."
assert [row[1] for row in rows] == expected_predictions, "Predictions do not match the corrected pipeline."

correct = sum(row[1] == row[2] for row in rows)
expected_accuracy = correct / len(rows)
original_predictions = open(PREDS, 'rb').read()

# Actually execute evaluate.sh and retain the original metric assertion.
try:
    os.remove(METRICS)
except FileNotFoundError:
    pass
run(['bash', EVALUATE], cwd='/home/user')
reported_accuracy = read_metric()
assert abs(reported_accuracy - expected_accuracy) < 1e-4, \
    f"Reported accuracy {reported_accuracy} does not match calculated accuracy {expected_accuracy}."
assert open(PREDS, 'rb').read() == original_predictions, "evaluate.sh must not modify predictions.csv."

# Exercise evaluate.sh on independently chosen inputs so a fixed metric cannot pass.
probes = [
    ([['1','positive','positive'], ['2','negative','positive'], ['3','negative','negative'], ['4','positive','positive']], 0.75),
    ([['1','positive','negative'], ['2','negative','positive'], ['3','positive','positive']], 1.0 / 3.0),
]
for probe_rows, expected in probes:
    with open(PREDS, 'w', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerow(['id', 'predicted_sentiment', 'true_sentiment'])
        writer.writerows(probe_rows)
    try:
        os.remove(METRICS)
    except FileNotFoundError:
        pass
    run(['bash', EVALUATE], cwd='/home/user')
    actual = read_metric()
    assert abs(actual - expected) < 1e-4, f"evaluate.sh reported {actual}; expected {expected}."

# Restore the required final artifacts and verify the final metric once more.
with open(PREDS, 'wb') as f:
    f.write(original_predictions)
try:
    os.remove(METRICS)
except FileNotFoundError:
    pass
run(['bash', EVALUATE], cwd='/home/user')
assert abs(read_metric() - expected_accuracy) < 1e-4
assert open(PREDS, 'rb').read() == original_predictions
PY_EOF

if /home/user/venv/bin/python /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
