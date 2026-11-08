#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import math
import os
import re
import subprocess

import pytest

PIPELINE_DIR = "/home/user/pipeline"


@pytest.fixture(scope="session", autouse=True)
def rebuild_from_makefile():
    # Preserve the original end-state requirement that the agent built both artifacts.
    for name in ("libfilter.so", "test_runner"):
        path = os.path.join(PIPELINE_DIR, name)
        assert os.path.isfile(path), f"Required build artifact {path} does not exist."

    clean = subprocess.run(
        ["make", "clean"], cwd=PIPELINE_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert clean.returncode == 0, f"make clean failed:\n{clean.stdout}"
    for name in ("libfilter.so", "filter.o", "test_runner"):
        assert not os.path.exists(os.path.join(PIPELINE_DIR, name)), \
            f"make clean did not remove {name}"

    build = subprocess.run(
        ["make"], cwd=PIPELINE_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60
    )
    assert build.returncode == 0, f"make failed:\n{build.stdout}"


def load_library():
    so_path = os.path.join(PIPELINE_DIR, "libfilter.so")
    assert os.path.isfile(so_path), f"Shared library {so_path} was not built."
    try:
        lib = ctypes.CDLL(so_path)
    except OSError as e:
        pytest.fail(f"Failed to load {so_path} as a shared library: {e}")
    assert hasattr(lib, "moving_average"), \
        "libfilter.so does not export 'moving_average'"
    lib.moving_average.argtypes = [
        ctypes.POINTER(ctypes.c_double),
        ctypes.POINTER(ctypes.c_double),
        ctypes.c_int,
        ctypes.c_int,
    ]
    lib.moving_average.restype = None
    return lib


def expected_moving_average(values, window):
    result = []
    for i in range(len(values)):
        start = max(0, i - window + 1)
        segment = values[start:i + 1]
        result.append(sum(segment) / len(segment))
    return result


def test_libfilter_so_built_and_valid():
    load_library()


def test_moving_average_numerical_behavior():
    lib = load_library()
    cases = [
        ([3.5], 1),
        ([1.0, 2.0, 3.0, 4.0, 5.0], 3),
        ([-2.5, 7.0, 0.25, -1.75, 10.0, 4.5], 4),
        ([0.5, -0.5, 2.25, 8.0], 10),
    ]

    for values, window in cases:
        array_type = ctypes.c_double * len(values)
        input_array = array_type(*values)
        output_array = array_type()
        lib.moving_average(input_array, output_array, len(values), window)
        expected = expected_moving_average(values, window)
        actual = list(output_array)
        assert len(actual) == len(expected)
        for index, (got, want) in enumerate(zip(actual, expected)):
            assert math.isclose(got, want, rel_tol=1e-12, abs_tol=1e-12), \
                f"Incorrect result for window={window} at index {index}: got {got}, expected {want}"


def test_filter_cpp_memory_leak_fixed():
    cpp_path = os.path.join(PIPELINE_DIR, "filter.cpp")
    assert os.path.isfile(cpp_path), f"{cpp_path} does not exist."
    with open(cpp_path, "r") as f:
        content = f.read()

    # Accept either removal of the allocation or a matching array delete.
    has_new = "new double" in content
    normalized = re.sub(r"\s+", "", content)
    has_delete = "delete[]temp" in normalized
    assert not has_new or has_delete, \
        "Memory leak in filter.cpp does not appear to be fixed."


def test_valgrind_log_shows_no_leaks_and_runner_is_clean():
    log_path = os.path.join(PIPELINE_DIR, "valgrind.log")
    assert os.path.isfile(log_path), f"Valgrind log {log_path} does not exist."
    with open(log_path, "r", errors="replace") as f:
        submitted_content = f.read()

    success_indicators = [
        "All heap blocks were freed -- no leaks are possible",
        "definitely lost: 0 bytes",
    ]
    assert any(indicator in submitted_content for indicator in success_indicators), \
        "valgrind.log does not indicate that the memory leak was fixed (0 bytes lost)."

    verification_log = "/tmp/verifier_valgrind.log"
    with open(verification_log, "w") as stderr_file:
        run = subprocess.run(
            [
                "valgrind",
                "--leak-check=full",
                "--show-leak-kinds=all",
                "--errors-for-leak-kinds=all",
                "--error-exitcode=97",
                "./test_runner",
            ],
            cwd=PIPELINE_DIR,
            stdout=subprocess.DEVNULL,
            stderr=stderr_file,
            timeout=60,
        )
    with open(verification_log, "r", errors="replace") as f:
        actual_content = f.read()
    assert run.returncode == 0, \
        f"test_runner failed under valgrind with exit code {run.returncode}:\n{actual_content[-4000:]}"
    assert any(indicator in actual_content for indicator in success_indicators), \
        f"Fresh valgrind run did not report zero leaks:\n{actual_content[-4000:]}"


def test_benchmark_result_exists_and_complete_and_script_runs():
    res_path = os.path.join(PIPELINE_DIR, "benchmark_result.txt")
    assert os.path.isfile(res_path), f"Benchmark result {res_path} does not exist."
    with open(res_path, "r", errors="replace") as f:
        content = f.read()

    assert "Benchmark complete." in content, \
        "benchmark_result.txt does not contain 'Benchmark complete.'"
    assert "C++ Time:" in content, \
        "benchmark_result.txt does not contain C++ benchmark results."
    assert "Python Time:" in content, \
        "benchmark_result.txt does not contain Python benchmark results."

    run = subprocess.run(
        ["python3", os.path.join(PIPELINE_DIR, "benchmark.py")],
        cwd=PIPELINE_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert run.returncode == 0, \
        f"benchmark.py failed with exit code {run.returncode}:\n{run.stderr}"
    assert "Benchmark complete." in run.stdout, \
        "Fresh benchmark.py output is incomplete."

    cpp_match = re.search(r"^C\+\+ Time:\s*([0-9]+(?:\.[0-9]+)?)s\s*$", run.stdout, re.MULTILINE)
    py_match = re.search(r"^Python Time:\s*([0-9]+(?:\.[0-9]+)?)s\s*$", run.stdout, re.MULTILINE)
    assert cpp_match, f"Fresh benchmark output lacks a valid C++ timing:\n{run.stdout}"
    assert py_match, f"Fresh benchmark output lacks a valid Python timing:\n{run.stdout}"
    assert math.isfinite(float(cpp_match.group(1)))
    assert math.isfinite(float(py_match.group(1)))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
