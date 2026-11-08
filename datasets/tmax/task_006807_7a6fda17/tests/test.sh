#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "numpy:numpy"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import pstats
import re
import subprocess
from pathlib import Path

import numpy as np
import pytest
from scipy.optimize import minimize

HOME = Path('/home/user')
OUTPUTS = [
    HOME / 'opt_result.txt',
    HOME / 'mcmc_mean.txt',
    HOME / 'mcmc_profile.prof',
    HOME / 'profile_stats.txt',
]


def rosenbrock(v):
    x, y = v
    return (1.0 - x) ** 2 + 100.0 * (y - x ** 2) ** 2


def parse_pair(path):
    content = path.read_text().strip()
    assert re.fullmatch(r'[+-]?(?:\d+\.\d{4})\s+[+-]?(?:\d+\.\d{4})', content), \
        f'{path} must contain exactly two values formatted to four decimal places'
    return np.array([float(x) for x in content.split()])


def reference_chain(always_draw):
    optimum = minimize(rosenbrock, [0.0, 0.0], method='BFGS').x
    rng = np.random.RandomState(42)
    current = optimum.copy()
    current_f = rosenbrock(current)
    total = np.zeros(2)
    for _ in range(100000):
        proposal = current + rng.normal(0.0, 0.5, size=2)
        proposal_f = rosenbrock(proposal)
        ratio = np.exp(min(0.0, -(proposal_f - current_f) / 10.0))
        if always_draw:
            accept = rng.random_sample() < ratio
        elif ratio >= 1.0:
            accept = True
        else:
            accept = rng.random_sample() < ratio
        if accept:
            current = proposal
            current_f = proposal_f
        total += current
    return total / 100000.0


@pytest.fixture(scope='session', autouse=True)
def run_pipeline():
    sampler = HOME / 'sampler.py'
    makefile = HOME / 'Makefile'
    assert sampler.is_file(), 'sampler.py is missing or is not a regular file'
    assert makefile.is_file(), 'Makefile is missing or is not a regular file'

    for path in OUTPUTS:
        if path.exists() or path.is_symlink():
            path.unlink()

    first = subprocess.run(
        ['make', '-B', 'all'], cwd=HOME, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=240
    )
    assert first.returncode == 0, f'make all failed:\n{first.stdout}'
    for path in OUTPUTS:
        assert path.is_file(), f'Pipeline did not create {path}'
    first_opt = (HOME / 'opt_result.txt').read_bytes()
    first_mean = (HOME / 'mcmc_mean.txt').read_bytes()

    # Execute the requested artifact again rather than trusting pre-created files.
    second = subprocess.run(
        ['python3', str(sampler)], cwd=HOME, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180
    )
    assert second.returncode == 0, f'sampler.py failed:\n{second.stdout}'
    assert (HOME / 'opt_result.txt').read_bytes() == first_opt
    assert (HOME / 'mcmc_mean.txt').read_bytes() == first_mean, \
        'Repeated execution was not reproducible'


def test_sampler_structure_and_required_operations():
    source = (HOME / 'sampler.py').read_text()
    tree = ast.parse(source)
    calls = [n for n in ast.walk(tree) if isinstance(n, ast.Call)]

    def call_name(call):
        parts = []
        node = call.func
        while isinstance(node, ast.Attribute):
            parts.append(node.attr)
            node = node.value
        if isinstance(node, ast.Name):
            parts.append(node.id)
        return '.'.join(reversed(parts))

    names = [call_name(c) for c in calls]
    constants = [n.value for n in ast.walk(tree) if isinstance(n, ast.Constant)]

    seed_calls = [c for c in calls if call_name(c).endswith('random.seed')]
    assert seed_calls and any(c.args and isinstance(c.args[0], ast.Constant) and c.args[0].value == 42
                              for c in seed_calls), 'numpy.random.seed(42) is required'

    minimize_calls = [c for c in calls if call_name(c).endswith('minimize')]
    assert minimize_calls, 'scipy.optimize.minimize was not called'
    assert any(any(k.arg == 'method' and isinstance(k.value, ast.Constant) and
                       str(k.value.value).upper() == 'BFGS' for k in c.keywords)
               for c in minimize_calls), 'minimize must use method="BFGS"'

    assert 100000 in constants, 'The sampler must specify exactly 100,000 iterations'
    assert 0.5 in constants, 'The Gaussian proposal standard deviation must be 0.5'
    assert 10.0 in constants or 10 in constants, 'The acceptance ratio must use temperature 10.0'
    assert any(n.endswith(('.normal', '.randn', '.multivariate_normal')) for n in names), \
        'No numpy.random Gaussian proposal call was found'
    assert any(n.startswith('cProfile.') or n.endswith('.Profile') for n in names), \
        'cProfile is not used'
    assert any(n.startswith('pstats.') or n.endswith('pstats.Stats') for n in names), \
        'pstats is not used'
    assert any(n.endswith('.sort_stats') for n in names), 'pstats.sort_stats is not used'
    assert any(n.endswith('.print_stats') for n in names), 'pstats.print_stats is not used'

    functions_with_loops = {
        node.name for node in ast.walk(tree)
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and
        any(isinstance(child, (ast.For, ast.While)) for child in ast.walk(node))
    }
    assert functions_with_loops, 'MCMC must be implemented as a sampling function with a loop'


