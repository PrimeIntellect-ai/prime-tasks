#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import sys
import tempfile
import pytest

REFERENCE_SCRIPT = r'''
import pandas as pd
from sklearn.decomposition import PCA
from sklearn.linear_model import BayesianRidge

df = pd.read_csv('/home/user/data.csv')
df_boot = df.sample(n=1000, replace=True, random_state=42)

pca = PCA(n_components=2, random_state=42)
X_pca = pca.fit_transform(df_boot[['x1', 'x2', 'x3', 'x4']])

model = BayesianRidge()
model.fit(X_pca, df_boot['y'])

print(f"{model.alpha_:.4f}")
'''

@pytest.fixture(scope='session')
def executed_pipeline():
    # Build a verifier-owned environment and compute the answer independently.
    ref_dir = tempfile.mkdtemp(prefix='verifier-ref-', dir='/tmp')
    ref_venv = os.path.join(ref_dir, 'venv')
    try:
        subprocess.run(
            [sys.executable, '-m', 'venv', '--system-site-packages', ref_venv],
            check=True, capture_output=True, text=True, timeout=120
        )
        subprocess.run(
            [os.path.join(ref_venv, 'bin', 'python'), '-m', 'pip', 'install',
             '--disable-pip-version-check', 'pandas', 'scikit-learn'],
            check=True, capture_output=True, text=True, timeout=600
        )
        result = subprocess.run(
            [os.path.join(ref_venv, 'bin', 'python'), '-I', '-c', REFERENCE_SCRIPT],
            check=True, capture_output=True, text=True, timeout=120
        )
        expected_val = result.stdout.strip()

        # Require the submitted artifact to recreate all requested outputs.
        shutil.rmtree('/home/user/venv', ignore_errors=True)
        try:
            os.remove('/home/user/output.txt')
        except FileNotFoundError:
            pass

        subprocess.run(
            ['/usr/sbin/runuser', '-u', 'user', '--', '/home/user/pipeline.sh'],
            cwd='/home/user', check=True, capture_output=True, text=True, timeout=600
        )
        return expected_val
    finally:
        shutil.rmtree(ref_dir, ignore_errors=True)

def test_pipeline_sh_exists_and_executable(executed_pipeline):
    path = '/home/user/pipeline.sh'
    assert os.path.isfile(path), f"File not found: {path}"
    assert os.access(path, os.X_OK), f"File is not executable: {path}"

def test_venv_exists(executed_pipeline):
    path = '/home/user/venv'
    assert os.path.isdir(path), f"Virtual environment not found at {path}"
    assert os.path.isfile(os.path.join(path, 'bin', 'python')), "Python executable not found in venv"

def test_output_txt(executed_pipeline):
    output_path = '/home/user/output.txt'
    assert os.path.isfile(output_path), f"Output file not found: {output_path}"

    with open(output_path, 'r') as f:
        student_val = f.read().strip()

    assert student_val == executed_pipeline, (
        f"Expected output {executed_pipeline}, but got {student_val}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
