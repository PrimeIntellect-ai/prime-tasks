#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import struct
import math
import json
import subprocess
import textwrap
import hashlib
import numpy as np


def test_c_file_exists_and_openmp():
    path = "/home/user/process_spectra.c"
    assert os.path.exists(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    assert "#pragma omp" in content, "OpenMP pragma (#pragma omp) missing in C code."


def test_executable_exists():
    path = "/home/user/process_spectra"
    assert os.path.exists(path), f"Executable {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_python_script_exists():
    path = "/home/user/plot_energies.py"
    assert os.path.exists(path), f"Python script {path} does not exist."


def test_png_exists():
    path = "/home/user/energies_plot.png"
    assert os.path.exists(path), f"Plot image {path} does not exist."


def test_energies_csv():
    csv_path = "/home/user/energies.csv"
    assert os.path.exists(csv_path), f"CSV file {csv_path} does not exist."

    spectra_path = "/home/user/spectra.dat"
    assert os.path.exists(spectra_path), f"Data file {spectra_path} does not exist."

    with open(spectra_path, "rb") as f:
        data = f.read()

    N = 1000
    M = 2048
    assert len(data) == N * M * 8, "spectra.dat size is incorrect."

    # Compute expected energies
    expected_energies = []
    for i in range(N):
        offset = i * M * 8
        signal_bytes = data[offset:offset + M * 8]
        signal = struct.unpack(f"{M}d", signal_bytes)

        energy = 0.0
        for j in range(M):
            w = 0.5 * (1.0 - math.cos(2.0 * math.pi * j / (M - 1)))
            xw = signal[j] * w
            energy += xw * xw
        expected_energies.append(energy)

    with open(csv_path, "r") as f:
        lines = f.read().strip().split('\n')

    assert len(lines) == N + 1, f"CSV should have 1001 lines (header + 1000 data rows), found {len(lines)}."
    assert lines[0].strip() == "Signal_ID,Energy", f"CSV header mismatch. Expected 'Signal_ID,Energy', got '{lines[0].strip()}'."

    for i in range(N):
        parts = lines[i+1].strip().split(',')
        assert len(parts) == 2, f"CSV format error on line {i+2}: {lines[i+1]}"
        assert int(parts[0]) == i, f"Signal_ID mismatch on line {i+2}. Expected {i}, got {parts[0]}."

        actual_energy = float(parts[1])
        expected_energy = expected_energies[i]

        # Check within a reasonable tolerance for formatting string %.6f
        assert math.isclose(actual_energy, expected_energy, rel_tol=1e-5), \
            f"Energy mismatch at Signal_ID {i}: expected {expected_energy:.6f}, got {actual_energy:.6f}."


def _assert_openmp_binary(path):
    result = subprocess.run(
        ["nm", "-D", path], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, check=True
    )
    assert "GOMP_" in result.stdout or "omp_" in result.stdout, \
        f"{path} does not contain references to the OpenMP runtime."


def _run_and_validate(binary):
    N, M = 1000, 2048
    seed = int.from_bytes(os.urandom(16), "little")
    rng = np.random.default_rng(seed)
    data = rng.normal(0.0, 1.7, size=(N, M)).astype(np.float64)
    data += rng.uniform(-0.75, 0.75, size=(N, 1))
    data.tofile("/home/user/spectra.dat")

    csv_path = "/home/user/energies.csv"
    if os.path.lexists(csv_path):
        if os.path.isdir(csv_path) and not os.path.islink(csv_path):
            os.rmdir(csv_path)
        else:
            os.unlink(csv_path)

    env = os.environ.copy()
    env["OMP_NUM_THREADS"] = "4"
    env["OMP_DYNAMIC"] = "FALSE"
    subprocess.run(
        [binary], cwd="/", env=env, check=True, timeout=60,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )

    assert os.path.isfile(csv_path), f"{binary} did not create energies.csv."
    with open(csv_path, "r", newline="") as f:
        raw = f.read()
    lines = raw.splitlines()
    assert len(lines) == N + 1
    assert lines[0] == "Signal_ID,Energy"

    window = 0.5 * (1.0 - np.cos(2.0 * np.pi * np.arange(M) / (M - 1)))
    expected = np.sum((data * window) ** 2, axis=1)
    actual = np.empty(N, dtype=np.float64)
    for i, line in enumerate(lines[1:]):
        assert re.fullmatch(rf"{i},[+-]?\d+\.\d{{6}}", line), \
            f"CSV line {i + 2} is not in %d,%.6f format: {line!r}"
        actual[i] = float(line.split(",", 1)[1])
    assert np.allclose(actual, expected, rtol=1e-5, atol=1e-6), \
        "Executable produced incorrect energies for verifier-generated spectra."


def test_compile_and_execute_c_openmp_implementation():
    source = "/home/user/process_spectra.c"
    required_binary = "/home/user/process_spectra"
    with open(source, "r") as f:
        content = f.read()

    combined = re.search(r"#\s*pragma\s+omp\s+parallel\s+for\b", content, re.I)
    separate = (re.search(r"#\s*pragma\s+omp\s+parallel\b", content, re.I) and
                re.search(r"#\s*pragma\s+omp\s+for\b", content, re.I))
    assert combined or separate, "C source does not use an OpenMP parallel loop."

    rebuilt = "/tmp/process_spectra_rebuilt"
    subprocess.run(
        ["gcc", "-O2", "-fopenmp", source, "-o", rebuilt, "-lm"],
        check=True, timeout=60, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    _assert_openmp_binary(required_binary)
    _assert_openmp_binary(rebuilt)

    # Exercise both the requested executable and a fresh build of the submitted source
    # on independently generated data, preventing precomputed CSVs or dummy binaries.
    _run_and_validate(required_binary)
    _run_and_validate(rebuilt)


def test_execute_plot_script_and_validate_scatter():
    script = "/home/user/plot_energies.py"
    png = "/home/user/energies_plot.png"
    with open(script, "r") as f:
        content = f.read()
    assert re.search(r"\bmatplotlib\b", content), "Plotting script does not use matplotlib."

    probe_dir = "/tmp/mpl_probe"
    os.makedirs(probe_dir, exist_ok=True)
    probe_file = "/tmp/scatter_calls.json"
    try:
        os.unlink(probe_file)
    except FileNotFoundError:
        pass

    sitecustomize = r'''
import atexit
import json
import numpy as np
from matplotlib.axes import Axes

_calls = []
_original_scatter = Axes.scatter

def _scatter(self, x, y, *args, **kwargs):
    try:
        data = kwargs.get("data")
        if isinstance(x, str) and data is not None:
            x = data[x]
        if isinstance(y, str) and data is not None:
            y = data[y]
        xa = np.asarray(x).reshape(-1).astype(float)
        ya = np.asarray(y).reshape(-1).astype(float)
        if xa.size <= 10000 and ya.size <= 10000:
            _calls.append({"x": xa.tolist(), "y": ya.tolist()})
    except Exception:
        pass
    return _original_scatter(self, x, y, *args, **kwargs)

Axes.scatter = _scatter

@atexit.register
def _save_calls():
    with open("/tmp/scatter_calls.json", "w") as f:
        json.dump(_calls, f)
'''
    with open(os.path.join(probe_dir, "sitecustomize.py"), "w") as f:
        f.write(textwrap.dedent(sitecustomize))

    if os.path.lexists(png):
        if os.path.isdir(png) and not os.path.islink(png):
            os.rmdir(png)
        else:
            os.unlink(png)

    env = os.environ.copy()
    env["MPLBACKEND"] = "Agg"
    env["PYTHONPATH"] = probe_dir + os.pathsep + env.get("PYTHONPATH", "")
    subprocess.run(
        ["python3", script], cwd="/", env=env, check=True, timeout=60,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )

    assert os.path.isfile(png), "Running plot_energies.py did not create energies_plot.png."
    with open(png, "rb") as f:
        signature = f.read(8)
    assert signature == b"\x89PNG\r\n\x1a\n", "energies_plot.png is not a PNG image."

    import matplotlib.image as mpimg
    image = mpimg.imread(png)
    assert image.ndim in (2, 3) and image.shape[0] >= 100 and image.shape[1] >= 100, \
        "Generated plot has invalid dimensions."
    assert float(np.nanmax(image) - np.nanmin(image)) > 0.05, "Generated plot is blank."

    assert os.path.isfile(probe_file), "No matplotlib scatter-call record was produced."
    with open(probe_file, "r") as f:
        calls = json.load(f)

    ids = []
    energies = []
    with open("/home/user/energies.csv", "r") as f:
        next(f)
        for line in f:
            signal_id, energy = line.strip().split(",")
            ids.append(float(signal_id))
            energies.append(float(energy))
    ids = np.asarray(ids)
    energies = np.asarray(energies)

    matched = False
    for call in calls:
        x = np.asarray(call.get("x", []), dtype=float)
        y = np.asarray(call.get("y", []), dtype=float)
        if (x.shape == ids.shape and y.shape == energies.shape and
                np.allclose(x, ids, rtol=0, atol=0) and
                np.allclose(y, energies, rtol=1e-12, atol=1e-12)):
            matched = True
            break
    assert matched, "The script did not scatter Energy versus Signal_ID from energies.csv."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