def test_makefile():
    text = (HOME / 'Makefile').read_text()
    assert re.search(r'^all\s*:', text, re.MULTILINE), 'Makefile has no all target'
    assert 'numpy' in text.lower() and 'scipy' in text.lower(), \
        'The all target must ensure numpy and scipy are available'
    assert re.search(r'python3\s+(?:/home/user/)?sampler\.py', text), \
        'The Makefile must execute sampler.py with python3'


def test_opt_result_file():
    actual = parse_pair(HOME / 'opt_result.txt')
    expected = minimize(rosenbrock, [0.0, 0.0], method='BFGS').x
    assert np.allclose(actual, expected, atol=1e-2), \
        f'Optimization result {actual} does not match BFGS result {expected}'
    assert abs(actual[0] - 1.0) < 1e-2
    assert abs(actual[1] - 1.0) < 1e-2


def test_mcmc_mean_file():
    actual = parse_pair(HOME / 'mcmc_mean.txt')
    references = [reference_chain(True), reference_chain(False)]
    errors = [np.abs(actual - ref) for ref in references]
    assert any(err[0] < 0.25 and err[1] < 0.75 for err in errors), \
        f'MCMC mean {actual} is inconsistent with the seeded 100,000-step MH chain; references={references}'


def test_mcmc_profile_file():
    path = HOME / 'mcmc_profile.prof'
    try:
        stats = pstats.Stats(str(path))
    except Exception as exc:
        pytest.fail(f'Could not load profile data from {path}: {exc}')
    assert stats.total_calls > 0, 'Profile data seems empty'

    entries = []
    for (filename, line, name), values in stats.stats.items():
        primitive_calls, total_calls, total_time, cumulative_time, callers = values
        entries.append((filename, name, primitive_calls, total_calls, total_time, cumulative_time))

    sampler_entries = [e for e in entries if os.path.realpath(e[0]) == '/home/user/sampler.py']
    assert sampler_entries, 'Profile does not contain code from sampler.py'
    assert any(e[3] == 1 and e[4] > 0 for e in sampler_entries), \
        'No single profiled execution of the sampling function was found'

    rendered = ' '.join(f'{e[0]} {e[1]}' for e in entries).lower()
    assert 'minimize_bfgs' not in rendered and '_minimize' not in rendered, \
        'Optimization was included in the MCMC-only profile'

    gaussian_calls = sum(
        e[3] for e in entries
        if any(token in e[1].lower() for token in ('normal', 'randn', 'multivariate_normal'))
    )
    assert 100000 <= gaussian_calls <= 100005, \
        f'Profile records {gaussian_calls} Gaussian proposal calls, expected 100,000'


def test_profile_stats_file():
    content = (HOME / 'profile_stats.txt').read_text()
    assert 'function calls' in content
    assert 'tottime' in content
    assert 'sampler.py' in content, 'Stats output does not report the sampler'
    data_lines = [line for line in content.splitlines()
                  if re.match(r'^\s*\d+(?:/\d+)?\s+', line)]
    assert 1 <= len(data_lines) <= 10, 'profile_stats.txt must contain the top 10 profile entries'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
