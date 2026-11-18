#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import math
import os
import subprocess

import numpy as np
import pytest
from scipy.integrate import solve_ivp
from scipy.stats import gaussian_kde

ANALYSIS_DIR = '/home/user/analysis'
SCRIPT_PATH = os.path.join(ANALYSIS_DIR, 'sim_pop.py')
OUTPUT_PATH = os.path.join(ANALYSIS_DIR, 'final_metrics.json')
INPUT_PATH = os.path.join(ANALYSIS_DIR, 'input_profiles.npy')


def _call_name(node):
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        prefix = _call_name(node.value)
        return f'{prefix}.{node.attr}' if prefix else node.attr
    return ''


def _literal_bindings(tree):
    bindings = {}
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            value = node.value
            try:
                literal = ast.literal_eval(value)
            except Exception:
                continue
            for target in targets:
                if isinstance(target, ast.Name):
                    bindings[target.id] = literal
    return bindings


def _value(node, bindings):
    if isinstance(node, ast.Name) and node.id in bindings:
        return bindings[node.id]
    try:
        return ast.literal_eval(node)
    except Exception:
        return None


def test_script_uses_required_algorithm_and_preserves_derivative():
    assert os.path.isfile(SCRIPT_PATH), f'Script {SCRIPT_PATH} is missing.'
    with open(SCRIPT_PATH, 'r', encoding='utf-8') as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT_PATH)
    bindings = _literal_bindings(tree)

    functions = {
        node.name: node for node in tree.body if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
    }
    assert 'gene_dynamics' in functions, 'gene_dynamics is missing.'

    canonical = ast.parse('''\
def gene_dynamics(t, y):
    target = np.linspace(0, 1, len(y))
    return -50.0 * (y - target) + np.sin(t) * y
''').body[0]
    submitted = functions['gene_dynamics']
    assert ast.dump(submitted.args, include_attributes=False) == ast.dump(canonical.args, include_attributes=False), \
        'gene_dynamics arguments were changed.'
    assert ast.dump(ast.Module(body=submitted.body, type_ignores=[]), include_attributes=False) == \
           ast.dump(ast.Module(body=canonical.body, type_ignores=[]), include_attributes=False), \
        'The exact mathematical definition of gene_dynamics must remain intact.'

    calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)]
    ivp_calls = [c for c in calls if _call_name(c.func).split('.')[-1] == 'solve_ivp']
    assert ivp_calls, 'sim_pop.py must call scipy.integrate.solve_ivp.'

    valid_ivp = False
    for call in ivp_calls:
        keywords = {kw.arg: _value(kw.value, bindings) for kw in call.keywords if kw.arg}
        method = keywords.get('method')
        span = _value(call.args[1], bindings) if len(call.args) >= 2 else keywords.get('t_span')
        if method == 'BDF' and isinstance(span, (tuple, list)) and len(span) == 2 \
                and float(span[0]) == 0.0 and float(span[1]) == 10.0:
            valid_ivp = True
    assert valid_ivp, "solve_ivp must integrate from 0 to 10 with method='BDF'."

    pool_calls = [c for c in calls if _call_name(c.func).split('.')[-1] == 'Pool']
    valid_pool = False
    for call in pool_calls:
        positional = _value(call.args[0], bindings) if call.args else None
        keywords = {kw.arg: _value(kw.value, bindings) for kw in call.keywords if kw.arg}
        workers = keywords.get('processes', positional)
        if workers == 4:
            valid_pool = True
    assert valid_pool, 'multiprocessing.Pool must be constructed with exactly 4 worker processes.'

    call_suffixes = [_call_name(c.func).split('.')[-1] for c in calls]
    assert 'map' in call_suffixes or 'starmap' in call_suffixes, \
        'The Pool must use an order-preserving map operation.'
    assert 'map_unordered' not in call_suffixes and 'imap_unordered' not in call_suffixes, \
        'An unordered Pool mapping would not preserve profile order.'

    kde_calls = [c for c in calls if _call_name(c.func).split('.')[-1] == 'gaussian_kde']
    assert kde_calls, 'Each final state must be processed with scipy.stats.gaussian_kde.'
    assert any(all(kw.arg != 'bw_method' or _value(kw.value, bindings) is None for kw in c.keywords)
               for c in kde_calls), 'gaussian_kde must use its default bandwidth.'
    assert any(any(isinstance(_value(arg, bindings), (int, float)) and
                       float(_value(arg, bindings)) == 0.5 for arg in c.args)
               for c in calls), 'The fitted KDE must be evaluated at x = 0.5.'


def test_script_executes_and_regenerates_output():
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    env = os.environ.copy()
    env.update({
        'OPENBLAS_NUM_THREADS': '1',
        'OMP_NUM_THREADS': '1',
        'MKL_NUM_THREADS': '1',
        'NUMEXPR_NUM_THREADS': '1',
    })
    result = subprocess.run(
        ['python3', SCRIPT_PATH], cwd=ANALYSIS_DIR, env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=600
    )
    assert result.returncode == 0, \
        f'sim_pop.py failed with exit code {result.returncode}.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}'
    assert os.path.isfile(OUTPUT_PATH), 'sim_pop.py did not create final_metrics.json.'


def test_final_metrics_json_exists():
    """Test that the final_metrics.json file was created."""
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing."


def test_final_metrics_json_structure():
    """Test that the JSON file contains the correct structure and data types."""
    if not os.path.isfile(OUTPUT_PATH):
        pytest.fail(f"Output file {OUTPUT_PATH} is missing.")

    with open(OUTPUT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail('final_metrics.json is not valid JSON.')

    assert isinstance(data, dict), 'final_metrics.json must contain a dictionary.'
    assert set(data) == {'kde_at_05'}, 'The dictionary must contain only the key kde_at_05.'
    assert 'kde_at_05' in data, "Key 'kde_at_05' not found in JSON."

    results = data['kde_at_05']
    assert isinstance(results, list), "'kde_at_05' should be a list."
    assert len(results) == 100, f"Expected exactly 100 values in 'kde_at_05', got {len(results)}."

    for i, val in enumerate(results):
        assert isinstance(val, (int, float)), f'Value at index {i} is not a number: {val}'
        assert not isinstance(val, bool), f'Value at index {i} is a boolean, not a density.'
        assert math.isfinite(val), f'Value at index {i} is not finite: {val}'


def test_metrics_are_numerically_correct():
    inputs = np.load(INPUT_PATH)
    assert inputs.shape == (100, 500), f'Unexpected input shape: {inputs.shape}'

    # The vector ODE is linear. Its exact solution at t=10 is alpha*y0 + c*target,
    # where alpha is the homogeneous multiplier and c obeys one scalar ODE.
    alpha = math.exp(-500.0 + 1.0 - math.cos(10.0))
    scalar = solve_ivp(
        lambda t, c: (-50.0 + math.sin(t)) * c + 50.0,
        (0.0, 10.0), [0.0], method='DOP853', rtol=1e-12, atol=1e-14
    )
    assert scalar.success
    c_final = float(scalar.y[0, -1])
    target = np.linspace(0.0, 1.0, 500)
    expected = np.asarray([
        float(gaussian_kde(alpha * profile + c_final * target)([0.5])[0])
        for profile in inputs
    ])

    with open(OUTPUT_PATH, 'r', encoding='utf-8') as f:
        actual = np.asarray(json.load(f)['kde_at_05'], dtype=float)

    assert np.allclose(actual, expected, rtol=2e-3, atol=2e-3), \
        f'KDE values are numerically incorrect (maximum error {np.max(np.abs(actual - expected))}).'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
