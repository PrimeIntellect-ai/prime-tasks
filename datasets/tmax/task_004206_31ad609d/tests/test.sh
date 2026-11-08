#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import stat
import subprocess

EXPECTED_SOURCE = '''#include <stdio.h>
#include <stdlib.h>

int main() {
    int nx = 100;
    double dx = 1.0 / (nx - 1);
    double alpha = 0.1;
    double T = 0.5;

    // TODO: Change N to the minimum integer value that ensures numerical stability
    int N = 981; 
    double dt = T / N;

    double* u = (double*)malloc(nx * sizeof(double));
    double* un = (double*)malloc(nx * sizeof(double));

    for(int i = 0; i < nx; i++) {
        double x = i * dx;
        u[i] = x * (1.0 - x) * 4.0;
    }

    for(int n = 0; n < N; n++) {
        for(int i = 1; i < nx - 1; i++) {
            un[i] = u[i] + alpha * dt / (dx * dx) * (u[i+1] - 2*u[i] + u[i-1]);
        }
        un[0] = 0.0;
        un[nx-1] = 0.0;
        for(int i = 0; i < nx; i++) {
            u[i] = un[i];
        }
    }

    double sum = 0.0;
    for(int i = 0; i < nx; i++) {
        sum += u[i];
    }

    printf("%.6f\\n", sum);
    free(u);
    free(un);
    return 0;
}
'''


def minimum_stable_n():
    nx = 100
    dx = 1.0 / (nx - 1)
    alpha = 0.1
    T = 0.5
    threshold = 2.0 * alpha * T / (dx * dx)
    n = math.ceil(threshold)
    while alpha * (T / n) / (dx * dx) > 0.5:
        n += 1
    while n > 1 and alpha * (T / (n - 1)) / (dx * dx) <= 0.5:
        n -= 1
    return n


def get_expected_sum():
    nx = 100
    dx = 1.0 / (nx - 1)
    alpha = 0.1
    T = 0.5
    N = minimum_stable_n()
    dt = T / N

    u = [0.0] * nx
    un = [0.0] * nx

    for i in range(nx):
        x = i * dx
        u[i] = x * (1.0 - x) * 4.0

    for n in range(N):
        for i in range(1, nx - 1):
            un[i] = u[i] + alpha * dt / (dx * dx) * (u[i+1] - 2.0*u[i] + u[i-1])
        un[0] = 0.0
        un[nx-1] = 0.0
        for i in range(nx):
            u[i] = un[i]

    total_sum = 0.0
    for i in range(nx):
        total_sum += u[i]

    return f"{total_sum:.6f}"


def test_result_file_exists_and_correct():
    result_path = "/home/user/result.txt"
    assert os.path.isfile(result_path), f"File {result_path} does not exist."

    with open(result_path, 'r') as f:
        content = f.read().strip()

    expected_output = get_expected_sum()
    assert content == expected_output, f"Expected output '{expected_output}', but got '{content}' in {result_path}."


def test_sim_c_modified_only_as_requested():
    sim_c_path = "/home/user/sim.c"
    assert os.path.isfile(sim_c_path), f"File {sim_c_path} does not exist."

    with open(sim_c_path, 'r') as f:
        content = f.read()

    # Preserve the original assertion and additionally require the sole requested edit.
    assert "int N = 100;" not in content, "The value of N in sim.c was not changed from 100."
    assert minimum_stable_n() == 981
    assert content == EXPECTED_SOURCE, "sim.c must differ from the supplied source only by changing N from 100 to 981."


def test_source_compiles_and_runs_with_expected_output(tmp_path):
    output_binary = tmp_path / "sim_from_source"
    compile_result = subprocess.run(
        ["gcc", "-O2", "/home/user/sim.c", "-o", str(output_binary)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, f"sim.c failed to compile: {compile_result.stderr}"

    run_result = subprocess.run(
        [str(output_binary)], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=30
    )
    assert run_result.returncode == 0, f"Compiled sim.c failed to run: {run_result.stderr}"
    assert run_result.stdout == get_expected_sum() + "\n"
    assert run_result.stderr == ""


def test_requested_compiled_executable_exists_and_runs():
    executable = "/home/user/sim"
    assert os.path.isfile(executable), f"Compiled executable {executable} does not exist."
    assert os.access(executable, os.X_OK), f"{executable} is not executable."
    assert stat.S_ISREG(os.stat(executable).st_mode)
    with open(executable, "rb") as f:
        assert f.read(4) == b"\\x7fELF", f"{executable} is not a compiled ELF executable."

    run_result = subprocess.run(
        [executable], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=30
    )
    assert run_result.returncode == 0, f"{executable} failed to run: {run_result.stderr}"
    assert run_result.stdout == get_expected_sum() + "\n"
    assert run_result.stderr == ""
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
