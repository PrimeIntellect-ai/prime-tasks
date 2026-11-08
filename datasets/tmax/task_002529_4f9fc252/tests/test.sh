#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import re
import shutil
import subprocess
import tempfile

import pytest

PROJECT_DIR = "/home/user/project"
SRC_DIR = os.path.join(PROJECT_DIR, "src")
BUILD_DIR = os.path.join(PROJECT_DIR, "build")
RESULT_FILE = "/home/user/result.txt"
SOLVER_LIB = os.path.join(BUILD_DIR, "libsolver_core.so")
MATH_LIB = os.path.join(BUILD_DIR, "libmath_utils.so")
EDGES = [(0, 1), (1, 2), (2, 3), (3, 4), (4, 0), (0, 2)]


def run_checked(command, **kwargs):
    result = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        **kwargs,
    )
    assert result.returncode == 0, (
        f"Command failed: {command}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def clean_environment():
    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    return env


def get_valid_scores():
    """Dynamically compute all valid scores for the CSP."""
    valid_scores = set()
    for c1 in [1, 2, 3]:
        for c2 in [1, 2, 3]:
            for c3 in [1, 2, 3]:
                for c4 in [1, 2, 3]:
                    colors = [1, c1, c2, c3, c4]
                    if all(colors[u] != colors[v] for u, v in EDGES):
                        valid_scores.add(
                            sum(colors[i] * (i + 1) * 10 for i in range(5))
                        )
    return valid_scores


def assert_valid_coloring(colors):
    assert len(colors) == 5, f"wrapper passed {len(colors)} items instead of 5"
    assert colors[0] == 1, f"Node 0 must have color 1, got {colors[0]}"
    assert all(color in (1, 2, 3) for color in colors), (
        f"Colors must be integers 1, 2, or 3, got {colors}"
    )
    assert all(colors[u] != colors[v] for u, v in EDGES), (
        f"wrapper passed an invalid graph coloring: {colors}"
    )


@pytest.fixture(scope="session", autouse=True)
def rebuild_project():
    cmake_path = os.path.join(PROJECT_DIR, "CMakeLists.txt")
    assert os.path.isfile(cmake_path), f"File missing: {cmake_path}"
    shutil.rmtree(BUILD_DIR, ignore_errors=True)
    os.makedirs(BUILD_DIR)
    run_checked(["cmake", "-S", PROJECT_DIR, "-B", BUILD_DIR], cwd=PROJECT_DIR)
    run_checked(["cmake", "--build", BUILD_DIR, "--clean-first"], cwd=PROJECT_DIR)


def test_cmake_fixed():
    """Retain the source assertion and verify that CMake really links the targets."""
    cmake_path = os.path.join(PROJECT_DIR, "CMakeLists.txt")
    assert os.path.isfile(cmake_path), f"File missing: {cmake_path}"
    with open(cmake_path, "r") as f:
        content = f.read()
    assert "target_link_libraries" in content and "solver_core" in content and "math_utils" in content, \
        "CMakeLists.txt must use target_link_libraries to link solver_core with math_utils."

    dynamic = run_checked(["readelf", "-d", SOLVER_LIB]).stdout
    assert re.search(r"NEEDED.*libmath_utils[^]]*\.so", dynamic), (
        "libsolver_core.so does not have a dynamic dependency on libmath_utils.so"
    )


def test_c_code_fixed():
    """Retain the original source checks; behavioral and Valgrind tests follow."""
    c_path = os.path.join(SRC_DIR, "solver_core.c")
    assert os.path.isfile(c_path), f"File missing: {c_path}"
    with open(c_path, "r") as f:
        content = f.read()
    assert "i <= num_items" not in content, \
        "Buffer overflow bug (<= num_items) is still present in solver_core.c."
    assert re.search(r"free\s*\(", content), \
        "Memory leak bug is still present: missing free() in solver_core.c."


def test_build_artifacts_and_loader():
    """Check the original artifact conditions plus exact ELF artifacts and clean loading."""
    assert os.path.isdir(BUILD_DIR), f"Build directory missing: {BUILD_DIR}"
    so_files = []
    for root, dirs, files in os.walk(BUILD_DIR):
        for filename in files:
            if filename.endswith(".so"):
                so_files.append(filename)
    assert any("solver_core" in f for f in so_files), \
        "libsolver_core.so was not found in the build directory."
    assert any("math_utils" in f for f in so_files), \
        "libmath_utils.so was not found in the build directory."

    assert os.path.isfile(SOLVER_LIB), f"Exact library missing: {SOLVER_LIB}"
    assert os.path.isfile(MATH_LIB), f"Exact library missing: {MATH_LIB}"
    assert "ELF" in run_checked(["file", SOLVER_LIB]).stdout
    assert "shared object" in run_checked(["file", SOLVER_LIB]).stdout
    assert "ELF" in run_checked(["file", MATH_LIB]).stdout
    assert "shared object" in run_checked(["file", MATH_LIB]).stdout

    probe = (
        "import ctypes\n"
        f"p={SOLVER_LIB!r}\n"
        "lib=ctypes.CDLL(p)\n"
        "fn=lib.compute_score\n"
        "fn.argtypes=[ctypes.POINTER(ctypes.c_int), ctypes.c_int]\n"
        "fn.restype=ctypes.c_int\n"
        "a=(ctypes.c_int*3)(2,-1,4)\n"
        "assert fn(a,3)==120\n"
    )
    run_checked(["python3", "-c", probe], cwd=PROJECT_DIR, env=clean_environment())


def test_compute_score_on_derived_inputs():
    """Call the submitted library on unpredictable inputs and derive every answer."""
    lib = ctypes.CDLL(SOLVER_LIB)
    compute_score = lib.compute_score
    compute_score.argtypes = [ctypes.POINTER(ctypes.c_int), ctypes.c_int]
    compute_score.restype = ctypes.c_int

    rng = random.SystemRandom()
    cases = [[]]
    for _ in range(12):
        cases.append([rng.randint(-30, 30) for _ in range(rng.randint(1, 18))])

    for values in cases:
        expected = sum(value * (index + 1) * 10 for index, value in enumerate(values))
        if values:
            array = (ctypes.c_int * len(values))(*values)
            pointer = array
        else:
            array = (ctypes.c_int * 1)(123)
            pointer = array
        actual = compute_score(pointer, len(values))
        assert actual == expected, (
            f"compute_score({values}, {len(values)}) returned {actual}, expected {expected}"
        )


def test_compute_score_is_memory_safe_and_leak_free():
    """Exercise compute_score under Valgrind, including a zero-length and random calls."""
    rng = random.SystemRandom()
    cases = [[]]
    for _ in range(10):
        cases.append([rng.randint(-20, 20) for _ in range(rng.randint(1, 24))])

    lines = [
        "#include <stdio.h>",
        "extern int compute_score(int *items, int num_items);",
        "int main(void) {",
        "  int dummy = 17;",
    ]
    for index, values in enumerate(cases):
        expected = sum(value * (i + 1) * 10 for i, value in enumerate(values))
        if values:
            initializer = ",".join(str(v) for v in values)
            lines.append(f"  int a{index}[] = {{{initializer}}};")
            argument = f"a{index}"
        else:
            argument = "&dummy"
        lines.append(
            f"  if (compute_score({argument}, {len(values)}) != {expected}) return {index + 10};"
        )
    lines.extend(["  return 0;", "}"])

    with tempfile.TemporaryDirectory(prefix="solver-valgrind-") as temp_dir:
        source = os.path.join(temp_dir, "harness.c")
        executable = os.path.join(temp_dir, "harness")
        with open(source, "w") as f:
            f.write("\n".join(lines) + "\n")
        run_checked(["gcc", "-std=c99", source, SOLVER_LIB, "-o", executable])
        run_checked(
            [
                "valgrind",
                "--quiet",
                "--leak-check=full",
                "--show-leak-kinds=all",
                "--errors-for-leak-kinds=definite,indirect,possible",
                "--error-exitcode=97",
                executable,
            ],
            cwd=PROJECT_DIR,
            env=clean_environment(),
        )


def test_wrapper_execution_and_real_integration():
    """Observe the arguments passed by wrapper.py and require it to write the C return value."""
    wrapper_path = os.path.join(PROJECT_DIR, "wrapper.py")
    assert os.path.isfile(wrapper_path), f"File missing: {wrapper_path}"

    rng = random.SystemRandom()
    sentinel = rng.randint(1000000, 2000000000)
    with tempfile.TemporaryDirectory(prefix="solver-spy-") as temp_dir:
        log_path = os.path.join(temp_dir, "call.log")
        spy_source = os.path.join(temp_dir, "spy.c")
        spy_library = os.path.join(temp_dir, "libsolver_core.so")
        backup_library = os.path.join(BUILD_DIR, ".libsolver_core.real.so")
        source = f'''#include <stdio.h>
int compute_score(int *items, int num_items) {{
    FILE *f = fopen({json.dumps(log_path)}, "w");
    if (f) {{
        fprintf(f, "%d", num_items);
        if (items && num_items >= 0 && num_items <= 64) {{
            for (int i = 0; i < num_items; ++i) fprintf(f, " %d", items[i]);
        }}
        fprintf(f, "\\n");
        fclose(f);
    }}
    return {sentinel};
}}
'''
        with open(spy_source, "w") as f:
            f.write(source)
        run_checked(["gcc", "-shared", "-fPIC", spy_source, "-o", spy_library])

        if os.path.exists(RESULT_FILE):
            os.remove(RESULT_FILE)
        os.rename(SOLVER_LIB, backup_library)
        shutil.copy2(spy_library, SOLVER_LIB)
        try:
            result = subprocess.run(
                ["python3", wrapper_path],
                cwd=PROJECT_DIR,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=clean_environment(),
            )
            spy_log_exists = os.path.isfile(log_path)
            spy_log = open(log_path).read().strip() if spy_log_exists else ""
            spy_result_exists = os.path.isfile(RESULT_FILE)
            spy_result = open(RESULT_FILE).read().strip() if spy_result_exists else ""
        finally:
            if os.path.exists(SOLVER_LIB):
                os.remove(SOLVER_LIB)
            os.rename(backup_library, SOLVER_LIB)

        assert result.returncode == 0, f"wrapper.py failed to run. Stderr: {result.stderr}"
        assert spy_log_exists, "wrapper.py did not call compute_score from libsolver_core.so"
        fields = [int(value) for value in spy_log.split()]
        assert fields, "The compute_score call log was empty"
        num_items, colors = fields[0], fields[1:]
        assert num_items == 5, f"wrapper passed num_items={num_items}, expected 5"
        assert len(colors) == num_items, "wrapper passed an invalid or unreadable integer array"
        assert_valid_coloring(colors)
        assert spy_result_exists, f"Result file missing: {RESULT_FILE}"
        assert spy_result == str(sentinel), (
            "wrapper.py must write the actual integer returned by compute_score; "
            f"expected spy return {sentinel}, got {spy_result!r}"
        )

    if os.path.exists(RESULT_FILE):
        os.remove(RESULT_FILE)
    result = subprocess.run(
        ["python3", wrapper_path],
        cwd=PROJECT_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=clean_environment(),
    )
    assert result.returncode == 0, f"wrapper.py failed to run. Stderr: {result.stderr}"
    assert os.path.isfile(RESULT_FILE), f"Result file missing: {RESULT_FILE}"
    with open(RESULT_FILE, "r") as f:
        content = f.read().strip()
    assert content.isdigit(), f"Result file must contain only an integer, got: '{content}'"
    score = int(content)
    valid_scores = get_valid_scores()
    assert score in valid_scores, (
        f"Score {score} is not a valid score for any correct coloring. Valid scores: {valid_scores}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
