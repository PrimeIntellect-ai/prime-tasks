#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import glob
import importlib
import importlib.metadata
import importlib.util
import math
import os
import re
import subprocess

import nbformat
import numpy as np
import pytest

SCRIPT = '/home/user/run_pipeline.sh'
DATA_DIR = '/home/user/data'
OUT_DIR = '/home/user/notebooks_out'
METRIC_FILE = '/home/user/final_mean_kl.txt'


@pytest.fixture(scope='session', autouse=True)
def run_pipeline_from_clean_state():
    assert os.path.isfile(SCRIPT), f'The script {SCRIPT} does not exist.'
    assert os.access(SCRIPT, os.X_OK), f'The script {SCRIPT} is not executable.'

    os.makedirs(OUT_DIR, exist_ok=True)
    for path in glob.glob(os.path.join(OUT_DIR, '*_out.ipynb')):
        os.remove(path)
    for path in glob.glob('/home/user/*_metrics.txt'):
        os.remove(path)
    if os.path.exists(METRIC_FILE):
        os.remove(METRIC_FILE)

    result = subprocess.run(
        [SCRIPT],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
    )
    assert result.returncode == 0, 'run_pipeline.sh failed:\n' + result.stdout


def test_run_pipeline_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f'The script {SCRIPT} does not exist.'
    assert os.access(SCRIPT, os.X_OK), f'The script {SCRIPT} is not executable.'


def test_setup_uses_numpy_include_directory():
    setup_path = '/app/graph_factor_lib/setup.py'
    with open(setup_path, 'r') as f:
        tree = ast.parse(f.read(), filename=setup_path)

    extension_calls = [
        node for node in ast.walk(tree)
        if isinstance(node, ast.Call)
        and ((isinstance(node.func, ast.Name) and node.func.id == 'Extension')
             or (isinstance(node.func, ast.Attribute) and node.func.attr == 'Extension'))
    ]
    assert extension_calls, 'setup.py does not define the C extension.'

    def contains_get_include(node):
        return any(
            isinstance(child, ast.Call)
            and isinstance(child.func, ast.Attribute)
            and child.func.attr == 'get_include'
            for child in ast.walk(node)
        )

    assert any(
        kw.arg == 'include_dirs' and contains_get_include(kw.value)
        for call in extension_calls for kw in call.keywords
    ), 'The C extension include_dirs does not use NumPy get_include().'


def test_graph_factor_lib_installed_and_c_extension_built():
    spec = importlib.util.find_spec('graph_factor_lib')
    assert spec is not None, "The package 'graph_factor_lib' is not installed in the active Python environment."
    assert importlib.metadata.version('graph_factor_lib')

    extension = importlib.import_module('graph_factor_lib._factorize')
    origin = os.path.realpath(extension.__file__)
    assert origin.endswith(('.so', '.pyd')), f'C extension was not loaded from a compiled module: {origin}'
    assert '/app/graph_factor_lib/' in origin, f'Loaded the wrong graph_factor_lib extension: {origin}'
    assert extension.dummy() is None


def test_solver_regularizes_before_inversion():
    solver = importlib.import_module('graph_factor_lib.solver')
    assert os.path.realpath(solver.__file__) == os.path.realpath('/app/graph_factor_lib/graph_factor_lib/solver.py')

    L = np.array([[1.0, -1.0], [-1.0, 1.0]])
    expected = np.linalg.inv(L + 1e-5 * np.eye(L.shape[0]))
    actual = solver.solve_laplacian(L.copy())
    assert np.all(np.isfinite(actual))
    assert np.allclose(actual, expected, rtol=1e-7, atol=1e-7), \
        'solve_laplacian does not invert L + 1e-5 * np.eye(n).'

    adjacency = np.array([[0.0, 1.0], [1.0, 0.0]])
    result = solver.factorize(adjacency)
    assert np.all(np.isfinite(result)), 'factorize still fails or returns non-finite values for a singular graph Laplacian.'


def test_notebooks_out_generated_by_successful_execution():
    assert os.path.isdir(OUT_DIR), f'The directory {OUT_DIR} does not exist.'
    edges_files = sorted(glob.glob(os.path.join(DATA_DIR, '*.edges')))
    assert edges_files, 'No input .edges files were found.'

    for edge_file in edges_files:
        basename = os.path.splitext(os.path.basename(edge_file))[0]
        expected_notebook = os.path.join(OUT_DIR, f'{basename}_out.ipynb')
        assert os.path.isfile(expected_notebook), f'Expected output notebook {expected_notebook} was not generated.'

        notebook = nbformat.read(expected_notebook, as_version=4)
        assert 'papermill' in notebook.metadata, f'{expected_notebook} is not a papermill output notebook.'
        assert notebook.metadata.papermill.get('parameters', {}).get('input_graph') == edge_file

        code_cells = [cell for cell in notebook.cells if cell.cell_type == 'code']
        assert any(edge_file in ''.join(cell.source) for cell in code_cells), \
            f'{expected_notebook} was not parameterized with {edge_file}.'
        assert any(cell.execution_count is not None for cell in code_cells), \
            f'{expected_notebook} contains no executed code cells.'
        errors = [
            output for cell in code_cells for output in cell.get('outputs', [])
            if output.get('output_type') == 'error'
        ]
        assert not errors, f'{expected_notebook} contains notebook execution errors: {errors}'

        metric_path = f'/home/user/{basename}_metrics.txt'
        assert os.path.isfile(metric_path), f'Notebook did not generate {metric_path}.'
        with open(metric_path, 'r') as f:
            metric_text = f.read().strip()
        metric = float(metric_text)
        assert math.isfinite(metric)
        assert math.isclose(metric, 0.04, rel_tol=0.0, abs_tol=1e-12), \
            f'Unexpected metric from the executed evaluation notebook for {basename}: {metric}'


def test_final_mean_kl_metric_is_recomputed_aggregate():
    assert os.path.isfile(METRIC_FILE), f'The file {METRIC_FILE} does not exist.'
    with open(METRIC_FILE, 'r') as f:
        content = f.read().strip()

    number_pattern = r'[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?'
    assert re.fullmatch(number_pattern, content), \
        f'{METRIC_FILE} must contain only one numeric value. Content: {content!r}'
    val = float(content)
    assert math.isfinite(val)

    generated_metrics = sorted(glob.glob('/home/user/*_metrics.txt'))
    assert generated_metrics, 'No generated metric files were found.'
    values = []
    for path in generated_metrics:
        with open(path, 'r') as f:
            values.append(float(f.read().strip()))
    expected_mean = sum(values) / len(values)
    assert math.isclose(val, expected_mean, rel_tol=1e-9, abs_tol=1e-12), \
        f'The reported mean {val} does not equal the mean of generated metrics {expected_mean}.'

    threshold = 0.05
    assert val <= threshold, f'The mean KL divergence ({val}) is greater than the threshold ({threshold}).'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
