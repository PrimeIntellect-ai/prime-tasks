#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile

import pandas as pd
import pytest
from scipy.stats import ttest_ind

PIPELINE = '/home/user/pipeline.py'
REVIEWS = '/home/user/data/reviews.csv'
USERS = '/home/user/data/users.csv'
PROCESSED = '/home/user/processed'
OUTPUTS = {
    'parquet': os.path.join(PROCESSED, 'cleaned.parquet'),
    'top': os.path.join(PROCESSED, 'top_3.json'),
    'stats': os.path.join(PROCESSED, 'stats.json'),
}

CANONICAL_REVIEWS = [
    (101, 1, 'The screen is decent but it lacks brightness.'),
    (102, 2, 'Amazing photos! The battery lasted me two whole days.'),
    (103, 3, 'It broke after a week. Terrible build quality.'),
    (104, 4, 'Great camera, very good battery life overall.'),
    (105, 5, 'Too expensive for what it offers.'),
    (106, 6, 'I love the design and the battery is okay.'),
    (107, 7, 'Not bad, but the camera could be better in low light.'),
    (108, 8, 'Super fast processing, absolutely stunning camera!'),
    (109, 9, 'Worst phone I have ever bought. Screen cracked.'),
    (110, 10, 'Fantastic battery life, camera is top notch.'),
]
CANONICAL_USERS = [
    (1, True), (2, True), (4, True), (6, False),
    (7, True), (8, True), (10, True),
]


def write_inputs(reviews, users):
    os.makedirs(os.path.dirname(REVIEWS), exist_ok=True)
    pd.DataFrame(reviews, columns=['review_id', 'user_id', 'text']).to_csv(REVIEWS, index=False)
    pd.DataFrame(users, columns=['user_id', 'is_verified']).to_csv(USERS, index=False)


def expected_frame(reviews, users):
    reviews_df = pd.DataFrame(reviews, columns=['review_id', 'user_id', 'text'])
    users_df = pd.DataFrame(users, columns=['user_id', 'is_verified'])
    expected = reviews_df.merge(users_df, on='user_id', how='left')
    expected['is_verified'] = expected['is_verified'].fillna(False).astype(bool)
    return expected


def expected_p_value(expected):
    lengths = expected['text'].str.len()
    verified = lengths[expected['is_verified']]
    unverified = lengths[~expected['is_verified']]
    return float(ttest_ind(verified, unverified, equal_var=False).pvalue)


