#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import ast
import csv
import hashlib
import os
import re
import subprocess
import traceback

import matplotlib.image as mpimg
import numpy as np
import pandas as pd
from sklearn.decomposition import PCA
from sklearn.preprocessing import StandardScaler

SCRIPT = '/home/user/etl_pipeline.py'
DATA = '/home/user/data.csv'
OUTPUT = '/home/user/output.csv'
PLOT = '/home/user/pca_plot.png'


def inspect_script():
    assert os.path.exists(SCRIPT), f"Script file {SCRIPT} is missing."
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is not a file."
    with open(SCRIPT, 'r', encoding='utf-8') as f:
        content = f.read()

    # Preserve the original source assertions.
    assert 'Agg' in content or 'savefig' in content, \
        "The script does not appear to use the Agg backend or savefig."
    assert 'plt.show()' not in content or content.startswith('#') or '#' in content.split('plt.show()')[0] or 'show()' not in content, \
        "The script still contains an active plt.show() which will crash in a headless environment."

    tree = ast.parse(content, filename=SCRIPT)
    calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)]

    active_show = any(
        isinstance(call.func, ast.Attribute) and call.func.attr == 'show'
        for call in calls
    )
    assert not active_show, "The script still contains an active show() call."

    saves_plot = any(
        isinstance(call.func, ast.Attribute) and call.func.attr == 'savefig'
        for call in calls
    )
    assert saves_plot, "The script must save the plot with savefig()."

    agg_call = False
    for call in calls:
        if isinstance(call.func, ast.Attribute) and call.func.attr in ('use', 'switch_backend'):
            if call.args and isinstance(call.args[0], ast.Constant):
                agg_call |= str(call.args[0].value).lower() == 'agg'
    agg_environment = bool(re.search(r'MPLBACKEND[^\n]*Agg', content, re.IGNORECASE))
    assert agg_call or agg_environment, "The script does not explicitly configure the Agg backend."


def expected_rows(df):
    imputed = df.fillna(df.mean(numeric_only=True))
    scaled = StandardScaler().fit_transform(imputed)
    components = PCA(n_components=2, random_state=42).fit_transform(scaled)
    return [[f'{value:.4f}' for value in row] for row in components]


def run_script():
    for path in (OUTPUT, PLOT):
        if os.path.lexists(path):
            os.remove(path)
    env = os.environ.copy()
    env.pop('DISPLAY', None)
    env.pop('MPLBACKEND', None)
    result = subprocess.run(
        ['python3', SCRIPT], cwd='/home/user', env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=30
    )
    assert result.returncode == 0, \
        f"Pipeline failed in a headless environment.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"


def validate_csv(df, require_original_first_row=False):
    assert os.path.exists(OUTPUT), f"The output file {OUTPUT} does not exist."
    assert os.path.isfile(OUTPUT), f"{OUTPUT} is not a file."

    with open(OUTPUT, 'r', encoding='utf-8', newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ['PC1', 'PC2'], \
            f"CSV header is incorrect. Expected ['PC1', 'PC2'], got {header}"
        rows = list(reader)

    assert len(rows) == len(df), f"Expected {len(df)} data rows in CSV, got {len(rows)}"
    for i, row in enumerate(rows):
        assert len(row) == 2, f"Row {i+1} does not have exactly 2 columns: {row}"
        for value in row:
            try:
                parsed = float(value)
            except ValueError:
                raise AssertionError(f"Row {i+1} contains non-float values: {row}")
            assert np.isfinite(parsed), f"Row {i+1} contains a non-finite value: {row}"
            assert re.fullmatch(r'-?\d+\.\d{4}', value), \
                f"Value {value!r} in row {i+1} is not written to exactly 4 decimal places."

    expected = expected_rows(df)
    assert rows == expected, "PCA output does not match mean imputation, standard scaling, and PCA for every row."

    if require_original_first_row:
        assert len(rows) == 50, f"Expected 50 data rows in CSV, got {len(rows)}"
        first_row_pc1 = float(rows[0][0])
        assert abs(first_row_pc1 - (-0.4137)) < 0.05, \
            f"PC1 value in first row is incorrect. Expected ~-0.4137, got {first_row_pc1}"


def validate_plot():
    assert os.path.exists(PLOT), f"The plot file {PLOT} does not exist."
    assert os.path.isfile(PLOT), f"{PLOT} is not a file."
    assert os.path.getsize(PLOT) > 0, f"The plot file {PLOT} is empty."
    with open(PLOT, 'rb') as f:
        raw = f.read()
    assert raw.startswith(b'\x89PNG\r\n\x1a\n'), "pca_plot.png is not a PNG file."
    image = mpimg.imread(PLOT)
    assert image.ndim in (2, 3) and image.shape[0] >= 100 and image.shape[1] >= 100, \
        "The saved PNG is not a usable plot image."
    assert float(np.nanstd(image)) > 0.01, "The saved PNG appears blank."
    return raw, image.copy()


def generated_frame(seed, shift):
    rng = np.random.default_rng(seed)
    values = rng.normal(loc=shift, scale=[0.7, 1.3, 2.1, 0.9, 1.7], size=(50, 5))
    values[:, 1] += np.linspace(-2.0, 3.0, 50)
    values[:, 3] += values[:, 0] * 0.8
    for row, col in ((1, 0), (7, 2), (18, 4), (29, 1), (41, 3)):
        values[row, col] = np.nan
    return pd.DataFrame(values, columns=['A', 'B', 'C', 'D', 'E'])


def main():
    inspect_script()
    with open(DATA, 'rb') as f:
        original_data = f.read()
    original_df = pd.read_csv(DATA)

    error = None
    trial_images = []
    try:
        seeds = [int.from_bytes(os.urandom(8), 'big'), int.from_bytes(os.urandom(8), 'big')]
        for index, seed in enumerate(seeds):
            frame = generated_frame(seed, shift=index * 3.5)
            frame.to_csv(DATA, index=False)
            run_script()
            validate_csv(frame)
            raw, image = validate_plot()
            trial_images.append((hashlib.sha256(raw).digest(), image))

        same_pixels = (
            trial_images[0][1].shape == trial_images[1][1].shape
            and np.array_equal(trial_images[0][1], trial_images[1][1])
        )
        assert not same_pixels, "The plot image did not change when the PCA input changed."
    except BaseException:
        error = traceback.format_exc()
    finally:
        with open(DATA, 'wb') as f:
            f.write(original_data)
        try:
            run_script()
            validate_csv(original_df, require_original_first_row=True)
            validate_plot()
        except BaseException:
            final_error = traceback.format_exc()
            error = (error + '\nFinal original-data run also failed:\n' + final_error) if error else final_error

    if error:
        raise AssertionError(error)


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
