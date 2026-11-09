#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import operator
import os
import random
import subprocess
import sys


def test_libmetrics_so_exists():
    """Test that the shared library was built."""
    path = "/home/user/libmetrics.so"
    assert os.path.isfile(path), f"Shared library {path} does not exist."


def test_eval_results():
    """Test that eval_results.txt contains the correct evaluated results."""
    path = "/home/user/eval_results.txt"
    assert os.path.isfile(path), f"Results file {path} does not exist."

    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()

    expected_values = ["20.0", "25.0", "16.0", "21.0"]
    for val in expected_values:
        assert val in content, f"Expected value {val} not found in {path}."


def test_metrics_out():
    """Test that metrics.out contains the correct final sum."""
    path = "/home/user/metrics.out"
    assert os.path.isfile(path), f"Metrics output file {path} does not exist."

    with open(path, 'r', encoding='utf-8') as f:
        content = f.read().strip()

    assert "82.00" in content, f"Expected sum 82.00 not found in {path}."


def test_valgrind_log():
    """Test that valgrind.log exists and contains leak check output."""
    path = "/home/user/valgrind.log"
    assert os.path.isfile(path), f"Valgrind log file {path} does not exist."

    with open(path, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read().lower()

    assert "definitely lost:" in content, f"Valgrind log {path} does not contain expected leak check output."


def _evaluate(node):
    binary = {
        ast.Add: operator.add,
        ast.Sub: operator.sub,
        ast.Mult: operator.mul,
        ast.Div: operator.truediv,
        ast.Pow: operator.pow,
    }
    unary = {ast.UAdd: operator.pos, ast.USub: operator.neg}
    if isinstance(node, ast.Expression):
        return _evaluate(node.body)
    if isinstance(node, ast.Constant) and type(node.value) in (int, float):
        return node.value
    if isinstance(node, ast.BinOp) and type(node.op) in binary:
        return binary[type(node.op)](_evaluate(node.left), _evaluate(node.right))
    if isinstance(node, ast.UnaryOp) and type(node.op) in unary:
        return unary[type(node.op)](_evaluate(node.operand))
    raise AssertionError("Unsupported expression in data.bin")


def test_results_are_exactly_derived_from_utf16_input():
    with open('/home/user/data.bin', 'rb') as f:
        expressions = [line for line in f.read().decode('utf-16le').splitlines() if line.strip()]
    expected = [str(float(_evaluate(ast.parse(expr, mode='eval')))) for expr in expressions]
    with open('/home/user/eval_results.txt', 'r', encoding='utf-8') as f:
        actual = f.read().splitlines()
    assert actual == expected, f"Expected one evaluated result per input expression: {expected!r}"
    with open('/home/user/metrics.out', 'r', encoding='utf-8') as f:
        metric = f.read().strip()
    assert metric == f"{sum(map(float, expected)):.2f}"


def test_library_is_loadable_and_works_via_ffi_under_valgrind():
    library = '/home/user/libmetrics.so'
    with open(library, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'libmetrics.so is not an ELF library'

    rng = random.SystemRandom()
    values = [rng.randint(-2000, 2000) / 4.0 for _ in range(7)]
    harness = '/tmp/verify_metrics_ffi.py'
    with open(harness, 'w', encoding='utf-8') as f:
        f.write('import ctypes\n')
        f.write(f"lib = ctypes.CDLL({library!r})\n")
        f.write("fn = lib.record_metric\n")
        f.write("fn.argtypes = [ctypes.c_double]\n")
        f.write("fn.restype = None\n")
        f.write(f"for value in {values!r}: fn(value)\n")

    log = '/tmp/verifier_valgrind.log'
    with open(log, 'wb') as err:
        proc = subprocess.run(
            ['valgrind', '--leak-check=full', '--show-leak-kinds=all',
             '--error-exitcode=97', sys.executable, harness],
            stdout=subprocess.PIPE, stderr=err, timeout=60
        )
    assert proc.returncode == 0, f'FFI harness failed under valgrind with status {proc.returncode}'

    with open('/home/user/metrics.out', 'r', encoding='utf-8') as f:
        actual_total = f.read().strip()
    assert actual_total == f"{sum(values):.2f}", 'record_metric did not accumulate arbitrary FFI inputs correctly'

    with open(log, 'r', encoding='utf-8', errors='ignore') as f:
        valgrind_output = f.read().lower()
    assert 'valgrind' in valgrind_output
    assert 'heap summary:' in valgrind_output
    assert 'leak summary:' in valgrind_output
    assert 'definitely lost:' in valgrind_output
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
