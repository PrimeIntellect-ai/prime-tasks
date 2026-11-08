#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import math
import os
import re
import struct
import subprocess
import sys
import textwrap

import numpy as np
import pytest
from scipy.optimize import brentq

OUTPUTS = [
    "/home/user/normalized_dataset.npy",
    "/home/user/dataset_visualization.png",
    "/home/user/dataset_stats.txt",
]
PLOT_LOG = "/tmp/dataset_plot_log.json"


def expected_data():
    values = np.linspace(-5.0, 5.0, 25)
    xx, yy = np.meshgrid(values, values)
    x = xx.ravel()
    y = yy.ravel()
    z = np.array([
        brentq(lambda value: value ** 3 + np.sin(value) - (xv * yv), -4.0, 4.0)
        for xv, yv in zip(x, y)
    ])
    raw = np.column_stack((x, y, z))
    normalized = (raw - raw.mean(axis=0)) / raw.std(axis=0, ddof=0)
    return raw, normalized


def sorted_rows(array):
    return np.asarray(sorted(map(tuple, np.asarray(array, dtype=float))))


def test_00_execute_submission_script():
    """Execute the submitted Python script and require it to regenerate all outputs."""
    scripts = sorted(
        path for path in glob.glob("/home/user/**/*.py", recursive=True)
        if os.path.isfile(path) and not path.startswith("/home/user/.cache/")
    )
    assert scripts, "No Python script was found under /home/user."

    hook_dir = "/tmp/verifier_hook"
    os.makedirs(hook_dir, exist_ok=True)
    hook = r'''
import json
import os
import numpy as np
from matplotlib.figure import Figure
from mpl_toolkits.mplot3d.axes3d import Axes3D

_calls = []
_original_scatter = Axes3D.scatter
_original_savefig = Figure.savefig


def _scatter(self, xs, ys, zs=0, *args, **kwargs):
    try:
        xa = np.asarray(xs, dtype=float).ravel()
        ya = np.asarray(ys, dtype=float).ravel()
        za = np.asarray(zs, dtype=float).ravel()
        if za.size == 1 and xa.size != 1:
            za = np.full(xa.size, float(za[0]))
        _calls.append({"x": xa.tolist(), "y": ya.tolist(), "z": za.tolist()})
    except Exception:
        pass
    return _original_scatter(self, xs, ys, zs, *args, **kwargs)


def _savefig(self, fname, *args, **kwargs):
    try:
        if os.path.basename(os.fspath(fname)) == "dataset_visualization.png":
            axes = []
            for ax in self.axes:
                axes.append({
                    "xlabel": ax.get_xlabel(),
                    "ylabel": ax.get_ylabel(),
                    "zlabel": ax.get_zlabel() if hasattr(ax, "get_zlabel") else None,
                })
            with open("/tmp/dataset_plot_log.json", "w") as f:
                json.dump({"scatter_calls": _calls, "axes": axes}, f)
    except Exception:
        pass
    return _original_savefig(self, fname, *args, **kwargs)


Axes3D.scatter = _scatter
Figure.savefig = _savefig
'''
    with open(os.path.join(hook_dir, "sitecustomize.py"), "w") as f:
        f.write(textwrap.dedent(hook))

    errors = []
    for script in scripts:
        for output in OUTPUTS:
            try:
                os.remove(output)
            except FileNotFoundError:
                pass
        try:
            os.remove(PLOT_LOG)
        except FileNotFoundError:
            pass

        env = os.environ.copy()
        env["MPLBACKEND"] = "Agg"
        env["PYTHONPATH"] = hook_dir + os.pathsep + env.get("PYTHONPATH", "")
        try:
            result = subprocess.run(
                [sys.executable, script],
                cwd="/home/user",
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=120,
            )
        except Exception as exc:
            errors.append(f"{script}: {exc}")
            continue

        if result.returncode == 0 and all(os.path.isfile(path) for path in OUTPUTS):
            return
        errors.append(f"{script}: exit={result.returncode}, stderr={result.stderr[-500:]}")

    pytest.fail("No submitted Python script successfully regenerated all outputs. " + " | ".join(errors))


def test_dataset_stats_txt():
    """Check that dataset_stats.txt contains the correct max Z value."""
    stats_file = "/home/user/dataset_stats.txt"
    assert os.path.exists(stats_file), f"{stats_file} does not exist."

    with open(stats_file, "r") as f:
        content = f.read().strip()

    expected_str = "Max Z: 2.9155"
    assert expected_str in content, f"Expected '{expected_str}' in {stats_file}, but got '{content}'."


def test_dataset_visualization_png():
    """Check that dataset_visualization.png exists and is a valid PNG file."""
    img_file = "/home/user/dataset_visualization.png"
    assert os.path.exists(img_file), f"{img_file} does not exist."

    with open(img_file, "rb") as f:
        header = f.read(8)

    png_signature = b'\x89PNG\r\n\x1a\n'
    assert header == png_signature, f"{img_file} is not a valid PNG file based on its signature."


