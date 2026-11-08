#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import stat
import subprocess
import tempfile

import h5py
import numpy as np
import pytest

SRC = '/home/user/src/density_omp.cpp'
EXE = '/home/user/bin/density_omp'
BENCH = '/home/user/bin/benchmark.sh'
DATA = '/home/user/data/particles.h5'
HIST = '/home/user/results/histogram.out'
CI = '/home/user/results/ci.txt'
TIME_RE = re.compile(r'^Compute Time: ([0-9]+(?:\.[0-9]+)?) ms\n?$')
CI_RE = re.compile(r'^Mean CI: \[([0-9]+\.[0-9]{2}), ([0-9]+\.[0-9]{2})\]$')


def expected_histogram():
    with h5py.File(DATA, 'r') as f:
        assert '/x_coords' in f, 'Dataset /x_coords is missing.'
        values = f['/x_coords'][:]
    assert values.ndim == 1
    bins = np.floor(values).astype(np.int64)
    assert np.all((bins >= 0) & (bins < 100))
    return np.bincount(bins, minlength=100).astype(np.int64)


def read_histogram():
    assert os.path.isfile(HIST), f'Histogram output {HIST} does not exist.'
    with open(HIST, 'r', encoding='utf-8') as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == 100, f'Expected 100 lines in {HIST}, got {len(lines)}.'
    result = []
    for i, line in enumerate(lines):
        try:
            result.append(int(line))
        except ValueError:
            pytest.fail(f"Line {i + 1} in {HIST} is not a valid integer: '{line}'")
    assert sum(result) == 1000000, f'Expected sum of histogram counts to be 1000000, got {sum(result)}.'
    return np.asarray(result, dtype=np.int64)


def run_density(timeout=120):
    env = os.environ.copy()
    env['OMP_NUM_THREADS'] = '4'
    result = subprocess.run([EXE], capture_output=True, text=True, env=env, timeout=timeout)
    assert result.returncode == 0, f'density_omp failed: {result.stderr}'
    match = TIME_RE.fullmatch(result.stdout)
    assert match, f'Unexpected stdout from density_omp: {result.stdout!r}'
    assert float(match.group(1)) > 0.0, 'Reported compute time must be positive.'
    return result


def test_directories_exist():
    for directory in ['/home/user/src', '/home/user/bin', '/home/user/results']:
        assert os.path.isdir(directory), f'Directory {directory} does not exist.'


def test_cpp_source():
    assert os.path.isfile(SRC), f'Source file {SRC} does not exist.'
    with open(SRC, 'r', encoding='utf-8') as f:
        content = f.read()
    assert '#pragma omp' in content, f'{SRC} does not contain OpenMP pragmas.'
    assert 'hdf5.h' in content or 'H5Cpp.h' in content, f'{SRC} does not contain HDF5 includes.'
    assert 'H5Cpp.h' in content, f'{SRC} does not use the requested HDF5 C++ API.'


def test_executable():
    assert os.path.isfile(EXE), f'Executable {EXE} does not exist.'
    assert os.access(EXE, os.X_OK), f'File {EXE} is not executable.'
    result = subprocess.run(['ldd', EXE], capture_output=True, text=True)
    assert result.returncode == 0, f'Failed to run ldd on {EXE}.'
    output = result.stdout.lower()
    assert 'libhdf5' in output, f'{EXE} is not linked against libhdf5.'
    assert 'libgomp' in output, f'{EXE} is not linked against OpenMP (libgomp).'


def test_bash_script():
    assert os.path.isfile(BENCH), f'Bash script {BENCH} does not exist.'
    assert os.access(BENCH, os.X_OK), f'File {BENCH} is not executable.'
    with open(BENCH, 'r', encoding='utf-8') as f:
        content = f.read()
    assert '1000' in content, f'{BENCH} does not seem to contain the 1000 resamples logic.'


def test_histogram_out_against_hdf5_data():
    expected = expected_histogram()
    run_density()
    actual = read_histogram()
    assert np.array_equal(actual, expected), 'Histogram counts do not match /x_coords.'


