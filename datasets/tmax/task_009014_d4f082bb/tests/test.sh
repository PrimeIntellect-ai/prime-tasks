#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import math
import os
import re
import subprocess

import numpy as np

RAW = "/home/user/raw_signal.csv"
RESULTS = "/home/user/fit_results.txt"


def parse_exact_results():
    assert os.path.isfile(RESULTS), f"The expected output file '{RESULTS}' does not exist."
    with open(RESULTS, "r") as f:
        content = f.read()
    number = r"[+-]?(?:\d+\.\d{4,})(?:[eE][+-]?\d+)?"
    match = re.fullmatch(
        rf"f_est:\s*({number})\s*\nA_mean:\s*({number})\s*\nphi_mean:\s*({number})\s*(?:\n)?",
        content,
    )
    assert match is not None, "Results must contain exactly the three required lines, with at least four decimal places."
    values = tuple(float(v) for v in match.groups())
    assert all(math.isfinite(v) for v in values), "All reported values must be finite."
    return values, content


def write_dataset(x, y):
    with open(RAW, "w") as f:
        for xi, yi in zip(x, y):
            f.write(f"{xi:.17g},{yi:.17g}\n")


def reference_values(x, y):
    mesh_x = np.linspace(float(x[0]), float(x[-1]), 1024)
    mesh_y = np.interp(mesh_x, x, y)
    spectrum = np.fft.fft(mesh_y)
    # The instruction restricts the search to k < N/2 and excludes DC.
    k = int(np.argmax(np.abs(spectrum[1:512])) + 1)
    frequency = k / float(x[-1] - x[0])

    angle = 2.0 * np.pi * frequency * x
    design = np.column_stack((np.sin(angle), np.cos(angle)))
    sin_coef, cos_coef = np.linalg.lstsq(design, y, rcond=None)[0]
    amplitude = float(np.hypot(sin_coef, cos_coef))
    phase = float(np.arctan2(cos_coef, sin_coef) % (2.0 * np.pi))
    return frequency, amplitude, phase


def run_program(executable, timeout=45):
    if os.path.lexists(RESULTS):
        os.remove(RESULTS)
    proc = subprocess.run(
        [executable], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=timeout
    )
    assert proc.returncode == 0, f"Program exited with {proc.returncode}: {proc.stderr[-1000:]}"
    return parse_exact_results()


def exercise(executable, datasets):
    first_content = None
    for index, (x, y) in enumerate(datasets):
        write_dataset(x, y)
        expected_f, expected_a, expected_phi = reference_values(x, y)
        (f_est, a_mean, phi_mean), content = run_program(executable)

        assert abs(f_est - expected_f) <= 6e-4, (
            f"Synthetic case {index}: DFT frequency {f_est} does not match the frequency "
            f"derived from the required 1024-point linear interpolation ({expected_f})."
        )
        assert abs(a_mean - expected_a) <= 0.25, (
            f"Synthetic case {index}: amplitude {a_mean} is inconsistent with the likelihood "
            f"over the original uneven samples (expected near {expected_a})."
        )
        phase_error = abs((phi_mean - expected_phi + math.pi) % (2.0 * math.pi) - math.pi)
        assert phase_error <= 0.22, (
            f"Synthetic case {index}: phase {phi_mean} is inconsistent with the likelihood "
            f"over the original uneven samples (expected near {expected_phi})."
        )
        if index == 0:
            first_content = content

    # Re-run the first hidden input to check the required fixed-seed reproducibility.
    x, y = datasets[0]
    write_dataset(x, y)
    _, repeated_content = run_program(executable)
    assert repeated_content == first_content, "Repeated execution is not reproducible with the required fixed seed."


