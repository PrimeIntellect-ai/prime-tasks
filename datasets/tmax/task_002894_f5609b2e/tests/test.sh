#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess

import pytest

SIM_FILE = '/home/user/sim.c'
INIT_FILE = '/home/user/init.txt'
OUT_FILE = '/home/user/mean_energy.txt'
EXE_FILE = '/tmp/sim_verified'


def strip_c_comments_and_strings(source):
    result = []
    i = 0
    state = 'code'
    while i < len(source):
        ch = source[i]
        nxt = source[i + 1] if i + 1 < len(source) else ''
        if state == 'code':
            if ch == '/' and nxt == '*':
                result.extend('  ')
                i += 2
                state = 'block_comment'
            elif ch == '/' and nxt == '/':
                result.extend('  ')
                i += 2
                state = 'line_comment'
            elif ch == '"':
                result.append(' ')
                i += 1
                state = 'string'
            elif ch == "'":
                result.append(' ')
                i += 1
                state = 'char'
            else:
                result.append(ch)
                i += 1
        elif state == 'block_comment':
            if ch == '*' and nxt == '/':
                result.extend('  ')
                i += 2
                state = 'code'
            else:
                result.append('\n' if ch == '\n' else ' ')
                i += 1
        elif state == 'line_comment':
            if ch == '\n':
                result.append('\n')
                state = 'code'
            else:
                result.append(' ')
            i += 1
        elif state in ('string', 'char'):
            quote = '"' if state == 'string' else "'"
            if ch == '\\' and i + 1 < len(source):
                result.extend('  ')
                i += 2
            elif ch == quote:
                result.append(' ')
                i += 1
                state = 'code'
            else:
                result.append('\n' if ch == '\n' else ' ')
                i += 1
    return ''.join(result)


def run_simulation():
    env = os.environ.copy()
    env['OMP_NUM_THREADS'] = '4'
    subprocess.run(
        [EXE_FILE],
        cwd='/home/user',
        env=env,
        check=True,
        timeout=20,
    )


@pytest.fixture(scope='session', autouse=True)
def compile_and_run_submission():
    assert os.path.isfile(SIM_FILE), f"Missing {SIM_FILE}. The C source code file must exist."
    assert os.path.getsize(SIM_FILE) > 0, f"{SIM_FILE} must not be empty."

    with open(SIM_FILE, 'r', encoding='utf-8', errors='replace') as f:
        source = f.read()
    active_source = strip_c_comments_and_strings(source)
    assert re.search(r'^\s*#\s*pragma\s+omp\s+parallel\s+for\b', active_source, re.MULTILINE), \
        "sim.c must contain an active '#pragma omp parallel for' directive."

    subprocess.run(
        ['gcc', '-O2', '-fopenmp', SIM_FILE, '-lm', '-o', EXE_FILE],
        check=True,
        timeout=30,
    )
    assert os.path.isfile(EXE_FILE) and os.access(EXE_FILE, os.X_OK), \
        "Compiling sim.c did not produce an executable."

    assert os.path.isfile(INIT_FILE), f"Missing {INIT_FILE}. The initial coordinates file must exist."
    with open(INIT_FILE, 'rb') as f:
        original_init = f.read()
    run_simulation()
    assert os.path.isfile(INIT_FILE), "The simulation must not remove init.txt."
    with open(INIT_FILE, 'rb') as f:
        assert f.read() == original_init, "The simulation must not modify init.txt."


def test_mean_energy_output():
    init_file = '/home/user/init.txt'
    out_file = '/home/user/mean_energy.txt'

    assert os.path.isfile(init_file), f"Missing {init_file}. The initial coordinates file must exist."
    assert os.path.isfile(out_file), f"Missing {out_file}. The simulation must output the mean energy to this file."

    x_sq_sum = 0.0
    y_sq_sum = 0.0
    count = 0
    with open(init_file, 'r') as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) == 2:
                x, y = map(float, parts)
                x_sq_sum += x**2
                y_sq_sum += y**2
                count += 1

    assert count == 1000, f"Expected 1000 points in {init_file}, got {count}."

    mean_x_sq = x_sq_sum / count
    mean_y_sq = y_sq_sum / count

    # alpha_max = 0.02, alpha = 0.019
    # x_mult = 1 - 2(0.019) = 0.962
    # y_mult = 1 - 100(0.019) = -0.900
    x_mult_sq = (0.962)**200
    y_mult_sq = (-0.9)**200

    expected_mean_E = mean_x_sq * x_mult_sq + 50 * mean_y_sq * y_mult_sq
    expected_str = f"{expected_mean_E:.6f}"

    with open(out_file, 'r') as f:
        actual_str = f.read().strip()

    assert actual_str == expected_str, f"Expected mean energy '{expected_str}' in {out_file}, but got '{actual_str}'."


def test_sim_c_exists():
    sim_file = '/home/user/sim.c'
    assert os.path.isfile(sim_file), f"Missing {sim_file}. The C source code file must exist."


def test_compiled_simulation_on_unseen_input():
    with open(INIT_FILE, 'rb') as f:
        original_init = f.read()

    points = []
    for _ in range(1000):
        x = (secrets.randbelow(200000001) - 100000000) / 1000000.0
        y = (secrets.randbelow(200000001) - 100000000) / 1000000.0
        points.append((x, y))

    try:
        with open(INIT_FILE, 'w') as f:
            for x, y in points:
                f.write(f'{x:.6f} {y:.6f}\n')

        run_simulation()
        assert os.path.isfile(OUT_FILE), f"Missing {OUT_FILE} after executing the compiled C program."

        mean_x_sq = sum(x * x for x, _ in points) / 1000
        mean_y_sq = sum(y * y for _, y in points) / 1000
        expected = mean_x_sq * (0.962 ** 200) + 50 * mean_y_sq * ((-0.9) ** 200)
        expected_str = f'{expected:.6f}'

        with open(OUT_FILE, 'r') as f:
            actual_str = f.read().strip()
        assert actual_str == expected_str, \
            f"Compiled sim.c produced '{actual_str}' on an unseen input; expected '{expected_str}'."
    finally:
        with open(INIT_FILE, 'wb') as f:
            f.write(original_init)
        run_simulation()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
