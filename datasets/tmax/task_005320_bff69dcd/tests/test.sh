#!/bin/bash
set -e
mkdir -p /logs/verifier

# Make the legacy oracle unavailable while submissions are evaluated.
ORACLE_HOLD="$(mktemp -d /tmp/legacy-hold.XXXXXX)"
chmod 700 "$ORACLE_HOLD"
mv /app/legacy_filter "$ORACLE_HOLD/legacy_filter"
restore_oracle() {
    if [ -f "$ORACLE_HOLD/legacy_filter" ]; then
        mv "$ORACLE_HOLD/legacy_filter" /app/legacy_filter
    fi
    rmdir "$ORACLE_HOLD" 2>/dev/null || true
}
trap restore_oracle EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile

import matplotlib.image as mpimg
import numpy as np
import pytest

SCRIPT_PATH = "/home/user/filter.py"
W = np.array([1.0, -1.0, 0.5, 0.5, -0.2, 0.2, 0.0, 0.0, 1.0, -1.0])


def run_as_user(argv, **kwargs):
    return subprocess.run(["runuser", "-u", "user", "--", *argv], **kwargs)


def clean_row(rng):
    while True:
        row = rng.normal(size=10)
        if abs(W @ row) < 0.55:
            return row


def evil_row(rng):
    while True:
        row = rng.normal(size=10)
        if abs(W @ row) > 1.0:
            return row


def make_hidden_corpus():
    rng = np.random.default_rng(secrets.randbits(128))
    root = tempfile.mkdtemp(prefix="sensor-inputs-")
    os.chmod(root, 0o755)
    cases = []

    # Clean and anomalous batches share one directory and have random names, so
    # expected output cannot be inferred from the supplied path.
    labels = ["clean"] * 24 + ["evil"] * 24
    rng.shuffle(labels)
    for expected in labels:
        rows = np.array([clean_row(rng) for _ in range(100)])
        if expected == "evil":
            rows[rng.integers(0, 100)] = evil_row(rng)
        path = os.path.join(root, secrets.token_hex(16) + ".csv")
        np.savetxt(path, rows, delimiter=",", fmt="%.9f")
        os.chmod(path, 0o644)
        cases.append((path, expected))
    return cases


def test_filter_clean_and_evil_hidden_corpus():
    assert os.path.isfile(SCRIPT_PATH), f"Missing script at {SCRIPT_PATH}"
    cases = make_hidden_corpus()
    failed = []
    for csv_file, expected in cases:
        result = run_as_user(
            ["python3", SCRIPT_PATH, csv_file],
            capture_output=True,
            text=True,
            timeout=20,
        )
        if result.returncode != 0 or result.stdout != expected + "\n":
            failed.append(
                f"{os.path.basename(csv_file)}: expected {expected!r}, "
                f"returncode={result.returncode}, stdout={result.stdout!r}"
            )
    if failed:
        pytest.fail(f"{len(failed)} of {len(cases)} hidden batches failed: " + "; ".join(failed[:10]))


def test_plot_data_fixed():
    script_path = "/home/user/plot_data.py"
    assert os.path.isfile(script_path), f"Missing script at {script_path}"

    workdir = tempfile.mkdtemp(prefix="plot-check-")
    os.chmod(workdir, 0o777)
    env = os.environ.copy()
    env.pop("DISPLAY", None)
    env["MPLBACKEND"] = "TkAgg"
    env["MPLCONFIGDIR"] = os.path.join(workdir, ".matplotlib")

    result = run_as_user(
        ["python3", script_path],
        cwd=workdir,
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        "plot_data.py failed under a deliberately unsuitable interactive backend; "
        f"it must select a headless backend itself. Error: {result.stderr}"
    )

    plot_path = os.path.join(workdir, "plot.png")
    assert os.path.isfile(plot_path), "plot_data.py did not create plot.png"
    assert os.path.getsize(plot_path) > 1000, "plot.png is empty or invalid"
    image = mpimg.imread(plot_path)
    assert image.ndim in (2, 3) and image.shape[0] > 10 and image.shape[1] > 10
    assert float(np.std(image)) > 0.01, "plot.png appears blank"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
