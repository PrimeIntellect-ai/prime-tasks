#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import shutil
import stat
import subprocess

VENV = '/home/user/venv'
VENV_PYTHON = '/home/user/venv/bin/python'


def test_venv_exists():
    assert os.path.isdir('/home/user/venv'), "/home/user/venv directory does not exist. Did you create the virtual environment?"
    assert os.path.isfile('/home/user/venv/bin/activate') or os.path.isfile('/home/user/venv/bin/python'), "Virtual environment does not appear to be properly initialized."


def test_venv_is_functional_and_has_required_packages():
    assert os.path.isfile(VENV_PYTHON), "The virtual environment has no Python interpreter."
    code = '''
import json, os, sys
import numpy, pandas, sklearn
print(json.dumps({
    "prefix": os.path.realpath(sys.prefix),
    "numpy": os.path.realpath(numpy.__file__),
    "pandas": os.path.realpath(pandas.__file__),
    "sklearn": os.path.realpath(sklearn.__file__),
}))
'''
    proc = subprocess.run(
        [VENV_PYTHON, '-I', '-c', code], text=True, capture_output=True, timeout=30
    )
    assert proc.returncode == 0, f"The venv cannot import numpy, pandas, and scikit-learn: {proc.stderr}"
    info = json.loads(proc.stdout.strip())
    assert info['prefix'] == os.path.realpath(VENV), "venv/bin/python is not running inside /home/user/venv."
    for package in ('numpy', 'pandas', 'sklearn'):
        assert os.path.commonpath([info[package], os.path.realpath(VENV)]) == os.path.realpath(VENV), \
            f"{package} is not installed in /home/user/venv."


def test_run_etl_sh_exists_and_correct():
    path = '/home/user/run_etl.sh'
    assert os.path.isfile(path), f"Missing file: {path}"

    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {path} is not executable. Did you run chmod +x?"

    with open(path, 'r') as f:
        content = f.read()

    assert 'activate' in content or '/venv/bin/' in content, "run_etl.sh does not seem to use the virtual environment."
    assert 'OMP_NUM_THREADS=1' in content, "run_etl.sh does not set OMP_NUM_THREADS=1"
    assert 'OPENBLAS_NUM_THREADS=1' in content, "run_etl.sh does not set OPENBLAS_NUM_THREADS=1"
    assert 'python' in content and 'etl.py' in content, "run_etl.sh does not execute the etl.py script."


def test_etl_output_correct():
    path = '/home/user/etl_output.txt'
    assert os.path.isfile(path), f"Missing output file: {path}. Did you run the pipeline?"

    with open(path, 'r') as f:
        content = f.read().strip()

    try:
        val = float(content)
    except ValueError:
        assert False, f"The content of {path} ('{content}') is not a valid float."

    # The expected output is approximately 0.8521 or -0.8521 depending on scikit-learn version/PCA sign
    expected_abs_val = 0.8521
    actual_abs_val = abs(val)

    assert abs(actual_abs_val - expected_abs_val) < 0.001, f"The output value {val} is incorrect. The data leakage might not be properly fixed, or the wrong split/random state was used."


def test_etl_py_fixed():
    path = '/home/user/etl.py'
    assert os.path.isfile(path), f"Missing file: {path}"

    with open(path, 'r') as f:
        content = f.read()

    assert "pca.fit_transform(X)" not in content, "The data leakage bug (fitting PCA on the entire dataset 'X') is still present in etl.py."
    assert "train_test_split(X," in content or "train_test_split(X " in content or "train_test_split" in content, "train_test_split seems to be missing."


def _expected_for_current_data():
    code = '''
import pandas as pd
from sklearn.decomposition import PCA
from sklearn.model_selection import train_test_split

df = pd.read_csv("/home/user/data.csv")
X = df.drop("target", axis=1)
y = df["target"]
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42
)
pca = PCA(n_components=2, random_state=42)
pca.fit(X_train)
X_test_pca = pca.transform(X_test)
print(repr(float(X_test_pca[:, 0].mean())))
'''
    env = os.environ.copy()
    env['OMP_NUM_THREADS'] = '1'
    env['OPENBLAS_NUM_THREADS'] = '1'
    proc = subprocess.run(
        [VENV_PYTHON, '-I', '-c', code], env=env,
        text=True, capture_output=True, timeout=30
    )
    assert proc.returncode == 0, f"Could not independently compute expected result: {proc.stderr}"
    return float(proc.stdout.strip())


def _write_challenge_data(seed, rows):
    rng = random.Random(seed)
    with open('/home/user/data.csv', 'w') as f:
        f.write('f1,f2,f3,f4,target\n')
        for i in range(rows):
            # Mixed scales, trends, and occasional outliers make fitting PCA on all
            # rows observably different from fitting it on the training partition.
            f1 = rng.uniform(-15, 20) + i * 0.13
            f2 = -1.8 * f1 + rng.uniform(-4, 4)
            f3 = rng.uniform(-8, 11) + (35 if i % 17 == 0 else 0)
            f4 = 0.7 * f3 + 0.25 * f1 + rng.uniform(-2, 2)
            target = int(f1 + f3 > 3)
            f.write(f'{f1:.8f},{f2:.8f},{f3:.8f},{f4:.8f},{target}\n')


def test_pipeline_is_executed_and_computes_from_data():
    data_path = '/home/user/data.csv'
    output_path = '/home/user/etl_output.txt'
    original_data = open(data_path, 'rb').read()
    original_output = open(output_path, 'rb').read() if os.path.exists(output_path) else None

    try:
        seeds = [int.from_bytes(os.urandom(8), 'big'), int.from_bytes(os.urandom(8), 'big')]
        for seed, rows in zip(seeds, (53, 67)):
            _write_challenge_data(seed, rows)
            expected = _expected_for_current_data()
            if os.path.exists(output_path):
                os.remove(output_path)

            env = os.environ.copy()
            env['OMP_NUM_THREADS'] = '9'
            env['OPENBLAS_NUM_THREADS'] = '9'
            proc = subprocess.run(
                ['/home/user/run_etl.sh'], env=env,
                text=True, capture_output=True, timeout=60
            )
            assert proc.returncode == 0, f"run_etl.sh failed: {proc.stdout}\n{proc.stderr}"
            assert os.path.isfile(output_path), "run_etl.sh did not create /home/user/etl_output.txt."

            content = open(output_path).read().strip()
            try:
                actual = float(content)
            except ValueError:
                assert False, f"Pipeline output is not a single valid float: {content!r}"
            assert math.isfinite(actual), f"Pipeline output is not finite: {actual}"
            assert abs(abs(actual) - abs(expected)) <= 0.0006, \
                f"Pipeline produced {actual}, but training-only PCA gives {expected}."
    finally:
        with open(data_path, 'wb') as f:
            f.write(original_data)
        if original_output is None:
            if os.path.exists(output_path):
                os.remove(output_path)
        else:
            with open(output_path, 'wb') as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
