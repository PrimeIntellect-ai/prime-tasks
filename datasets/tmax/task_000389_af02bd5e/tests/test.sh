#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import tarfile
import tempfile

import jsonschema
import numpy as np
import pytest
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import BayesianRidge
from sklearn.metrics import mean_squared_error
from sklearn.metrics.pairwise import cosine_similarity

DATASET_PATH = '/home/user/mlops/dataset.jsonl'
SCHEMA_PATH = '/home/user/mlops/schema.json'
VALID_DATA_PATH = '/home/user/mlops/valid_data.jsonl'
TAR_PATH = '/home/user/artifact.tar.gz'
ARTIFACT_DIR = '/home/user/mlops/artifact'


def generate_original_inputs():
    np.random.seed(42)
    random.seed(42)

    schema = {
        'type': 'object',
        'properties': {
            'log_id': {'type': 'integer'},
            'message': {'type': 'string'},
            'features': {
                'type': 'array',
                'items': {'type': 'number'},
                'minItems': 2,
                'maxItems': 2,
            },
            'recovery_time': {'type': 'number'},
        },
        'required': ['log_id', 'message', 'features', 'recovery_time'],
    }

    words = ['disk', 'cpu', 'memory', 'overload', 'kernel', 'panic',
             'process', 'killed', 'critical', 'timeout', 'connection',
             'lost', 'network', 'latency', 'node', 'failure']
    data = []
    for i in range(500):
        num_words = random.randint(3, 8)
        msg_words = random.choices(words, k=num_words)
        if random.random() < 0.3:
            msg_words.extend(['critical', 'timeout', 'connection', 'lost'])

        f1 = np.random.normal(0, 1)
        f2 = np.random.normal(0, 1)
        recovery = 3.5 * f1 - 2.1 * f2 + 10 + np.random.normal(0, 0.5)
        record = {
            'log_id': i,
            'message': ' '.join(msg_words),
            'features': [float(f1), float(f2)],
            'recovery_time': float(recovery),
        }

        if random.random() < 0.1:
            del record['recovery_time']
        elif random.random() < 0.1:
            record['features'] = 'invalid'
        data.append(record)

    return schema, data


EXPECTED_SCHEMA, ORIGINAL_DATA = generate_original_inputs()
EXPECTED_VALID = []
for record in ORIGINAL_DATA:
    try:
        jsonschema.validate(instance=record, schema=EXPECTED_SCHEMA)
    except jsonschema.ValidationError:
        continue
    EXPECTED_VALID.append(record)

messages = [record['message'] for record in EXPECTED_VALID]
vectorizer = TfidfVectorizer(stop_words='english')
message_vectors = vectorizer.fit_transform(messages)
query_vector = vectorizer.transform(['critical timeout connection lost'])
similarities = cosine_similarity(query_vector, message_vectors).ravel()
top_indices = np.argsort(-similarities, kind='stable')[:50]
retrieved = [EXPECTED_VALID[int(i)] for i in top_indices]
X = np.asarray([record['features'] for record in retrieved], dtype=float)
y = np.asarray([record['recovery_time'] for record in retrieved], dtype=float)
model = BayesianRidge()
model.fit(X, y)
EXPECTED_MSE = float(mean_squared_error(y, model.predict(X)))
EXPECTED_WEIGHTS = ','.join(f'{coefficient:.4f}' for coefficient in model.coef_)


def load_jsonl(path):
    with open(path, 'r') as handle:
        raw_lines = handle.read().splitlines()
    records = []
    for index, line in enumerate(raw_lines):
        assert line.strip(), f'Line {index + 1} in {path} is blank.'
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError:
            pytest.fail(f'Line {index + 1} in {path} is not valid JSON.')
    return records


