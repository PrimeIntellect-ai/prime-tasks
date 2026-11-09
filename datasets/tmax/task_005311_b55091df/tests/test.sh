#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import json
import math
import os
import shutil
import subprocess
import tempfile

import pytest

BASE = '/home/user/math_system'
SO_PATH = os.path.join(BASE, 'libeval.so')


class Node(ctypes.Structure):
    _fields_ = [
        ('op', ctypes.c_int),
        ('value', ctypes.c_double),
        ('left_idx', ctypes.c_int),
        ('right_idx', ctypes.c_int),
    ]


def test_shared_library_built():
    build = subprocess.run(
        ['make', '-B'], cwd=BASE, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    )
    assert build.returncode == 0, f"Running make failed:\n{build.stdout}"

    so_path = SO_PATH
    assert os.path.isfile(so_path), f"Shared library {so_path} was not built."

    # Check if it's an ELF shared object
    with open(so_path, 'rb') as f:
        header = f.read(16)
    assert header.startswith(b'\x7fELF'), f"{so_path} is not a valid ELF file."
    # e_type is at offset 16
    with open(so_path, 'rb') as f:
        f.seek(16)
        e_type = int.from_bytes(f.read(2), byteorder='little')
    # ET_DYN is 3 (Shared object file)
    assert e_type == 3, f"{so_path} is not compiled as a shared library (missing -shared or -fPIC)."


def test_eval_c_updated():
    eval_c_path = os.path.join(BASE, 'eval.c')
    assert os.path.isfile(eval_c_path), f"{eval_c_path} is missing."
    with open(eval_c_path, 'r') as f:
        content = f.read()
    assert 'OP_DIV' in content, "eval.c is missing OP_DIV."
    assert 'OP_POW' in content, "eval.c is missing OP_POW."
    assert 'pow(' in content or 'pow (' in content, "eval.c does not seem to use the pow() function for OP_POW."


def test_compiled_evaluator_behavior():
    lib = ctypes.CDLL(SO_PATH)
    evaluate = lib.evaluate_ast
    evaluate.argtypes = [ctypes.POINTER(Node), ctypes.c_int]
    evaluate.restype = ctypes.c_double

    # Root is ADD(POW(2.5, 3.2), DIV(91, 7)).
    nodes = (Node * 7)(
        Node(1, 0.0, 1, 2),
        Node(5, 0.0, 3, 4),
        Node(4, 0.0, 5, 6),
        Node(0, 2.5, -1, -1),
        Node(0, 3.2, -1, -1),
        Node(0, 91.0, -1, -1),
        Node(0, 7.0, -1, -1),
    )
    expected = math.pow(2.5, 3.2) + 13.0
    assert math.isclose(evaluate(nodes, 0), expected, rel_tol=1e-12, abs_tol=1e-12)

    div_zero = (Node * 3)(
        Node(4, 0.0, 1, 2),
        Node(0, -73.5, -1, -1),
        Node(0, 0.0, -1, -1),
    )
    assert evaluate(div_zero, 0) == 0.0


