#!/bin/bash
mkdir -p /logs/verifier

# Execute the required artifact and require it to freshly generate results.csv.
rm -f /home/user/results.csv
pipeline_ok=0
if cd /home/user && timeout 300 /home/user/run_pipeline.sh > /tmp/run_pipeline.log 2>&1; then
    if [ -f /home/user/results.csv ]; then
        pipeline_ok=1
    fi
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import os
import subprocess
import pytest


def solve_3x3(M, y):
    """Solves a 3x3 linear system using Cramer's rule."""
    def det(A):
        return (A[0][0] * (A[1][1] * A[2][2] - A[1][2] * A[2][1]) -
                A[0][1] * (A[1][0] * A[2][2] - A[1][2] * A[2][0]) +
                A[0][2] * (A[1][0] * A[2][1] - A[1][1] * A[2][0]))

    d = det(M)
    if d == 0:
        raise ValueError("Determinant is zero, singular matrix.")

    M0 = [[y[i] if j == 0 else M[i][j] for j in range(3)] for i in range(3)]
    M1 = [[y[i] if j == 1 else M[i][j] for j in range(3)] for i in range(3)]
    M2 = [[y[i] if j == 2 else M[i][j] for j in range(3)] for i in range(3)]

    return [det(M0)/d, det(M1)/d, det(M2)/d]


def fasta_seq_ids():
    ids = []
    with open('/home/user/data/sequences.fasta', 'r') as f:
        for line in f:
            if line.startswith('>'):
                ids.append(line[1:].strip().split()[0])
    return ids


