#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import numpy as np
import pandas as pd
from pandas.testing import assert_frame_equal
from sklearn.linear_model import LogisticRegression

OUTPUT_PATH = '/home/user/processed_data.parquet'
TRAIN_PATH = '/home/user/train.parquet'
INCOMING_PATH = '/home/user/incoming.parquet'


def canonical_inputs():
    # Independently reproduce the immutable task inputs so submissions cannot
    # weaken verification by replacing train.parquet or incoming.parquet.
    np.random.seed(42)

    n_train = 1000
    f1_train = np.random.uniform(0.1, 10, n_train)
    f2_train = np.random.normal(0, 1, n_train)
    f3_train = np.random.uniform(0, 99, n_train)
    z = 0.5 * f1_train - 1.2 * f2_train + 0.05 * f3_train - 2.0
    p = 1 / (1 + np.exp(-z))
    label_train = np.random.binomial(1, p)
    train = pd.DataFrame({
        'f1': f1_train,
        'f2': f2_train,
        'f3': f3_train,
        'label': label_train,
    })

    n_inc = 100
    f1_inc = np.random.uniform(0.1, 10, n_inc)
    f2_inc = np.random.normal(0, 1, n_inc)
    f3_inc = np.random.uniform(0, 99, n_inc)
    f1_inc[5] = -1.0
    f1_inc[12] = 0.0
    f3_inc[45] = 105.0
    f3_inc[88] = 100.0
    incoming = pd.DataFrame({
        'id': range(n_inc),
        'f1': f1_inc,
        'f2': f2_inc,
        'f3': f3_inc,
    })
    return train, incoming


def test_processed_data_exists():
    assert os.path.exists(OUTPUT_PATH), f'Error: {OUTPUT_PATH} does not exist.'
    assert os.path.isfile(OUTPUT_PATH), f'Error: {OUTPUT_PATH} is not a file.'


def test_processed_data_content():
    assert os.path.exists(OUTPUT_PATH), 'Output file missing, cannot verify content.'

    expected_train, expected_incoming = canonical_inputs()
    train = pd.read_parquet(TRAIN_PATH)
    incoming = pd.read_parquet(INCOMING_PATH)
    assert_frame_equal(train.reset_index(drop=True), expected_train, check_exact=True)
    assert_frame_equal(incoming.reset_index(drop=True), expected_incoming, check_exact=True)

    model = LogisticRegression(random_state=42)
    model.fit(train[['f1', 'f2', 'f3']], train['label'])

    valid = incoming.loc[
        (incoming['f1'] > 0) & (incoming['f3'] < 100),
        ['id', 'f1', 'f2', 'f3'],
    ].copy()
    features = valid[['f1', 'f2', 'f3']]
    valid['predicted_label'] = model.predict(features)
    positive_index = list(model.classes_).index(1)
    valid['probability'] = model.predict_proba(features)[:, positive_index]

    actual = pd.read_parquet(OUTPUT_PATH)

    # Preserve the original structural and range assertions.
    assert len(actual) == 96, f'Expected 96 rows, found {len(actual)}'
    expected_columns = {'id', 'f1', 'f2', 'f3', 'predicted_label', 'probability'}
    assert set(actual.columns) == expected_columns, (
        f'Columns do not match expected schema. Found {list(actual.columns)}'
    )
    assert actual['probability'].between(0, 1).all(), (
        'Invalid probabilities found (not between 0 and 1).'
    )

    # Compare by preserved ID so an otherwise equivalent row order is accepted.
    actual = actual.sort_values('id', kind='stable').reset_index(drop=True)
    valid = valid.sort_values('id', kind='stable').reset_index(drop=True)

    assert_frame_equal(
        actual[['id', 'f1', 'f2', 'f3']],
        valid[['id', 'f1', 'f2', 'f3']],
        check_exact=True,
        check_dtype=True,
    )
    np.testing.assert_array_equal(
        actual['predicted_label'].to_numpy(),
        valid['predicted_label'].to_numpy(),
    )
    np.testing.assert_allclose(
        actual['probability'].to_numpy(dtype=float),
        valid['probability'].to_numpy(dtype=float),
        rtol=1e-10,
        atol=1e-12,
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
