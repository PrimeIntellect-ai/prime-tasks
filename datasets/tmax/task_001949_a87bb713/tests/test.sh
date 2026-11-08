#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import itertools
import os
import secrets
import subprocess

BASE = "/home/user/math_port"
EXE = os.path.join(BASE, "det_calc")
SOURCE = os.path.join(BASE, "det_calc.c")
MAKEFILE = os.path.join(BASE, "Makefile")
LOG = os.path.join(BASE, "verification.log")
VERIFY_PROPS = os.path.join(BASE, "verify_props.py")


def determinant(matrix):
    n = len(matrix)
    total = 0
    for perm in itertools.permutations(range(n)):
        inversions = sum(
            1 for i in range(n) for j in range(i + 1, n)
            if perm[i] > perm[j]
        )
        term = -1 if inversions % 2 else 1
        for row, col in enumerate(perm):
            term *= matrix[row][col]
        total += term
    return total


def matrix_input(matrix):
    return str(len(matrix)) + "\n" + "\n".join(
        " ".join(str(value) for value in row) for row in matrix
    ) + "\n"


def run_tool(path, matrix):
    result = subprocess.run(
        [path],
        input=matrix_input(matrix),
        text=True,
        capture_output=True,
        timeout=10,
        cwd=BASE,
    )
    assert result.returncode == 0, (
        f"{path} exited with {result.returncode}. stderr: {result.stderr}"
    )
    try:
        return float(result.stdout.strip())
    except ValueError as exc:
        raise AssertionError(f"Invalid determinant output: {result.stdout!r}") from exc


def test_build_behavior_memory_and_property_script():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} does not exist."
    assert os.path.isfile(MAKEFILE), f"Makefile at {MAKEFILE} does not exist."
    assert os.path.isfile(VERIFY_PROPS), f"Property test script {VERIFY_PROPS} does not exist."

    # Require the submitted Makefile to recreate the requested executable.
    if os.path.lexists(EXE):
        os.remove(EXE)
    if os.path.lexists(LOG):
        os.remove(LOG)

    build = subprocess.run(
        ["make", "-B", "det_calc"],
        cwd=BASE,
        text=True,
        capture_output=True,
        timeout=60,
    )
    assert build.returncode == 0, (
        f"Makefile failed to build det_calc.\nstdout:\n{build.stdout}\nstderr:\n{build.stderr}"
    )
    assert os.path.isfile(EXE), "Makefile did not create det_calc."

    # Include deterministic row-swap cases and unpredictable integer matrices.
    matrices = [
        [[0, 1], [1, 0]],
        [[0, 2, 0], [3, 0, 0], [0, 0, 5]],
        [[0, 1, 0], [0, 0, 1], [1, 0, 0]],
        [[0, 0, 2], [0, 3, 0], [4, 0, 0]],
        [[2, 4, 6], [1, 2, 3], [5, 0, 1]],
    ]
    rng = secrets.SystemRandom()
    for _ in range(14):
        n = rng.randint(2, 5)
        matrices.append([[rng.randint(-7, 7) for _ in range(n)] for _ in range(n)])

    for matrix in matrices:
        expected = float(determinant(matrix))
        actual = run_tool(EXE, matrix)
        assert abs(actual - expected) <= 1e-4, (
            f"Wrong determinant for {matrix}: expected {expected}, got {actual}"
        )

    # Compile the submitted source dynamically so Valgrind can reliably observe
    # its allocations even though the deliverable itself must be static.
    valgrind_exe = "/tmp/det_calc_valgrind"
    compile_result = subprocess.run(
        ["gcc", "-O0", "-g", SOURCE, "-o", valgrind_exe, "-lm"],
        text=True,
        capture_output=True,
        timeout=60,
    )
    assert compile_result.returncode == 0, (
        f"Could not compile submitted source for Valgrind.\n"
        f"stdout:\n{compile_result.stdout}\nstderr:\n{compile_result.stderr}"
    )
    leak_matrix = [[0, 2, 1, 3], [4, 1, 0, 2], [2, 0, 5, 1], [1, 3, 2, 4]]
    valgrind = subprocess.run(
        [
            "valgrind", "--leak-check=full", "--show-leak-kinds=all",
            "--errors-for-leak-kinds=definite,indirect,possible",
            "--error-exitcode=97", valgrind_exe,
        ],
        input=matrix_input(leak_matrix),
        text=True,
        capture_output=True,
        timeout=60,
    )
    assert valgrind.returncode == 0, (
        f"Valgrind found an error or memory leak.\nstdout:\n{valgrind.stdout}\n"
        f"stderr:\n{valgrind.stderr}"
    )

    # The instruction explicitly requires running the supplied property script.
    props = subprocess.run(
        ["python3", VERIFY_PROPS],
        cwd=BASE,
        text=True,
        capture_output=True,
        timeout=300,
    )
    assert props.returncode == 0, (
        f"verify_props.py failed.\nstdout:\n{props.stdout}\nstderr:\n{props.stderr}"
    )


def test_verification_log_success():
    log_path = "/home/user/math_port/verification.log"
    assert os.path.isfile(log_path), f"Verification log {log_path} does not exist. Did you run the python script?"

    with open(log_path, "r") as f:
        content = f.read().strip()

    assert content == "SUCCESS", f"Expected verification log to contain 'SUCCESS', but found: '{content}'"


def test_executable_is_statically_linked():
    exe_path = "/home/user/math_port/det_calc"
    assert os.path.isfile(exe_path), f"Executable {exe_path} does not exist. Did you compile the code?"

    # Use the 'file' command to check if it's statically linked
    result = subprocess.run(["file", exe_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Failed to run 'file' command on {exe_path}"

    output = result.stdout.lower()
    assert "statically linked" in output, f"Executable {exe_path} is not statically linked. Output of 'file': {output}"


def test_makefile_exists():
    makefile_path = "/home/user/math_port/Makefile"
    assert os.path.isfile(makefile_path), f"Makefile at {makefile_path} does not exist."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
