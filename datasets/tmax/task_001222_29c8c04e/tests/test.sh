#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import subprocess
import tempfile

import nbformat
import pytest

NB_FILE = '/home/user/simulation.ipynb'
TRACE_FILE = '/home/user/trace.txt'


def get_golden_trace():
    script = """
import numpy as np
np.random.seed(42)
t = np.linspace(0, 1, 100)
signals = np.sin(2 * np.pi * 10 * t) + 0.1 * np.random.randn(50, 100)
F = np.fft.fft(signals, axis=1)
F[:, 20:-20] = 0
filtered = np.real(np.fft.ifft(F, axis=1))
C = np.cov(filtered)
L = np.linalg.cholesky(C + 1e-5 * np.eye(C.shape[0]))
print(np.trace(L))
"""
    try:
        output = subprocess.check_output(['python3', '-c', script], text=True)
        return float(output.strip())
    except Exception as e:
        pytest.fail(f'Failed to compute golden trace: {e}')


def assert_trace_correct():
    assert os.path.isfile(TRACE_FILE), f'The file {TRACE_FILE} was not generated.'
    with open(TRACE_FILE, 'r') as f:
        content = f.read().strip()
    assert content, f'The file {TRACE_FILE} is empty.'
    try:
        trace_val = float(content)
    except ValueError:
        pytest.fail(f'The content of {TRACE_FILE} is not a valid float: {content}')
    golden_val = get_golden_trace()
    assert abs(trace_val - golden_val) < 1e-4, (
        f'The trace value in {TRACE_FILE} ({trace_val}) does not match the expected '
        f'regularized trace value (approx {golden_val}).'
    )


def load_and_assert_executed(path):
    assert os.path.isfile(path), f'Notebook file {path} is missing.'
    with open(path, 'r') as f:
        try:
            raw = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'Notebook file {path} is not valid JSON.')
    code_cells = [c for c in raw.get('cells', []) if c.get('cell_type') == 'code']
    assert code_cells, 'No code cells found in the notebook.'
    for i, cell in enumerate(code_cells):
        assert cell.get('execution_count') is not None, (
            f'Code cell {i+1} was not executed (execution_count is null).'
        )
        for output in cell.get('outputs', []):
            if output.get('output_type') == 'error':
                pytest.fail(
                    f"Notebook execution resulted in an error in cell {i+1}: "
                    f"{output.get('ename', 'UnknownError')} - {output.get('evalue', '')}"
                )
    return raw


def dump(node):
    return ast.dump(node, include_attributes=False)


def is_name(node, name):
    return isinstance(node, ast.Name) and node.id == name


def is_eye(node):
    if not isinstance(node, ast.Call) or len(node.args) != 1 or node.keywords:
        return False
    func = node.func
    if not (
        isinstance(func, ast.Attribute) and func.attr == 'eye' and
        isinstance(func.value, ast.Name) and func.value.id == 'np'
    ):
        return False
    arg = node.args[0]
    return (
        isinstance(arg, ast.Subscript) and
        isinstance(arg.value, ast.Attribute) and arg.value.attr == 'shape' and
        is_name(arg.value.value, 'C') and
        isinstance(arg.slice, ast.Constant) and arg.slice.value == 0
    )


def is_regularizer(node):
    if not isinstance(node, ast.BinOp) or not isinstance(node.op, ast.Mult):
        return False
    pairs = ((node.left, node.right), (node.right, node.left))
    return any(
        isinstance(number, ast.Constant) and
        isinstance(number.value, (int, float)) and
        float(number.value) == 1e-5 and is_eye(eye)
        for number, eye in pairs
    )


def is_c_plus_regularizer(node):
    return (
        isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add) and
        ((is_name(node.left, 'C') and is_regularizer(node.right)) or
         (is_name(node.right, 'C') and is_regularizer(node.left)))
    )


def cholesky_argument(stmt):
    if not isinstance(stmt, (ast.Assign, ast.AnnAssign)):
        return None
    value = stmt.value
    if not isinstance(value, ast.Call) or len(value.args) != 1:
        return None
    func = value.func
    if not (
        isinstance(func, ast.Attribute) and func.attr == 'cholesky' and
        isinstance(func.value, ast.Attribute) and func.value.attr == 'linalg' and
        isinstance(func.value.value, ast.Name) and func.value.value.id == 'np'
    ):
        return None
    targets = stmt.targets if isinstance(stmt, ast.Assign) else [stmt.target]
    if not any(is_name(t, 'L') for t in targets):
        return None
    return value.args[0]


