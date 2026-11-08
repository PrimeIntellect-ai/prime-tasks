#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "h5py:h5py"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import struct
import subprocess

import h5py
import numpy as np
import pytest

HOME = "/home/user"


def validate_callgrind(path):
    assert os.path.isfile(path), f"Callgrind output file {path} is missing."
    assert os.path.getsize(path) > 1000, f"Callgrind output file {path} is too small."
    with open(path, "r", errors="ignore") as f:
        content = f.read()
    lower = content.lower()
    assert "creator: callgrind" in lower or "events:" in lower or "positions:" in lower, \
        "File does not appear to be a valid callgrind output."
    assert re.search(r"(?m)^events:\s*\S+", content), "Callgrind events declaration is missing."
    summary = re.search(r"(?m)^summary:\s+([0-9 ]+)$", content)
    assert summary, "Callgrind summary is missing."
    assert any(int(x) > 0 for x in summary.group(1).split()), "Callgrind recorded no events."
    assert "/home/user/spectromark" in content, "Callgrind output does not identify the SpectroMark executable."


@pytest.fixture(scope="session", autouse=True)
def execute_and_prepare(tmp_path_factory):
    binary = "/home/user/spectromark"
    assert os.path.isfile(binary), f"Compiled binary {binary} is missing."
    assert os.access(binary, os.X_OK), f"Compiled binary {binary} is not executable."

    work = tmp_path_factory.mktemp("spectromark_verify")
    generated_callgrind = str(work / "callgrind.out")

    for path in ("/home/user/spectra.h5", "/home/user/svd_results.txt", "/home/user/svd_plot.png"):
        if os.path.lexists(path):
            os.remove(path)

    valgrind = shutil.which("valgrind")
    assert valgrind, "Valgrind is not installed."
    run = subprocess.run(
        [valgrind, "--tool=callgrind", f"--callgrind-out-file={generated_callgrind}", binary],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=600,
    )
    assert run.returncode == 0, f"SpectroMark failed under Callgrind:\n{run.stdout}\n{run.stderr}"
    validate_callgrind(generated_callgrind)

    plot_script = "/home/user/plot_svd.py"
    assert os.path.isfile(plot_script), f"Python visualization script {plot_script} is missing."
    env = os.environ.copy()
    env["MPLBACKEND"] = "Agg"
    plotted = subprocess.run(
        ["python3", plot_script], cwd=HOME, env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=120,
    )
    assert plotted.returncode == 0, f"Visualization script failed:\n{plotted.stdout}\n{plotted.stderr}"


def test_source_code_exists():
    assert os.path.isfile("/home/user/spectromark.cpp"), "C++ source code /home/user/spectromark.cpp is missing."


def test_compiled_binary_exists_and_is_elf():
    binary_path = "/home/user/spectromark"
    assert os.path.isfile(binary_path), f"Compiled binary {binary_path} is missing."
    with open(binary_path, "rb") as f:
        magic = f.read(4)
    assert magic == b"\x7fELF", f"{binary_path} is not a valid ELF binary."
    assert os.access(binary_path, os.X_OK), f"{binary_path} is not executable."


def expected_matrix(tmp_path):
    generator = tmp_path / "expected.cpp"
    output = tmp_path / "expected.bin"
    generator.write_text(r'''
#include <cmath>
#include <cstdint>
#include <fstream>
#include <random>
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    std::mt19937 gen(42);
    std::uniform_real_distribution<double> dist(0.0, 0.1);
    std::ofstream out(argv[1], std::ios::binary);
    if (!out) return 3;
    for (int i = 0; i < 1000; ++i) {
        for (int j = 0; j < 500; ++j) {
            double value = std::sin(j * 0.05) + dist(gen);
            out.write(reinterpret_cast<const char *>(&value), sizeof(value));
        }
    }
    return out ? 0 : 4;
}
''')
    subprocess.run(
        ["g++", "-std=c++11", "-O2", str(generator), "-o", str(tmp_path / "expected")],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60,
    )
    subprocess.run([str(tmp_path / "expected"), str(output)], check=True, timeout=60)
    values = np.fromfile(output, dtype=np.float64)
    assert values.size == 1000 * 500
    return values.reshape(1000, 500)


def test_hdf5_file_exists_and_valid(tmp_path):
    h5_path = "/home/user/spectra.h5"
    assert os.path.isfile(h5_path), f"HDF5 file {h5_path} is missing."

    with open(h5_path, "rb") as f:
        magic = f.read(8)
    assert magic == b"\x89HDF\x0d\x0a\x1a\x0a", f"{h5_path} is not a valid HDF5 file."

    if shutil.which("h5ls"):
        result = subprocess.run(["h5ls", h5_path], capture_output=True, text=True)
        assert "raw_data" in result.stdout and "1000, 500" in result.stdout, \
            "Dataset 'raw_data' of size 1000x500 not found in HDF5 file."

    expected = expected_matrix(tmp_path)
    with h5py.File(h5_path, "r") as h5:
        assert "raw_data" in h5, "Dataset 'raw_data' is missing."
        dataset = h5["raw_data"]
        assert dataset.shape == (1000, 500), f"raw_data has incorrect shape {dataset.shape}."
        assert dataset.dtype == np.dtype(np.float64), f"raw_data must contain double-precision values, not {dataset.dtype}."
        actual = dataset[...]
    assert np.array_equal(actual, expected), \
        f"raw_data does not match the required seed-42 Monte Carlo matrix (maximum error {np.max(np.abs(actual-expected))})."


def test_svd_results_correctness(tmp_path):
    txt_path = "/home/user/svd_results.txt"
    assert os.path.isfile(txt_path), f"SVD results file {txt_path} is missing."

    with open(txt_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 5, f"Expected exactly 5 lines in {txt_path}, found {len(lines)}."
    assert all(re.fullmatch(r"-?\d+\.\d{4}", line) for line in lines), \
        "Each singular value must be written in fixed-point format with exactly four decimal places."

    values = []
    for line in lines:
        try:
            values.append(float(line))
        except ValueError:
            assert False, f"Could not parse '{line}' as a float in {txt_path}."

    assert values == sorted(values, reverse=True), "Singular values are not in descending order."
    assert 400 < values[0] < 700, f"First singular value {values[0]} is out of expected range (400-700)."

    expected = expected_matrix(tmp_path)
    expected_top5 = np.linalg.svd(expected, compute_uv=False)[:5]
    assert np.allclose(np.asarray(values), expected_top5, rtol=0.0, atol=5.1e-5), \
        f"Reported singular values are incorrect: got {values}, expected {[float(f'{x:.4f}') for x in expected_top5]}."


def test_callgrind_output_exists():
    validate_callgrind("/home/user/callgrind.out")


def test_visualization_script_exists():
    py_path = "/home/user/plot_svd.py"
    assert os.path.isfile(py_path), f"Python visualization script {py_path} is missing."


def test_plot_image_exists_and_is_png():
    png_path = "/home/user/svd_plot.png"
    assert os.path.isfile(png_path), f"Plot image {png_path} is missing."

    with open(png_path, "rb") as f:
        data = f.read()
    assert data[:8] == b"\x89PNG\x0d\x0a\x1a\x0a", f"{png_path} is not a valid PNG image."
    assert len(data) > 1000, "PNG image is implausibly small."
    assert data[12:16] == b"IHDR", "PNG is missing its IHDR chunk."
    width, height = struct.unpack(">II", data[16:24])
    assert width >= 100 and height >= 100, f"Plot dimensions are too small: {width}x{height}."
    assert b"IDAT" in data and data.endswith(b"IEND\xaeB`\x82"), "PNG is incomplete."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
