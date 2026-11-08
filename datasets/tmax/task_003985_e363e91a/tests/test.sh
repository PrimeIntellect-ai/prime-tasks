#!/bin/bash
set -e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt
trap 'if [ ! -s /logs/verifier/reward.txt ]; then echo "0" > /logs/verifier/reward.txt; fi' EXIT

cat << 'INTERPOSE_EOF' > /tmp/solver_interpose.c
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>

static double determinant_3x3(const double *m) {
    return m[0] * (m[4] * m[8] - m[5] * m[7])
         - m[1] * (m[3] * m[8] - m[5] * m[6])
         + m[2] * (m[3] * m[7] - m[4] * m[6]);
}

int solve_3x3(const double *A, const double *B, double *solution) {
    const char *log_path = getenv("SOLVER_CALL_LOG");
    if (log_path) {
        int fd = open(log_path, O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (fd >= 0) {
            (void)write(fd, "called\n", 7);
            close(fd);
        }
    }

    double detA = determinant_3x3(A);
    if (detA == 0.0) return -1;

    double Ax[9] = {B[0], A[1], A[2], B[1], A[4], A[5], B[2], A[7], A[8]};
    double Ay[9] = {A[0], B[0], A[2], A[3], B[1], A[5], A[6], B[2], A[8]};
    double Az[9] = {A[0], A[1], B[0], A[3], A[4], B[1], A[6], A[7], B[2]};

    solution[0] = determinant_3x3(Ax) / detA;
    solution[1] = determinant_3x3(Ay) / detA;
    solution[2] = determinant_3x3(Az) / detA;
    return 0;
}
INTERPOSE_EOF

gcc -shared -fPIC -O2 -o /tmp/libsolver_interpose.so /tmp/solver_interpose.c

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess

SO_PATH = "/home/user/math_utils/libsystemsolver.so"
SOURCE_PATH = "/home/user/src/compute_boundaries.c"
BIN_PATH = "/home/user/bin/compute_boundaries"
CSV_PATH = "/home/user/data/density_points.csv"
RESULT_PATH = "/home/user/results/boundaries.txt"
REBUILT_PATH = "/tmp/compute_boundaries_rebuilt"
INTERPOSER_PATH = "/tmp/libsolver_interpose.so"


def test_shared_library_exists():
    so_path = SO_PATH
    assert os.path.exists(so_path), f"Shared library {so_path} is missing. Did you compile the C library correctly?"


def test_c_source_exists():
    c_path = SOURCE_PATH
    assert os.path.exists(c_path), f"Source file {c_path} is missing."


def test_executable_exists():
    bin_path = BIN_PATH
    assert os.path.exists(bin_path), f"Executable {bin_path} is missing. Did you compile your C program?"
    assert os.access(bin_path, os.X_OK), f"{bin_path} is not executable."


def _readelf(*args):
    return subprocess.run(
        ["readelf", *args], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=10
    )


def _assert_dynamic_artifact(path, shared=False):
    header = _readelf("-h", path)
    assert header.returncode == 0, f"{path} is not a valid ELF file:\n{header.stdout}"
    assert "ELF Header:" in header.stdout, f"{path} is not an ELF artifact."
    if shared:
        assert "Type:" in header.stdout and "DYN" in header.stdout, f"{path} is not a shared ELF library."
        symbols = _readelf("--dyn-syms", path)
        assert symbols.returncode == 0 and "solve_3x3" in symbols.stdout, \
            f"{path} does not export solve_3x3."
    else:
        dynamic = _readelf("-d", path)
        assert dynamic.returncode == 0, f"Cannot inspect dynamic dependencies of {path}."
        assert "libsystemsolver.so" in dynamic.stdout, \
            f"{path} is not dynamically linked against libsystemsolver.so."
        symbols = _readelf("--dyn-syms", path)
        assert symbols.returncode == 0, f"Cannot inspect dynamic symbols of {path}."
        matching = [line for line in symbols.stdout.splitlines() if "solve_3x3" in line]
        assert matching and any("UND" in line for line in matching), \
            f"{path} does not dynamically import solve_3x3."


def test_artifacts_are_dynamic_elf_and_linked():
    _assert_dynamic_artifact(SO_PATH, shared=True)
    _assert_dynamic_artifact(BIN_PATH, shared=False)


def test_source_rebuilds_to_required_binary():
    proc = subprocess.run([
        "gcc", "-std=c11", "-Wall", "-Wextra", "-O2",
        "-I/home/user/math_utils", SOURCE_PATH,
        "-L/home/user/math_utils", "-lsystemsolver",
        "-Wl,-rpath,/home/user/math_utils", "-lm",
        "-o", REBUILT_PATH,
    ], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
    assert proc.returncode == 0, f"compute_boundaries.c could not be compiled:\n{proc.stdout}"
    _assert_dynamic_artifact(REBUILT_PATH, shared=False)


def det3(m):
    return (m[0][0] * (m[1][1]*m[2][2] - m[1][2]*m[2][1]) -
            m[0][1] * (m[1][0]*m[2][2] - m[1][2]*m[2][0]) +
            m[0][2] * (m[1][0]*m[2][1] - m[1][1]*m[2][0]))


def _expected_from_csv():
    points = []
    with open(CSV_PATH, 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                x, y = map(float, line.split(','))
                points.append((x, y))

    assert len(points) == 3, "Expected exactly 3 points in CSV."

    A = [[p[0]**2, p[0], 1.0] for p in points]
    B = [p[1] for p in points]
    detA = det3(A)
    assert detA != 0, "Matrix is singular, cannot solve."

    Ax = [[B[i] if j == 0 else A[i][j] for j in range(3)] for i in range(3)]
    Ay = [[B[i] if j == 1 else A[i][j] for j in range(3)] for i in range(3)]
    Az = [[B[i] if j == 2 else A[i][j] for j in range(3)] for i in range(3)]

    a = det3(Ax) / detA
    b = det3(Ay) / detA
    c = det3(Az) / detA

    c_adj = c - 0.5
    discriminant = b**2 - 4*a*c_adj
    assert discriminant >= 0, "No real roots found for y=0.5."

    root1 = (-b - math.sqrt(discriminant)) / (2*a)
    root2 = (-b + math.sqrt(discriminant)) / (2*a)
    return f"{min(root1, root2):.6f},{max(root1, root2):.6f}"


def _run_binary(path, require_solver_call=False):
    if os.path.exists(RESULT_PATH):
        os.remove(RESULT_PATH)

    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = "/home/user/math_utils"
    call_log = f"/tmp/solver_called_{os.getpid()}_{secrets.token_hex(8)}"
    if require_solver_call:
        env["LD_PRELOAD"] = INTERPOSER_PATH
        env["SOLVER_CALL_LOG"] = call_log

    proc = subprocess.run(
        [path], env=env, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=10
    )
    assert proc.returncode == 0, f"{path} exited with {proc.returncode}:\n{proc.stdout}"
    assert os.path.exists(RESULT_PATH), f"{path} did not create {RESULT_PATH}."

    with open(RESULT_PATH, "r") as f:
        actual = f.read().strip()
    expected = _expected_from_csv()
    assert actual == expected, f"Expected output '{expected}', but got '{actual}' in {RESULT_PATH}."

    if require_solver_call:
        assert os.path.exists(call_log) and os.path.getsize(call_log) > 0, \
            f"{path} did not call the dynamically linked solve_3x3 function."
        os.remove(call_log)


def test_boundaries_output():
    csv_path = CSV_PATH
    assert os.path.exists(csv_path), f"CSV file {csv_path} is missing."

    # Execute the required artifact rather than trusting a pre-created result.
    _run_binary(BIN_PATH)

    expected_output = _expected_from_csv()
    res_path = RESULT_PATH
    assert os.path.exists(res_path), f"Results file {res_path} is missing. Did your program run successfully?"

    with open(res_path, 'r') as f:
        actual_output = f.read().strip()

    assert actual_output == expected_output, f"Expected output '{expected_output}', but got '{actual_output}' in {res_path}."


def test_programs_read_runtime_csv_and_use_solver():
    with open(CSV_PATH, "r") as f:
        original_csv = f.read()

    rng = secrets.SystemRandom()
    try:
        for _ in range(3):
            r1 = rng.uniform(-4.5, -0.8)
            r2 = rng.uniform(0.7, 4.8)
            scale = -rng.uniform(0.35, 2.25)
            xs = [-3.7, -0.2, 3.1]
            points = [(x, scale * (x - r1) * (x - r2) + 0.5) for x in xs]
            with open(CSV_PATH, "w") as f:
                for x, y in points:
                    f.write(f"{x:.12f},{y:.12f}\n")

            _run_binary(BIN_PATH, require_solver_call=True)
            _run_binary(REBUILT_PATH, require_solver_call=True)
    finally:
        with open(CSV_PATH, "w") as f:
            f.write(original_csv)
        # Leave the required result file corresponding to the original dataset.
        _run_binary(BIN_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