def test_ci_txt():
    assert os.path.isfile(CI), f'CI output {CI} does not exist.'
    with open(CI, 'r', encoding='utf-8') as f:
        content = f.read().strip()
    assert CI_RE.fullmatch(content), f"Content of {CI} ('{content}') does not match expected format 'Mean CI: [lower, upper]'."


def test_executable_uses_current_hdf5_contents():
    fd, backup = tempfile.mkstemp(prefix='particles-', suffix='.h5')
    os.close(fd)
    shutil.copy2(DATA, backup)
    rng = np.random.default_rng(int.from_bytes(os.urandom(8), 'little'))
    chosen_bins = rng.integers(0, 100, size=1000000, dtype=np.int64)
    values = chosen_bins.astype(np.float64) + 0.25
    expected = np.bincount(chosen_bins, minlength=100).astype(np.int64)
    try:
        with h5py.File(DATA, 'w') as f:
            f.create_dataset('/x_coords', data=values)
        run_density()
        actual = read_histogram()
        assert np.array_equal(actual, expected), 'Executable did not compute the histogram from the test HDF5 data.'
    finally:
        shutil.copy2(backup, DATA)
        os.unlink(backup)
        # Leave histogram.out corresponding to the required original input.
        subprocess.run([EXE], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)


def test_benchmark_executes_50_runs_and_bootstraps_means():
    log_file = tempfile.mktemp(prefix='density-calls-')
    fd, exe_backup = tempfile.mkstemp(prefix='density-real-')
    os.close(fd)
    os.unlink(exe_backup)
    os.replace(EXE, exe_backup)
    wrapper = f'''#!/bin/bash
printf 'call\\n' >> {log_file!r}
n=$(wc -l < {log_file!r})
printf 'Compute Time: %d.00 ms\\n' "$n"
'''
    try:
        with open(EXE, 'w', encoding='utf-8') as f:
            f.write(wrapper)
        os.chmod(EXE, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                      stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)
        if os.path.exists(CI):
            os.unlink(CI)
        result = subprocess.run([BENCH], capture_output=True, text=True, timeout=120)
        assert result.returncode == 0, f'benchmark.sh failed: stdout={result.stdout!r}, stderr={result.stderr!r}'
        with open(log_file, 'r', encoding='utf-8') as f:
            calls = len(f.readlines())
        assert calls == 50, f'benchmark.sh executed density_omp {calls} times instead of exactly 50.'
        assert os.path.isfile(CI), 'benchmark.sh did not create ci.txt.'
        with open(CI, 'r', encoding='utf-8') as f:
            content = f.read().strip()
        match = CI_RE.fullmatch(content)
        assert match, f'benchmark-generated ci.txt has invalid format: {content!r}'
        lower, upper = map(float, match.groups())

        # For observations 1..50, compare with high-precision reference bootstrap
        # percentiles. A genuine B=1000 bootstrap varies slightly, so allow a
        # tolerance wider than its expected Monte Carlo error.
        ref_rng = np.random.default_rng(8675309)
        reference_means = np.empty(200000, dtype=np.float64)
        for start in range(0, reference_means.size, 10000):
            samples = ref_rng.integers(1, 51, size=(10000, 50))
            reference_means[start:start + 10000] = samples.mean(axis=1)
        expected_lower, expected_upper = np.percentile(reference_means, [2.5, 97.5])
        assert abs(lower - expected_lower) <= 0.8, \
            f'Lower bound {lower:.2f} is not a 2.5th-percentile bootstrap mean bound (expected near {expected_lower:.2f}).'
        assert abs(upper - expected_upper) <= 0.8, \
            f'Upper bound {upper:.2f} is not a 97.5th-percentile bootstrap mean bound (expected near {expected_upper:.2f}).'
        assert lower < 25.5 < upper, 'Bootstrap interval does not contain the observed sample mean.'
    finally:
        if os.path.lexists(EXE):
            os.unlink(EXE)
        os.replace(exe_backup, EXE)
        if os.path.exists(log_file):
            os.unlink(log_file)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
