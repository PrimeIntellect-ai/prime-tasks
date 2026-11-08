#!/bin/bash
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess

import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression

RUN_SH = '/home/user/run.sh'
TRAIN_MODEL = '/home/user/train_model.py'
LOGS_CSV = '/home/user/logs.csv'
SIM_TXT = '/home/user/sim.txt'
METRICS_TXT = '/home/user/metrics.txt'


def test_run_sh_exists_and_executable():
    assert os.path.isfile(RUN_SH), f"{RUN_SH} does not exist."
    assert os.access(RUN_SH, os.X_OK), f"{RUN_SH} is not executable."


def test_train_model_exists():
    assert os.path.isfile(TRAIN_MODEL), f"{TRAIN_MODEL} does not exist."


def expected_values(frame):
    matrix = TfidfVectorizer().fit_transform(frame['text'])
    similarity = round(float(matrix[0].dot(matrix[1].T).toarray()[0, 0]), 4)
    model = LogisticRegression(random_state=42)
    model.fit(matrix, frame['label'])
    accuracy = round(float(model.score(matrix, frame['label'])), 4)
    return similarity, accuracy


def read_float(path):
    assert os.path.isfile(path), f"{path} does not exist. Did the script run successfully?"
    content = open(path, 'r').read().strip()
    try:
        return float(content)
    except ValueError:
        raise AssertionError(f"{path} does not contain a valid float. Found: '{content}'")


def run_case(frame):
    expected_sim, expected_acc = expected_values(frame)
    frame.to_csv(LOGS_CSV, index=False)

    for path in (SIM_TXT, METRICS_TXT):
        if os.path.exists(path):
            os.remove(path)

    subprocess.run(
        [RUN_SH],
        cwd='/home/user',
        check=True,
        timeout=180,
    )

    sim_val = read_float(SIM_TXT)
    acc_val = read_float(METRICS_TXT)

    # Preserve the original numerical assertions, using values derived from
    # the actual input and the specified sklearn defaults.
    assert abs(sim_val - expected_sim) < 0.001, (
        f"Expected similarity ~{expected_sim}, but got {sim_val}"
    )
    assert abs(acc_val - expected_acc) < 0.001, (
        f"Expected accuracy ~{expected_acc}, but got {acc_val}"
    )

    # The files must contain the requested values rounded to four places.
    assert abs(sim_val - expected_sim) <= 0.00005
    assert abs(acc_val - expected_acc) <= 0.00005


def test_pipeline_executes_and_computes_outputs():
    with open(LOGS_CSV, 'rb') as source:
        original_bytes = source.read()

    original_frame = pd.read_csv(LOGS_CSV)
    hidden_frames = [
        pd.DataFrame({
            'id': [101, 102, 103, 104, 105, 106],
            'label': [0, 0, 0, 1, 1, 1],
            'text': [
                'alpha beta beta common',
                'alpha gamma common',
                'delta delta common',
                'bright calm signal',
                'bright signal signal',
                'calm bright beacon',
            ],
        }),
        pd.DataFrame({
            'id': [21, 22, 23, 24, 25, 26, 27, 28],
            'label': ['low', 'high', 'low', 'high', 'low', 'high', 'low', 'high'],
            'text': [
                'network timeout packet loss',
                'network packet restored service',
                'disk failure sector error',
                'disk service healthy restored',
                'memory pressure failure alert',
                'memory healthy service stable',
                'packet error timeout alert',
                'stable restored healthy network',
            ],
        }),
    ]

    try:
        run_case(original_frame)
        for frame in hidden_frames:
            run_case(frame)
    finally:
        with open(LOGS_CSV, 'wb') as destination:
            destination.write(original_bytes)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
