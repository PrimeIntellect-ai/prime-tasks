#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import re
import shutil
import subprocess
import tempfile

import numpy as np

WORKSPACE_DIR = '/home/user/workspace'
PYTHON_SCRIPT = os.path.join(WORKSPACE_DIR, 'fft_mpi.py')
BASH_SCRIPT = os.path.join(WORKSPACE_DIR, 'run_profiling.sh')
RESULTS_FILE = os.path.join(WORKSPACE_DIR, 'scaling_results.txt')
SIGNAL_FILE = '/home/user/data/signal.npy'


def test_scripts_exist():
    """Test that the required scripts have been created."""
    assert os.path.isfile(PYTHON_SCRIPT), f"Python script {PYTHON_SCRIPT} is missing."
    assert os.path.isfile(BASH_SCRIPT), f"Bash script {BASH_SCRIPT} is missing."


def test_bash_script_executable():
    """Test that the bash script is executable."""
    assert os.access(BASH_SCRIPT, os.X_OK), f"Bash script {BASH_SCRIPT} is not executable."


def test_results_file_exists():
    """Test that the results file was generated."""
    assert os.path.isfile(RESULTS_FILE), f"Results file {RESULTS_FILE} is missing. Did you run the bash script?"


def test_results_file_content():
    """Test that the results file contains the correct output format and values."""
    with open(RESULTS_FILE, 'r') as f:
        content = f.read()

    expected_patterns = [
        r"Cores:\s*1,\s*Average Peak Index:\s*1024\.00",
        r"Cores:\s*2,\s*Average Peak Index:\s*512\.00",
        r"Cores:\s*4,\s*Average Peak Index:\s*256\.00"
    ]

    for pattern in expected_patterns:
        match = re.search(pattern, content)
        assert match is not None, (
            f"Could not find expected output matching '{pattern}' in {RESULTS_FILE}.\n"
            f"File content:\n{content}"
        )


def test_python_script_uses_required_mpi_operations():
    with open(PYTHON_SCRIPT, 'r', encoding='utf-8') as f:
        source = f.read()
    tree = ast.parse(source, filename=PYTHON_SCRIPT)

    imports_mpi4py = any(
        (isinstance(node, ast.Import) and any(alias.name == 'mpi4py' for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == 'mpi4py')
        for node in ast.walk(tree)
    )
    assert imports_mpi4py, "fft_mpi.py must import mpi4py."

    called_attributes = {
        node.func.attr
        for node in ast.walk(tree)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
    }
    assert 'Get_rank' in called_attributes, "fft_mpi.py must obtain the MPI rank."
    assert 'Get_size' in called_attributes, "fft_mpi.py must obtain the MPI world size."
    assert called_attributes.intersection({'gather', 'Gather'}), (
        "fft_mpi.py must gather local peak indices at rank 0."
    )


def _derived_answers(signal):
    answers = {}
    for processes in (1, 2, 4):
        chunk_length = signal.size // processes
        indices = []
        for rank in range(processes):
            chunk = signal[rank * chunk_length:(rank + 1) * chunk_length]
            indices.append(int(np.argmax(np.abs(np.fft.fft(chunk)))))
        answers[processes] = f"{np.mean(indices):.2f}"
    return answers


def test_run_profiling_executes_distributed_fft_on_unseen_data():
    temp_root = tempfile.mkdtemp(prefix='fft_verifier_')
    signal_backup = os.path.join(temp_root, 'signal.npy')
    results_backup = os.path.join(temp_root, 'scaling_results.txt')
    hook_dir = os.path.join(temp_root, 'hook')
    audit_dir = os.path.join(temp_root, 'calls')
    os.makedirs(hook_dir)
    os.makedirs(audit_dir)
    os.chmod(temp_root, 0o755)
    os.chmod(hook_dir, 0o755)
    os.chmod(audit_dir, 0o777)

    shutil.copy2(SIGNAL_FILE, signal_backup)
    shutil.copy2(RESULTS_FILE, results_backup)

    hook = r'''import os
import numpy as _np
_real_fft = _np.fft.fft

def _audited_fft(a, *args, **kwargs):
    rank = os.environ.get("OMPI_COMM_WORLD_RANK", "missing")
    audit_dir = os.environ.get("FFT_AUDIT_DIR")
    if audit_dir:
        path = os.path.join(audit_dir, "call_%s_%s.txt" % (rank, os.getpid()))
        with open(path, "a", encoding="utf-8") as out:
            out.write("%s,%s\n" % (rank, len(a)))
    return _real_fft(a, *args, **kwargs)

_np.fft.fft = _audited_fft
'''
    with open(os.path.join(hook_dir, 'sitecustomize.py'), 'w', encoding='utf-8') as f:
        f.write(hook)

    try:
        rng = np.random.default_rng(20260911)
        challenge = rng.standard_normal(4_194_304).astype(np.float64)
        expected = _derived_answers(challenge)
        np.save(SIGNAL_FILE, challenge)
        del challenge

        os.remove(RESULTS_FILE)
        env = os.environ.copy()
        env['PYTHONPATH'] = hook_dir + os.pathsep + env.get('PYTHONPATH', '')
        env['FFT_AUDIT_DIR'] = audit_dir
        env['OMPI_MCA_rmaps_base_oversubscribe'] = '1'

        completed = subprocess.run(
            ['runuser', '-u', 'user', '-m', '--', BASH_SCRIPT],
            cwd=WORKSPACE_DIR,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=240,
        )
        assert completed.returncode == 0, (
            f"run_profiling.sh failed with exit code {completed.returncode}.\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
        assert os.path.isfile(RESULTS_FILE), "run_profiling.sh did not generate scaling_results.txt."

        with open(RESULTS_FILE, 'r', encoding='utf-8') as f:
            lines = [line.strip() for line in f if line.strip()]
        pattern = re.compile(r'Cores: (1|2|4), Average Peak Index: (-?\d+\.\d{2})')
        parsed = []
        for line in lines:
            match = pattern.fullmatch(line)
            assert match is not None, f"Invalid profiling output line: {line!r}"
            parsed.append((int(match.group(1)), match.group(2)))
        assert [cores for cores, _ in parsed] == [1, 2, 4], (
            "run_profiling.sh must execute exactly the 1, 2, and 4 process runs in order."
        )
        for cores, value in parsed:
            assert value == expected[cores], (
                f"Incorrect result for {cores} processes on verifier data: "
                f"expected {expected[cores]}, got {value}."
            )

        observed = set()
        for name in os.listdir(audit_dir):
            with open(os.path.join(audit_dir, name), 'r', encoding='utf-8') as f:
                for line in f:
                    rank_text, length_text = line.strip().split(',')
                    observed.add((int(rank_text), int(length_text)))

        required = set()
        total_length = 4_194_304
        for processes in (1, 2, 4):
            local_length = total_length // processes
            for rank in range(processes):
                required.add((rank, local_length))
        missing = required - observed
        assert not missing, (
            "Every MPI rank must call numpy.fft.fft on its evenly split local chunk; "
            f"missing rank/chunk observations: {sorted(missing)}"
        )
    finally:
        shutil.copy2(signal_backup, SIGNAL_FILE)
        shutil.copy2(results_backup, RESULTS_FILE)
        shutil.rmtree(temp_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
