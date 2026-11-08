#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import subprocess
import tempfile
from pathlib import Path

import matplotlib.image as mpimg
import numpy as np
import pandas as pd
import pytest

FILTER_SCRIPT = "/home/user/filter.py"
PLOT_SCRIPT = "/home/user/plot_posteriors.py"
EVIL_CORPUS_DIR = "/app/test_corpus/evil/"
CLEAN_CORPUS_DIR = "/app/test_corpus/clean/"


def test_filter_script_exists():
    assert os.path.exists(FILTER_SCRIPT), f"Missing script at {FILTER_SCRIPT}"
    assert os.path.isfile(FILTER_SCRIPT), f"{FILTER_SCRIPT} is not a file"


def run_filter(csv_path):
    result = subprocess.run(
        ["python3", FILTER_SCRIPT, csv_path],
        capture_output=True,
        text=True,
        timeout=5
    )
    return result.stdout.strip()


def test_evil_corpus():
    assert os.path.exists(EVIL_CORPUS_DIR), "Evil corpus directory missing"
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.csv')]
    assert len(evil_files) > 0, "No CSV files in evil corpus"

    bypassed = []
    for f in evil_files:
        path = os.path.join(EVIL_CORPUS_DIR, f)
        output = run_filter(path)
        if output != "EVIL":
            bypassed.append((f, output))

    if bypassed:
        details = ", ".join([f"{f} (output: {out})" for f, out in bypassed])
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil bypassed: {details}")


def test_clean_corpus():
    assert os.path.exists(CLEAN_CORPUS_DIR), "Clean corpus directory missing"
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.csv')]
    assert len(clean_files) > 0, "No CSV files in clean corpus"

    modified = []
    for f in clean_files:
        path = os.path.join(CLEAN_CORPUS_DIR, f)
        output = run_filter(path)
        if output != "CLEAN":
            modified.append((f, output))

    if modified:
        details = ", ".join([f"{f} (output: {out})" for f, out in modified])
        pytest.fail(f"{len(modified)} of {len(clean_files)} clean modified: {details}")


def expected_label(df):
    values = df[["S1", "S2", "S3"]].copy()
    values = values.fillna(values.mean())
    anomalous = (
        values["S1"] * values["S1"]
        + values["S2"]
        - 0.5 * values["S3"]
        > 15.0
    )
    return "EVIL" if anomalous.mean() > 0.10 else "CLEAN"


def make_case(rng, want_evil):
    for _ in range(100):
        n = int(rng.integers(70, 141))
        s1 = rng.uniform(-2.0, 2.0, n)
        s2 = rng.uniform(-5.0, 2.0, n)
        s3 = rng.uniform(-2.0, 5.0, n)

        count = max(1, int(n * (0.24 if want_evil else 0.04)))
        idx = rng.choice(n, count, replace=False)
        for j, row in enumerate(idx):
            mode = j % 3
            if mode == 0:
                s1[row] = rng.choice([-1.0, 1.0]) * rng.uniform(4.5, 6.0)
                s2[row] = rng.uniform(-1.0, 3.0)
                s3[row] = rng.uniform(-2.0, 2.0)
            elif mode == 1:
                s1[row] = rng.uniform(-1.0, 1.0)
                s2[row] = rng.uniform(19.0, 25.0)
                s3[row] = rng.uniform(-2.0, 2.0)
            else:
                s1[row] = rng.uniform(-1.0, 1.0)
                s2[row] = rng.uniform(3.0, 6.0)
                s3[row] = rng.uniform(-32.0, -26.0)

        df = pd.DataFrame({"S1": s1, "S2": s2, "S3": s3})
        # Exercise per-file, per-column mean imputation in every generated case.
        for column in ("S1", "S2", "S3"):
            missing = rng.choice(n, max(2, n // 25), replace=False)
            df.loc[missing, column] = np.nan

        if (expected_label(df) == "EVIL") == want_evil:
            return df
    raise AssertionError("Could not construct generated test case")


def test_generated_neutral_path_cases():
    # All cases reuse the same randomly named path, so a solution cannot infer the
    # answer from directory or filename labels and must read the current CSV.
    rng = np.random.default_rng()
    cases = [make_case(rng, want) for want in ([False, True] * 6)]
    rng.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="sensor_check_") as directory:
        csv_path = os.path.join(directory, "readings.csv")
        seen = set()
        for df in cases:
            expected = expected_label(df)
            seen.add(expected)
            df.to_csv(csv_path, index=False)
            result = subprocess.run(
                ["python3", FILTER_SCRIPT, csv_path],
                capture_output=True,
                text=True,
                timeout=5,
            )
            assert result.returncode == 0, result.stderr
            assert result.stdout in (expected, expected + "\n"), (
                f"Expected exactly {expected}, got stdout={result.stdout!r}, "
                f"stderr={result.stderr!r}"
            )
        assert seen == {"CLEAN", "EVIL"}


def png_state(roots):
    state = {}
    for root in roots:
        root = Path(root)
        if not root.exists():
            continue
        for path in root.rglob("*.png"):
            try:
                data = path.read_bytes()
                stat = path.stat()
                state[str(path)] = (stat.st_mtime_ns, len(data), hashlib.sha256(data).hexdigest())
            except OSError:
                pass
    return state


def is_nonblank_png(path):
    try:
        image = np.asarray(mpimg.imread(path))
    except Exception:
        return False
    if image.size == 0 or image.ndim < 2 or image.shape[0] < 10 or image.shape[1] < 10:
        return False
    visible = image[..., :3] if image.ndim == 3 and image.shape[-1] >= 3 else image
    finite = visible[np.isfinite(visible)]
    return finite.size > 0 and float(np.max(finite) - np.min(finite)) > 1e-4


def test_plot_script_generates_nonblank_png():
    assert os.path.exists(PLOT_SCRIPT), f"Missing script at {PLOT_SCRIPT}"
    assert os.path.isfile(PLOT_SCRIPT), f"{PLOT_SCRIPT} is not a file"

    with tempfile.TemporaryDirectory(prefix="plot_check_") as workdir:
        roots = ["/home/user", workdir]
        before = png_state(roots)
        env = os.environ.copy()
        env["MPLBACKEND"] = "Agg"
        result = subprocess.run(
            ["python3", PLOT_SCRIPT],
            cwd=workdir,
            env=env,
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, result.stderr

        after = png_state(roots)
        generated = [path for path, state in after.items() if before.get(path) != state]
        assert generated, "plot_posteriors.py did not create or update any PNG file"
        assert any(is_nonblank_png(path) for path in generated), (
            f"Generated PNG files were blank or invalid: {generated}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
