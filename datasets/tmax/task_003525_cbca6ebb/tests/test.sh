#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile
import csv
import glob
import json
import secrets
import pytest
import numpy as np
import pandas as pd

SCRIPT_PATH = "/home/user/filter_pipeline.py"
PACKAGE_ROOT = "/app/fast_bayes_infer"
CLEAN_CORPUS_DIR = "/app/data/clean"
EVIL_CORPUS_DIR = "/app/data/evil"
TRAIN_PATH = "/app/data/train.csv"


def count_csv_rows(filepath):
    with open(filepath, 'r', newline='') as f:
        reader = csv.reader(f)
        rows = list(reader)
        return len(rows) - 1 if len(rows) > 0 else 0


def get_csv_rows(filepath):
    with open(filepath, 'r', newline='') as f:
        reader = csv.reader(f)
        return list(reader)


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"


def test_vendored_and_installed_package_handle_batches():
    probe = r'''
import json
import sys
import numpy as np
MODE = sys.argv[1]
if MODE == "source":
    sys.path.insert(0, "/app/fast_bayes_infer")
from fast_bayes_infer import GaussianBayes
X = np.array([
    [-2.0, 0.5],
    [-0.5, 1.5],
    [1.0, -1.0],
    [2.5, 2.0],
    [0.25, -0.25],
])
Q = np.array([[-1.0, 0.25], [0.75, -0.5], [2.0, 1.25]])
m = GaussianBayes()
m.fit(X)
got = np.asarray(m.log_likelihood(Q))
diff = Q - X.mean(axis=0)
cov = np.cov(X, rowvar=False)
expected = -0.5 * (
    X.shape[1] * np.log(2 * np.pi)
    + np.log(np.linalg.det(cov))
    + np.einsum("ij,jk,ik->i", diff, np.linalg.inv(cov), diff)
)
assert got.shape == (len(Q),), got.shape
assert np.allclose(got, expected, rtol=1e-10, atol=1e-10), (got, expected)
print(json.dumps(got.tolist()))
'''
    source = subprocess.run(
        ["python3", "-c", probe, "source"], capture_output=True, text=True, cwd="/tmp"
    )
    assert source.returncode == 0, "Vendored package is not fixed:\n" + source.stdout + source.stderr

    env = os.environ.copy()
    env.pop("PYTHONPATH", None)
    installed = subprocess.run(
        ["python3", "-c", probe, "installed"],
        capture_output=True,
        text=True,
        cwd="/tmp",
        env=env,
    )
    assert installed.returncode == 0, "Fixed package is not installed or is broken:\n" + installed.stdout + installed.stderr


def test_clean_corpus_preserved():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.csv"))
    assert len(clean_files) > 0, f"No clean CSV files found in {CLEAN_CORPUS_DIR}"

    failed_files = []

    with tempfile.TemporaryDirectory() as tmpdir:
        for filepath in clean_files:
            basename = os.path.basename(filepath)
            outpath = os.path.join(tmpdir, basename)

            cmd = ["python3", SCRIPT_PATH, "--input", filepath, "--output", outpath]
            result = subprocess.run(cmd, capture_output=True, text=True)

            if result.returncode != 0:
                failed_files.append((basename, "Script crashed or returned non-zero"))
                continue

            if not os.path.isfile(outpath):
                failed_files.append((basename, "Output file not created"))
                continue

            input_rows = get_csv_rows(filepath)
            output_rows = get_csv_rows(outpath)

            if input_rows != output_rows:
                failed_files.append((basename, f"Expected {len(input_rows)} rows, got {len(output_rows)} rows, or contents differed"))

    if failed_files:
        errors = [f"{name}: {reason}" for name, reason in failed_files]
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified/failed.\nDetails:\n" + "\n".join(errors))


def test_evil_corpus_rejected():
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.csv"))
    assert len(evil_files) > 0, f"No evil CSV files found in {EVIL_CORPUS_DIR}"

    failed_files = []

    with tempfile.TemporaryDirectory() as tmpdir:
        for filepath in evil_files:
            basename = os.path.basename(filepath)
            outpath = os.path.join(tmpdir, basename)

            cmd = ["python3", SCRIPT_PATH, "--input", filepath, "--output", outpath]
            result = subprocess.run(cmd, capture_output=True, text=True)

            if result.returncode != 0:
                failed_files.append((basename, "Script crashed or returned non-zero"))
                continue

            if not os.path.isfile(outpath):
                failed_files.append((basename, "Output file not created"))
                continue

            input_rows = get_csv_rows(filepath)
            output_rows = get_csv_rows(outpath)

            if len(output_rows) > 1:
                failed_files.append((basename, f"Expected 0 data rows, got {len(output_rows) - 1} rows bypassed"))
            elif len(output_rows) == 1 and len(input_rows) > 0 and output_rows[0] != input_rows[0]:
                failed_files.append((basename, "Header mismatch in output"))

    if failed_files:
        errors = [f"{name}: {reason}" for name, reason in failed_files]
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil bypassed/failed.\nDetails:\n" + "\n".join(errors))


