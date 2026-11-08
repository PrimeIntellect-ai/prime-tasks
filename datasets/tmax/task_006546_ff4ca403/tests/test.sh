#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import runpy

import numpy as np
import pandas as pd
import sklearn.model_selection as model_selection

PIPELINE = "/home/user/pipeline.py"
RAW_DATA = "/home/user/raw_data.csv"
OUTPUT = "/home/user/best_alpha.txt"
ALPHAS = [0.1, 1.0, 10.0]


def _contains_ridge(estimator):
    candidates = [estimator]
    if hasattr(estimator, "get_params"):
        try:
            candidates.extend(estimator.get_params(deep=True).values())
        except Exception:
            pass
    return any(
        value.__class__.__name__ == "Ridge"
        and value.__class__.__module__.startswith("sklearn.linear_model")
        for value in candidates
    )


def _alpha_grid_is_correct(param_grid):
    grids = param_grid if isinstance(param_grid, list) else [param_grid]
    alpha_entries = []
    for grid in grids:
        if isinstance(grid, dict):
            for key, values in grid.items():
                if key == "alpha" or key.endswith("__alpha"):
                    try:
                        alpha_entries.extend(float(v) for v in values)
                    except TypeError:
                        return False
    return sorted(alpha_entries) == ALPHAS


def _read_numeric_output():
    assert os.path.isfile(OUTPUT), (
        f"Expected output file {OUTPUT} does not exist. Did you execute the pipeline script?"
    )
    with open(OUTPUT, "r") as f:
        content = f.read().strip()
    assert re.fullmatch(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", content), (
        f"Content of {OUTPUT} is not a plain numerical value: '{content}'"
    )
    try:
        return float(content)
    except ValueError:
        assert False, f"Content of {OUTPUT} is not a valid float: '{content}'"


def _run_instrumented(expected_rows):
    real_grid_search = model_selection.GridSearchCV
    records = []

    def grid_search_spy(*args, **kwargs):
        search = real_grid_search(*args, **kwargs)
        record = {"search": search, "fit": False}
        records.append(record)
        real_fit = search.fit

        def fit_spy(X, y=None, **fit_params):
            record["fit"] = True
            record["x_shape"] = np.asarray(X).shape
            record["x_numeric"] = np.issubdtype(np.asarray(X).dtype, np.number)
            record["y_shape"] = None if y is None else np.asarray(y).shape
            record["y_numeric"] = y is not None and np.issubdtype(np.asarray(y).dtype, np.number)
            if hasattr(X, "columns"):
                record["x_columns"] = list(X.columns)
            return real_fit(X, y, **fit_params)

        search.fit = fit_spy
        return search

    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)

    old_grid_search = model_selection.GridSearchCV
    model_selection.GridSearchCV = grid_search_spy
    try:
        try:
            runpy.run_path(PIPELINE, run_name="__main__")
        except SystemExit as exc:
            assert exc.code in (None, 0), f"pipeline.py exited unsuccessfully: {exc.code}"
    finally:
        model_selection.GridSearchCV = old_grid_search

    output_alpha = _read_numeric_output()
    valid = []
    for record in records:
        search = record["search"]
        if not record["fit"]:
            continue
        if search.cv != 3 or search.scoring != "neg_mean_squared_error":
            continue
        if not _alpha_grid_is_correct(search.param_grid):
            continue
        if not _contains_ridge(search.estimator):
            continue
        valid.append(record)

    assert valid, (
        "pipeline.py must fit GridSearchCV with cv=3, scoring='neg_mean_squared_error', "
        "the alpha grid [0.1, 1.0, 10.0], and a Ridge estimator."
    )

    matching_best = []
    for record in valid:
        search = record["search"]
        assert record["x_shape"] == (expected_rows, 2), (
            "GridSearchCV must receive exactly the cleaned feature_A and feature_B rows."
        )
        assert record["y_shape"] == (expected_rows,), "GridSearchCV received an incorrect target."
        assert record["x_numeric"] and record["y_numeric"], (
            "Features and target passed to GridSearchCV must be numeric."
        )
        if "x_columns" in record:
            assert record["x_columns"] == ["feature_A", "feature_B"], (
                "Only feature_A and feature_B, in that order, may be used as features."
            )
        alpha_keys = [
            key for key in search.best_params_
            if key == "alpha" or key.endswith("__alpha")
        ]
        assert len(alpha_keys) == 1
        matching_best.append(float(search.best_params_[alpha_keys[0]]))

    assert output_alpha in matching_best, (
        f"{OUTPUT} contains {output_alpha}, but the fitted GridSearchCV selected "
        f one of {matching_best}."
    )
    return output_alpha


def _write_noisy_case(seed):
    rng = np.random.RandomState(seed)
    n = 24
    frame = pd.DataFrame({
        "feature_A": rng.normal(size=n),
        "feature_B": rng.normal(size=n),
        "target": rng.normal(size=n),
        "extra_col": rng.normal(size=n) * 100000,
    })
    bad = pd.DataFrame([
        {"feature_A": None, "feature_B": 2.0, "target": 1.0, "extra_col": 7},
        {"feature_A": 1.0, "feature_B": None, "target": 2.0, "extra_col": 8},
        {"feature_A": 1.0, "feature_B": 2.0, "target": None, "extra_col": 9},
        {"feature_A": "not-a-number", "feature_B": 2.0, "target": 3.0, "extra_col": 10},
        {"feature_A": 1.0, "feature_B": "bad", "target": 3.0, "extra_col": 11},
        {"feature_A": 1.0, "feature_B": 2.0, "target": "bad", "extra_col": 12},
    ])
    pd.concat([frame, bad], ignore_index=True).to_csv(RAW_DATA, index=False)
    return n


def test_complete_pipeline_behavior():
    # Preserve the original existence assertion.
    assert os.path.isfile(PIPELINE), (
        f"Expected script {PIPELINE} does not exist. Did you write the pipeline script?"
    )

    with open(RAW_DATA, "rb") as f:
        original_raw = f.read()

    final_output = None
    try:
        original = pd.read_csv(RAW_DATA)
        cleaned = original[["feature_A", "feature_B", "target"]].apply(
            pd.to_numeric, errors="coerce"
        ).dropna()
        original_alpha = _run_instrumented(len(cleaned))

        # Preserve the original expected-result assertion for the supplied data.
        assert original_alpha == 0.1, (
            f"Expected best alpha to be 0.1, but got {original_alpha}. "
            "Check your data cleaning and GridSearchCV setup."
        )
        with open(OUTPUT, "rb") as f:
            final_output = f.read()

        # Exercise the submitted artifact on unseen noisy inputs. At least one
        # case must force a result other than the originally hardcoded answer.
        observed = []
        for seed in (17, 41, 93):
            expected_rows = _write_noisy_case(seed)
            observed.append(_run_instrumented(expected_rows))
        assert any(alpha != 0.1 for alpha in observed), (
            "Dynamic test cases unexpectedly did not distinguish a hardcoded 0.1 output."
        )
    finally:
        with open(RAW_DATA, "wb") as f:
            f.write(original_raw)
        if final_output is not None:
            with open(OUTPUT, "wb") as f:
                f.write(final_output)


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
