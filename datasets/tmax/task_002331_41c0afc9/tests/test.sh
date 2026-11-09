#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.metadata
import json
import os
import subprocess
import sys
import tempfile
import uuid

import matplotlib.image as mpimg
import numpy as np
import pytest

CLEAN_CORPUS_DIR = "/app/corpus/clean/"
EVIL_CORPUS_DIR = "/app/corpus/evil/"
DETECTOR_SCRIPT = "/home/user/detector.py"
VISUALIZE_SCRIPT = "/home/user/visualize.py"
PLOT_FILE = "/home/user/svd_plot.png"
PACKAGE_DIR = "/app/fast_svd_custom-0.1.0"


def run_detector(path, instrumentation_dir=None, marker=None):
    env = os.environ.copy()
    if instrumentation_dir:
        env["PYTHONPATH"] = instrumentation_dir + os.pathsep + env.get("PYTHONPATH", "")
    if marker:
        env["SVD_CALL_MARKER"] = marker
    return subprocess.run(
        [sys.executable, DETECTOR_SCRIPT, path],
        capture_output=True,
        text=True,
        timeout=20,
        env=env,
    )


def test_detector_exists():
    assert os.path.isfile(DETECTOR_SCRIPT), f"Detector script missing: {DETECTOR_SCRIPT}"


def test_visualize_exists():
    assert os.path.isfile(VISUALIZE_SCRIPT), f"Visualization script missing: {VISUALIZE_SCRIPT}"


def test_plot_exists():
    assert os.path.isfile(PLOT_FILE), f"Plot file missing: {PLOT_FILE}"
    assert os.path.getsize(PLOT_FILE) > 0, f"Plot file is empty: {PLOT_FILE}"


def test_package_is_installed_and_functional(tmp_path):
    dist = importlib.metadata.distribution("fast_svd_custom")
    assert dist.version == "0.1.0"

    import fast_svd_custom
    module_path = os.path.realpath(fast_svd_custom.__file__)
    assert not module_path.startswith(os.path.realpath(PACKAGE_DIR) + os.sep), \
        "fast_svd_custom is only importable from the source tree, not installed"

    matrix = np.array([[3.0, 1.0], [0.0, 2.0]])
    u, s, vh = fast_svd_custom.get_svd(matrix)
    assert np.allclose(u @ np.diag(s) @ vh, matrix)
    assert np.allclose(s, np.linalg.svd(matrix, compute_uv=False))

    regression = subprocess.run(
        [sys.executable, "-m", "pytest", "tests/"],
        cwd=PACKAGE_DIR,
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert regression.returncode == 0, regression.stdout + regression.stderr

    wheel_dir = tmp_path / "wheel"
    wheel_dir.mkdir()
    build = subprocess.run(
        [sys.executable, "-m", "pip", "wheel", "--no-deps", "--no-build-isolation",
         "-w", str(wheel_dir), PACKAGE_DIR],
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert build.returncode == 0, build.stdout + build.stderr
    assert list(wheel_dir.glob("fast_svd_custom-0.1.0-*.whl")), "Package did not build a wheel"


def test_detector_clean_corpus():
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith(".npy")]
    assert len(clean_files) > 0, "No clean corpus files found."

    failed_clean = []
    for f in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, f)
        result = run_detector(filepath)
        if result.returncode != 0 or result.stdout.strip() != "CLEAN":
            failed_clean.append(f)

    assert len(failed_clean) == 0, f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected. Offending files: {failed_clean}"


def test_detector_evil_corpus():
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith(".npy")]
    assert len(evil_files) > 0, "No evil corpus files found."

    failed_evil = []
    for f in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, f)
        result = run_detector(filepath)
        if result.returncode != 0 or result.stdout.strip() != "EVIL":
            failed_evil.append(f)

    assert len(failed_evil) == 0, f"{len(failed_evil)} of {len(evil_files)} evil bypassed. Offending files: {failed_evil}"


