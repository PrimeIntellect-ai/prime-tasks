#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
import pytest

PIPELINE = '/home/user/pipeline'
TOPO_SH = os.path.join(PIPELINE, 'topo.sh')
DEPS_TXT = os.path.join(PIPELINE, 'deps.txt')
TOPO_PY = os.path.join(PIPELINE, 'topo.py')


def expected_topological_output(path):
    graph = {}
    nodes = set()

    with open(path, 'r') as f:
        for line in f:
            parts = line.strip().split()
            if not parts:
                continue
            node = parts[0]
            nodes.add(node)
            graph.setdefault(node, []).extend(parts[1:])
            for dep in parts[1:]:
                nodes.add(dep)

    visited = set()
    temp_mark = set()
    order = []

    def visit(node):
        if node in temp_mark:
            raise RuntimeError('Cycle detected')
        if node not in visited:
            temp_mark.add(node)
            for dep in graph.get(node, []):
                visit(dep)
            temp_mark.remove(node)
            visited.add(node)
            order.insert(0, node)

    for node in sorted(nodes):
        if node not in visited:
            visit(node)

    return ' '.join(order) + '\n'


def run_topo(path):
    try:
        return subprocess.run(
            [TOPO_SH, path],
            cwd=PIPELINE,
            capture_output=True,
            text=True,
            check=True,
            timeout=10,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f'Execution of {TOPO_SH} failed: {e.stderr}')


def test_topo_sh_exists_and_executable():
    assert os.path.isfile(TOPO_SH), f'{TOPO_SH} does not exist.'
    assert os.access(TOPO_SH, os.X_OK), f'{TOPO_SH} is not executable.'


def test_topo_sh_no_python_or_perl():
    with open(TOPO_SH, 'r') as f:
        content = f.read().lower()

    assert 'python' not in content, f"{TOPO_SH} contains 'python', which is not allowed."
    assert 'perl' not in content, f"{TOPO_SH} contains 'perl', which is not allowed."

    with open(TOPO_SH, 'rb') as submitted, open(TOPO_PY, 'rb') as reference:
        assert submitted.read() != reference.read(), 'topo.sh must be a Bash translation, not a copy of topo.py.'


def test_test_results_log_exists_and_correct():
    log_path = os.path.join(PIPELINE, 'test_results.log')
    assert os.path.isfile(log_path), f"{log_path} does not exist. Did you run 'make test'?"

    with open(log_path, 'r') as f:
        content = f.read().strip()

    expected = 'INIT_SUCCESS: 35'
    assert expected in content, f"Expected '{expected}' in {log_path}, but got '{content}'"


def test_topo_sh_output_format():
    result = run_topo(DEPS_TXT)
    output = result.stdout.strip()
    modules = output.split()
    expected_modules = {'module_main', 'module_ui', 'module_auth', 'module_crypto', 'module_core'}

    assert set(modules) == expected_modules, 'The output of topo.sh does not contain all the required modules.'
    assert len(modules) == len(expected_modules), 'The output of topo.sh contains duplicate or extra modules.'


def test_topo_sh_matches_reference_and_dependency_order():
    result = run_topo(DEPS_TXT)
    expected = expected_topological_output(DEPS_TXT)
    assert result.stdout == expected, f'Expected exact output {expected!r}, got {result.stdout!r}'

    reference = subprocess.run(
        ['python3', TOPO_PY, DEPS_TXT],
        cwd=PIPELINE,
        capture_output=True,
        text=True,
        check=True,
        timeout=10,
    )
    assert result.stdout == reference.stdout, 'topo.sh output does not exactly match topo.py.'

    positions = {name: i for i, name in enumerate(result.stdout.split())}
    with open(DEPS_TXT, 'r') as f:
        for line in f:
            parts = line.split()
            if parts:
                for dep in parts[1:]:
                    assert positions[parts[0]] < positions[dep], (
                        f'{parts[0]} must appear before its dependency {dep} in linking order.'
                    )


def test_topo_sh_handles_unseen_dependency_graph():
    token = secrets.token_hex(6)
    nodes = [f'unit_{token}_{i}' for i in range(8)]
    rng = secrets.SystemRandom()
    lines = []

    for i, node in enumerate(nodes):
        deps = []
        if i + 1 < len(nodes):
            deps.append(nodes[i + 1])
        for j in range(i + 2, len(nodes)):
            if rng.random() < 0.45:
                deps.append(nodes[j])
        rng.shuffle(deps)
        lines.append(' '.join([node] + deps))

    rng.shuffle(lines)
    graph_text = '\n' + '\n\n'.join(lines) + '\n'

    with tempfile.NamedTemporaryFile(mode='w', delete=False, prefix='deps_', suffix='.txt') as f:
        f.write(graph_text)
        graph_path = f.name

    try:
        result = run_topo(graph_path)
        expected = expected_topological_output(graph_path)
        assert result.stdout == expected, (
            'topo.sh did not reproduce the required traversal and ordering on an unseen graph. '
            f'Expected {expected!r}, got {result.stdout!r}'
        )
    finally:
        os.unlink(graph_path)


def test_make_test_runs_fresh_and_generates_correct_log():
    subprocess.run(['make', 'clean'], cwd=PIPELINE, check=True, capture_output=True, text=True, timeout=30)
    subprocess.run(['make', 'test'], cwd=PIPELINE, check=True, capture_output=True, text=True, timeout=30)

    log_path = os.path.join(PIPELINE, 'test_results.log')
    assert os.path.isfile(log_path), 'make test did not generate test_results.log.'
    with open(log_path, 'r') as f:
        assert f.read() == 'INIT_SUCCESS: 35\n', 'Fresh make test output was not correct.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