def compute_expected_results():
    """Computes the expected normalized OLS coefficients from the raw data."""
    basis = []
    with open('/home/user/data/basis.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            basis.append([float(row['alpha']), float(row['beta']), float(row['coil'])])

    spectra = {}
    with open('/home/user/data/spectra.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            seq_id = row['seq_id']
            if seq_id not in spectra:
                spectra[seq_id] = []
            spectra[seq_id].append(float(row['intensity']))

    M = [[0, 0, 0], [0, 0, 0], [0, 0, 0]]
    for i in range(3):
        for j in range(3):
            M[i][j] = sum(basis[k][i] * basis[k][j] for k in range(len(basis)))

    expected = {}
    for seq_id, S in spectra.items():
        y = [0, 0, 0]
        for i in range(3):
            y[i] = sum(basis[k][i] * S[k] for k in range(len(basis)))

        c = solve_3x3(M, y)
        c_sum = sum(c)
        c_norm = [round(x / c_sum, 4) for x in c]
        expected[seq_id] = c_norm

    return expected


def test_venv_exists():
    """Test that the Python virtual environment is set up."""
    venv_path = '/home/user/venv'
    assert os.path.isdir(venv_path), f"Virtual environment directory {venv_path} does not exist."
    assert os.path.isfile(os.path.join(venv_path, 'bin', 'python')), "Python executable not found in the virtual environment."


def test_required_packages_are_installed_in_venv():
    """Require all requested distributions to be installed in the created venv."""
    python = '/home/user/venv/bin/python'
    code = r'''
import importlib
import importlib.metadata
import json
import os

venv = os.path.realpath('/home/user/venv')
packages = {
    'numpy': 'numpy',
    'scipy': 'scipy',
    'biopython': 'Bio',
    'pandas': 'pandas',
}
result = {}
for distribution, module in packages.items():
    imported = importlib.import_module(module)
    dist = importlib.metadata.distribution(distribution)
    location = os.path.realpath(str(dist.locate_file('')))
    result[distribution] = {
        'module': os.path.realpath(imported.__file__),
        'distribution': location,
        'in_venv': os.path.commonpath([venv, location]) == venv,
    }
print(json.dumps(result))
'''
    completed = subprocess.run([python, '-c', code], text=True, capture_output=True)
    assert completed.returncode == 0, completed.stderr
    installed = json.loads(completed.stdout)
    assert set(installed) == {'numpy', 'scipy', 'biopython', 'pandas'}
    for name, info in installed.items():
        assert info['in_venv'], f"{name} is not installed in /home/user/venv: {info}"


def test_scripts_exist_and_executable():
    """Test that the required scripts exist and the bash script is executable."""
    bash_script = '/home/user/run_pipeline.sh'
    python_script = '/home/user/fit_spectra.py'

    assert os.path.isfile(bash_script), f"Bash script {bash_script} does not exist."
    assert os.access(bash_script, os.X_OK), f"Bash script {bash_script} is not executable."
    assert os.path.isfile(python_script), f"Python script {python_script} does not exist."


def test_fit_script_uses_pool_with_exactly_four_workers():
    """Verify that fit_spectra.py dispatches work through multiprocessing.Pool(4)."""
    path = '/home/user/fit_spectra.py'
    with open(path, 'r') as f:
        tree = ast.parse(f.read(), filename=path)

    module_aliases = set()
    pool_aliases = set()
    constants = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == 'multiprocessing':
                    module_aliases.add(alias.asname or 'multiprocessing')
        elif isinstance(node, ast.ImportFrom) and node.module == 'multiprocessing':
            for alias in node.names:
                if alias.name == 'Pool':
                    pool_aliases.add(alias.asname or 'Pool')
        elif isinstance(node, (ast.Assign, ast.AnnAssign)):
            value = node.value
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            if isinstance(value, ast.Constant) and isinstance(value.value, int):
                for target in targets:
                    if isinstance(target, ast.Name):
                        constants[target.id] = value.value

    def is_pool_call(node):
        if not isinstance(node, ast.Call):
            return False
        if isinstance(node.func, ast.Name):
            return node.func.id in pool_aliases
        return (isinstance(node.func, ast.Attribute) and node.func.attr == 'Pool' and
                isinstance(node.func.value, ast.Name) and node.func.value.id in module_aliases)

    def integer_value(node):
        if isinstance(node, ast.Constant) and isinstance(node.value, int):
            return node.value
        if isinstance(node, ast.Name):
            return constants.get(node.id)
        return None

    pool_calls = [node for node in ast.walk(tree) if is_pool_call(node)]
    assert pool_calls, "fit_spectra.py does not create a multiprocessing.Pool."

    for call in pool_calls:
        workers = integer_value(call.args[0]) if call.args else None
        for keyword in call.keywords:
            if keyword.arg in ('processes', 'workers'):
                workers = integer_value(keyword.value)
        assert workers == 4, "multiprocessing.Pool must be created with exactly 4 worker processes."

    pool_variables = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and is_pool_call(node.value):
            for target in node.targets:
                if isinstance(target, ast.Name):
                    pool_variables.add(target.id)
        elif isinstance(node, ast.With):
            for item in node.items:
                if is_pool_call(item.context_expr) and isinstance(item.optional_vars, ast.Name):
                    pool_variables.add(item.optional_vars.id)

    dispatch_methods = {'map', 'starmap', 'imap', 'imap_unordered', 'map_async',
                        'starmap_async', 'apply', 'apply_async'}
    dispatched = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
            continue
        receiver = node.func.value
        if node.func.attr in dispatch_methods and (
            (isinstance(receiver, ast.Name) and receiver.id in pool_variables) or
            is_pool_call(receiver)
        ):
            dispatched = True
            break
    assert dispatched, "The four-process Pool is not used to dispatch fitting work."


def test_results_csv_correctness():
    """Test that results.csv exists, is formatted correctly, and contains the correct OLS results."""
    results_file = '/home/user/results.csv'
    assert os.path.isfile(results_file), f"Results file {results_file} does not exist."

    expected = compute_expected_results()
    fasta_ids = fasta_seq_ids()
    assert len(fasta_ids) == len(set(fasta_ids)), "Duplicate IDs in input FASTA."
    assert set(expected) == set(fasta_ids), "Spectra IDs do not match the FASTA protein IDs."

    with open(results_file, 'r') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ['seq_id', 'alpha', 'beta', 'coil'], f"Incorrect header in results.csv: {header}"
        rows = list(reader)

    assert len(rows) == len(expected), f"Expected {len(expected)} rows, found {len(rows)}."
    assert all(len(row) == 4 for row in rows), "Each results row must contain exactly four columns."

    seq_ids = [row[0] for row in rows]
    assert seq_ids == sorted(seq_ids), "The results.csv file is not sorted alphabetically by seq_id."
    assert len(seq_ids) == len(set(seq_ids)), "Duplicate seq_id rows found in results.csv."
    assert set(seq_ids) == set(fasta_ids), "results.csv must contain every FASTA protein exactly once."

    for row in rows:
        seq_id = row[0]
        assert seq_id in expected, f"Unexpected seq_id {seq_id} in results.csv."

        try:
            alpha = float(row[1])
            beta = float(row[2])
            coil = float(row[3])
        except ValueError:
            pytest.fail(f"Non-numeric coefficient found for {seq_id}.")

        exp_alpha, exp_beta, exp_coil = expected[seq_id]
        assert abs(alpha - exp_alpha) <= 1e-4, f"Alpha coefficient for {seq_id} incorrect. Expected {exp_alpha}, got {alpha}."
        assert abs(beta - exp_beta) <= 1e-4, f"Beta coefficient for {seq_id} incorrect. Expected {exp_beta}, got {beta}."
        assert abs(coil - exp_coil) <= 1e-4, f"Coil coefficient for {seq_id} incorrect. Expected {exp_coil}, got {coil}."
TEST_EOF

if [ "$pipeline_ok" -eq 1 ] && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    if [ "$pipeline_ok" -ne 1 ]; then
        cat /tmp/run_pipeline.log 2>/dev/null || true
    fi
    echo "0" > /logs/verifier/reward.txt
fi
