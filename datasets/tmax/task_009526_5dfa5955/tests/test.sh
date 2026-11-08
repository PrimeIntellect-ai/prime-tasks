#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import secrets
import shutil
import subprocess

import numpy as np
import pytest


def test_virtual_environment_exists():
    """Test that the virtual environment is created at the correct location."""
    venv_dir = '/home/user/scienv'
    assert os.path.exists(venv_dir), f"Virtual environment directory {venv_dir} does not exist."
    assert os.path.isdir(venv_dir), f"{venv_dir} is not a directory."
    python_bin = os.path.join(venv_dir, 'bin', 'python')
    assert os.path.exists(python_bin), f"Python binary not found at {python_bin}."


def test_packages_installed_in_venv():
    """Test that mpi4py, numpy, and scipy are installed in the virtual environment."""
    venv_python = '/home/user/scienv/bin/python'
    if not os.path.exists(venv_python):
        pytest.skip("Virtual environment Python binary missing.")

    cmd = [venv_python, '-c', 'import mpi4py, numpy, scipy']
    result = subprocess.run(cmd, capture_output=True, text=True)
    assert result.returncode == 0, f"Failed to import required packages in venv. Error: {result.stderr}"


def test_mpi_script_exists():
    """Test that the MPI profiler script exists."""
    script_file = '/home/user/mpi_profiler.py'
    assert os.path.exists(script_file), f"MPI script {script_file} does not exist."
    assert os.path.isfile(script_file), f"{script_file} is not a file."


def test_profiling_report_exists():
    """Test that the profiling report JSON file exists."""
    report_file = '/home/user/profiling_report.json'
    assert os.path.exists(report_file), f"Profiling report {report_file} does not exist."
    assert os.path.isfile(report_file), f"{report_file} is not a file."


def test_profiling_report_contents():
    """Test that the initially generated report contains the correct data."""
    report_file = '/home/user/profiling_report.json'
    if not os.path.exists(report_file):
        pytest.skip(f"{report_file} missing, skipping content test.")

    try:
        with open(report_file, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f"Failed to parse JSON from {report_file}: {e}")

    assert 'processes' in data, "Key 'processes' missing in JSON report."
    assert data['processes'] == 4, f"Expected 'processes' to be 4, got {data['processes']}."

    assert 'wasserstein_distance' in data, "Key 'wasserstein_distance' missing in JSON report."
    dist = data['wasserstein_distance']
    assert isinstance(dist, (int, float)), f"Expected 'wasserstein_distance' to be a float, got {type(dist)}."
    assert abs(dist - 0.05) < 1e-4, f"Expected 'wasserstein_distance' to be ~0.05, got {dist}."


