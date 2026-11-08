#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import pwd
import shutil
import stat
import subprocess
import sys

import numpy as np
import pandas as pd
import pytest
from sklearn.decomposition import PCA


def remove_path(path):
    if not os.path.lexists(path):
        return
    if os.path.isdir(path) and not os.path.islink(path):
        shutil.rmtree(path)
    else:
        os.unlink(path)


# Reconstruct the exact original datasets independently of any files the agent
# may have modified, and retain the expected result in verifier memory.
np.random.seed(42)
id_a = np.arange(1, 81)
df_a = pd.DataFrame({
    'id': id_a,
    'f1': np.random.randint(10, 50, size=80),
    'f2': np.random.randint(100, 200, size=80),
    'f3': np.random.randint(0, 10, size=80),
})
id_b = np.arange(60, 121)
df_b = pd.DataFrame({
    'id': id_b,
    'f4': np.random.randint(500, 1000, size=61),
    'f5': np.random.randint(-50, 50, size=61),
})

_expected_joined = pd.merge(df_a, df_b, on='id', how='outer')
_expected_joined = _expected_joined.sort_values('id', ascending=True)
_features = ['f1', 'f2', 'f3', 'f4', 'f5']
_expected_joined[_features] = _expected_joined[_features].fillna(0)
_expected_pca = PCA(n_components=2, svd_solver='full', random_state=42).fit_transform(
    _expected_joined[_features]
)
EXPECTED = pd.DataFrame({
    'id': _expected_joined['id'].astype(int),
    'pc1': _expected_pca[:, 0],
    'pc2': _expected_pca[:, 1],
})


@pytest.fixture(scope='session', autouse=True)
def restore_inputs_and_execute_submission():
    process_path = '/home/user/process.py'
    assert os.path.exists(process_path), f'Missing file: {process_path}'
    mode = os.lstat(process_path).st_mode
    assert stat.S_ISREG(mode), f'{process_path} must be a regular Python script'

    # Replace potentially modified inputs with the exact datasets supplied by
    # setup before executing the submitted script.
    data_dir = '/home/user/data'
    remove_path(data_dir)
    os.mkdir(data_dir, 0o755)
    df_a.to_csv(os.path.join(data_dir, 'dataset_A.csv'), index=False)
    df_b.to_csv(os.path.join(data_dir, 'dataset_B.csv'), index=False)

    output_path = '/home/user/pca_result.csv'
    remove_path(output_path)

    user = pwd.getpwnam('user')
    env = os.environ.copy()
    env['HOME'] = user.pw_dir
    subprocess.run(
        ['runuser', '-u', 'user', '--', sys.executable, process_path],
        check=True,
        cwd=user.pw_dir,
        env=env,
    )


def test_pca_result_exists_and_format():
    path = '/home/user/pca_result.csv'
    assert os.path.exists(path), f'Missing file: {path}'

    with open(path, 'r') as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header == ['id', 'pc1', 'pc2'], f"Incorrect columns. Expected ['id', 'pc1', 'pc2'], got {header}"

        rows = list(reader)
        assert len(rows) > 0, 'The result CSV is empty except for the header'

        for i, row in enumerate(rows):
            id_val = row[0]
            assert '.' not in id_val, f"Row {i+1}: 'id' column contains float formatting ('{id_val}') instead of integer."
            try:
                int(id_val)
            except ValueError:
                assert False, f"Row {i+1}: 'id' column value '{id_val}' is not a valid integer."


def test_pca_result_values():
    user_path = '/home/user/pca_result.csv'
    with open(user_path, 'r') as f_usr:
        usr_reader = csv.reader(f_usr)
        next(usr_reader)
        usr_rows = list(usr_reader)

    assert len(usr_rows) == len(EXPECTED), f'Expected {len(EXPECTED)} rows, but got {len(usr_rows)} rows.'

    for i, (usr_row, exp_row) in enumerate(zip(usr_rows, EXPECTED.itertuples(index=False))):
        expected_id = str(int(exp_row.id))
        assert usr_row[0] == expected_id, f'Row {i+1}: Expected id {expected_id}, got {usr_row[0]}'

        try:
            usr_pc1 = float(usr_row[1])
            usr_pc2 = float(usr_row[2])
        except ValueError:
            assert False, f'Row {i+1}: pc1 or pc2 is not a valid float.'

        exp_pc1 = float(exp_row.pc1)
        exp_pc2 = float(exp_row.pc2)
        assert math.isclose(usr_pc1, exp_pc1, abs_tol=1e-4), f'Row {i+1} (id={usr_row[0]}): pc1 value mismatch. Expected {exp_pc1}, got {usr_pc1}'
        assert math.isclose(usr_pc2, exp_pc2, abs_tol=1e-4), f'Row {i+1} (id={usr_row[0]}): pc2 value mismatch. Expected {exp_pc2}, got {usr_pc2}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
