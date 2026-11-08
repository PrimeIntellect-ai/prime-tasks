#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import re
import subprocess
from pathlib import Path

import nbformat

SCRIPT = Path('/home/user/run_regression.sh')
PROJECT = Path('/home/user/sim_project')
GRAPH = PROJECT / 'lattice.edgelist'
REF = PROJECT / 'ref_dist.csv'
OUTPUT = PROJECT / 'test_dist.csv'
EXECUTED = PROJECT / 'diffusion_executed.ipynb'
LOG = Path('/home/user/regression_result.log')


def run_script():
    for path in (OUTPUT, EXECUTED, LOG):
        try:
            path.unlink()
        except FileNotFoundError:
            pass
    return subprocess.run(
        [str(SCRIPT)], cwd='/home/user', text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=180
    )


def read_distribution(path):
    with open(path, newline='') as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header == ['node', 'prob'], "CSV header is incorrect; expected 'node,prob'."
        rows = list(reader)
    result = {}
    for row in rows:
        assert len(row) == 2
        node = int(row[0])
        assert node not in result
        result[node] = float(row[1])
    return rows, result


def assert_fresh_notebook():
    assert EXECUTED.is_file(), f"Executed notebook {EXECUTED} is missing."
    nb = nbformat.read(EXECUTED, as_version=4)
    assert nb.metadata.get('papermill', {}).get('status') == 'completed', \
        'Executed notebook does not contain completed Papermill metadata.'
    sources = [cell.source for cell in nb.cells if cell.cell_type == 'code']
    assert any('/home/user/sim_project/lattice.edgelist' in source and
               '/home/user/sim_project/test_dist.csv' in source
               for source in sources), 'Papermill parameters were not injected into the executed notebook.'
    simulation_cells = [cell for cell in nb.cells
                        if cell.cell_type == 'code' and 'nx.read_edgelist' in cell.source]
    assert simulation_cells and all(cell.execution_count is not None for cell in simulation_cells), \
        'The simulation cell was not executed.'


def test_complete_regression_workflow():
    # Preserve the original existence/executable assertion and reject scripts that
    # delegate the required shell-side distance calculation to Python.
    assert SCRIPT.is_file(), f"Script {SCRIPT} is missing."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."
    source = SCRIPT.read_text()
    active_source = '\n'.join(line.split('#', 1)[0] for line in source.splitlines()
                              if not line.lstrip().startswith('#'))
    assert re.search(r'\bpapermill\b', active_source), 'The script does not invoke papermill.'
    assert re.search(r'\bawk\b', active_source), 'The TVD calculation is not implemented with shell/POSIX utilities.'
    assert not re.search(r'\bpython(?:[0-9.]*)?\b', active_source, re.IGNORECASE), \
        'Python may not be used to calculate TVD.'

    original_graph = GRAPH.read_bytes()
    original_ref = REF.read_bytes()

    # Exercise the script on an unpredictable graph and reference distribution.
    rng = random.SystemRandom()
    edges = {(min(i, (i + 1) % 8), max(i, (i + 1) % 8)) for i in range(8)}
    candidates = [(i, j) for i in range(8) for j in range(i + 1, 8)
                  if (i, j) not in edges]
    edges.update(rng.sample(candidates, rng.randint(5, 10)))
    degrees = {i: 0 for i in range(8)}
    for a, b in edges:
        degrees[a] += 1
        degrees[b] += 1
    total_degree = sum(degrees.values())
    expected_output = {node: degree / total_degree for node, degree in degrees.items()}

    dominant = rng.randrange(8)
    weights = {i: rng.randint(20, 60) for i in range(8)}
    weights[dominant] = rng.randint(650, 850)
    weight_total = sum(weights.values())
    ref_values = {i: weights[i] / weight_total for i in range(8)}

    GRAPH.write_text(''.join(f'{a} {b}\n' for a, b in sorted(edges)))
    REF.write_text('node,prob\n' + ''.join(
        f'{i},{ref_values[i]:.12f}\n' for i in range(8)))
    # Derive the expected value from the exact numbers written to the test input.
    written_ref = {i: float(f'{ref_values[i]:.12f}') for i in range(8)}
    expected_tvd = 0.5 * sum(abs(expected_output[i] - written_ref[i]) for i in range(8))
    assert expected_tvd >= 0.05

    try:
        changed = run_script()
        assert changed.returncode == 1, (
            f'Expected status 1 for TVD {expected_tvd:.4f}; stdout={changed.stdout!r}, '
            f'stderr={changed.stderr!r}')
        assert 'FAIL' in changed.stdout.splitlines(), 'The script did not print FAIL to standard output.'
        assert OUTPUT.is_file(), f"Output CSV {OUTPUT} is missing."
        rows, actual = read_distribution(OUTPUT)
        assert len(rows) == 8, f"Expected 8 rows in CSV, found {len(rows)}."
        assert set(actual) == set(expected_output)
        for node, expected in expected_output.items():
            assert abs(actual[node] - expected) < 1e-12, \
                f'Notebook output for node {node} is incorrect.'
        assert_fresh_notebook()
        assert LOG.is_file(), f"Log file {LOG} is missing."
        changed_log = LOG.read_text().strip()
        assert changed_log == f'TVD={expected_tvd:.4f}', \
            f'Expected dynamically calculated TVD={expected_tvd:.4f}, got {changed_log!r}.'
    finally:
        GRAPH.write_bytes(original_graph)
        REF.write_bytes(original_ref)

    # Run the required original case last and retain all original final-state checks.
    baseline = run_script()
    assert baseline.returncode == 0, \
        f'Baseline run failed; stdout={baseline.stdout!r}, stderr={baseline.stderr!r}'
    assert 'PASS' in baseline.stdout.splitlines(), 'The script did not print PASS to standard output.'
    assert_fresh_notebook()

    assert OUTPUT.is_file(), f"Output CSV {OUTPUT} is missing."
    rows, actual = read_distribution(OUTPUT)
    assert len(rows) == 8, f"Expected 8 rows in CSV, found {len(rows)}."
    expected_baseline = {
        0: 0.3125, 1: 0.125, 2: 0.125, 3: 0.125,
        4: 0.125, 5: 0.0625, 6: 0.0625, 7: 0.0625,
    }
    assert set(actual) == set(expected_baseline)
    for node, expected in expected_baseline.items():
        assert abs(actual[node] - expected) < 1e-12

    assert LOG.is_file(), f"Log file {LOG} is missing."
    content = LOG.read_text().strip()
    assert content == 'TVD=0.0124', \
        f"Log file content is incorrect. Expected 'TVD=0.0124', got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
