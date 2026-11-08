#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'RUNNER_EOF' > /tmp/bootstrap_runner.py
import os
import runpy
import sys
import numpy as np
import pandas as pd

script = sys.argv[1]
os.chdir(os.path.dirname(script) or "/home/user")

import pyspectro.voigt as voigt
real_fit = voigt.fit_spectrum
bases = []


def is_residual_resample(y, base):
    y = np.asarray(y, dtype=float).ravel()
    if y.shape != base["y"].shape:
        return False
    delta = y - base["model"]
    pools = (base["residual"], base["residual"] - np.mean(base["residual"]))
    for pool in pools:
        ordered = np.sort(pool)
        pos = np.searchsorted(ordered, delta)
        lo = ordered[np.clip(pos - 1, 0, len(ordered) - 1)]
        hi = ordered[np.clip(pos, 0, len(ordered) - 1)]
        distance = np.minimum(np.abs(delta - lo), np.abs(delta - hi))
        if np.all(distance <= 1e-6):
            return True
    return False


def monitored_fit(x, y, *args, **kwargs):
    xa = np.asarray(x, dtype=float).ravel()
    ya = np.asarray(y, dtype=float).ravel()
    matched = None
    for base in bases:
        if xa.shape == base["x"].shape and np.allclose(xa, base["x"], rtol=0, atol=1e-10):
            if is_residual_resample(ya, base):
                matched = base
                break

    result = real_fit(x, y, *args, **kwargs)
    if not isinstance(result, tuple) or len(result) < 2:
        raise AssertionError("pyspectro.voigt.fit_spectrum did not return centers and a fitted model")
    centers = np.asarray(result[0], dtype=float).ravel()
    model = np.asarray(result[1], dtype=float).ravel()
    if not np.all(np.isfinite(centers)) or model.shape != ya.shape:
        raise AssertionError("fit_spectrum returned invalid results")

    if matched is not None:
        matched["bootstrap_centers"].append(centers.copy())
    else:
        bases.append({
            "x": xa.copy(),
            "y": ya.copy(),
            "model": model.copy(),
            "residual": ya - model,
            "centers": centers.copy(),
            "bootstrap_centers": [],
        })
    return result


voigt.fit_spectrum = monitored_fit
runpy.run_path(script, run_name="__main__")

qualified = [b for b in bases if len(b["bootstrap_centers"]) >= 500]
selected = []
three_peak = [b for b in qualified if b["centers"].size == 3 and all(c.size == 3 for c in b["bootstrap_centers"])]
if three_peak:
    selected = [max(three_peak, key=lambda b: len(b["bootstrap_centers"]))]
else:
    one_peak = [b for b in qualified if b["centers"].size == 1 and all(c.size == 1 for c in b["bootstrap_centers"])]
    if len(one_peak) >= 3:
        selected = sorted(one_peak, key=lambda b: float(b["centers"][0]))[:3]

assert selected, "No residual bootstrap using at least 500 fit_spectrum refits was observed"

if len(selected) == 1:
    samples = np.vstack(selected[0]["bootstrap_centers"])
else:
    samples = np.column_stack([
        np.array([c[0] for c in b["bootstrap_centers"]], dtype=float)
        for b in selected
    ])

expected_mean = np.mean(samples, axis=0)
expected_lower = np.percentile(samples, 2.5, axis=0)
expected_upper = np.percentile(samples, 97.5, axis=0)
order = np.argsort(expected_mean)
expected_mean = expected_mean[order]
expected_lower = expected_lower[order]
expected_upper = expected_upper[order]

out = pd.read_csv("/home/user/peak_confidence.csv").sort_values("peak_id")
assert list(out.columns) == ["peak_id", "center_mean", "ci_lower", "ci_upper"]
assert list(out["peak_id"]) == [1, 2, 3]
actual = out[["center_mean", "ci_lower", "ci_upper"]].to_numpy(dtype=float)
expected = np.column_stack([expected_mean, expected_lower, expected_upper])
assert np.all(np.isfinite(actual)), "Bootstrap output contains non-finite values"
assert np.allclose(actual, expected, rtol=0, atol=5e-3), (
    "CSV statistics do not equal the mean and 2.5/97.5 percentiles of the observed bootstrap refits"
)
RUNNER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.metadata
import os
from pathlib import Path
import shutil
import subprocess

import numpy as np
import pandas as pd
import pytest

CSV_PATH = "/home/user/peak_confidence.csv"
EXPECTED_COLUMNS = ['peak_id', 'center_mean', 'ci_lower', 'ci_upper']


