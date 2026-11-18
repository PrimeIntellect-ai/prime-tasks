#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import builtins
import json
import math
import os
import subprocess
import sys
import textwrap

import pandas as pd
import pytest
from sklearn.linear_model import Ridge
from sklearn.model_selection import GridSearchCV

PIPELINE_PATH = "/home/user/pipeline.py"
RESULTS_PATH = "/home/user/experiment_results.json"
USERS_PATH = "/home/user/users.csv"
TRANSACTIONS_PATH = "/home/user/transactions.csv"
ALPHAS = [0.1, 1.0, 10.0]


def run_pipeline(env=None, command=None):
    result = subprocess.run(
        command or [sys.executable, PIPELINE_PATH],
        capture_output=True,
        text=True,
        env=env,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"pipeline.py execution failed with error:\n{result.stderr}\n"
        f"stdout:\n{result.stdout}"
    )
    assert os.path.exists(RESULTS_PATH), (
        "pipeline.py did not generate experiment_results.json upon execution"
    )
    with open(RESULTS_PATH) as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Generated {RESULTS_PATH} is not valid JSON")


def assert_result_shape(data):
    assert set(data) == {"best_alpha", "best_score"}, (
        "Results JSON must contain exactly best_alpha and best_score"
    )
    assert isinstance(data["best_alpha"], (int, float)) and not isinstance(data["best_alpha"], bool)
    assert isinstance(data["best_score"], (int, float)) and not isinstance(data["best_score"], bool)
    assert math.isfinite(float(data["best_alpha"]))
    assert math.isfinite(float(data["best_score"]))


def test_pipeline_script_exists():
    assert os.path.exists(PIPELINE_PATH), f"File missing: {PIPELINE_PATH}"
    assert os.path.isfile(PIPELINE_PATH), f"Not a regular file: {PIPELINE_PATH}"
    with open(PIPELINE_PATH) as f:
        ast.parse(f.read(), filename=PIPELINE_PATH)


def test_pipeline_script_env_vars():
    with open(PIPELINE_PATH, "r") as f:
        code = f.read()

    assert "OMP_NUM_THREADS" in code, "OMP_NUM_THREADS not found in pipeline.py"
    assert "OPENBLAS_NUM_THREADS" in code, "OPENBLAS_NUM_THREADS not found in pipeline.py"
    assert "MKL_NUM_THREADS" in code, "MKL_NUM_THREADS not found in pipeline.py"
    assert "os.environ" in code, "Thread settings must be made using os.environ"


def test_experiment_results_json():
    assert os.path.exists(RESULTS_PATH), f"Results file missing: {RESULTS_PATH}"

    with open(RESULTS_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS_PATH} is not valid JSON")

    assert "best_alpha" in data, "Missing key 'best_alpha' in results JSON"
    assert "best_score" in data, "Missing key 'best_score' in results JSON"
    assert isinstance(data["best_alpha"], (int, float)), "'best_alpha' must be numeric"
    assert isinstance(data["best_score"], (int, float)), "'best_score' must be numeric"
    assert_result_shape(data)


def test_pipeline_execution():
    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)

    data = run_pipeline()
    assert "best_alpha" in data, "Missing key 'best_alpha' in regenerated results JSON"
    assert "best_score" in data, "Missing key 'best_score' in regenerated results JSON"
    assert_result_shape(data)


def test_thread_variables_are_one_before_numerical_imports():
    wrapper = textwrap.dedent(f"""
        import builtins, json, os, runpy
        wanted = {{'OMP_NUM_THREADS', 'OPENBLAS_NUM_THREADS', 'MKL_NUM_THREADS'}}
        seen = set()
        real_import = builtins.__import__
        def checked_import(name, globals=None, locals=None, fromlist=(), level=0):
            root = name.split('.')[0]
            if root in {{'pandas', 'numpy', 'sklearn'}}:
                assert all(os.environ.get(k) == '1' for k in wanted), \\
                    'thread environment variables were not all 1 before importing ' + name
                seen.add(root)
            return real_import(name, globals, locals, fromlist, level)
        builtins.__import__ = checked_import
        runpy.run_path({PIPELINE_PATH!r}, run_name='__main__')
        assert 'pandas' in seen, 'pipeline did not import pandas'
        assert 'sklearn' in seen, 'pipeline did not import scikit-learn'
    """)
    env = os.environ.copy()
    for name in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS"):
        env[name] = "9"
    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)
    data = run_pipeline(env=env, command=[sys.executable, "-c", wrapper])
    assert_result_shape(data)


