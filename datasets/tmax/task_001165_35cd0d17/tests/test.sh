#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import pytest
import numpy as np
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import Ridge
from sklearn.model_selection import GridSearchCV, KFold


def get_expected_valid_rows():
    schema_path = '/home/user/schema.json'
    data_path = '/home/user/raw_data.csv'

    with open(schema_path, 'r') as f:
        schema = json.load(f)

    min_f2 = schema.get("f2", {}).get("min_value", -10.0)
    allowed_cat = set(schema.get("cat", {}).get("allowed_values", [0, 1, 2]))

    valid_count = 0
    with open(data_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                # Check for missing values
                if any(row[k] is None or row[k].strip() == "" for k in ['f1', 'f2', 'cat', 'target']):
                    continue

                f1 = float(row['f1'])
                f2 = float(row['f2'])
                target = float(row['target'])

                # cat must be integer
                cat_str = row['cat']
                if '.' in cat_str:
                    # if it's a float string like '1.0', it might fail strict int parsing depending on interpretation,
                    # but built-in int() raises ValueError for '1.0'. Let's allow float conversion then check if integer.
                    cat_val = float(cat_str)
                    if not cat_val.is_integer():
                        continue
                    cat = int(cat_val)
                else:
                    cat = int(cat_str)

                if f2 <= min_f2:
                    continue

                if cat not in allowed_cat:
                    continue

                valid_count += 1
            except ValueError:
                continue

    return valid_count


def get_expected_model_results():
    with open('/home/user/schema.json', 'r') as f:
        schema = json.load(f)
    with open('/home/user/pipeline_spec.json', 'r') as f:
        spec = json.load(f)

    min_f2 = schema.get("f2", {}).get("min_value", -10.0)
    allowed_cat = set(schema.get("cat", {}).get("allowed_values", [0, 1, 2]))
    features = []
    targets = []

    with open('/home/user/raw_data.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                if any(row[k] is None or row[k].strip() == "" for k in ['f1', 'f2', 'cat', 'target']):
                    continue

                f1 = float(row['f1'])
                f2 = float(row['f2'])
                target = float(row['target'])

                cat_str = row['cat']
                if '.' in cat_str:
                    cat_val = float(cat_str)
                    if not cat_val.is_integer():
                        continue
                    cat = int(cat_val)
                else:
                    cat = int(cat_str)

                if f2 <= min_f2 or cat not in allowed_cat:
                    continue

                features.append([f1, f2, cat])
                targets.append(target)
            except ValueError:
                continue

    X = np.asarray(features, dtype=float)
    y = np.asarray(targets, dtype=float)
    expected = {}

    for seed in [10, 20, 30]:
        pipeline = Pipeline([
            ('StandardScaler', StandardScaler()),
            ('Ridge', Ridge()),
        ])
        search = GridSearchCV(
            pipeline,
            param_grid=spec['param_grid'],
            cv=KFold(n_splits=3, shuffle=True, random_state=seed),
        )
        search.fit(X, y)
        expected[seed] = {
            'best_alpha': search.best_params_['Ridge__alpha'],
            'best_cv_score': round(float(search.best_score_), 4),
        }

    return expected


def test_output_file_exists():
    path = "/home/user/etl_output.json"
    assert os.path.exists(path), f"Output file {path} is missing."
    assert os.path.isfile(path), f"{path} is not a file."


def test_output_structure_and_values():
    path = "/home/user/etl_output.json"
    assert os.path.exists(path), "Cannot test structure, output file missing."

    with open(path, 'r') as f:
        try:
            output = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Output file is not valid JSON.")

    assert "valid_rows_count" in output, "Key 'valid_rows_count' missing from output."
    assert "reproducibility_test" in output, "Key 'reproducibility_test' missing from output."

    # Check valid rows count
    expected_rows = get_expected_valid_rows()
    assert output["valid_rows_count"] == expected_rows, f"Expected {expected_rows} valid rows, got {output['valid_rows_count']}"

    # Check reproducibility test structure
    rep_test = output["reproducibility_test"]
    assert isinstance(rep_test, list), "'reproducibility_test' must be a list."
    assert len(rep_test) == 3, f"Expected 3 results in 'reproducibility_test', got {len(rep_test)}."

    expected_seeds = {10, 20, 30}
    found_seeds = set()

    with open('/home/user/pipeline_spec.json', 'r') as f:
        spec = json.load(f)
    allowed_alphas = set(spec.get("param_grid", {}).get("Ridge__alpha", []))
    expected_model_results = get_expected_model_results()

    for res in rep_test:
        assert "seed" in res, "Missing 'seed' in reproducibility_test item."
        assert "best_alpha" in res, "Missing 'best_alpha' in reproducibility_test item."
        assert "best_cv_score" in res, "Missing 'best_cv_score' in reproducibility_test item."

        seed = res["seed"]
        found_seeds.add(seed)

        alpha = res["best_alpha"]
        assert isinstance(alpha, (int, float)), f"best_alpha must be a number, got {type(alpha)}"
        if allowed_alphas:
            assert alpha in allowed_alphas, f"best_alpha {alpha} is not in the param_grid {allowed_alphas}"

        cv_score = res["best_cv_score"]
        assert isinstance(cv_score, (int, float)), f"best_cv_score must be a number, got {type(cv_score)}"

        # Check if rounded to 4 decimal places
        score_str = str(cv_score)
        if '.' in score_str:
            decimals = len(score_str.split('.')[1])
            assert decimals <= 4, f"best_cv_score {cv_score} is not rounded to 4 decimal places."

        assert seed in expected_model_results, f"Unexpected seed {seed}."
        expected = expected_model_results[seed]
        assert alpha == expected['best_alpha'], (
            f"For seed {seed}, expected best_alpha {expected['best_alpha']}, got {alpha}."
        )
        assert cv_score == expected['best_cv_score'], (
            f"For seed {seed}, expected best_cv_score {expected['best_cv_score']}, got {cv_score}."
        )

    assert found_seeds == expected_seeds, f"Expected seeds {expected_seeds}, but got {found_seeds}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