def assert_required_code(nb):
    source = '\n'.join(
        cell.get('source', '') for cell in nb.get('cells', [])
        if cell.get('cell_type') == 'code'
    )
    try:
        tree = ast.parse(source)
    except SyntaxError as e:
        pytest.fail(f'Notebook code is not valid Python: {e}')

    original = """
np.random.seed(42)
t = np.linspace(0, 1, 100)
signals = np.sin(2 * np.pi * 10 * t) + 0.1 * np.random.randn(50, 100)
F = np.fft.fft(signals, axis=1)
F[:, 20:-20] = 0
filtered = np.real(np.fft.ifft(F, axis=1))
C = np.cov(filtered)
"""
    required = [dump(s) for s in ast.parse(original).body]
    body_dumps = [dump(s) for s in tree.body]
    pos = -1
    for expected in required:
        try:
            pos = body_dumps.index(expected, pos + 1)
        except ValueError:
            pytest.fail('The original random seed or signal-generation/filtering steps were altered or removed.')

    chol_index = None
    chol_arg = None
    for i, stmt in enumerate(tree.body):
        arg = cholesky_argument(stmt)
        if arg is not None:
            chol_index, chol_arg = i, arg
            break
    assert chol_index is not None, 'No assignment L = np.linalg.cholesky(...) was found.'

    regularized = is_c_plus_regularizer(chol_arg)
    if not regularized and isinstance(chol_arg, ast.Name):
        input_name = chol_arg.id
        for stmt in reversed(tree.body[:chol_index]):
            if isinstance(stmt, ast.AugAssign) and is_name(stmt.target, input_name):
                regularized = (
                    input_name == 'C' and isinstance(stmt.op, ast.Add) and
                    is_regularizer(stmt.value)
                )
                break
            if isinstance(stmt, ast.Assign) and any(is_name(t, input_name) for t in stmt.targets):
                regularized = is_c_plus_regularizer(stmt.value)
                break
    assert regularized, (
        'The Cholesky decomposition is not fed C + 1e-5 * np.eye(C.shape[0]).'
    )

    save_code = """with open('/home/user/trace.txt', 'w') as f:
    f.write(str(np.trace(L)))
"""
    save_dump = dump(ast.parse(save_code).body[0])
    assert save_dump in body_dumps[chol_index + 1:], (
        'The required final write of np.trace(L) to /home/user/trace.txt is missing or altered.'
    )


def execute_artifact_with_required_environment(original_nb):
    marker = '__VERIFIER_OMP_THREADS_2__'
    nb = nbformat.from_dict(original_nb)
    check_cell = nbformat.v4.new_code_cell(
        "import os\n"
        "assert os.environ.get('OMP_NUM_THREADS') == '2'\n"
        f"print('{marker}')"
    )
    nb.cells.insert(0, check_cell)

    with tempfile.TemporaryDirectory() as td:
        candidate = os.path.join(td, 'simulation.ipynb')
        nbformat.write(nb, candidate)
        env = os.environ.copy()
        env['OMP_NUM_THREADS'] = '2'
        proc = subprocess.run(
            [
                'jupyter', 'nbconvert', '--to', 'notebook', '--execute', '--inplace',
                '--ExecutePreprocessor.timeout=120',
                '--ExecutePreprocessor.kernel_name=python3', candidate
            ],
            cwd=td, env=env, text=True, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, timeout=180
        )
        assert proc.returncode == 0, f'Notebook failed when executed with OMP_NUM_THREADS=2:\n{proc.stdout}'
        executed = load_and_assert_executed(candidate)
        outputs = executed['cells'][0].get('outputs', [])
        rendered = ''.join(
            ''.join(o.get('text', [])) if isinstance(o.get('text', ''), list)
            else o.get('text', '')
            for o in outputs
        )
        assert marker in rendered, 'The notebook kernel did not receive OMP_NUM_THREADS=2.'


def test_final_state_and_reexecution():
    # Preserve the original final-state assertions before verifier re-execution.
    assert_trace_correct()
    original_nb = load_and_assert_executed(NB_FILE)

    # Verify the requested code change, then execute that actual notebook under
    # the required environment rather than trusting cached outputs/counts.
    assert_required_code(original_nb)
    execute_artifact_with_required_environment(original_nb)
    assert_trace_correct()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