def test_required_estimator_grid_folds_features_and_target_are_used():
    wrapper = textwrap.dedent(f"""
        import json, os, runpy
        import pandas as pd
        import sklearn.linear_model as lm
        import sklearn.model_selection as ms
        from pandas.testing import assert_frame_equal

        expected = pd.read_csv({USERS_PATH!r}).merge(
            pd.read_csv({TRANSACTIONS_PATH!r}), on='user_id', how='inner'
        )

        class SpyRidge:
            def __init__(self, *args, **kwargs):
                self.args = args
                self.kwargs = kwargs

        class SpyGridSearchCV:
            def __init__(self, estimator, param_grid, *args, **kwargs):
                cv = kwargs.get('cv', args[0] if args else None)
                assert isinstance(estimator, SpyRidge), 'GridSearchCV estimator must be Ridge'
                assert param_grid == {{'alpha': [0.1, 1.0, 10.0]}}, 'incorrect alpha grid'
                assert cv == 3, 'GridSearchCV must use cv=3'
                self.best_params_ = {{'alpha': 7.25}}
                self.best_score_ = 0.3141592653589793

            def fit(self, X, y, *args, **kwargs):
                assert list(X.columns) == ['age', 'signup_days', 'txn_count'], \\
                    'X must contain age, signup_days, txn_count in that order'
                assert getattr(y, 'name', None) == 'total_spend', \\
                    'y must be the total_spend column'
                actual = X.reset_index(drop=True).copy()
                actual['total_spend'] = y.reset_index(drop=True)
                wanted = expected[['age', 'signup_days', 'txn_count', 'total_spend']].copy()
                cols = ['age', 'signup_days', 'txn_count', 'total_spend']
                actual = actual.sort_values(cols).reset_index(drop=True)
                wanted = wanted.sort_values(cols).reset_index(drop=True)
                assert_frame_equal(actual, wanted, check_dtype=False)
                return self

        lm.Ridge = SpyRidge
        ms.GridSearchCV = SpyGridSearchCV
        runpy.run_path({PIPELINE_PATH!r}, run_name='__main__')
        with open({RESULTS_PATH!r}) as f:
            result = json.load(f)
        assert result == {{'best_alpha': 7.25, 'best_score': 0.3141592653589793}}, \\
            'pipeline must write GridSearchCV best_params_ and best_score_'
    """)
    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)
    data = run_pipeline(command=[sys.executable, "-c", wrapper])
    assert data == {"best_alpha": 7.25, "best_score": 0.3141592653589793}


def expected_result(users, transactions):
    joined = users.merge(transactions, on="user_id", how="inner")
    X = joined[["age", "signup_days", "txn_count"]]
    y = joined["total_spend"]
    search = GridSearchCV(Ridge(), {"alpha": ALPHAS}, cv=3)
    search.fit(X, y)
    return float(search.best_params_["alpha"]), float(search.best_score_)


def test_pipeline_matches_independently_computed_results_on_changed_inputs():
    with open(USERS_PATH, "rb") as f:
        old_users = f.read()
    with open(TRANSACTIONS_PATH, "rb") as f:
        old_transactions = f.read()

    cases = []
    for offset, scale in [(100, 1.0), (500, 2.7)]:
        ids = list(range(offset, offset + 12))
        users = pd.DataFrame({
            "user_id": ids + [offset + 90],
            "age": [19 + ((i * 7) % 43) for i in range(12)] + [99],
            "signup_days": [15 + i * i * 3 for i in range(12)] + [9999],
        })
        transactions = pd.DataFrame({
            "user_id": list(reversed(ids)) + [offset + 91],
            "total_spend": [
                scale * (37.0 + 4.3 * i + (i % 4) * 17.5 + (i * i) * 0.8)
                for i in reversed(range(12))
            ] + [123456.0],
            "txn_count": [2 + ((i * 5) % 19) for i in reversed(range(12))] + [777],
        })
        cases.append((users, transactions))

    try:
        for users, transactions in cases:
            users.to_csv(USERS_PATH, index=False)
            transactions.to_csv(TRANSACTIONS_PATH, index=False)
            wanted_alpha, wanted_score = expected_result(users, transactions)
            if os.path.exists(RESULTS_PATH):
                os.remove(RESULTS_PATH)
            actual = run_pipeline()
            assert_result_shape(actual)
            assert float(actual["best_alpha"]) == pytest.approx(wanted_alpha, abs=1e-12)
            assert float(actual["best_score"]) == pytest.approx(
                wanted_score, rel=1e-10, abs=1e-10
            )
    finally:
        with open(USERS_PATH, "wb") as f:
            f.write(old_users)
        with open(TRANSACTIONS_PATH, "wb") as f:
            f.write(old_transactions)

    # Leave the required output consistent with the restored original datasets.
    final_data = run_pipeline()
    assert_result_shape(final_data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