def test_detector_on_opaque_generated_inputs_and_uses_custom_svd(tmp_path):
    instrumentation = tmp_path / "instrumentation"
    instrumentation.mkdir()
    (instrumentation / "sitecustomize.py").write_text(
        """import os\n"
        "marker = os.environ.get('SVD_CALL_MARKER')\n"
        "if marker:\n"
        "    import fast_svd_custom\n"
        "    _real_get_svd = fast_svd_custom.get_svd\n"
        "    def _checked_get_svd(*args, **kwargs):\n"
        "        with open(marker, 'a', encoding='utf-8') as f:\n"
        "            f.write('called\\n')\n"
        "        return _real_get_svd(*args, **kwargs)\n"
        "    fast_svd_custom.get_svd = _checked_get_svd\n"
        """,
        encoding="utf-8",
    )

    data_dir = tmp_path / ("inputs_" + uuid.uuid4().hex)
    data_dir.mkdir()
    rng = np.random.default_rng(20260911)
    base = rng.normal(size=(7, 7))
    spd = base @ base.T + np.eye(7) * 0.25
    diagonal_spd = np.diag([0.2, 0.5, 1.0, 2.0, 4.0])
    asymmetric = spd.copy()
    asymmetric[1, 5] += 0.02
    indefinite = np.diag([4.0, 2.0, 1.0, -0.25, 3.0])
    semidefinite = np.diag([4.0, 2.0, 1.0, 0.0, 3.0])

    cases = [
        (spd, "CLEAN"),
        (diagonal_spd, "CLEAN"),
        (asymmetric, "EVIL"),
        (indefinite, "EVIL"),
        (semidefinite, "EVIL"),
    ]
    rng.shuffle(cases)

    for matrix, expected in cases:
        path = data_dir / (uuid.uuid4().hex + ".npy")
        marker = tmp_path / (uuid.uuid4().hex + ".marker")
        np.save(path, matrix)
        result = run_detector(str(path), str(instrumentation), str(marker))
        assert result.returncode == 0, result.stderr
        assert result.stdout.strip() == expected, f"Wrong classification for generated matrix: {result.stdout!r}"
        assert marker.is_file() and marker.read_text(encoding="utf-8").strip(), \
            "detector.py did not call fast_svd_custom.get_svd"


def test_detector_requires_exactly_one_argument():
    no_arg = subprocess.run([sys.executable, DETECTOR_SCRIPT], capture_output=True, text=True, timeout=20)
    extra_arg = subprocess.run(
        [sys.executable, DETECTOR_SCRIPT, "one.npy", "two.npy"],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert no_arg.returncode != 0
    assert extra_arg.returncode != 0


def test_visualization_executes_and_plots_actual_singular_values(tmp_path):
    matrix_dir = tmp_path / ("matrices_" + uuid.uuid4().hex)
    matrix_dir.mkdir()
    matrices = [
        np.diag([9.0, 4.0, 1.0]),
        np.diag([6.0, 2.5, 0.5]),
        np.array([[3.0, 1.0, 0.0], [0.0, 2.0, 0.0], [0.0, 0.0, 0.25]]),
    ]
    for matrix in matrices:
        np.save(matrix_dir / (uuid.uuid4().hex + ".npy"), matrix)

    instrumentation = tmp_path / "viz_instrumentation"
    instrumentation.mkdir()
    scatter_log = tmp_path / "scatter.jsonl"
    (instrumentation / "sitecustomize.py").write_text(
        """import json, os\n"
        "log = os.environ.get('SCATTER_LOG')\n"
        "if log:\n"
        "    from matplotlib.axes import Axes\n"
        "    _real_scatter = Axes.scatter\n"
        "    def _record_scatter(self, x, y, *args, **kwargs):\n"
        "        with open(log, 'a', encoding='utf-8') as f:\n"
        "            f.write(json.dumps([list(x), list(y)]) + '\\n')\n"
        "        return _real_scatter(self, x, y, *args, **kwargs)\n"
        "    Axes.scatter = _record_scatter\n"
        """,
        encoding="utf-8",
    )

    if os.path.exists(PLOT_FILE):
        os.remove(PLOT_FILE)
    env = os.environ.copy()
    env["PYTHONPATH"] = str(instrumentation) + os.pathsep + env.get("PYTHONPATH", "")
    env["SCATTER_LOG"] = str(scatter_log)
    env["MPLBACKEND"] = "Agg"
    result = subprocess.run(
        [sys.executable, VISUALIZE_SCRIPT, "--dir", str(matrix_dir)],
        capture_output=True,
        text=True,
        timeout=60,
        env=env,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert os.path.isfile(PLOT_FILE) and os.path.getsize(PLOT_FILE) > 0
    with open(PLOT_FILE, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", "svd_plot.png is not a PNG image"
    image = mpimg.imread(PLOT_FILE)
    assert image.ndim in (2, 3) and image.shape[0] > 10 and image.shape[1] > 10
    assert float(np.max(image) - np.min(image)) > 0.01, "Plot image appears blank"

    assert scatter_log.is_file(), "visualize.py did not create a scatter plot"
    records = [json.loads(line) for line in scatter_log.read_text(encoding="utf-8").splitlines()]
    expected = sorted(
        (float(np.linalg.svd(m, compute_uv=False)[0]), float(np.linalg.svd(m, compute_uv=False)[1]))
        for m in matrices
    )
    matched = False
    for xs, ys in records:
        if len(xs) == len(expected) and len(ys) == len(expected):
            actual = sorted((float(x), float(y)) for x, y in zip(xs, ys))
            if np.allclose(actual, expected, rtol=1e-6, atol=1e-8):
                matched = True
                break
    assert matched, "Scatter coordinates are not the first and second singular values of the input matrices"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
