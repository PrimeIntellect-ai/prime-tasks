#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import stat
import subprocess
import sys

import pandas as pd

ETL_PATH = '/home/user/etl.py'
PROFILES_PATH = '/home/user/profiles.csv'
LOGS_PATH = '/home/user/logs.csv'
PARQUET_PATH = '/home/user/output.parquet'
TXT_PATH = '/home/user/similar_users.txt'
EXPECTED_COLUMNS = ['user_id', 'activity_score', 'feat1', 'feat2', 'feat3']


def canonical_inputs():
    profiles = pd.DataFrame([
        [100, 5, 4, 6],
        [101, 4, 3, 5],
        [102, 1, 5, 1],
        [103, 6, 5, 7],
        [105, 2, 1, 3],
    ], columns=['user_id', 'feat1', 'feat2', 'feat3'])
    logs = pd.DataFrame([
        [100, 10],
        [101, 8],
        [102, 2],
        [103, 9],
        [104, 5],
        [105, 3],
    ], columns=['user_id', 'activity_score'])
    return profiles, logs


def varied_inputs():
    ids = set()
    while len(ids) < 6:
        ids.add(1_000_000 + secrets.randbelow(8_000_000))
    a, b, c, d, e, missing = list(ids)

    profiles = pd.DataFrame([
        [100, 1, 2, 4],
        [a, 2, 4, 8],
        [b, 1, 2, 5],
        [c, 2, 5, 4],
        [d, 4, 2, 1],
        [e, 1, 5, 2],
    ], columns=['user_id', 'feat1', 'feat2', 'feat3'])
    logs = pd.DataFrame([
        [100, 17],
        [a, 11],
        [b, 23],
        [c, 7],
        [d, 19],
        [e, 29],
        [missing, 13],
    ], columns=['user_id', 'activity_score'])
    return profiles, logs


def write_inputs(profiles, logs):
    profiles.to_csv(PROFILES_PATH, index=False)
    logs.to_csv(LOGS_PATH, index=False)


def expected_results(profiles, logs):
    expected = pd.merge(logs, profiles, on='user_id', how='left')
    feature_cols = ['feat1', 'feat2', 'feat3']
    expected[feature_cols] = expected[feature_cols].fillna(0)
    expected[EXPECTED_COLUMNS] = expected[EXPECTED_COLUMNS].astype('int64')

    features = expected.set_index('user_id')[feature_cols]
    corr = features.T.corr()
    ranked = corr[100].sort_values(ascending=False).dropna()
    ranked = ranked[ranked.index != 100]
    similar = [int(uid) for uid in ranked.index[:3]]
    return expected, similar, corr


def run_pipeline():
    for path in (PARQUET_PATH, TXT_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        [sys.executable, ETL_PATH],
        cwd='/home/user',
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'etl.py failed with exit code {result.returncode}\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def validate_outputs(profiles, logs, canonical=False):
    expected, expected_similar, corr = expected_results(profiles, logs)

    assert os.path.exists(PARQUET_PATH), f'Output parquet file is missing: {PARQUET_PATH}'
    try:
        actual = pd.read_parquet(PARQUET_PATH)
    except Exception as exc:
        raise AssertionError(f'Failed to read parquet file: {exc}') from exc

    for col in EXPECTED_COLUMNS:
        assert col in actual.columns, f'Missing column: {col}'
        assert str(actual[col].dtype) == 'int64', (
            f'Column {col} has incorrect type: {actual[col].dtype} (expected int64)'
        )
    assert set(actual.columns) == set(EXPECTED_COLUMNS), (
        f'Unexpected final columns: {list(actual.columns)}'
    )
    assert not actual[EXPECTED_COLUMNS].isna().any().any(), 'Final DataFrame contains missing values'

    actual_cmp = actual[EXPECTED_COLUMNS].sort_values(EXPECTED_COLUMNS).reset_index(drop=True)
    expected_cmp = expected[EXPECTED_COLUMNS].sort_values(EXPECTED_COLUMNS).reset_index(drop=True)
    pd.testing.assert_frame_equal(actual_cmp, expected_cmp, check_dtype=True)

    missing_ids = set(logs['user_id']) - set(profiles['user_id'])
    for uid in missing_ids:
        row = actual[actual['user_id'] == uid]
        assert len(row) == 1, f'Expected exactly one merged row for missing-profile user {uid}'
        assert (row.iloc[0][['feat1', 'feat2', 'feat3']] == 0).all(), (
            f'Missing features for user {uid} were not all filled with 0'
        )

    if canonical:
        user_104 = actual[actual['user_id'] == 104]
        assert not user_104.empty, 'Merged output is missing user 104'
        assert user_104.iloc[0]['feat1'] == 0, 'Missing features for user 104 were not filled with 0.'

    assert os.path.exists(TXT_PATH), f'Output file missing: {TXT_PATH}'
    with open(TXT_PATH, 'r', encoding='utf-8') as handle:
        content = handle.read().strip()
    assert content, 'The similar_users.txt file is empty.'

    raw_users = content.split(',')
    assert len(raw_users) == 3, f'Expected exactly 3 similar users, but found {len(raw_users)}: {raw_users}'
    users = []
    for value in raw_users:
        value = value.strip()
        assert re.fullmatch(r'-?\d+', value), f'Invalid integer user_id in similar_users.txt: {value!r}'
        users.append(int(value))

    assert users == expected_similar, (
        f'Users are not the top 3 in descending Pearson similarity order: '
        f'expected {expected_similar}, got {users}'
    )
    assert 100 not in users, 'Target user 100 must be excluded from similar_users.txt'
    scores = [corr.loc[uid, 100] for uid in users]
    assert all(scores[i] >= scores[i + 1] for i in range(len(scores) - 1)), (
        f'Users are not in descending similarity order: {users}'
    )

    if canonical:
        expected_users = {'101', '103', '105'}
        actual_users = {str(uid) for uid in users}
        assert actual_users == expected_users, (
            f'Expected similar users {expected_users}, but got {actual_users}'
        )


def test_pipeline_artifact_and_outputs():
    assert os.path.lexists(ETL_PATH), f'Missing required script: {ETL_PATH}'
    mode = os.lstat(ETL_PATH).st_mode
    assert stat.S_ISREG(mode), 'etl.py must be a regular Python file'
    with open(ETL_PATH, 'rb') as handle:
        source = handle.read()
    assert source.strip(), 'etl.py is empty'
    compile(source, ETL_PATH, 'exec')

    canonical_profiles, canonical_logs = canonical_inputs()
    write_inputs(canonical_profiles, canonical_logs)

    try:
        run_pipeline()
        validate_outputs(canonical_profiles, canonical_logs, canonical=True)

        test_profiles, test_logs = varied_inputs()
        write_inputs(test_profiles, test_logs)
        run_pipeline()
        validate_outputs(test_profiles, test_logs)
    finally:
        # Restore the supplied datasets and leave freshly generated canonical outputs.
        write_inputs(canonical_profiles, canonical_logs)
        run_pipeline()

    validate_outputs(canonical_profiles, canonical_logs, canonical=True)
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
