#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import pathlib
import random
import re
import subprocess

CPP_PATH = pathlib.Path('/home/user/fisher_sim.cpp')
ANALYZE_PATH = pathlib.Path('/home/user/analyze.py')
STATE_PATH = pathlib.Path('/home/user/final_state.txt')
GENERATED_STATE_PATH = pathlib.Path('/tmp/generated_final_state.txt')
RESULTS_PATH = pathlib.Path('/home/user/regression_results.txt')
BINARY_PATH = pathlib.Path('/tmp/fisher_sim_verify')


def compute_golden_state_and_values():
    N = 1000
    L = 1.0
    dx = L / (N - 1)
    D = 0.01
    r = 1.0
    T = 1.0

    dt = 0.4 * (dx * dx) / D
    steps = math.ceil(T / dt)

    u = [0.0] * N
    for i in range(N // 10):
        u[i] = 1.0

    for _ in range(steps):
        u_new = list(u)
        for i in range(1, N - 1):
            diffusion = D * (u[i + 1] - 2 * u[i] + u[i - 1]) / (dx * dx)
            reaction = r * u[i] * (1 - u[i])
            u_new[i] = u[i] + dt * (diffusion + reaction)
        u = u_new

    x = [i * dx for i in range(N)]
    filtered_x = []
    filtered_u = []
    for i in range(N):
        if 0.2 - 1e-12 <= x[i] <= 0.8 + 1e-12:
            filtered_x.append(x[i])
            filtered_u.append(u[i])

    n = len(filtered_x)
    sum_x = sum(filtered_x)
    sum_y = sum(filtered_u)
    sum_xx = sum(xi * xi for xi in filtered_x)
    sum_xy = sum(xi * yi for xi, yi in zip(filtered_x, filtered_u))
    denominator = n * sum_xx - sum_x * sum_x
    slope = (n * sum_xy - sum_x * sum_y) / denominator
    intercept = (sum_y - slope * sum_x) / n

    return x, u, f'Slope: {slope:.6f}\nIntercept: {intercept:.6f}'


GOLDEN_X, GOLDEN_U, GOLDEN_RESULTS = compute_golden_state_and_values()


def parse_state(path):
    rows = []
    with open(path, 'r') as f:
        for line_number, line in enumerate(f, 1):
            fields = line.split()
            assert len(fields) == 2, f'{path}:{line_number} must contain exactly x and u'
            try:
                x, u = map(float, fields)
            except ValueError as exc:
                raise AssertionError(f'{path}:{line_number} contains non-numeric data') from exc
            assert math.isfinite(x) and math.isfinite(u), f'{path}:{line_number} contains NaN or infinity'
            rows.append((x, u))
    return rows


def run_analyzer():
    completed = subprocess.run(
        ['runuser', '-u', 'user', '--', 'python3', str(ANALYZE_PATH)],
        cwd='/home/user', text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=60
    )
    assert completed.returncode == 0, f'analyze.py failed:\n{completed.stdout}'
    assert RESULTS_PATH.is_file(), f'Missing required output file: {RESULTS_PATH}'


def strip_cpp_comments(content):
    content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
    return re.sub(r'//[^\n]*', '', content)


def test_cpp_file_updated():
    cpp_path = '/home/user/fisher_sim.cpp'
    assert os.path.isfile(cpp_path), f'C++ file missing: {cpp_path}'

    with open(cpp_path, 'r') as f:
        content = f.read()

    # Preserve the original source assertions.
    assert '1000' in content, 'The C++ file does not seem to have been updated to N=1000.'
    assert 'omp' in content.lower() or 'pragma' in content.lower(), 'The C++ file does not seem to contain OpenMP pragmas.'

    code = strip_cpp_comments(content)
    assert re.search(r'\bN\s*=\s*1000\s*;', code), 'N is not actually assigned 1000 in the C++ code.'
    assert re.search(
        r'\bdt\s*=\s*0\.4\s*\*\s*\(\s*dx\s*\*\s*dx\s*\)\s*/\s*D\s*;', code
    ), 'dt is not calculated as exactly 0.4 * (dx * dx) / D.'
    assert re.search(
        r'^\s*#\s*pragma\s+omp\s+parallel\s+for\b[^\n]*\n\s*for\s*\(\s*int\s+i\s*=\s*1\s*;\s*i\s*<\s*N\s*-\s*1\s*;',
        code, flags=re.MULTILINE
    ), 'The spatial update loop is not parallelized with an OpenMP parallel-for pragma.'

    symbols = subprocess.run(
        ['nm', '-D', str(BINARY_PATH)], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=True
    ).stdout
    assert 'GOMP_parallel' in symbols, 'The compiled simulation does not contain an active OpenMP parallel region.'


def test_final_state_generated_by_simulation():
    assert GENERATED_STATE_PATH.is_file(), 'Running the compiled simulation did not generate final_state.txt.'
    rows = parse_state(GENERATED_STATE_PATH)
    assert len(rows) == 1000, f'Expected 1000 final-state rows, got {len(rows)}.'

    for i, ((actual_x, actual_u), expected_x, expected_u) in enumerate(zip(rows, GOLDEN_X, GOLDEN_U)):
        assert abs(actual_x - expected_x) <= 1e-6, (
            f'Incorrect x coordinate at row {i}: expected {expected_x}, got {actual_x}'
        )
        assert abs(actual_u - expected_u) <= 5e-6, (
            f'Incorrect simulated concentration at row {i}: expected {expected_u}, got {actual_u}'
        )


def test_regression_results():
    assert ANALYZE_PATH.is_file(), f'Missing required analysis script: {ANALYZE_PATH}'
    assert RESULTS_PATH.is_file(), f'Missing required output file: {RESULTS_PATH}'

    with open(RESULTS_PATH, 'r') as f:
        content = f.read().strip()

    expected_content = GOLDEN_RESULTS.strip()
    assert content == expected_content, (
        f'Contents of {RESULTS_PATH} do not match the expected values.\n'
        f'Expected:\n{expected_content}\n\nGot:\n{content}'
    )

    # Exercise analyze.py on fresh, unpredictable data so a hardcoded result cannot pass.
    rng = random.SystemRandom()
    xs = [0.0, 0.2, 0.31, 0.47, 0.63, 0.8, 1.0]
    ys = [rng.uniform(-20, 20) for _ in xs]
    filtered = [(x, y) for x, y in zip(xs, ys) if 0.2 <= x <= 0.8]
    fx = [p[0] for p in filtered]
    fy = [p[1] for p in filtered]
    n = len(fx)
    sum_x = sum(fx)
    sum_y = sum(fy)
    sum_xx = sum(x * x for x in fx)
    sum_xy = sum(x * y for x, y in filtered)
    denominator = n * sum_xx - sum_x * sum_x
    slope = (n * sum_xy - sum_x * sum_y) / denominator
    intercept = (sum_y - slope * sum_x) / n
    dynamic_expected = f'Slope: {slope:.6f}\nIntercept: {intercept:.6f}'

    original_state = GENERATED_STATE_PATH.read_bytes()
    try:
        STATE_PATH.write_text(''.join(f'{x:.17g} {y:.17g}\n' for x, y in zip(xs, ys)))
        os.chown(STATE_PATH, 1000, 1000)
        if RESULTS_PATH.exists():
            RESULTS_PATH.unlink()
        run_analyzer()
        dynamic_actual = RESULTS_PATH.read_text().strip()
        assert dynamic_actual == dynamic_expected, (
            'analyze.py did not compute the required filtered linear regression on fresh input.\n'
            f'Expected:\n{dynamic_expected}\n\nGot:\n{dynamic_actual}'
        )
    finally:
        STATE_PATH.write_bytes(original_state)
        os.chown(STATE_PATH, 1000, 1000)
        if RESULTS_PATH.exists():
            RESULTS_PATH.unlink()
        run_analyzer()

    restored_content = RESULTS_PATH.read_text().strip()
    assert restored_content == expected_content, (
        'analyze.py did not regenerate the correct final regression results from the simulation output.'
    )
TEST_EOF

verify_task() {
    test -f /home/user/fisher_sim.cpp || return 1
    test -f /home/user/analyze.py || return 1

    rm -f /home/user/final_state.txt /home/user/regression_results.txt \
          /tmp/generated_final_state.txt /tmp/fisher_sim_verify

    g++ -std=c++11 -fopenmp /home/user/fisher_sim.cpp -o /tmp/fisher_sim_verify || return 1
    chmod 755 /tmp/fisher_sim_verify

    timeout 180s runuser -u user -- env OMP_NUM_THREADS=2 /tmp/fisher_sim_verify || return 1
    test -f /home/user/final_state.txt || return 1
    cp /home/user/final_state.txt /tmp/generated_final_state.txt || return 1

    timeout 60s runuser -u user -- python3 /home/user/analyze.py || return 1
    test -f /home/user/regression_results.txt || return 1

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
}

if verify_task; then
    echo '1' > /logs/verifier/reward.txt
else
    echo '0' > /logs/verifier/reward.txt
fi
