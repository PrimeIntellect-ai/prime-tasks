#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import importlib.metadata
import json
import os
import random
import re
import shutil
import stat
import subprocess

import numpy as np

HOME = '/home/user'
VENV = f'{HOME}/venv'
PYTHON = f'{VENV}/bin/python'
if not os.path.exists(PYTHON):
    PYTHON = f'{VENV}/bin/python3'
PIPELINE = f'{HOME}/pipeline.py'
RAW = f'{HOME}/raw_data.jsonl'
OUTLIERS = f'{HOME}/outliers.txt'
METRICS = f'{HOME}/metrics.txt'


def expected_dataset():
    random.seed(42)
    texts_a = [
        'The company reported strong earnings this quarter.',
        'Revenue grew by 20 percent year over year.',
        'Profits exceeded expectations.',
        'Sales are up in the European market.',
        'The quarterly dividend was increased.',
        'Investors responded positively to the financial report.',
        'Operating margins improved significantly.',
        'Cash flow remains very healthy.',
        'The balance sheet is stronger than ever.',
        'Earnings per share hit a record high.'
    ] * 4
    texts_b = [
        'The new software update fixes several bugs.',
        'Users can now enjoy faster load times.',
        'The UI has been completely redesigned.',
        'Security patches were applied to the server.',
        'The database migration completed successfully.',
        'We added a new feature for data export.',
        'API response times have decreased.',
        'The mobile app is now available on both platforms.',
        'Authentication errors have been resolved.',
        'Cloud storage limits were increased for premium accounts.'
    ] * 4
    records = []
    current_id = 1
    for text in texts_a:
        records.append({'id': current_id, 'text': text, 'label': 'Finance'})
        current_id += 1
    for text in texts_b:
        records.append({'id': current_id, 'text': text, 'label': 'Technology'})
        current_id += 1
    anomaly_texts = [
        'Pineapple pizza is the best food.',
        'My cat slept for 14 hours today.',
        'Running shoes are on sale at the mall.',
        'The recipe calls for two cups of flour.',
        'I need to buy more coffee beans.',
        'Jupiter is the largest planet in the solar system.',
        'The guitar strings need to be replaced.',
        'He scored a hat-trick in the final match.',
        'A rare bird was spotted in the park.'
    ]
    for text in anomaly_texts:
        records.append({
            'id': current_id,
            'text': text,
            'label': 'Finance' if random.random() > 0.5 else 'Technology'
        })
        current_id += 1
    random.shuffle(records)
    return records


def load_records(path):
    with open(path, 'r', encoding='utf-8') as handle:
        return [json.loads(line) for line in handle if line.strip()]


def write_records(path, records):
    with open(path, 'w', encoding='utf-8') as handle:
        for record in records:
            handle.write(json.dumps(record) + '\n')


