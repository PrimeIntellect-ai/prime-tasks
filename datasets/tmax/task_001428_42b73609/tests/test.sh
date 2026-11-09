#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import pytest
import pandas as pd
import joblib
from sklearn.metrics import mean_absolute_error
from sklearn.pipeline import Pipeline
from sklearn.compose import ColumnTransformer
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.decomposition import TruncatedSVD


def test_redis_status():
    """Verify that the agent successfully connected to Redis and set the status key."""
    try:
        import redis
        r = redis.Redis(host='localhost', port=6379, decode_responses=True)
        status = r.get('pipeline_status')
        assert status == 'success', f"Expected Redis key 'pipeline_status' to be 'success', got {status}"
    except ImportError:
        result = subprocess.run(['redis-cli', 'get', 'pipeline_status'], capture_output=True, text=True)
        assert result.returncode == 0, "Failed to connect to Redis using redis-cli."
        output = result.stdout.strip()
        assert 'success' in output, f"Expected Redis key 'pipeline_status' to contain 'success', got {output}"
    except Exception as e:
        pytest.fail(f"Redis connection or assertion failed: {e}")


def _walk_estimators(obj, seen=None):
    if seen is None:
        seen = set()
    if id(obj) in seen:
        return
    seen.add(id(obj))
    yield obj
    if isinstance(obj, Pipeline):
        for _, child in obj.steps:
            yield from _walk_estimators(child, seen)
    elif isinstance(obj, ColumnTransformer):
        transformers = getattr(obj, 'transformers_', obj.transformers)
        for _, child, _ in transformers:
            if child not in ('drop', 'passthrough'):
                yield from _walk_estimators(child, seen)
    for attr in ('transformer', 'transformer_', 'estimator', 'estimator_'):
        child = getattr(obj, attr, None)
        if child is not None and child is not obj:
            yield from _walk_estimators(child, seen)


def test_pipeline_evaluation_metric():
    """Verify structure, raw-input prediction, and MAE on the held-out oracle."""
    pipeline_path = '/home/user/final_pipeline.pkl'
    assert os.path.isfile(pipeline_path), f"Final pipeline file not found at {pipeline_path}"
    try:
        pipeline = joblib.load(pipeline_path)
    except Exception as e:
        pytest.fail(f"Failed to load the pipeline from {pipeline_path} using joblib. Error: {e}")

    assert isinstance(pipeline, Pipeline), "Saved artifact must be an sklearn Pipeline"
    components = list(_walk_estimators(pipeline))
    assert any(isinstance(x, ColumnTransformer) for x in components), "Pipeline must contain a ColumnTransformer"
    assert any(isinstance(x, TfidfVectorizer) for x in components), "Pipeline must contain TF-IDF"
    assert any(isinstance(x, TruncatedSVD) for x in components), "Pipeline must contain TruncatedSVD"
    assert any('targetencoder' in type(x).__name__.lower() for x in components), "Pipeline must contain a target encoder"

    hidden_data_path = '/tests/hidden_data.csv'
    assert os.path.isfile(hidden_data_path), f"Hidden test data not found at {hidden_data_path}"
    hidden_df = pd.read_csv(hidden_data_path)
    X_hidden = hidden_df[['description', 'category']]
    y_hidden = hidden_df['price']
    try:
        preds = pipeline.predict(X_hidden)
    except Exception as e:
        pytest.fail(f"Pipeline failed to predict on raw hidden data: {e}")
    mae = mean_absolute_error(y_hidden, preds)
    assert mae < 45.0, f"Pipeline MAE on hidden test set is {mae:.2f}, not strictly less than 45.0."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