def test_unseen_mixed_rows_are_filtered_with_vectorized_gaussianbayes():
    train = pd.read_csv(TRAIN_PATH)
    features = [c for c in train.columns if c != "label"]
    clean_train = train.loc[train["label"] == "clean", features].to_numpy(dtype=float)
    evil_train = train.loc[train["label"] == "evil", features].to_numpy(dtype=float)

    mean = clean_train.mean(axis=0)
    cov = np.cov(clean_train, rowvar=False)
    inv_cov = np.linalg.inv(cov)
    log_det = np.log(np.linalg.det(cov))

    def ll(x):
        x = np.asarray(x, dtype=float)
        d = x - mean
        return -0.5 * (len(features) * np.log(2 * np.pi) + log_det + np.einsum("ij,jk,ik->i", d, inv_cov, d))

    clean_floor = ll(clean_train).min()
    evil_ceiling = ll(evil_train).max()
    assert evil_ceiling < clean_floor, "Training data does not have the promised separating likelihood gap"

    rng = np.random.default_rng(secrets.randbits(128))
    generated_clean = mean + rng.normal(0.0, 0.18, size=(19, len(features)))
    generated_evil = evil_train.mean(axis=0) + rng.normal(0.0, 0.18, size=(19, len(features)))
    assert np.all(ll(generated_clean) > clean_floor)
    assert np.all(ll(generated_evil) < evil_ceiling)

    tagged = [(row, True) for row in generated_clean] + [(row, False) for row in generated_evil]
    order = rng.permutation(len(tagged))
    mixed = [tagged[i] for i in order]
    expected = np.asarray([row for row, is_clean in mixed if is_clean])

    with tempfile.TemporaryDirectory(prefix="batch_") as tmpdir:
        input_path = os.path.join(tmpdir, secrets.token_hex(10) + ".csv")
        output_path = os.path.join(tmpdir, secrets.token_hex(10) + ".csv")
        trace_path = os.path.join(tmpdir, secrets.token_hex(10) + ".trace")
        hook_dir = os.path.join(tmpdir, "hooks")
        os.mkdir(hook_dir)

        pd.DataFrame([row for row, _ in mixed], columns=features).to_csv(input_path, index=False)

        hook = r'''
import os
import numpy as np
from fast_bayes_infer import GaussianBayes
_trace = os.environ.get("FBI_TRACE_FILE")
_original_fit = GaussianBayes.fit
_original_ll = GaussianBayes.log_likelihood

def _record(kind, value):
    if _trace:
        with open(_trace, "a") as f:
            f.write("%s:%d\n" % (kind, value))

def _fit(self, X):
    a = np.asarray(X)
    _record("fit", a.shape[0] if a.ndim > 1 else 1)
    return _original_fit(self, X)

def _ll(self, X):
    a = np.asarray(X)
    _record("log_likelihood", a.shape[0] if a.ndim > 1 else 1)
    return _original_ll(self, X)

GaussianBayes.fit = _fit
GaussianBayes.log_likelihood = _ll
'''
        with open(os.path.join(hook_dir, "sitecustomize.py"), "w") as f:
            f.write(hook)

        env = os.environ.copy()
        old_pythonpath = env.get("PYTHONPATH")
        env["PYTHONPATH"] = hook_dir + (os.pathsep + old_pythonpath if old_pythonpath else "")
        env["FBI_TRACE_FILE"] = trace_path
        result = subprocess.run(
            ["python3", SCRIPT_PATH, "--input", input_path, "--output", output_path],
            capture_output=True,
            text=True,
            env=env,
            cwd=tmpdir,
        )
        assert result.returncode == 0, "Script failed on an unseen mixed file:\n" + result.stdout + result.stderr
        assert os.path.isfile(output_path), "Output file was not created for unseen mixed input"

        with open(input_path, newline="") as f:
            input_header = next(csv.reader(f))
        with open(output_path, newline="") as f:
            output_rows = list(csv.reader(f))
        assert output_rows, "Output must retain the input header"
        assert output_rows[0] == input_header, "Output header differs from input header"
        assert len(output_rows) - 1 == len(expected), "Wrong number of rows retained from unseen mixed input"
        actual = np.asarray([[float(v) for v in row] for row in output_rows[1:]])
        assert actual.shape == expected.shape
        assert np.allclose(actual, expected, rtol=1e-12, atol=1e-12), "Wrong rows or row order in mixed output"

        assert os.path.isfile(trace_path), "The pipeline did not use fast_bayes_infer.GaussianBayes"
        with open(trace_path) as f:
            trace = [line.strip() for line in f if line.strip()]
        batch_sizes = [int(line.split(":", 1)[1]) for line in trace if line.startswith("log_likelihood:")]
        assert batch_sizes, "The pipeline did not call GaussianBayes.log_likelihood"
        assert max(batch_sizes) > 1, "GaussianBayes.log_likelihood was not used with vectorized batched input"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