def test_peak_confidence_results():
    assert os.path.exists(CSV_PATH), f"Expected output file not found at {CSV_PATH}"
    try:
        df = pd.read_csv(CSV_PATH)
    except Exception as e:
        pytest.fail(f"Failed to read {CSV_PATH} as a CSV file: {e}")

    assert list(df.columns) == EXPECTED_COLUMNS, (
        f"CSV headers do not match the expected format.\n"
        f"Expected: {EXPECTED_COLUMNS}\nFound: {list(df.columns)}"
    )
    df = df.sort_values('peak_id')
    assert list(df['peak_id'].values) == [1, 2, 3], "peak_id column must contain exactly [1, 2, 3]."

    true_centers = np.array([450.0, 520.5, 600.2])
    estimated_centers = df['center_mean'].values
    mae = np.mean(np.abs(estimated_centers - true_centers))
    threshold = 0.05
    assert mae < threshold, (
        f"MAE of estimated peak centers is too high.\nMeasured MAE: {mae:.4f}\n"
        f"Threshold: < {threshold}\nEstimated centers: {estimated_centers}\nTrue centers: {true_centers}"
    )

    numeric = df[['center_mean', 'ci_lower', 'ci_upper']].apply(pd.to_numeric, errors='coerce').to_numpy()
    assert np.all(np.isfinite(numeric)), "Center and confidence interval values must be finite numbers."
    assert np.all(numeric[:, 1] < numeric[:, 2]), "Each 95% confidence interval must have positive width."
    assert np.all((numeric[:, 1] <= numeric[:, 0]) & (numeric[:, 0] <= numeric[:, 2])), (
        "Each center_mean must lie within its confidence interval."
    )


def test_package_was_fixed_and_installed():
    dist = importlib.metadata.distribution('pyspectro')
    assert dist.version == '1.0.0'
    requirements = [r.lower().replace(' ', '') for r in (dist.requires or [])]
    assert any(r.startswith('numpy') for r in requirements), "Installed pyspectro metadata must require numpy."
    assert any(r.startswith('scipy') for r in requirements), "Installed pyspectro metadata must require scipy."

    import pyspectro.voigt as voigt
    assert callable(voigt.fit_spectrum)

    setup_path = Path('/app/pyspectro-1.0.0/setup.py')
    tree = ast.parse(setup_path.read_text())
    install_requires = None
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            for kw in node.keywords:
                if kw.arg == 'install_requires':
                    install_requires = ast.literal_eval(kw.value)
    assert isinstance(install_requires, (list, tuple))
    names = [str(x).lower() for x in install_requires]
    assert 'numpy' in names and 'scipy' in names, "The missing comma in install_requires was not fixed."


def test_processing_script_executes_real_residual_bootstrap():
    roots = [Path('/home/user'), Path('/app'), Path('/root'), Path('/tmp')]
    candidates = []
    for root in roots:
        if not root.exists():
            continue
        for path in root.rglob('*.py'):
            text_path = str(path)
            if text_path in ['/tmp/test_final_state.py', '/tmp/bootstrap_runner.py']:
                continue
            if '/app/pyspectro-1.0.0/pyspectro/' in text_path:
                continue
            if any(part in {'.cache', 'site-packages', '__pycache__'} for part in path.parts):
                continue
            try:
                source = path.read_text(errors='ignore')
            except OSError:
                continue
            if 'fit_spectrum' in source and ('bootstrap' in source.lower() or 'residual' in source.lower()):
                candidates.append(path)

    assert candidates, "No Python processing script using fit_spectrum and residual bootstrap was found."
    candidates.sort(key=lambda p: (0 if str(p).startswith('/home/user/') else 1, len(str(p))))

    backup = Path('/tmp/original_peak_confidence.csv')
    shutil.copy2(CSV_PATH, backup)
    failures = []
    passed = False
    try:
        for script in candidates:
            if os.path.exists(CSV_PATH):
                os.remove(CSV_PATH)
            try:
                result = subprocess.run(
                    ['python3', '/tmp/bootstrap_runner.py', str(script)],
                    text=True, capture_output=True, timeout=600
                )
            except subprocess.TimeoutExpired:
                failures.append(f"{script}: timed out")
                continue
            if result.returncode == 0:
                passed = True
                break
            failures.append(f"{script}: {result.stderr[-1200:]}")
    finally:
        shutil.copy2(backup, CSV_PATH)
        backup.unlink(missing_ok=True)

    assert passed, "No processing script passed execution/bootstrapping checks:\n" + "\n".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