def run_pipeline():
    for path in (OUTLIERS, METRICS):
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)
    result = subprocess.run(
        [PYTHON, PIPELINE],
        cwd=HOME,
        env={**os.environ, 'TOKENIZERS_PARALLELISM': 'false'},
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=1200
    )
    assert result.returncode == 0, (
        f'pipeline.py exited with status {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def derive_results(records, embeddings):
    from sklearn.ensemble import IsolationForest
    from sklearn.linear_model import LogisticRegression
    from sklearn.metrics import accuracy_score
    from sklearn.model_selection import train_test_split

    detector = IsolationForest(random_state=42, contamination=0.1)
    predictions = detector.fit_predict(embeddings)
    outlier_ids = sorted(
        record['id'] for record, prediction in zip(records, predictions)
        if prediction == -1
    )
    inlier_mask = predictions == 1
    x_inliers = embeddings[inlier_mask]
    y_inliers = np.asarray([record['label'] for record in records])[inlier_mask]
    x_train, x_test, y_train, y_test = train_test_split(
        x_inliers, y_inliers, test_size=0.2, random_state=42
    )
    classifier = LogisticRegression(random_state=42, max_iter=1000)
    classifier.fit(x_train, y_train)
    accuracy = accuracy_score(y_test, classifier.predict(x_test))
    return outlier_ids, f'Accuracy: {accuracy:.4f}', float(accuracy)


def check_outputs(expected_ids, expected_metrics, require_high_accuracy=False):
    assert os.path.exists(OUTLIERS), f'Expected {OUTLIERS} to exist.'
    assert os.path.isfile(OUTLIERS), f'{OUTLIERS} is not a file.'
    with open(OUTLIERS, 'r', encoding='utf-8') as handle:
        content = handle.read().strip()
    assert content, f'{OUTLIERS} is empty.'
    lines = content.split('\n')
    ids = []
    for line in lines:
        assert line.isdigit(), f"Expected each line to be an integer ID, but found '{line}'."
        ids.append(int(line))
    assert ids == sorted(ids), f'Expected IDs in {OUTLIERS} to be sorted in ascending order.'
    assert len(set(ids)) == len(ids), f'Expected all IDs in {OUTLIERS} to be unique.'
    assert ids == expected_ids, f'Outlier IDs are incorrect: expected {expected_ids}, got {ids}.'

    assert os.path.exists(METRICS), f'Expected {METRICS} to exist.'
    assert os.path.isfile(METRICS), f'{METRICS} is not a file.'
    with open(METRICS, 'r', encoding='utf-8') as handle:
        metrics_content = handle.read().strip()
    match = re.match(r'^Accuracy:\s*(0\.\d{4}|1\.0{4})$', metrics_content)
    assert match, (
        f"Content '{metrics_content}' in {METRICS} does not match the required "
        "format 'Accuracy: 0.XXXX'."
    )
    accuracy = float(match.group(1))
    assert 0.0 <= accuracy <= 1.0, f'Parsed accuracy {accuracy} is not between 0 and 1.'
    if require_high_accuracy:
        assert accuracy > 0.8, (
            f'Expected a high accuracy (>0.8) for this simple task, but got {accuracy}.'
        )
    assert metrics_content == expected_metrics, (
        f'Accuracy is incorrect: expected {expected_metrics!r}, got {metrics_content!r}.'
    )


def main():
    assert os.path.exists(VENV), 'Virtual environment directory /home/user/venv does not exist.'
    assert os.path.exists(PYTHON), 'Python executable not found in /home/user/venv/bin/.'
    assert os.path.exists(PIPELINE), f'Script not found at {PIPELINE}.'
    assert os.path.isfile(PIPELINE), f'{PIPELINE} is not a file.'
    assert not os.path.islink(PIPELINE), f'{PIPELINE} must be a regular script, not a symlink.'
    assert stat.S_ISREG(os.stat(PIPELINE).st_mode), f'{PIPELINE} is not a regular file.'

    # Confirm that the requested libraries are installed in the virtual environment.
    importlib.metadata.distribution('scikit-learn')
    importlib.metadata.distribution('sentence-transformers')
    from sentence_transformers import SentenceTransformer

    original_bytes = open(RAW, 'rb').read()
    records = load_records(RAW)
    assert records == expected_dataset(), 'The supplied raw_data.jsonl dataset was modified.'

    original_outliers = None
    original_metrics = None
    try:
        # Execute the submitted artifact from a clean output state.
        run_pipeline()
        assert open(RAW, 'rb').read() == original_bytes, 'pipeline.py modified raw_data.jsonl.'

        model = SentenceTransformer('all-MiniLM-L6-v2')
        embeddings = np.asarray(model.encode([record['text'] for record in records]))
        expected_ids, expected_metrics, _ = derive_results(records, embeddings)
        check_outputs(expected_ids, expected_metrics, require_high_accuracy=True)
        original_outliers = open(OUTLIERS, 'rb').read()
        original_metrics = open(METRICS, 'rb').read()

        # A second, derived input prevents a script that only emits fixed fabricated answers.
        order = list(range(len(records) - 1, -1, -1))
        probe_records = []
        for index in order:
            record = dict(records[index])
            record['id'] = 10000 + 3 * record['id']
            if record['id'] % 5 == 0:
                record['label'] = 'Technology' if record['label'] == 'Finance' else 'Finance'
            probe_records.append(record)
        probe_embeddings = embeddings[order]
        write_records(RAW, probe_records)
        probe_bytes = open(RAW, 'rb').read()
        run_pipeline()
        assert open(RAW, 'rb').read() == probe_bytes, 'pipeline.py modified the probe dataset.'
        probe_ids, probe_metrics, _ = derive_results(probe_records, probe_embeddings)
        check_outputs(probe_ids, probe_metrics)
    finally:
        with open(RAW, 'wb') as handle:
            handle.write(original_bytes)
        if original_outliers is not None:
            with open(OUTLIERS, 'wb') as handle:
                handle.write(original_outliers)
        if original_metrics is not None:
            with open(METRICS, 'wb') as handle:
                handle.write(original_metrics)


if __name__ == '__main__':
    main()
PY_EOF

PYTHON=/home/user/venv/bin/python
if [ ! -x "$PYTHON" ]; then
    PYTHON=/home/user/venv/bin/python3
fi

if [ -x "$PYTHON" ] && "$PYTHON" /tmp/test_final_state.py; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