def assert_artifact_contents(artifact_dir):
    metrics_path = os.path.join(artifact_dir, 'metrics.json')
    assert os.path.isfile(metrics_path), 'metrics.json is missing from the artifact directory.'
    with open(metrics_path, 'r') as handle:
        try:
            metrics = json.load(handle)
        except json.JSONDecodeError:
            pytest.fail('metrics.json is not valid JSON.')

    assert 'mse' in metrics, "metrics.json does not contain the 'mse' key."
    assert set(metrics) == {'mse'}, "metrics.json must contain exactly the 'mse' key."
    mse = metrics['mse']
    assert isinstance(mse, (int, float)), "'mse' value must be a number."
    assert not isinstance(mse, bool), "'mse' value must be a number, not a boolean."
    assert 0.0 < mse < 2.0, f'MSE value {mse} is outside the expected reasonable bounds based on the true noise variance.'
    assert math.isclose(float(mse), EXPECTED_MSE, rel_tol=1e-10, abs_tol=1e-12), \
        f'MSE {mse} does not match the recomputed value {EXPECTED_MSE}.'

    weights_path = os.path.join(artifact_dir, 'weights.txt')
    assert os.path.isfile(weights_path), 'weights.txt is missing from the artifact directory.'
    with open(weights_path, 'r') as handle:
        weights_str = handle.read().strip()

    parts = weights_str.split(',')
    assert len(parts) == 2, 'weights.txt should contain exactly two comma-separated values.'
    try:
        w1 = float(parts[0])
        w2 = float(parts[1])
    except ValueError:
        pytest.fail('The values in weights.txt are not valid floats.')

    assert 2.5 < w1 < 4.5, f'First weight {w1} is outside expected bounds (should be around 3.5).'
    assert -3.5 < w2 < -1.0, f'Second weight {w2} is outside expected bounds (should be around -2.1).'
    assert weights_str == EXPECTED_WEIGHTS, \
        f'weights.txt is {weights_str!r}, expected {EXPECTED_WEIGHTS!r}.'


def test_source_inputs_are_unchanged():
    with open(SCHEMA_PATH, 'r') as handle:
        actual_schema = json.load(handle)
    assert actual_schema == EXPECTED_SCHEMA, 'schema.json was modified.'
    assert load_jsonl(DATASET_PATH) == ORIGINAL_DATA, 'dataset.jsonl was modified.'


def test_valid_data_jsonl_exists():
    assert os.path.isfile(VALID_DATA_PATH), f'{VALID_DATA_PATH} is missing.'
    records = load_jsonl(VALID_DATA_PATH)
    assert len(records) > 0, f'{VALID_DATA_PATH} is empty.'

    for i, record in enumerate(records):
        assert 'log_id' in record, f"Missing 'log_id' in line {i + 1}"
        assert 'message' in record, f"Missing 'message' in line {i + 1}"
        assert 'features' in record, f"Missing 'features' in line {i + 1}"
        assert 'recovery_time' in record, f"Missing 'recovery_time' in line {i + 1}"
        assert isinstance(record['features'], list) and len(record['features']) == 2, \
            f"'features' is not a list of 2 items in line {i + 1}"

    assert records == EXPECTED_VALID, \
        'valid_data.jsonl does not contain exactly the schema-valid input records in original order.'


@pytest.fixture(scope='module')
def extracted_artifact():
    assert os.path.isfile(TAR_PATH), f'Tarball {TAR_PATH} is missing.'
    with tempfile.TemporaryDirectory() as tmpdir:
        try:
            with tarfile.open(TAR_PATH, 'r:gz') as tar:
                for member in tar.getmembers():
                    normalized = os.path.normpath(member.name)
                    assert not os.path.isabs(member.name), 'Tarball contains an absolute path.'
                    assert normalized != '..' and not normalized.startswith('../'), \
                        'Tarball contains a path outside its extraction root.'
                    assert not member.issym() and not member.islnk(), \
                        'Tarball must not contain symbolic or hard links.'
                tar.extractall(path=tmpdir)
        except (tarfile.TarError, OSError) as error:
            pytest.fail(f'Failed to extract {TAR_PATH}: {error}')

        artifact_dir = os.path.join(tmpdir, 'artifact')
        assert os.path.isdir(artifact_dir), \
            "The tarball does not contain an 'artifact/' directory at its root."
        yield artifact_dir


def test_metrics_json(extracted_artifact):
    assert_artifact_contents(extracted_artifact)


def test_weights_txt(extracted_artifact):
    # The shared assertion retains and strengthens the original weight checks.
    assert_artifact_contents(extracted_artifact)


def test_unpacked_artifact_directory():
    assert os.path.isdir(ARTIFACT_DIR), f'{ARTIFACT_DIR} is missing.'
    assert_artifact_contents(ARTIFACT_DIR)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
