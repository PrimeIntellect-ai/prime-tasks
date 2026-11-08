#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess
import tempfile

import numpy as np


def strip_cpp_comments(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    return re.sub(r'//.*', '', text)


def test_cpp_source_fixed():
    cpp_file = '/home/user/src/nmf_solver.cpp'
    assert os.path.isfile(cpp_file), f"Missing {cpp_file}"
    with open(cpp_file, 'r') as f:
        content = f.read()
    assert "1e-9" in content, "The C++ source code does not seem to include the '1e-9' regularization term."

    code = strip_cpp_comments(content)
    idx_h = r'H\s*\[\s*k\s*\]\s*\[\s*j\s*\]'
    num_h = r'W_T_V\s*\[\s*k\s*\]\s*\[\s*j\s*\]'
    den_h = r'W_T_W_H\s*\[\s*k\s*\]\s*\[\s*j\s*\]'
    idx_w = r'W\s*\[\s*i\s*\]\s*\[\s*k\s*\]'
    num_w = r'V_H_T\s*\[\s*i\s*\]\s*\[\s*k\s*\]'
    den_w = r'W_H_H_T\s*\[\s*i\s*\]\s*\[\s*k\s*\]'

    h_sum = rf'(?:{den_h}\s*\+\s*1e-9|1e-9\s*\+\s*{den_h})'
    w_sum = rf'(?:{den_w}\s*\+\s*1e-9|1e-9\s*\+\s*{den_w})'
    h_update = rf'{idx_h}\s*\*=\s*{num_h}\s*/\s*\(\s*{h_sum}\s*\)\s*;'
    w_update = rf'{idx_w}\s*\*=\s*{num_w}\s*/\s*\(\s*{w_sum}\s*\)\s*;'
    assert re.search(h_update, code), "The H update denominator must include 1e-9."
    assert re.search(w_update, code), "The W update denominator must include 1e-9."


def test_executable_exists():
    exe_file = '/home/user/nmf_solver'
    assert os.path.isfile(exe_file), f"Missing executable {exe_file}"
    assert os.access(exe_file, os.X_OK), f"{exe_file} is not executable"
    with open(exe_file, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"{exe_file} is not a compiled ELF executable"


def load_matrix(filename):
    matrix = []
    with open(filename, 'r') as f:
        for line in f:
            parts = line.strip().split()
            if parts:
                matrix.append([float(x) for x in parts])
    return matrix


def checked_matrix(filename, shape):
    values = load_matrix(filename)
    assert len(values) == shape[0], f"{filename} has the wrong number of rows"
    assert all(len(row) == shape[1] for row in values), f"{filename} has the wrong number of columns"
    arr = np.asarray(values, dtype=float)
    assert np.isfinite(arr).all(), f"{filename} contains NaN or Inf"
    assert (arr >= 0).all(), f"{filename} contains negative values"
    return arr


def run_solver(executable, input_file, rank, w_file, h_file):
    for path in (w_file, h_file):
        if os.path.exists(path):
            os.remove(path)
    result = subprocess.run(
        [executable, input_file, str(rank), w_file, h_file],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
    )
    assert result.returncode == 0, f"Solver failed: {result.stderr}"
    assert os.path.isfile(w_file), f"Solver did not create {w_file}"
    assert os.path.isfile(h_file), f"Solver did not create {h_file}"


def relative_error(v, w, h):
    return float(np.linalg.norm(v - w @ h) / max(np.linalg.norm(v), 1e-15))


def test_executable_matches_fixed_source_and_handles_hidden_inputs():
    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, 'rebuilt_solver')
        compile_result = subprocess.run(
            ['g++', '-std=c++11', '-O3', '/home/user/src/nmf_solver.cpp', '-o', rebuilt],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
        )
        assert compile_result.returncode == 0, f"Fixed source does not compile: {compile_result.stderr}"

        rng = np.random.RandomState(731)
        a = rng.uniform(0.1, 1.0, size=(16, 3))
        b = rng.uniform(0.1, 1.0, size=(3, 11))
        low_rank = a @ b
        hidden_inputs = [low_rank, np.zeros((9, 7), dtype=float)]

        for case, v in enumerate(hidden_inputs):
            input_path = os.path.join(td, f'input_{case}.txt')
            np.savetxt(input_path, v, fmt='%.17g')
            sub_w = os.path.join(td, f'sub_w_{case}.txt')
            sub_h = os.path.join(td, f'sub_h_{case}.txt')
            ref_w = os.path.join(td, f'ref_w_{case}.txt')
            ref_h = os.path.join(td, f'ref_h_{case}.txt')

            run_solver('/home/user/nmf_solver', input_path, 5, sub_w, sub_h)
            run_solver(rebuilt, input_path, 5, ref_w, ref_h)

            sw = checked_matrix(sub_w, (v.shape[0], 5))
            sh = checked_matrix(sub_h, (5, v.shape[1]))
            rw = checked_matrix(ref_w, (v.shape[0], 5))
            rh = checked_matrix(ref_h, (5, v.shape[1]))
            assert np.array_equal(sw, rw) and np.array_equal(sh, rh), \
                "The installed executable does not correspond to the fixed source"

            if case == 0:
                assert relative_error(v, sw, sh) < 0.30, "Solver produced a poor rank-5 factorization"
            else:
                assert np.allclose(sw @ sh, 0.0, atol=1e-12), \
                    "Regularized solver did not handle a zero/near-singular input correctly"


def test_factorization_outputs():
    v = np.asarray(load_matrix('/home/user/data/input_matrix.txt'), dtype=float)
    assert v.shape == (100, 20), "Unexpected provided input dimensions"

    w_file = '/home/user/W.txt'
    h_file = '/home/user/H.txt'
    run_solver('/home/user/nmf_solver', '/home/user/data/input_matrix.txt', 5, w_file, h_file)

    assert os.path.isfile(w_file), f"Missing {w_file}"
    assert os.path.isfile(h_file), f"Missing {h_file}"
    w = checked_matrix(w_file, (100, 5))
    h = checked_matrix(h_file, (5, 20))

    for row in w:
        for val in row:
            assert not math.isnan(val), "W matrix contains NaN"
            assert not math.isinf(val), "W matrix contains Inf"
    for row in h:
        for val in row:
            assert not math.isnan(val), "H matrix contains NaN"
            assert not math.isinf(val), "H matrix contains Inf"

    assert relative_error(v, w, h) < 0.45, "Rank-5 NMF reconstruction quality is too poor"


def expected_kl_value(v, w, h):
    v_approx = w @ h
    v_flat = v.reshape(-1)
    q_flat = v_approx.reshape(-1)
    sum_v = float(v_flat.sum())
    sum_q = float(q_flat.sum())
    assert sum_v > 0 and sum_q > 0
    p = v_flat / sum_v
    q = q_flat / sum_q
    expected = 0.0
    for pv, qv in zip(p, q):
        if pv > 0 and qv > 0:
            expected += float(pv * math.log(pv / qv))
    return expected


def run_evaluator():
    kl_file = '/home/user/kl_divergence.txt'
    if os.path.exists(kl_file):
        os.remove(kl_file)
    result = subprocess.run(
        ['python3', '/home/user/evaluate.py'], cwd='/home/user',
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert result.returncode == 0, f"evaluate.py failed: {result.stderr}"
    assert os.path.isfile(kl_file), f"Missing {kl_file}"
    with open(kl_file, 'r') as f:
        content = f.read().strip()
    try:
        value = float(content)
    except ValueError:
        assert False, f"{kl_file} does not contain a valid float"
    assert not math.isnan(value), "KL divergence is NaN"
    assert not math.isinf(value), "KL divergence is Inf"
    assert value >= 0, "KL divergence must be non-negative"
    return value


def test_evaluation_script_and_output():
    eval_script = '/home/user/evaluate.py'
    kl_file = '/home/user/kl_divergence.txt'
    assert os.path.isfile(eval_script), f"Missing {eval_script}"

    v = np.asarray(load_matrix('/home/user/data/input_matrix.txt'), dtype=float)
    w = np.asarray(load_matrix('/home/user/W.txt'), dtype=float)
    h = np.asarray(load_matrix('/home/user/H.txt'), dtype=float)

    kl_val = run_evaluator()
    assert os.path.isfile(kl_file), f"Missing {kl_file}"
    expected_kl = expected_kl_value(v, w, h)
    assert math.isclose(kl_val, expected_kl, rel_tol=1e-3, abs_tol=1e-5), \
        f"KL divergence in {kl_file} ({kl_val}) does not match expected value ({expected_kl})"

    # Exercise the script on changed factors so a precomputed or hard-coded value cannot pass.
    w_path = '/home/user/W.txt'
    h_path = '/home/user/H.txt'
    with open(w_path, 'rb') as f:
        saved_w = f.read()
    with open(h_path, 'rb') as f:
        saved_h = f.read()
    try:
        changed_h = h * np.linspace(0.65, 1.35, h.shape[1])[None, :]
        np.savetxt(h_path, changed_h, fmt='%.17g')
        changed_kl = run_evaluator()
        changed_expected = expected_kl_value(v, w, changed_h)
        assert math.isclose(changed_kl, changed_expected, rel_tol=1e-3, abs_tol=1e-5), \
            "evaluate.py did not recompute KL from the current V, W, and H files"
    finally:
        with open(w_path, 'wb') as f:
            f.write(saved_w)
        with open(h_path, 'wb') as f:
            f.write(saved_h)

    # Restore the required final metric for the provided factorization.
    final_kl = run_evaluator()
    assert math.isclose(final_kl, expected_kl, rel_tol=1e-3, abs_tol=1e-5)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
