#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess
import textwrap

import pytest

CPP_PATH = '/home/user/src/energy_sim.cpp'
SIM_PATH = '/home/user/src/sim'
VERIFIED_SIM = '/tmp/verified_energy_sim'
HARNESS = '/tmp/energy_harness'


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, text=True, capture_output=True, timeout=30, **kwargs)


@pytest.fixture(scope='session', autouse=True)
def build_and_validate_artifacts():
    assert os.path.isfile(CPP_PATH), f'File {CPP_PATH} is missing.'

    # The task explicitly required the agent to build this executable.
    assert os.path.isfile(SIM_PATH), f'Compiled executable {SIM_PATH} is missing.'
    assert os.access(SIM_PATH, os.X_OK), f'{SIM_PATH} is not executable.'
    with open(SIM_PATH, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f'{SIM_PATH} is not a compiled ELF executable.'

    # Independently compile the submitted source so a fake/stale sim cannot pass.
    result = subprocess.run(
        ['g++', '-O3', '-fopenmp', '-I/home/user/eigen', CPP_PATH, '-o', VERIFIED_SIM],
        text=True, capture_output=True, timeout=60
    )
    assert result.returncode == 0, f'Submitted source did not compile:\n{result.stdout}\n{result.stderr}'

    harness_source = r'''
#define main submitted_energy_sim_main
#include "/home/user/src/energy_sim.cpp"
#undef main

#include <iomanip>
#include <iostream>
#include <string>
#include <vector>

int main(int argc, char** argv) {
    if (argc != 2) return 2;
    std::string mode = argv[1];

    if (mode == "energy") {
        std::vector<Atom> atoms = {
            {0.0f, 0.0f, 0.0f},
            {1.0f, 0.0f, 0.0f},
            {0.0f, 2.0f, 0.0f},
            {0.0f, 0.0f, 4.0f},
            {3.0f, -2.0f, 1.0f}
        };
        std::cout << std::setprecision(17) << compute_total_energy(atoms) << "\n";
        return 0;
    }
    if (mode == "fit1") {
        std::vector<double> x = {-3.0, -1.0, 0.0, 2.0, 4.0, 6.0};
        std::vector<double> y = {7.37, 1.93, 1.21, 2.48, 8.41, 18.55};
        fit_energy_curve(x, y);
        return 0;
    }
    if (mode == "fit2") {
        std::vector<double> x = {-2.5, -0.5, 1.5, 3.5, 7.0, 9.0};
        std::vector<double> y = {-6.08, -2.17, 2.84, 9.91, 29.63, 45.12};
        fit_energy_curve(x, y);
        return 0;
    }
    return 3;
}
'''
    with open('/tmp/energy_harness.cpp', 'w') as f:
        f.write(harness_source)
    result = subprocess.run(
        ['g++', '-O3', '-fopenmp', '-I/home/user/eigen', '/tmp/energy_harness.cpp', '-o', HARNESS],
        text=True, capture_output=True, timeout=60
    )
    assert result.returncode == 0, f'Could not link submitted functions into test harness:\n{result.stdout}\n{result.stderr}'


def test_stat_log_exists_and_correct():
    stat_log_path = '/home/user/results/stat_log.txt'
    assert os.path.isfile(stat_log_path), f'File {stat_log_path} is missing. Did you create the results directory and save the variance?'
    with open(stat_log_path, 'r') as f:
        content = f.read().strip()
    assert 'Variance: 0.0000' in content, f"Expected 'Variance: 0.0000' in {stat_log_path}, but found: {content}"


def test_fit_log_exists_and_correct():
    fit_log_path = '/home/user/results/fit_log.txt'
    assert os.path.isfile(fit_log_path), f'File {fit_log_path} is missing. Did you save the curve fitting output?'
    with open(fit_log_path, 'r') as f:
        content = f.read().strip()
    expected_str = 'Coeffs: 0.3800, 0.5229, 0.9857'
    assert expected_str in content, f"Expected '{expected_str}' in {fit_log_path}, but found: {content}"


def test_cpp_code_fixed():
    with open(CPP_PATH, 'r') as f:
        content = f.read()
    assert '#pragma omp atomic' not in content, "The code still contains '#pragma omp atomic', which causes non-deterministic reduction."
    assert (re.search(r'#pragma\s+omp\s+parallel\s+for\s+reduction\s*\(\s*\+\s*:\s*total_energy\s*\)', content)
            or re.search(r'reduction\s*\(\s*\+\s*:\s*total_energy\s*\)', content)), \
        "The code does not seem to contain a proper OpenMP reduction clause for 'total_energy'."
    assert re.search(r'double\s+total_energy\s*=\s*0\.0', content), \
        "The 'total_energy' accumulator should be changed to a 'double'."


def test_simulation_runs_reproducibly_and_matches_input():
    energies = []
    expected_coeff_line = 'Coeffs: 0.3800, 0.5229, 0.9857'
    env = os.environ.copy()
    env['OMP_NUM_THREADS'] = '4'
    for _ in range(10):
        result = run([VERIFIED_SIM], env=env)
        energy_match = re.search(r'^Total Energy:\s*([-+0-9.eE]+)\s*$', result.stdout, re.MULTILINE)
        assert energy_match, f'Simulation did not print Total Energy correctly:\n{result.stdout}'
        energies.append(energy_match.group(1))
        assert expected_coeff_line in result.stdout, f'Simulation curve-fit output is incorrect:\n{result.stdout}'

    assert len(set(energies)) == 1, f'Total Energy was not reproducible over 10 runs: {energies}'
    expected_energy = sum(1.0 / d for d in (2.0, 5.0, 9.0, 3.0, 7.0, 4.0))
    assert abs(float(energies[0]) - expected_energy) < 5e-7, \
        f'Energy for the supplied molecule is wrong: got {energies[0]}, expected {expected_energy}'


def solve_quadratic_least_squares(xs, ys):
    rows = [[1.0, x, x*x] for x in xs]
    a = [[sum(r[i] * r[j] for r in rows) for j in range(3)] for i in range(3)]
    b = [sum(r[i] * y for r, y in zip(rows, ys)) for i in range(3)]
    for col in range(3):
        pivot = max(range(col, 3), key=lambda row: abs(a[row][col]))
        a[col], a[pivot] = a[pivot], a[col]
        b[col], b[pivot] = b[pivot], b[col]
        for row in range(col + 1, 3):
            factor = a[row][col] / a[col][col]
            for j in range(col, 3):
                a[row][j] -= factor * a[col][j]
            b[row] -= factor * b[col]
    out = [0.0, 0.0, 0.0]
    for i in range(2, -1, -1):
        out[i] = (b[i] - sum(a[i][j] * out[j] for j in range(i + 1, 3))) / a[i][i]
    return out


def parse_coeffs(output):
    match = re.search(r'Coeffs:\s*([-+0-9.eE]+)\s*,\s*([-+0-9.eE]+)\s*,\s*([-+0-9.eE]+)', output)
    assert match, f'fit_energy_curve did not print coefficients in the required format:\n{output}'
    return [float(match.group(i)) for i in range(1, 4)]


@pytest.mark.parametrize('mode,xs,ys', [
    ('fit1', [-3.0, -1.0, 0.0, 2.0, 4.0, 6.0], [7.37, 1.93, 1.21, 2.48, 8.41, 18.55]),
    ('fit2', [-2.5, -0.5, 1.5, 3.5, 7.0, 9.0], [-6.08, -2.17, 2.84, 9.91, 29.63, 45.12]),
])
def test_quadratic_regression_on_additional_data(mode, xs, ys):
    actual = parse_coeffs(run([HARNESS, mode]).stdout)
    expected = solve_quadratic_least_squares(xs, ys)
    for index, (got, want) in enumerate(zip(actual, expected)):
        assert abs(got - want) <= 0.00011, \
            f'Wrong regression coefficient c{index} for {mode}: got {got}, expected {want:.4f}'


def test_energy_function_on_additional_atoms():
    env = os.environ.copy()
    env['OMP_NUM_THREADS'] = '4'
    values = [float(run([HARNESS, 'energy'], env=env).stdout.strip()) for _ in range(5)]
    points = [(0.0,0.0,0.0), (1.0,0.0,0.0), (0.0,2.0,0.0), (0.0,0.0,4.0), (3.0,-2.0,1.0)]
    expected = 0.0
    for i in range(len(points)):
        for j in range(i + 1, len(points)):
            expected += 1.0 / math.dist(points[i], points[j])
    assert all(abs(value - expected) < 2e-6 for value in values), \
        f'compute_total_energy returned {values}, expected approximately {expected}'
    assert len(set(values)) == 1, f'compute_total_energy was not reproducible: {values}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
