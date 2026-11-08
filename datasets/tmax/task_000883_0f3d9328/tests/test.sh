#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile

import matplotlib.image as mpimg
import numpy as np
import pandas as pd
import pytest
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score, f1_score
from sklearn.model_selection import train_test_split

PIPELINE = '/home/user/pipeline.py'
DATA = '/home/user/sensor_data.csv'
METRICS = '/home/user/metrics.json'
IMAGE = '/home/user/importance.png'
USER_TEST = '/home/user/test_pipeline.py'


@pytest.fixture(scope='session', autouse=True)
def execute_pipeline():
    assert os.path.isfile(PIPELINE), f'File {PIPELINE} missing.'
    assert os.path.isfile(DATA), f'File {DATA} missing.'

    for path in (METRICS, IMAGE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    # Override the environment default so the script itself must select Agg.
    env = os.environ.copy()
    env['MPLBACKEND'] = 'svg'
    code = (
        "import runpy, matplotlib; "
        f"runpy.run_path({PIPELINE!r}, run_name='__main__'); "
        "print('__VERIFIER_BACKEND__=' + str(matplotlib.get_backend()))"
    )
    result = subprocess.run(
        [sys.executable, '-c', code],
        cwd='/home/user', env=env, capture_output=True, text=True, timeout=120
    )
    assert result.returncode == 0, (
        f'Running {PIPELINE} failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}'
    )
    marker = [line for line in result.stdout.splitlines()
              if line.startswith('__VERIFIER_BACKEND__=')]
    assert marker, 'Could not determine the matplotlib backend used by pipeline.py.'
    assert marker[-1].split('=', 1)[1].strip().lower() == 'agg', (
        'pipeline.py did not use the Agg matplotlib backend.'
    )
    return result


def load_pipeline_module():
    spec = importlib.util.spec_from_file_location('submitted_pipeline', PIPELINE)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def assert_valid_one_hot(cleaned, categories):
    encoded_columns = [
        column for column in cleaned.columns
        if column not in {'temperature', 'vibration', 'failure'}
    ]
    assert len(encoded_columns) == len(set(categories)), (
        'clean_data must create one one-hot column for every sensor_type category.'
    )

    encoded = cleaned[encoded_columns]
    assert not encoded.isnull().any().any()
    values = encoded.to_numpy()
    assert np.all(np.isin(values, [0, 1, False, True])), 'One-hot values must be binary.'
    assert np.all(values.astype(int).sum(axis=1) == 1), (
        'Each row must have exactly one active sensor_type one-hot column.'
    )

    vectors = {}
    for row_number, category in enumerate(categories):
        vector = tuple(values[row_number].astype(int).tolist())
        if category in vectors:
            assert vectors[category] == vector
        else:
            vectors[category] = vector
    assert len(set(vectors.values())) == len(set(categories)), (
        'Different sensor_type categories must have different one-hot vectors.'
    )


def test_clean_data_behavior():
    module = load_pipeline_module()
    source = pd.DataFrame({
        'temperature': [1.0, np.nan, 100.0, 4.0, 8.0],
        'vibration': [np.nan, 2.0, 9.0, 4.0, np.nan],
        'sensor_type': ['alpha', 'beta', 'alpha', 'gamma', 'beta'],
        'failure': [1, 0, 1, 0, 1],
    })
    original_target = source['failure'].copy(deep=True)
    cleaned = module.clean_data(source.copy(deep=True))

    assert isinstance(cleaned, pd.DataFrame), 'clean_data must return a pandas DataFrame.'
    assert len(cleaned) == len(source), 'clean_data changed the number of rows.'
    assert 'sensor_type' not in cleaned.columns, 'The original sensor_type column was not dropped.'
    assert set(['temperature', 'vibration', 'failure']).issubset(cleaned.columns)
    assert not cleaned.isnull().any().any(), 'clean_data output still contains null values.'
    pd.testing.assert_series_equal(
        cleaned['failure'].reset_index(drop=True),
        original_target.reset_index(drop=True),
        check_names=False,
    )
    assert cleaned.loc[1, 'temperature'] == pytest.approx(6.0)
    assert cleaned.loc[0, 'vibration'] == pytest.approx(4.0)
    assert cleaned.loc[4, 'vibration'] == pytest.approx(4.0)
    assert_valid_one_hot(cleaned, source['sensor_type'].tolist())


def test_importance_png_exists():
    path = IMAGE
    assert os.path.isfile(path), f"File {path} does not exist. The plot was not saved correctly."
    assert os.path.getsize(path) > 0, f"File {path} is empty."

    # Preserve the original PNG signature assertion.
    with open(path, 'rb') as f:
        header = f.read(8)
    assert header == b'\x89PNG\r\n\x1a\n', f"File {path} is not a valid PNG image."

    image = mpimg.imread(path)
    assert image.ndim in (2, 3) and image.shape[0] > 1 and image.shape[1] > 1
    assert np.isfinite(image).all(), 'The generated PNG contains invalid pixel values.'
    assert float(np.var(image)) > 0, 'The generated feature-importance image is blank.'


def test_metrics_json():
    path = METRICS
    assert os.path.isfile(path), f"File {path} does not exist. Metrics were not saved."

    with open(path, 'r') as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} is not valid JSON.")

    assert "accuracy" in metrics, "Key 'accuracy' missing in metrics.json"
    assert "f1_score" in metrics, "Key 'f1_score' missing in metrics.json"
    assert set(metrics) == {'accuracy', 'f1_score'}, 'metrics.json must have exactly the required keys.'
    assert isinstance(metrics["accuracy"], (int, float)), "'accuracy' must be a numeric value"
    assert isinstance(metrics["f1_score"], (int, float)), "'f1_score' must be a numeric value"
    assert math.isfinite(metrics['accuracy']) and 0 <= metrics['accuracy'] <= 1
    assert math.isfinite(metrics['f1_score']) and 0 <= metrics['f1_score'] <= 1

    # Independently reproduce the prescribed validation from the verified cleaning output.
    module = load_pipeline_module()
    cleaned = module.clean_data(pd.read_csv(DATA))
    X = cleaned.drop('failure', axis=1)
    y = cleaned['failure']
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )
    model = RandomForestClassifier(random_state=42)
    model.fit(X_train, y_train)
    predictions = model.predict(X_test)
    expected_accuracy = accuracy_score(y_test, predictions)
    expected_f1 = f1_score(y_test, predictions, average='macro')

    assert metrics['accuracy'] == pytest.approx(expected_accuracy, abs=1e-12)
    assert metrics['f1_score'] == pytest.approx(expected_f1, abs=1e-12)


