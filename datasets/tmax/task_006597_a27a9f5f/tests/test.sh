#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY' > /tmp/test_final_state.py
import io
import os
import py_compile
import secrets
import stat
import subprocess
import sys

import numpy as np
import pandas as pd
from pandas.testing import assert_frame_equal

HOME = '/home/user'
DATA_DIR = os.path.join(HOME, 'data')
PIPELINE = os.path.join(HOME, 'pipeline.py')
PARQUET = os.path.join(HOME, 'cleaned_sensors.parquet')
CORRELATION = os.path.join(HOME, 'correlation.csv')
INPUTS = [
    os.path.join(DATA_DIR, 'sensor_A.csv'),
    os.path.join(DATA_DIR, 'sensor_B.csv'),
    os.path.join(DATA_DIR, 'sensor_C.csv'),
]


def expected_outputs():
    a = pd.read_csv(INPUTS[0])
    b = pd.read_csv(INPUTS[1])
    c = pd.read_csv(INPUTS[2])
    joined = a.merge(b, on='timestamp', how='inner').merge(c, on='timestamp', how='inner')
    joined = joined.sort_values('timestamp').reset_index(drop=True)
    joined = joined[['timestamp', 'val_A', 'val_B', 'val_C']]
    corr = joined[['val_A', 'val_B', 'val_C']].corr(method='pearson')
    buf = io.StringIO()
    corr.to_csv(buf, header=False, index=False, float_format='%.4f', lineterminator='\n')
    return joined, buf.getvalue()


def execute_pipeline():
    for path in (PARQUET, CORRELATION):
        if os.path.lexists(path):
            os.remove(path)
    subprocess.run(
        [sys.executable, PIPELINE],
        cwd=HOME,
        check=True,
        timeout=60,
    )


def verify_outputs(expected_frame, expected_correlation, check_fixed_values=False):
    # Preserve the original Parquet existence and magic-byte assertions.
    assert os.path.isfile(PARQUET), f'File {PARQUET} is missing.'
    with open(PARQUET, 'rb') as f:
        header = f.read(4)
        assert header == b'PAR1', f'File {PARQUET} does not have a valid Parquet header.'
        f.seek(-4, os.SEEK_END)
        footer = f.read(4)
        assert footer == b'PAR1', f'File {PARQUET} does not have a valid Parquet footer.'

    actual_frame = pd.read_parquet(PARQUET)
    assert list(actual_frame.columns) == ['timestamp', 'val_A', 'val_B', 'val_C']
    assert_frame_equal(actual_frame.reset_index(drop=True), expected_frame, check_dtype=True)

    # Preserve the original correlation file assertions.
    assert os.path.isfile(CORRELATION), f'File {CORRELATION} is missing.'
    with open(CORRELATION, 'r') as f:
        text = f.read()
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    assert len(lines) == 3, f'Expected 3 rows in {CORRELATION}, but found {len(lines)}.'

    if check_fixed_values:
        expected_lines = [
            '1.0000,0.4640,-0.5732',
            '0.4640,1.0000,-0.4072',
            '-0.5732,-0.4072,1.0000',
        ]
        for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
            assert actual == expected, f"Row {i+1} mismatch. Expected '{expected}', got '{actual}'."

    assert text == expected_correlation, 'correlation.csv is not the derived matrix in the required format.'


def install_challenge_inputs():
    rng = np.random.default_rng(secrets.randbits(128))
    base = secrets.randbelow(500_000_000) + 1_700_000_000
    common = base + np.arange(12) * 17
    x = rng.normal(size=12)
    y = 0.7 * x + rng.normal(scale=0.8, size=12)
    z = -0.4 * x + 0.3 * y + rng.normal(scale=0.6, size=12)

    a = pd.DataFrame({'timestamp': np.r_[common, base + 1001], 'val_A': np.r_[x, rng.normal()]})
    b = pd.DataFrame({'timestamp': np.r_[common, base + 1002], 'val_B': np.r_[y, rng.normal()]})
    c = pd.DataFrame({'timestamp': np.r_[common, base + 1003], 'val_C': np.r_[z, rng.normal()]})
    a.sample(frac=1, random_state=11).to_csv(INPUTS[0], index=False)
    b.sample(frac=1, random_state=22).to_csv(INPUTS[1], index=False)
    c.sample(frac=1, random_state=33).to_csv(INPUTS[2], index=False)


def main():
    assert os.path.isfile(PIPELINE), f'File {PIPELINE} is missing.'
    mode = os.stat(PIPELINE).st_mode
    assert stat.S_ISREG(mode), f'{PIPELINE} is not a regular file.'
    assert os.path.getsize(PIPELINE) > 0, f'{PIPELINE} is empty.'
    py_compile.compile(PIPELINE, doraise=True)

    backups = {path: open(path, 'rb').read() for path in INPUTS}
    try:
        original_frame, original_corr = expected_outputs()
        execute_pipeline()
        verify_outputs(original_frame, original_corr, check_fixed_values=True)

        install_challenge_inputs()
        challenge_frame, challenge_corr = expected_outputs()
        execute_pipeline()
        verify_outputs(challenge_frame, challenge_corr)
    finally:
        for path, contents in backups.items():
            with open(path, 'wb') as f:
                f.write(contents)

    # Leave the requested artifacts generated from the original supplied data.
    original_frame, original_corr = expected_outputs()
    execute_pipeline()
    verify_outputs(original_frame, original_corr, check_fixed_values=True)


if __name__ == '__main__':
    main()
PY

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
