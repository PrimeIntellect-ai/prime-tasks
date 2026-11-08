#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import math
import pandas as pd
from sklearn.linear_model import Ridge


def test_cleaned_test_exists_and_format():
    cleaned_path = "/home/user/cleaned_test.csv"
    assert os.path.isfile(cleaned_path), f"File {cleaned_path} does not exist"

    with open(cleaned_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        fieldnames = reader.fieldnames
        assert fieldnames is not None, "Cleaned test CSV is empty"
        assert set(fieldnames) == {'id', 'category', 'feature_A', 'feature_B'}, "Cleaned test CSV columns do not match expected"

        rows = list(reader)
        assert len(rows) == 3, "Cleaned test CSV should have exactly 3 rows"

        # Check specific imputed values and integer format
        id_to_feature_A = {row['id']: row['feature_A'] for row in rows}

        assert '8' in id_to_feature_A, "ID 8 missing in cleaned_test.csv"
        assert '9' in id_to_feature_A, "ID 9 missing in cleaned_test.csv"
        assert '10' in id_to_feature_A, "ID 10 missing in cleaned_test.csv"

        # Values should be string representation of integers (no decimals)
        assert id_to_feature_A['8'] == '11', f"Expected feature_A for ID 8 to be '11', got '{id_to_feature_A['8']}'"
        assert id_to_feature_A['9'] == '9', f"Expected feature_A for ID 9 to be '9', got '{id_to_feature_A['9']}'"
        assert id_to_feature_A['10'] == '5', f"Expected feature_A for ID 10 to be '5', got '{id_to_feature_A['10']}'"


def expected_predictions():
    train = pd.read_csv('/home/user/data/train.csv')
    test = pd.read_csv('/home/user/data/test.csv')

    category_medians = train.groupby('category')['feature_A'].median()
    train['feature_A'] = train['feature_A'].fillna(
        train['category'].map(category_medians)
    ).astype('int64')
    test['feature_A'] = test['feature_A'].fillna(
        test['category'].map(category_medians)
    ).astype('int64')

    train_features = pd.concat([
        train[['feature_A', 'feature_B']],
        pd.get_dummies(train['category'], prefix='category', drop_first=False),
    ], axis=1)
    test_features = pd.concat([
        test[['feature_A', 'feature_B']],
        pd.get_dummies(test['category'], prefix='category', drop_first=False),
    ], axis=1)
    test_features = test_features.reindex(columns=train_features.columns, fill_value=0)

    model = Ridge()
    model.fit(train_features, train['target'])
    predictions = model.predict(test_features)
    return {str(row_id): float(prediction) for row_id, prediction in zip(test['id'], predictions)}


def test_predictions_exists_and_format():
    preds_path = "/home/user/predictions.csv"
    assert os.path.isfile(preds_path), f"File {preds_path} does not exist"

    with open(preds_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        fieldnames = reader.fieldnames
        assert fieldnames is not None, "Predictions CSV is empty"
        assert set(fieldnames) == {'id', 'target'}, "Predictions CSV columns must be exactly 'id' and 'target'"

        rows = list(reader)
        assert len(rows) == 3, "Predictions CSV should have exactly 3 rows"

        ids = {row['id'] for row in rows}
        assert ids == {'8', '9', '10'}, f"Predictions CSV should contain IDs 8, 9, and 10, got {ids}"

        # Check that targets are valid floats
        parsed_predictions = {}
        for row in rows:
            try:
                parsed_predictions[row['id']] = float(row['target'])
            except ValueError:
                assert False, f"Target value '{row['target']}' for ID {row['id']} is not a valid float"

        # Verify that the targets are the predictions from the required Ridge pipeline.
        expected = expected_predictions()
        for row_id, expected_target in expected.items():
            actual_target = parsed_predictions[row_id]
            assert math.isfinite(actual_target), f"Target for ID {row_id} must be finite"
            assert math.isclose(actual_target, expected_target, rel_tol=1e-7, abs_tol=1e-7), (
                f"Incorrect Ridge prediction for ID {row_id}: expected {expected_target}, got {actual_target}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
