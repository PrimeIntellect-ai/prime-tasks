#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import subprocess
import sys
import tempfile

COMPUTE_PATH = '/home/user/compute.py'
RESULTS_PATH = '/home/user/results.h5'


def _assigned_names(target):
    if isinstance(target, ast.Name):
        return [target.id]
    if isinstance(target, (ast.Tuple, ast.List)):
        out = []
        for item in target.elts:
            out.extend(_assigned_names(item))
        return out
    return []


def _is_mpi_accessor(node, method, attribute):
    return (
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr == method
    ) or (isinstance(node, ast.Attribute) and node.attr == attribute)


def test_compute_script_and_mpi_structure():
    assert os.path.isfile(COMPUTE_PATH), f'{COMPUTE_PATH} does not exist or is not a file.'
    with open(COMPUTE_PATH, 'r', encoding='utf-8') as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=COMPUTE_PATH)
    except SyntaxError as e:
        raise AssertionError(f'compute.py is not valid Python: {e}')

    imports_mpi4py = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Import) and any(a.name == 'mpi4py' or a.name.startswith('mpi4py.') for a in node.names):
            imports_mpi4py = True
        if isinstance(node, ast.ImportFrom) and node.module == 'mpi4py':
            imports_mpi4py = True
    assert imports_mpi4py, 'compute.py must use mpi4py.'

    rank_names = set()
    size_names = set()
    assignments = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            for target in node.targets:
                assignments.append((_assigned_names(target), node.value))
        elif isinstance(node, ast.AnnAssign):
            assignments.append((_assigned_names(node.target), node.value))

    for names, value in assignments:
        if value is not None and _is_mpi_accessor(value, 'Get_rank', 'rank'):
            rank_names.update(names)
        if value is not None and _is_mpi_accessor(value, 'Get_size', 'size'):
            size_names.update(names)

    assert rank_names, 'compute.py must obtain the MPI rank.'
    assert size_names, 'compute.py must obtain the MPI communicator size.'

    def tags(node):
        found = set()
        if node is None:
            return found
        for child in ast.walk(node):
            if isinstance(child, ast.Name):
                if child.id in rank_names:
                    found.add('rank')
                if child.id in size_names:
                    found.add('size')
        return found

    # Propagate rank/size dependence through ordinary intermediate variables,
    # e.g. rows_per_rank = n // size; start = rank * rows_per_rank.
    changed = True
    while changed:
        changed = False
        for names, value in assignments:
            value_tags = tags(value)
            for name in names:
                if 'rank' in value_tags and name not in rank_names:
                    rank_names.add(name)
                    changed = True
                if 'size' in value_tags and name not in size_names:
                    size_names.add(name)
                    changed = True

    communication_methods = {
        'gather', 'Gather', 'gatherv', 'Gatherv',
        'allgather', 'Allgather', 'allgatherv', 'Allgatherv',
        'scatter', 'Scatter', 'scatterv', 'Scatterv',
        'send', 'Send', 'recv', 'Recv', 'reduce', 'Reduce',
        'allreduce', 'Allreduce'
    }
    called_methods = {
        node.func.attr for node in ast.walk(tree)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
    }
    assert called_methods & communication_methods, (
        'compute.py must communicate distributed work/results between MPI ranks.'
    )

    partitioned = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Subscript) and {'rank', 'size'} <= tags(node):
            partitioned = True
        if isinstance(node, ast.Call):
            name = node.func.attr if isinstance(node.func, ast.Attribute) else (
                node.func.id if isinstance(node.func, ast.Name) else ''
            )
            if name in {'range', 'arange'} and {'rank', 'size'} <= tags(node):
                partitioned = True

    # Also accept an even split handed out by an MPI scatter operation.
    has_scatter = bool(called_methods & {'scatter', 'Scatter', 'scatterv', 'Scatterv'})
    has_size_based_split = any(
        isinstance(node, ast.Call)
        and (node.func.attr if isinstance(node.func, ast.Attribute) else (
            node.func.id if isinstance(node.func, ast.Name) else ''
        )) in {'split', 'array_split'}
        and 'size' in tags(node)
        for node in ast.walk(tree)
    )
    partitioned = partitioned or (has_scatter and has_size_based_split)
    assert partitioned, 'compute.py must partition rows using both MPI rank and communicator size.'


def test_execute_with_exactly_four_mpi_processes():
    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)

    env = os.environ.copy()
    env['OMPI_ALLOW_RUN_AS_ROOT'] = '1'
    env['OMPI_ALLOW_RUN_AS_ROOT_CONFIRM'] = '1'
    env['OMPI_MCA_rmaps_base_oversubscribe'] = '1'
    result = subprocess.run(
        ['mpiexec', '-n', '4', sys.executable, COMPUTE_PATH],
        capture_output=True,
        text=True,
        env=env,
        timeout=180,
    )
    assert result.returncode == 0, (
        'compute.py failed when executed with exactly four MPI processes.\n'
        f'STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}'
    )
    assert os.path.exists(RESULTS_PATH), 'Four-process execution did not create results.h5.'


def test_results_file_exists():
    assert os.path.exists('/home/user/results.h5'), "Output file /home/user/results.h5 does not exist."


def test_results_correctness():
    """
    Verifies the correctness of the generated HDF5 file using numpy, h5py, and scipy.
    Runs in a subprocess to strictly adhere to the standard-library-only rule for the pytest file itself.
    """
    script = """
import sys
try:
    import numpy as np
    import h5py
    from scipy.special import logsumexp
except ImportError as e:
    print(f"ImportError: {e}")
    sys.exit(1)

try:
    with h5py.File('/home/user/seq_data.h5', 'r') as f:
        X = f['embeddings'][:]
except Exception as e:
    print(f"Failed to read input file: {e}")
    sys.exit(1)

try:
    with h5py.File('/home/user/results.h5', 'r') as f:
        if 'log_scores' not in f:
            print("Dataset 'log_scores' not found in results.h5")
            sys.exit(5)
        S_agent = f['log_scores'][:]
except Exception as e:
    print(f"Failed to read output file: {e}")
    sys.exit(1)

D = np.dot(X, X.T)
S_true = D - logsumexp(D, axis=1, keepdims=True)

if np.isnan(S_agent).any():
    print("Output contains NaNs. Numerical stability requirement failed.")
    sys.exit(2)

if S_agent.shape != S_true.shape:
    print(f"Expected shape {S_true.shape}, got {S_agent.shape}")
    sys.exit(3)

max_diff = np.max(np.abs(S_agent - S_true))
if max_diff > 1e-10:
    print(f"Values differ from ground truth by {max_diff}")
    sys.exit(4)

print("PASS")
sys.exit(0)
"""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as tmp:
        tmp.write(script)
        tmp_path = tmp.name

    try:
        result = subprocess.run([sys.executable, tmp_path], capture_output=True, text=True)
        assert result.returncode == 0, f"Verification failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    finally:
        os.remove(tmp_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
