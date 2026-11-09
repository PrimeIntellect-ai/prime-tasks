#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import itertools
import math
import os
import re
import subprocess
import textwrap

SIM_DIR = "/home/user/sim"
CPP_PATH = os.path.join(SIM_DIR, "pde_solver.cpp")
EXE_PATH = os.path.join(SIM_DIR, "pde_solver")
LOG_PATH = os.path.join(SIM_DIR, "result.log")
EXPECTED_REPORT = "Total Heat: 20000000.0\nDeterminant: 189.0"


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, text=True, capture_output=True, timeout=90, **kwargs)


def determinant(matrix):
    total = 0.0
    for perm in itertools.permutations(range(4)):
        inversions = sum(
            1 for i in range(4) for j in range(i + 1, 4) if perm[i] > perm[j]
        )
        term = 1.0
        for row, col in enumerate(perm):
            term *= matrix[row][col]
        total += (-term if inversions % 2 else term)
    return total


def test_executable_exists():
    assert os.path.isfile(EXE_PATH), f"Executable {EXE_PATH} was not found. Did you compile the C++ code?"
    assert os.access(EXE_PATH, os.X_OK), f"File {EXE_PATH} is not executable."
    with open(EXE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "pde_solver must be a compiled native executable."


def test_result_log_exists_and_correct():
    assert os.path.isfile(LOG_PATH), f"Result log {LOG_PATH} was not found."

    with open(LOG_PATH, "r") as f:
        content = f.read().strip()

    expected_heat = "Total Heat: 20000000.0"
    expected_det = "Determinant: 189.0"

    assert expected_heat in content, f"Expected '{expected_heat}' in {LOG_PATH}, but got:\n{content}"
    assert expected_det in content, f"Expected '{expected_det}' in {LOG_PATH}, but got:\n{content}"
    assert content == EXPECTED_REPORT, f"result.log is not the exact required report:\n{content}"


def test_cpp_constraints():
    assert os.path.isfile(CPP_PATH), f"Source file {CPP_PATH} is missing."

    with open(CPP_PATH, "r") as f:
        content = f.read()

    # Ensure grid is still a vector of floats
    assert re.search(r"std::vector<float>\s+grid\s*\(", content) or "std::vector<float> grid" in content, \
        "The grid data type must remain std::vector<float>. Do not change it to double."

    # Check that no external libraries like Eigen or lapack are included
    assert "Eigen" not in content, "External library Eigen is not allowed."
    assert "lapack" not in content.lower(), "External library LAPACK is not allowed."


def test_compiled_program_executes_and_matches_saved_report():
    completed = run([EXE_PATH], cwd=SIM_DIR)
    assert completed.stdout.strip() == EXPECTED_REPORT, (
        "The compiled pde_solver did not print the required final report. Got:\n"
        + completed.stdout
    )
    with open(LOG_PATH, "r") as f:
        saved = f.read().strip()
    assert saved == completed.stdout.strip(), "result.log must contain the exact report printed by pde_solver."


def test_functions_on_independent_inputs(tmp_path):
    harness = tmp_path / "function_harness.cpp"
    obj = tmp_path / "solver.o"
    harness_exe = tmp_path / "function_harness"
    rebuilt_exe = tmp_path / "rebuilt_solver"

    harness.write_text(textwrap.dedent(r'''
        #include <iostream>
        #include <iomanip>
        #include <vector>

        float compute_total_heat(const std::vector<float>& grid);
        float compute_determinant_lu(std::vector<std::vector<float>>& matrix);

        int main() {
            std::cout << std::setprecision(17);

            std::vector<float> many_ones(20000000, 1.0f);
            std::cout << "H0 " << compute_total_heat(many_ones) << "\n";

            std::vector<float> cancellation;
            cancellation.reserve(1002);
            cancellation.push_back(100000000.0f);
            for (int i = 0; i < 1000; ++i) cancellation.push_back(1.0f);
            cancellation.push_back(-100000000.0f);
            std::cout << "H1 " << compute_total_heat(cancellation) << "\n";

            std::vector<std::vector<std::vector<float>>> matrices = {
                {{4,1,1,1},{1,4,1,1},{1,1,4,1},{1,1,1,4}},
                {{2,3,1,5},{0,-3,2,1},{0,0,4,7},{0,0,0,0.5f}},
                {{10,2,3,4},{1,9,2,3},{2,1,8,2},{3,2,1,7}}
            };
            for (std::size_t i = 0; i < matrices.size(); ++i) {
                std::cout << "D" << i << " " << compute_determinant_lu(matrices[i]) << "\n";
            }
            return 0;
        }
    '''))

    # Compile the submitted functions into a separate harness so hardcoded log
    # output or a dummy pde_solver executable cannot satisfy the tests.
    run(["g++", "-O2", "-std=c++17", "-Dmain=pde_solver_original_main", "-c", CPP_PATH, "-o", str(obj)])
    run(["g++", "-O2", "-std=c++17", str(harness), str(obj), "-o", str(harness_exe)])
    completed = run([str(harness_exe)])

    values = {}
    for line in completed.stdout.splitlines():
        parts = line.split()
        assert len(parts) == 2, f"Unexpected function harness output: {line!r}"
        values[parts[0]] = float(parts[1])

    # These expectations are derived from the generated vectors rather than
    # from result.log. Both cases expose ordinary single-precision summation.
    assert values.get("H0") == float(20000000), "compute_total_heat loses increments on a large float grid."
    assert values.get("H1") == float(math.fsum([100000000.0] + [1.0] * 1000 + [-100000000.0])), \
        "compute_total_heat does not compensate for catastrophic cancellation."

    matrices = [
        [[4,1,1,1],[1,4,1,1],[1,1,4,1],[1,1,1,4]],
        [[2,3,1,5],[0,-3,2,1],[0,0,4,7],[0,0,0,0.5]],
        [[10,2,3,4],[1,9,2,3],[2,1,8,2],[3,2,1,7]],
    ]
    for i, matrix in enumerate(matrices):
        actual = values.get(f"D{i}")
        expected = determinant(matrix)
        assert actual is not None, f"Missing determinant result D{i}."
        assert math.isclose(actual, expected, rel_tol=1e-4, abs_tol=1e-3), \
            f"compute_determinant_lu returned {actual} for matrix {i}; expected {expected}."

    # Also rebuild and run the submitted full source, ensuring main remains
    # connected to the tested implementations.
    run(["g++", "-O3", "-std=c++17", CPP_PATH, "-o", str(rebuilt_exe)])
    rebuilt = run([str(rebuilt_exe)], cwd=SIM_DIR)
    assert rebuilt.stdout.strip() == EXPECTED_REPORT, (
        "A clean build of pde_solver.cpp did not produce the required report. Got:\n"
        + rebuilt.stdout
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