def test_run_py_migrates_and_invokes_library():
    run_path = os.path.join(BASE, 'run.py')
    formulas_path = os.path.join(BASE, 'formulas.json')
    results_path = os.path.join(BASE, 'results.json')
    assert os.path.isfile(run_path), f"{run_path} is missing."

    with open(run_path, 'r', encoding='utf-8') as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=run_path)
    except SyntaxError as exc:
        pytest.fail(f"{run_path} is not valid Python: {exc}")
    imports_ctypes = any(
        (isinstance(n, ast.Import) and any(a.name == 'ctypes' for a in n.names))
        or (isinstance(n, ast.ImportFrom) and n.module == 'ctypes')
        for n in ast.walk(tree)
    )
    assert imports_ctypes, "run.py must use ctypes to invoke libeval.so."

    challenge = [
        {
            'id': 'probe_pow',
            'expr': {
                'op': 'pow',
                'left': {'op': 'add', 'left': {'op': 'val', 'value': 1.75}, 'right': {'op': 'val', 'value': 2.25}},
                'right': {'op': 'val', 'value': 2.5}
            }
        },
        {
            'id': 'probe_nested',
            'expr': {
                'op': 'sub',
                'left': {'op': 'mul', 'left': {'op': 'val', 'value': -6.5}, 'right': {'op': 'val', 'value': 4.0}},
                'right': {'op': 'div', 'left': {'op': 'val', 'value': 81.0}, 'right': {'op': 'val', 'value': 9.0}}
            }
        },
        {
            'id': 'probe_zero',
            'expr': {'op': 'div', 'left': {'op': 'val', 'value': 123.0}, 'right': {'op': 'val', 'value': 0.0}}
        }
    ]
    normal_values = {
        'probe_pow': (1.75 + 2.25) ** 2.5,
        'probe_nested': (-6.5 * 4.0) - (81.0 / 9.0),
        'probe_zero': 0.0,
    }
    offset = 1000.25

    probe_source = r'''
#include <math.h>
#include <stdio.h>
typedef struct { int op; double value; int left_idx; int right_idx; } Node;
static double walk(Node *nodes, int idx, int depth) {
    if (idx < 0 || idx > 64 || depth > 64) return NAN;
    Node *n = &nodes[idx];
    if (n->op == 0) {
        if (n->left_idx != -1 || n->right_idx != -1) return NAN;
        return n->value;
    }
    if (n->op < 1 || n->op > 5 || n->left_idx < 0 || n->right_idx < 0) return NAN;
    double l = walk(nodes, n->left_idx, depth + 1);
    double r = walk(nodes, n->right_idx, depth + 1);
    switch (n->op) {
        case 1: return l + r;
        case 2: return l - r;
        case 3: return l * r;
        case 4: return r == 0.0 ? 0.0 : l / r;
        case 5: return pow(l, r);
    }
    return NAN;
}
double evaluate_ast(Node *nodes, int root_idx) {
    FILE *f = fopen("/tmp/math_probe_calls", "a");
    if (f) { fputs(root_idx == 0 ? "G\n" : "B\n", f); fclose(f); }
    if (root_idx != 0) return NAN;
    return walk(nodes, root_idx, 0) + 1000.25;
}
'''

    with tempfile.TemporaryDirectory() as td:
        backup_so = os.path.join(td, 'libeval.so')
        backup_formulas = os.path.join(td, 'formulas.json')
        backup_results = os.path.join(td, 'results.json')
        probe_c = os.path.join(td, 'probe.c')
        probe_so = os.path.join(td, 'probe.so')
        shutil.copy2(SO_PATH, backup_so)
        shutil.copy2(formulas_path, backup_formulas)
        had_results = os.path.isfile(results_path)
        if had_results:
            shutil.copy2(results_path, backup_results)

        try:
            with open(probe_c, 'w', encoding='utf-8') as f:
                f.write(probe_source)
            compile_probe = subprocess.run(
                ['gcc', '-shared', '-fPIC', '-o', probe_so, probe_c, '-lm'],
                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
            )
            assert compile_probe.returncode == 0, compile_probe.stdout
            shutil.copy2(probe_so, SO_PATH)
            with open(formulas_path, 'w', encoding='utf-8') as f:
                json.dump(challenge, f)
            if os.path.exists(results_path):
                os.unlink(results_path)
            if os.path.exists('/tmp/math_probe_calls'):
                os.unlink('/tmp/math_probe_calls')

            proc = subprocess.run(
                ['python3', run_path], cwd=BASE, text=True,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT
            )
            assert proc.returncode == 0, f"run.py failed:\n{proc.stdout}"
            assert os.path.isfile(results_path), "run.py did not create results.json."
            with open(results_path, 'r', encoding='utf-8') as f:
                actual = json.load(f)
            assert isinstance(actual, dict)
            assert set(normal_values).issubset(actual)
            for key, value in normal_values.items():
                assert isinstance(actual[key], (int, float))
                assert math.isclose(actual[key], value + offset, rel_tol=1e-9, abs_tol=1e-9), \
                    f"Result for {key} was not obtained from evaluate_ast."

            assert os.path.isfile('/tmp/math_probe_calls'), "libeval.so was not invoked."
            with open('/tmp/math_probe_calls', 'r', encoding='utf-8') as f:
                calls = [line.strip() for line in f if line.strip()]
            assert 'B' not in calls, "run.py did not pass root index 0."
            assert calls.count('G') >= len(challenge), "Not every formula was passed to evaluate_ast."
        finally:
            shutil.copy2(backup_so, SO_PATH)
            shutil.copy2(backup_formulas, formulas_path)
            if had_results:
                shutil.copy2(backup_results, results_path)
            elif os.path.exists(results_path):
                os.unlink(results_path)
            if os.path.exists('/tmp/math_probe_calls'):
                os.unlink('/tmp/math_probe_calls')

    # Generate the required final output using the real submitted library.
    proc = subprocess.run(
        ['python3', run_path], cwd=BASE, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    )
    assert proc.returncode == 0, f"run.py failed with the submitted library:\n{proc.stdout}"


def test_results_json_correct():
    formulas_path = os.path.join(BASE, 'formulas.json')
    results_path = os.path.join(BASE, 'results.json')

    assert os.path.isfile(formulas_path), f"{formulas_path} is missing."
    assert os.path.isfile(results_path), f"The output file {results_path} was not created."

    with open(formulas_path, 'r') as f:
        formulas = json.load(f)

    def eval_expr(expr):
        op = expr['op']
        if op == 'val':
            return float(expr['value'])

        left = eval_expr(expr['left'])
        right = eval_expr(expr['right'])

        if op == 'add':
            return left + right
        elif op == 'sub':
            return left - right
        elif op == 'mul':
            return left * right
        elif op == 'div':
            return 0.0 if right == 0.0 else left / right
        elif op == 'pow':
            return left ** right
        return 0.0

    expected_results = {}
    for item in formulas:
        expected_results[item['id']] = eval_expr(item['expr'])

    with open(results_path, 'r') as f:
        try:
            actual_results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{results_path} does not contain valid JSON.")

    assert isinstance(actual_results, dict), f"{results_path} should contain a JSON object (dictionary)."

    for eq_id, expected_val in expected_results.items():
        assert eq_id in actual_results, f"Equation ID '{eq_id}' is missing from {results_path}."
        actual_val = actual_results[eq_id]
        assert isinstance(actual_val, (int, float)), f"Result for '{eq_id}' should be a number."
        assert abs(actual_val - expected_val) < 1e-6, f"Incorrect result for '{eq_id}'. Expected {expected_val}, got {actual_val}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