def test_cpp_pipeline_is_built_and_executed():
    with open(RAW, "rb") as f:
        original_data = f.read()

    seed = int.from_bytes(os.urandom(8), "little")
    rng = np.random.default_rng(seed)

    # Ordinary uneven sampling, with the true frequency exactly on a DFT bin.
    x1 = np.sort(np.r_[0.0, rng.uniform(0.0, 7.5, 238), 7.5])
    f1 = 17.0 / 7.5
    y1 = 2.15 * np.sin(2.0 * np.pi * f1 * x1 + 0.72) + rng.normal(0.0, 0.35, x1.size)

    # Strongly nonuniform sampling and spatially varying amplitude distinguish use of
    # the original samples in the likelihood from use of the regularized mesh.
    x2 = np.sort(np.r_[0.0, rng.uniform(0.0, 2.0, 178), rng.uniform(2.0, 10.0, 40), 10.0])
    f2 = 24.0 / 10.0
    local_amp = np.where(x2 <= 2.0, 1.30, 3.80)
    y2 = local_amp * np.sin(2.0 * np.pi * f2 * x2 + 1.70) + rng.normal(0.0, 0.25, x2.size)
    datasets = [(x1, y1), (x2, y2)]

    sources = []
    for pattern in ("/home/user/**/*.cpp", "/home/user/**/*.cc", "/home/user/**/*.cxx"):
        sources.extend(glob.glob(pattern, recursive=True))
    sources = sorted(set(p for p in sources if os.path.isfile(p)))
    assert sources, "No C++ source file was created under /home/user."

    failures = []
    winner = None
    try:
        for number, source in enumerate(sources):
            try:
                with open(source, "r", errors="ignore") as f:
                    source_text = f.read()
                normalized = source_text.replace("'", "")
                assert re.search(r"\bmt19937\b", normalized), "The required std::mt19937 engine is absent."
                assert "42" in normalized, "The required seed 42 is absent."
                assert "1024" in normalized, "The required 1024-point mesh is absent."
                assert "10000" in normalized and "2000" in normalized, "The required iteration and burn-in counts are absent."
                assert "normal_distribution" in normalized, "No Gaussian proposal distribution was found."

                executable = f"/tmp/verified_fit_model_{number}"
                build = subprocess.run(
                    ["g++", "-O2", "-std=c++17", source, "-o", executable, "-lfftw3", "-lm"],
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=45
                )
                assert build.returncode == 0, f"Compilation failed: {build.stderr[-1000:]}"
                exercise(executable, datasets)
                winner = executable
                break
            except Exception as exc:
                failures.append(f"{source}: {exc}")

        assert winner is not None, "No created C++ program passed compilation and execution checks:\n" + "\n".join(failures)

        # Restore the supplied dataset and execute the verified artifact so the final
        # output checked below is genuinely produced by the pipeline.
        with open(RAW, "wb") as f:
            f.write(original_data)
        run_program(winner)
    finally:
        with open(RAW, "wb") as f:
            f.write(original_data)


def test_fit_results_exists():
    """Check if the results file was created."""
    file_path = "/home/user/fit_results.txt"
    assert os.path.exists(file_path), f"The expected output file '{file_path}' does not exist."
    assert os.path.isfile(file_path), f"'{file_path}' is not a regular file."


def test_fit_results_format_and_values():
    """Check the format and the correctness of the estimated values."""
    file_path = "/home/user/fit_results.txt"
    assert os.path.exists(file_path), f"Cannot test values because '{file_path}' is missing."

    with open(file_path, "r") as f:
        content = f.read()

    f_est_match = re.search(r'f_est:\s*([0-9.]+)', content)
    assert f_est_match is not None, "Could not find 'f_est: <float>' in the output file."
    f_est = float(f_est_match.group(1))

    A_mean_match = re.search(r'A_mean:\s*([0-9.]+)', content)
    assert A_mean_match is not None, "Could not find 'A_mean: <float>' in the output file."
    A_mean = float(A_mean_match.group(1))

    phi_mean_match = re.search(r'phi_mean:\s*([0-9.]+)', content)
    assert phi_mean_match is not None, "Could not find 'phi_mean: <float>' in the output file."
    phi_mean = float(phi_mean_match.group(1))

    assert 2.9 <= f_est <= 3.1, f"Expected f_est to be between 2.9 and 3.1, but got {f_est}."
    assert 2.2 <= A_mean <= 2.8, f"Expected A_mean to be between 2.2 and 2.8, but got {A_mean}."
    assert 0.9 <= phi_mean <= 1.5, f"Expected phi_mean to be between 0.9 and 1.5, but got {phi_mean}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