def test_pipeline_headless_config():
    path = PIPELINE
    assert os.path.isfile(path), f"File {path} missing."

    with open(path, 'r') as f:
        content = f.read()

    # Preserve the original source assertion and also ensure display was replaced.
    assert 'savefig' in content, "plt.savefig is not used in pipeline.py"
    tree = ast.parse(content)
    show_calls = [
        node for node in ast.walk(tree)
        if isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr == 'show'
    ]
    assert not show_calls, 'pipeline.py must save the plot instead of calling show().'


def test_pytest_execution():
    test_file = USER_TEST
    assert os.path.isfile(test_file), f"Test file {test_file} does not exist."

    result = subprocess.run(['pytest', test_file], capture_output=True, text=True, timeout=120)
    assert result.returncode == 0, f"pytest {test_file} failed with output:\n{result.stdout}\n{result.stderr}"
    assert 'test_clean_data' in result.stdout or 'test_clean_data' in open(test_file).read(), "test_clean_data not found in test file or execution."

    # Mutation-check the submitted test: an unchanged clean_data implementation must
    # cause the required test to fail, ruling out a vacuous passing test.
    with tempfile.TemporaryDirectory() as temp_dir:
        copied_test = os.path.join(temp_dir, 'test_pipeline.py')
        shutil.copy2(test_file, copied_test)
        fake_pipeline = os.path.join(temp_dir, 'pipeline.py')
        with open(fake_pipeline, 'w') as f:
            f.write(
                "import importlib.util\n"
                f"_spec = importlib.util.spec_from_file_location('_real_pipeline', {PIPELINE!r})\n"
                "_real = importlib.util.module_from_spec(_spec)\n"
                "_spec.loader.exec_module(_real)\n"
                "for _name in dir(_real):\n"
                "    if not _name.startswith('__'):\n"
                "        globals()[_name] = getattr(_real, _name)\n"
                "def clean_data(df):\n"
                "    return df\n"
            )
        env = os.environ.copy()
        env['PYTHONPATH'] = temp_dir + os.pathsep + '/home/user'
        mutant = subprocess.run(
            [sys.executable, '-m', 'pytest', '-q', copied_test],
            cwd=temp_dir, env=env, capture_output=True, text=True, timeout=120
        )
        assert mutant.returncode == 1, (
            'test_clean_data does not fail when clean_data leaves missing values and '
            f'sensor_type unchanged. Output:\n{mutant.stdout}\n{mutant.stderr}'
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
