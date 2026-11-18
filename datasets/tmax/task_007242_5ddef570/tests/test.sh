#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import inspect
import io
import os
import runpy
import subprocess
import sys

import numpy as np
import pandas as pd

SCRIPT = "/home/user/analyze.py"
DATASET = "/home/user/dataset.csv"
OUTPUT = "/home/user/pca_ci.txt"
FEATURES = [f"f{i}" for i in range(1, 51)]

# The requested artifact must exist and be valid Python.
assert os.path.isfile(SCRIPT), f"Analysis script not found: {SCRIPT}"
with open(SCRIPT, "rb") as f:
    source = f.read()
assert source, f"Analysis script is empty: {SCRIPT}"
compile(source, SCRIPT, "exec")

# Recreate the setup data independently, including its CSV round trip, and ensure
# the fixed task input was not replaced.
rng = np.random.RandomState(123)
data = rng.randn(500, 50)
data[:, :10] += rng.randn(500, 1) * 3
pristine = pd.DataFrame(data, columns=FEATURES)
pristine["f1"] = rng.randint(0, 10, size=500).astype(float)
pristine.loc[rng.choice(500, 25, replace=False), "f1"] = np.nan
csv_buffer = io.StringIO()
pristine.to_csv(csv_buffer, index=False)
csv_buffer.seek(0)
pristine = pd.read_csv(csv_buffer)
actual_dataset = pd.read_csv(DATASET)
pd.testing.assert_frame_equal(actual_dataset, pristine, check_exact=True)

# Permit a script that installs scikit-learn itself before importing it.
try:
    import sklearn.decomposition as decomposition
except ImportError:
    subprocess.run([sys.executable, SCRIPT], check=True, cwd="/home/user")
    import sklearn.decomposition as decomposition

sample_calls = []
pca_inputs = []
pca_ratios = []
percentile_calls = []

original_sample = pd.DataFrame.sample
original_fit = decomposition.PCA.fit
original_fit_transform = decomposition.PCA.fit_transform
original_percentile = np.percentile
pca_call_depth = 0

def tracked_sample(self, *args, **kwargs):
    bound = inspect.signature(original_sample).bind(self, *args, **kwargs)
    bound.apply_defaults()
    frac = bound.arguments["frac"]
    replace = bound.arguments["replace"]
    random_state = bound.arguments["random_state"]
    sample_calls.append((frac, replace, random_state))

    assert list(self.columns) == FEATURES, "Each bootstrap must sample all f1-f50 columns"
    assert self.shape == (500, 50), "Each bootstrap must sample the complete cleaned dataframe"
    assert self["f1"].notna().all(), "f1 still contains NaN values when sampled"
    assert pd.api.types.is_integer_dtype(self["f1"].dtype), "f1 was not cast to an integer dtype"
    return original_sample(self, *args, **kwargs)

def record_pca_result(estimator, X):
    shape = getattr(X, "shape", None)
    assert shape is not None and len(shape) == 2 and shape[1] == 50, "PCA must use all 50 features"
    if isinstance(X, pd.DataFrame):
        assert list(X.columns) == FEATURES, "PCA must use f1 through f50 in the dataset"
    pca_inputs.append(shape)
    pca_ratios.append(float(estimator.explained_variance_ratio_[0]))

def tracked_fit(self, X, *args, **kwargs):
    global pca_call_depth
    outer = pca_call_depth == 0
    pca_call_depth += 1
    try:
        result = original_fit(self, X, *args, **kwargs)
    finally:
        pca_call_depth -= 1
    if outer:
        record_pca_result(self, X)
    return result

def tracked_fit_transform(self, X, *args, **kwargs):
    global pca_call_depth
    outer = pca_call_depth == 0
    pca_call_depth += 1
    try:
        result = original_fit_transform(self, X, *args, **kwargs)
    finally:
        pca_call_depth -= 1
    if outer:
        record_pca_result(self, X)
    return result

def tracked_percentile(a, q, *args, **kwargs):
    result = original_percentile(a, q, *args, **kwargs)
    percentile_calls.append((np.asarray(a, dtype=float).ravel().copy(), np.asarray(q).ravel().copy(), np.asarray(result).ravel().copy()))
    return result

pd.DataFrame.sample = tracked_sample
decomposition.PCA.fit = tracked_fit
decomposition.PCA.fit_transform = tracked_fit_transform
np.percentile = tracked_percentile

try:
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    runpy.run_path(SCRIPT, run_name="__main__")
finally:
    pd.DataFrame.sample = original_sample
    decomposition.PCA.fit = original_fit
    decomposition.PCA.fit_transform = original_fit_transform
    np.percentile = original_percentile

# Verify the exact prescribed 1000-iteration pipeline was actually executed.
assert len(sample_calls) == 1000, f"Expected exactly 1000 bootstrap samples, got {len(sample_calls)}"
for i, (frac, replace, random_state) in enumerate(sample_calls):
    assert frac == 1, f"Bootstrap iteration {i} did not use frac=1"
    assert replace is True, f"Bootstrap iteration {i} did not use replace=True"
    assert random_state == i, f"Bootstrap iteration {i} used random_state={random_state!r} instead of {i}"
assert len(pca_inputs) == 1000, f"Expected exactly 1000 PCA fits, got {len(pca_inputs)}"

matching_percentiles = []
for values, q, result in percentile_calls:
    if values.shape == (1000,) and np.allclose(values, np.asarray(pca_ratios), rtol=0, atol=0):
        matching_percentiles.extend(zip(q.tolist(), result.tolist()))
qs = [float(q) for q, _ in matching_percentiles]
assert 2.5 in qs and 97.5 in qs, "numpy.percentile was not applied at 2.5 and 97.5 to all 1000 PC1 ratios"

# Independently compute the correct deterministic answer from the pristine input.
reference = pristine.copy()
reference["f1"] = reference["f1"].fillna(reference["f1"].median()).astype(int)
reference_ratios = []
for i in range(1000):
    sample = original_sample(reference, frac=1, replace=True, random_state=i)
    model = decomposition.PCA()
    original_fit(model, sample[FEATURES])
    reference_ratios.append(float(model.explained_variance_ratio_[0]))
low, high = original_percentile(reference_ratios, [2.5, 97.5])
expected = f"{low:.4f},{high:.4f}"

# Preserve the original output existence and exact-content assertions.
assert os.path.isfile(OUTPUT), f"Output file not found: {OUTPUT}"
with open(OUTPUT, "r") as f:
    content = f.read().strip()
assert content == expected, f"Incorrect confidence interval in {OUTPUT}. Expected '{expected}', but got '{content}'."

# Ensure execution did not replace the supplied dataset.
pd.testing.assert_frame_equal(pd.read_csv(DATASET), pristine, check_exact=True)
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
