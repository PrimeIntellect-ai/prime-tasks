#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import re
import secrets
import stat
import subprocess
import tempfile

import pytest

PROJECT = "/home/user/pr_review"
BUILD = os.path.join(PROJECT, "build")
BENCH = os.path.join(BUILD, "bench")
LIB = os.path.join(BUILD, "libmathops.so")
RESULTS = "/home/user/benchmark_results.txt"
ASSEMBLY = "/home/user/fast_compute.s"


def regular_file(path):
    return os.path.isfile(path) and stat.S_ISREG(os.lstat(path).st_mode)


def elf_file(path):
    with open(path, "rb") as f:
        return f.read(4) == b"\x7fELF"


@pytest.fixture(scope="session")
def verified_build():
    assert regular_file(BENCH), f"{BENCH} is missing or is not a regular executable file."
    assert os.access(BENCH, os.X_OK), f"{BENCH} is not executable."
    assert elf_file(BENCH), f"{BENCH} is not an ELF executable."
    assert regular_file(LIB), f"{LIB} is missing or is not a regular shared library."
    assert elf_file(LIB), f"{LIB} is not an ELF shared library."

    needed = subprocess.run(
        ["readelf", "-d", BENCH], text=True, capture_output=True, check=True
    ).stdout
    assert re.search(r"Shared library: \[libmathops\.so(?:\.[^]]*)?\]", needed), \
        "The built bench executable does not dynamically depend on libmathops.so."

    run = subprocess.run([BENCH], cwd=BUILD, text=True, capture_output=True, check=True)
    assert run.stderr == "", f"bench unexpectedly wrote to stderr: {run.stderr!r}"

    # Independently configure and build from the submitted CMake project so that
    # comments or stale/fabricated artifacts cannot satisfy the linkage checks.
    with tempfile.TemporaryDirectory(prefix="verify_cmake_") as clean_build:
        subprocess.run(
            ["cmake", "-S", PROJECT, "-B", clean_build],
            text=True, capture_output=True, check=True
        )
        subprocess.run(
            ["cmake", "--build", clean_build],
            text=True, capture_output=True, check=True
        )
        clean_bench = os.path.join(clean_build, "bench")
        clean_lib = os.path.join(clean_build, "libmathops.so")
        assert regular_file(clean_bench) and elf_file(clean_bench)
        assert regular_file(clean_lib) and elf_file(clean_lib)
        clean_needed = subprocess.run(
            ["readelf", "-d", clean_bench], text=True, capture_output=True, check=True
        ).stdout
        assert re.search(r"Shared library: \[libmathops\.so(?:\.[^]]*)?\]", clean_needed), \
            "A clean CMake build does not link bench against mathops."
        clean_run = subprocess.run(
            [clean_bench], cwd=clean_build, text=True, capture_output=True, check=True
        )
        assert clean_run.stdout == run.stdout, \
            "The submitted build output differs from a clean build of the project."

    return run.stdout


def test_protected_sources_unchanged():
    with open(os.path.join(PROJECT, "baseline.py"), "r") as f:
        assert f.read() == "def baseline_compute(a, b):\n    return (a * b) ^ (a + b)\n", \
            "baseline.py must not be modified."
    with open(os.path.join(PROJECT, "mathops.c"), "r") as f:
        assert f.read() == "int fast_compute(int a, int b) {\n    return (a * b) ^ (a + b);\n}\n", \
            "mathops.c must not be modified."


def test_baseline_compute_translation():
    # Compile bench.c separately and call baseline_compute directly over inputs
    # whose expected values are computed here rather than read from an artifact.
    with tempfile.TemporaryDirectory(prefix="verify_baseline_") as td:
        shared = os.path.join(td, "submitted_baseline.so")
        subprocess.run([
            "cc", "-shared", "-fPIC", "-Dmain=bench_original_main",
            os.path.join(PROJECT, "bench.c"), os.path.join(PROJECT, "mathops.c"),
            "-o", shared
        ], text=True, capture_output=True, check=True)
        loaded = ctypes.CDLL(shared)
        submitted = loaded.baseline_compute
        submitted.argtypes = [ctypes.c_int, ctypes.c_int]
        submitted.restype = ctypes.c_int

        cases = [(1234, 5678), (0, 0), (1, 1), (17, 29), (999, 3001)]
        cases.extend((secrets.randbelow(30001), secrets.randbelow(30001)) for _ in range(20))
        for a, b in cases:
            expected = (a * b) ^ (a + b)
            assert submitted(a, b) == expected, \
                f"baseline_compute({a}, {b}) did not match baseline.py."


def test_benchmark_results(verified_build):
    path = RESULTS
    assert os.path.isfile(path), f"File {path} does not exist. Did you run the benchmark and redirect standard output?"
    with open(path, "r") as f:
        content = f.read()

    expected_value = (1234 * 5678) ^ (1234 + 5678)
    expected_result = f"SUCCESS: {expected_value}"
    assert expected_result in content, f"Expected '{expected_result}' in {path}. Check your C translation and build."
    assert content == verified_build, \
        f"{path} is not the actual standard output of the built bench executable."


def normalize_objdump(text):
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if ": file format " in line:
            lines[i] = "<FILE>" + line[line.index(": file format "):]
            break
    return "\n".join(lines).strip()


def test_fast_compute_assembly(verified_build):
    path = ASSEMBLY
    assert os.path.isfile(path), f"File {path} does not exist. Did you run objdump and save the output?"
    assert regular_file(path), f"{path} must be a regular objdump output file."
    with open(path, "r") as f:
        content = f.read()
    assert "<fast_compute>:" in content, f"Expected to find '<fast_compute>:' in {path}. Ensure you disassembled libmathops.so correctly."

    actual = subprocess.run(
        ["objdump", "-d", LIB], text=True, capture_output=True, check=True
    ).stdout
    assert normalize_objdump(content) == normalize_objdump(actual), \
        f"{path} is not the objdump -d disassembly of the built libmathops.so."


def test_cmakelists_linked(verified_build):
    path = os.path.join(PROJECT, "CMakeLists.txt")
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    assert "target_link_libraries" in content, f"Expected 'target_link_libraries' to be used in {path} to link the shared library."
    assert "bench" in content and "mathops" in content, "CMakeLists.txt must reference both 'bench' and 'mathops'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