def run_pipeline():
    assert os.path.isfile(PIPELINE), f'{PIPELINE} does not exist or is not a regular file'
    os.makedirs(PROCESSED, exist_ok=True)
    for path in OUTPUTS.values():
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)

    env = os.environ.copy()
    env['HOME'] = '/home/user'
    env.setdefault('HF_HOME', '/home/user/.cache/huggingface')
    result = subprocess.run(
        [sys.executable, PIPELINE],
        cwd='/home/user',
        env=env,
        capture_output=True,
        text=True,
        timeout=600,
    )
    assert result.returncode == 0, (
        f'pipeline.py failed with exit code {result.returncode}\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    for path in OUTPUTS.values():
        assert os.path.isfile(path), f'Pipeline did not create {path}'


@pytest.fixture(scope='session', autouse=True)
def execute_canonical_pipeline():
    write_inputs(CANONICAL_REVIEWS, CANONICAL_USERS)
    run_pipeline()


def assert_cleaned_matches(reviews, users):
    path = OUTPUTS['parquet']
    assert os.path.exists(path), f'{path} does not exist. The ETL pipeline did not save the output.'

    code = f'''\nimport pandas as pd\nimport json\ntry:\n    df = pd.read_parquet({path!r})\n    dtypes = df.dtypes.astype(str).to_dict()\n    nulls = df.isnull().sum().to_dict()\n    print(json.dumps({{"dtypes": dtypes, "nulls": nulls}}))\nexcept Exception as e:\n    print(json.dumps({{"error": str(e)}}))\n'''
    res = subprocess.run([sys.executable, '-c', code], capture_output=True, text=True)
    assert res.returncode == 0, f'Error running pandas check: {res.stderr}'
    try:
        metadata = json.loads(res.stdout)
    except json.JSONDecodeError:
        pytest.fail(f'Failed to parse subprocess output: {res.stdout}')

    assert 'error' not in metadata, f"Failed to read parquet file: {metadata.get('error')}"
    dtypes = metadata['dtypes']
    assert 'review_id' in dtypes, 'review_id column missing from the parquet file'
    assert 'user_id' in dtypes, 'user_id column missing from the parquet file'
    assert 'is_verified' in dtypes, 'is_verified column missing from the parquet file'
    assert 'int' in dtypes['review_id'].lower(), f"review_id is not an integer type, got {dtypes['review_id']}"
    assert 'int' in dtypes['user_id'].lower(), f"user_id is not an integer type, got {dtypes['user_id']}"
    assert metadata['nulls'].get('is_verified', 0) == 0, 'is_verified column still contains null values'

    actual = pd.read_parquet(path)
    expected = expected_frame(reviews, users)
    assert list(actual.columns) == list(expected.columns), (
        f'Expected columns {list(expected.columns)}, got {list(actual.columns)}'
    )
    assert pd.api.types.is_integer_dtype(actual['review_id'].dtype)
    assert pd.api.types.is_integer_dtype(actual['user_id'].dtype)
    assert pd.api.types.is_bool_dtype(actual['is_verified'].dtype), (
        f"is_verified must be boolean, got {actual['is_verified'].dtype}"
    )

    actual_cmp = actual.sort_values('review_id').reset_index(drop=True).copy()
    expected_cmp = expected.sort_values('review_id').reset_index(drop=True).copy()
    actual_cmp['review_id'] = actual_cmp['review_id'].astype('int64')
    actual_cmp['user_id'] = actual_cmp['user_id'].astype('int64')
    actual_cmp['is_verified'] = actual_cmp['is_verified'].astype(bool)
    pd.testing.assert_frame_equal(actual_cmp, expected_cmp, check_dtype=False)


def load_top_3():
    path = OUTPUTS['top']
    assert os.path.exists(path), f'{path} does not exist'
    try:
        with open(path, 'r') as f:
            top_3 = json.load(f)
    except json.JSONDecodeError:
        pytest.fail('top_3.json is not valid JSON')
    assert isinstance(top_3, list), 'top_3.json should contain a JSON list'
    assert len(top_3) == 3, f'Expected exactly 3 review_ids, got {len(top_3)}'
    assert all(type(value) is int for value in top_3), 'All review_ids must be JSON integers'
    return top_3


def load_and_check_stats(expected):
    path = OUTPUTS['stats']
    assert os.path.exists(path), f'{path} does not exist'
    try:
        with open(path, 'r') as f:
            stats = json.load(f)
    except json.JSONDecodeError:
        pytest.fail('stats.json is not valid JSON')
    assert 'p_value' in stats, "stats.json is missing the 'p_value' key"
    p_value = stats['p_value']
    assert isinstance(p_value, float), 'p_value should be a float'
    expected_p = expected_p_value(expected)
    assert math.isclose(p_value, expected_p, rel_tol=1e-9, abs_tol=1e-12), (
        f'Expected p-value {expected_p} from the review text lengths, got {p_value}'
    )


def test_01_parquet_exists_types_rows_and_values():
    assert_cleaned_matches(CANONICAL_REVIEWS, CANONICAL_USERS)


def test_02_top_3_json():
    top_3 = load_top_3()
    expected = [104, 110, 102]
    assert top_3 == expected, f'Expected top 3 review_ids to be {expected}, got {top_3}'


def test_03_stats_json():
    load_and_check_stats(expected_frame(CANONICAL_REVIEWS, CANONICAL_USERS))


def test_99_pipeline_handles_remapped_ids_and_changed_verification_data():
    # The texts are unchanged, so their embedding ranking is unchanged, but review IDs
    # are remapped. Verification flags are also changed so the Welch result must be
    # recomputed rather than copied from the canonical run.
    variant_reviews = [(rid + 1000, uid + 100, text) for rid, uid, text in CANONICAL_REVIEWS]
    variant_users = [
        (101, False), (102, True), (104, False), (106, True),
        (107, False), (108, True), (110, False),
    ]
    expected_variant = expected_frame(variant_reviews, variant_users)

    backup_dir = tempfile.mkdtemp(prefix='canonical_outputs_')
    for name, path in OUTPUTS.items():
        shutil.copy2(path, os.path.join(backup_dir, name))

    try:
        write_inputs(variant_reviews, variant_users)
        run_pipeline()
        assert_cleaned_matches(variant_reviews, variant_users)
        assert load_top_3() == [1104, 1110, 1102]
        load_and_check_stats(expected_variant)
    finally:
        write_inputs(CANONICAL_REVIEWS, CANONICAL_USERS)
        for name, path in OUTPUTS.items():
            backup = os.path.join(backup_dir, name)
            if os.path.exists(backup):
                shutil.copy2(backup, path)
        shutil.rmtree(backup_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