def test_zz_profiler_executes_required_parallel_work():
    """Run the submitted artifact under MPI and observe generation, gathering, and comparison."""
    script = '/home/user/mpi_profiler.py'
    venv_python = '/home/user/scienv/bin/python'
    report = '/home/user/profiling_report.json'
    reference = '/home/user/reference_data.txt'
    backup = '/tmp/reference_data.verifier-backup'
    hook_dir = '/tmp/mpi_verifier_hook'
    trace_dir = '/tmp/mpi_verifier_trace'

    shutil.rmtree(hook_dir, ignore_errors=True)
    shutil.rmtree(trace_dir, ignore_errors=True)
    os.makedirs(hook_dir)
    os.makedirs(trace_dir)

    hook = r'''
import json
import os
import numpy as np
import scipy.stats as _stats

_trace = os.environ['MPI_VERIFIER_TRACE']
_rank = os.environ.get('OMPI_COMM_WORLD_RANK', os.environ.get('PMI_RANK', 'unknown'))
_events = os.path.join(_trace, 'events_' + str(_rank) + '.jsonl')

def _record(obj):
    with open(_events, 'a') as f:
        f.write(json.dumps(obj) + '\n')

_orig_default_rng = np.random.default_rng

class _RNGProxy:
    def __init__(self, rng):
        self._rng = rng
    def __getattr__(self, name):
        return getattr(self._rng, name)
    def standard_normal(self, *args, **kwargs):
        size = kwargs.get('size', args[0] if args else None)
        _record({'event': 'standard_normal', 'size': size})
        return self._rng.standard_normal(*args, **kwargs)

def _default_rng(seed=None):
    simple_seed = int(seed) if isinstance(seed, (int, np.integer)) else repr(seed)
    _record({'event': 'default_rng', 'seed': simple_seed})
    return _RNGProxy(_orig_default_rng(seed))

np.random.default_rng = _default_rng
_orig_wasserstein = _stats.wasserstein_distance

def _wasserstein(u_values, v_values, *args, **kwargs):
    np.savez(os.path.join(_trace, 'wasserstein_' + str(_rank) + '.npz'),
             u=np.asarray(u_values), v=np.asarray(v_values))
    _record({'event': 'wasserstein_distance'})
    return _orig_wasserstein(u_values, v_values, *args, **kwargs)

_stats.wasserstein_distance = _wasserstein
'''
    with open(os.path.join(hook_dir, 'sitecustomize.py'), 'w') as f:
        f.write(hook)

    shutil.copy2(reference, backup)
    try:
        # Use an unpredictable replacement dataset so a fixed, self-reported value cannot pass.
        challenge_rng = np.random.default_rng(secrets.randbits(128))
        challenge = challenge_rng.normal(loc=0.37, scale=1.41, size=40000)
        np.savetxt(reference, challenge)
        challenge = np.loadtxt(reference)

        if os.path.exists(report):
            os.remove(report)

        env = os.environ.copy()
        env['PYTHONPATH'] = hook_dir
        env['MPI_VERIFIER_TRACE'] = trace_dir
        env['OMPI_ALLOW_RUN_AS_ROOT'] = '1'
        env['OMPI_ALLOW_RUN_AS_ROOT_CONFIRM'] = '1'
        result = subprocess.run(
            ['mpirun', '-np', '4', venv_python, script],
            env=env,
            capture_output=True,
            text=True,
            timeout=120,
        )
        assert result.returncode == 0, (
            f"MPI profiler failed with exit code {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(report), "MPI execution did not create profiling_report.json."

        with open(report) as f:
            data = json.load(f)
        assert set(data) == {'wasserstein_distance', 'processes'}, "Report must contain exactly the required keys."
        assert data['processes'] == 4
        assert isinstance(data['wasserstein_distance'], (int, float))

        # Every MPI rank must use its own rank as the default_rng seed and generate exactly 10,000 values.
        for rank in range(4):
            event_file = os.path.join(trace_dir, f'events_{rank}.jsonl')
            assert os.path.isfile(event_file), f"No observed work from MPI rank {rank}."
            with open(event_file) as f:
                events = [json.loads(line) for line in f if line.strip()]
            rng_events = [e for e in events if e.get('event') == 'default_rng']
            sample_events = [e for e in events if e.get('event') == 'standard_normal']
            assert rng_events == [{'event': 'default_rng', 'seed': rank}], (
                f"Rank {rank} must call numpy.random.default_rng(seed={rank}) exactly once."
            )
            assert sample_events == [{'event': 'standard_normal', 'size': 10000}], (
                f"Rank {rank} must generate exactly 10,000 standard-normal samples."
            )

        captures = glob.glob(os.path.join(trace_dir, 'wasserstein_*.npz'))
        assert captures == [os.path.join(trace_dir, 'wasserstein_0.npz')], (
            "wasserstein_distance must be called exactly on Rank 0."
        )
        captured = np.load(captures[0])
        gathered = captured['u']
        compared_reference = captured['v']

        expected_parts = [np.random.default_rng(seed=rank).standard_normal(10000) for rank in range(4)]
        expected_gathered = np.concatenate(expected_parts)
        assert gathered.shape == (40000,), "Gathered sample array must be flat and contain 40,000 samples."
        assert np.array_equal(gathered, expected_gathered), (
            "Rank 0 did not compare the required rank-ordered concatenation of generated samples."
        )
        assert np.array_equal(compared_reference, challenge), (
            "Rank 0 did not compare against the reference dataset from reference_data.txt."
        )

        expected_distance = float(np.mean(np.abs(np.sort(expected_gathered) - np.sort(challenge))))
        assert np.isclose(data['wasserstein_distance'], expected_distance, rtol=0, atol=1e-12), (
            f"Reported distance {data['wasserstein_distance']} does not match calculated distance "
            f"{expected_distance}."
        )
    finally:
        if os.path.exists(backup):
            shutil.move(backup, reference)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