def test_normalized_dataset_npy():
    """Check the normalized_dataset.npy file for shape, mean, and std without third-party libraries."""
    npy_file = "/home/user/normalized_dataset.npy"
    assert os.path.exists(npy_file), f"{npy_file} does not exist."

    with open(npy_file, "rb") as f:
        magic = f.read(6)
        assert magic == b'\x93NUMPY', f"{npy_file} is not a valid .npy file."

        major, minor = struct.unpack('<BB', f.read(2))
        if major == 1:
            header_len = struct.unpack('<H', f.read(2))[0]
        elif major == 2:
            header_len = struct.unpack('<I', f.read(4))[0]
        else:
            pytest.fail(f"Unsupported .npy version: {major}")

        header_str = f.read(header_len).decode('ascii')

        shape_match = re.search(r"'shape':\s*\(\s*(\d+)\s*,\s*(\d+)\s*\)", header_str)
        assert shape_match is not None, "Could not parse shape from .npy header."
        rows, cols = int(shape_match.group(1)), int(shape_match.group(2))
        assert rows == 625 and cols == 3, f"Expected shape (625, 3), got ({rows}, {cols})."

        descr_match = re.search(r"'descr':\s*'([^']+)'", header_str)
        assert descr_match is not None, "Could not parse descr from .npy header."
        descr = descr_match.group(1)

        data_bytes = f.read()

    if descr == '<f8':
        fmt = f'<{rows * cols}d'
        expected_bytes = rows * cols * 8
    elif descr == '<f4':
        fmt = f'<{rows * cols}f'
        expected_bytes = rows * cols * 4
    else:
        pytest.fail(f"Unsupported data type in .npy file: {descr}")

    assert len(data_bytes) >= expected_bytes, "Not enough data in .npy file."
    data_bytes = data_bytes[:expected_bytes]
    floats = struct.unpack(fmt, data_bytes)

    for col in range(cols):
        col_data = [floats[r * cols + col] for r in range(rows)]
        mean = sum(col_data) / rows
        variance = sum((x - mean) ** 2 for x in col_data) / rows
        std = math.sqrt(variance)

        assert abs(mean) < 1e-3, f"Column {col} mean is {mean}, expected ~0.0"
        assert abs(std - 1.0) < 1e-3, f"Column {col} std is {std}, expected ~1.0"


def test_outputs_match_equation_grid_and_plot():
    """Verify the saved data, statistic, and plotted points against independently derived values."""
    raw, expected_normalized = expected_data()

    actual = np.load("/home/user/normalized_dataset.npy", allow_pickle=False)
    assert actual.shape == (625, 3)
    assert np.issubdtype(actual.dtype, np.floating)
    assert np.isfinite(actual).all()
    np.testing.assert_allclose(
        sorted_rows(actual),
        sorted_rows(expected_normalized),
        rtol=1e-5,
        atol=1e-5,
        err_msg="The normalized rows do not correspond to the required grid and nonlinear equation.",
    )

    expected_stats = f"Max Z: {raw[:, 2].max():.4f}"
    with open("/home/user/dataset_stats.txt", "r") as f:
        assert f.read().strip() == expected_stats

    import matplotlib.image as mpimg
    image = mpimg.imread("/home/user/dataset_visualization.png")
    assert image.ndim in (2, 3), "The PNG could not be decoded as an image."
    assert image.shape[0] >= 100 and image.shape[1] >= 100, "Visualization is implausibly small."
    assert np.isfinite(image).all() and float(np.std(image)) > 0.01, "Visualization is blank or invalid."

    assert os.path.exists(PLOT_LOG), "The script did not save a matplotlib figure for the requested visualization."
    with open(PLOT_LOG, "r") as f:
        plot_log = json.load(f)

    axes = plot_log.get("axes", [])
    assert any(
        ax.get("xlabel") == "X" and ax.get("ylabel") == "Y" and ax.get("zlabel") == "Z"
        for ax in axes
    ), "The saved 3D plot must label its axes X, Y, and Z."

    plotted = []
    for call in plot_log.get("scatter_calls", []):
        x = np.asarray(call.get("x", []), dtype=float)
        y = np.asarray(call.get("y", []), dtype=float)
        z = np.asarray(call.get("z", []), dtype=float)
        if x.size == y.size == z.size:
            plotted.extend(np.column_stack((x, y, z)).tolist())
    assert len(plotted) == 625, f"Expected exactly 625 plotted scatter points, found {len(plotted)}."
    np.testing.assert_allclose(
        sorted_rows(plotted),
        sorted_rows(raw),
        rtol=1e-5,
        atol=1e-5,
        err_msg="The visualization does not plot the required unnormalized manifold.",
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
