#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import shutil
import subprocess
import tempfile
from collections import Counter

import h5py
import numpy as np
from scipy.stats import norm, wasserstein_distance

HOME = '/home/user'
PY_SCRIPT = os.path.join(HOME, 'fit_and_compare.py')
R_SCRIPT = os.path.join(HOME, 'test_hypothesis.R')
DATA_PATH = os.path.join(HOME, 'data.h5')
DIST_PATH = os.path.join(HOME, 'distances.csv')
PVALUE_PATH = os.path.join(HOME, 'pvalue.txt')


def golden_distances(data):
    result = []
    probabilities = np.linspace(0.001, 0.999, 1000)
    for row in data:
        mu, std = norm.fit(row)
        quantiles = norm.ppf(probabilities, loc=mu, scale=std)
        result.append(float(wasserstein_distance(row, quantiles)))
    return result


def golden_pvalue(distances):
    with tempfile.TemporaryDirectory() as td:
        csv_path = os.path.join(td, 'distances.csv')
        script_path = os.path.join(td, 'test.R')
        np.savetxt(csv_path, distances)
        with open(script_path, 'w') as f:
            f.write("d <- read.csv(%r, header=FALSE)$V1\n" % csv_path)
            f.write("cat(t.test(d, mu=0.1)$p.value)\n")
        output = subprocess.check_output(
            ['Rscript', script_path], text=True, timeout=60
        ).strip()
        return float(output)


def read_distances():
    assert os.path.isfile(DIST_PATH), f"Output file {DIST_PATH} is missing."
    with open(DIST_PATH) as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == 200, \
        f"Expected 200 lines in {DIST_PATH}, found {len(lines)}."
    try:
        return [float(value) for value in lines]
    except ValueError:
        assert False, f"Not all values in {DIST_PATH} are valid numbers."


def read_pvalue():
    assert os.path.isfile(PVALUE_PATH), f"Output file {PVALUE_PATH} is missing."
    with open(PVALUE_PATH) as f:
        content = f.read().strip()
    try:
        return float(content)
    except ValueError:
        assert False, f"The content of {PVALUE_PATH} is not a valid number: {content}"


def assert_distances(actual, expected):
    for i, (student, gold) in enumerate(zip(actual, expected)):
        assert math.isclose(student, gold, rel_tol=1e-3, abs_tol=1e-4), \
            f"Distance at row {i} does not match. Expected ~{gold}, got {student}."


def make_monitor():
    monitor_dir = tempfile.mkdtemp(prefix='parallel_monitor_')
    log_path = os.path.join(monitor_dir, 'ppf_calls.log')
    sitecustomize = r'''
import os
try:
    from scipy.stats import norm
    _verifier_original_ppf = norm.ppf
    def _verifier_logged_ppf(*args, **kwargs):
        path = os.environ.get('VERIFIER_PPF_LOG')
        if path:
            with open(path, 'a') as log:
                log.write(str(os.getpid()) + "\n")
        return _verifier_original_ppf(*args, **kwargs)
    norm.ppf = _verifier_logged_ppf
except Exception:
    pass
'''
    with open(os.path.join(monitor_dir, 'sitecustomize.py'), 'w') as f:
        f.write(sitecustomize)
    return monitor_dir, log_path


def run_python_and_check_parallelism():
    monitor_dir, log_path = make_monitor()
    try:
        for path in (DIST_PATH, log_path):
            if os.path.exists(path):
                os.remove(path)
        env = os.environ.copy()
        old_pythonpath = env.get('PYTHONPATH', '')
        env['PYTHONPATH'] = monitor_dir + (os.pathsep + old_pythonpath if old_pythonpath else '')
        env['VERIFIER_PPF_LOG'] = log_path
        proc = subprocess.run(
            ['python3', PY_SCRIPT], cwd=HOME, env=env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=180
        )
        assert proc.returncode == 0, \
            f"Python script failed.\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
        assert os.path.isfile(log_path), \
            "No scipy.stats.norm.ppf calls were observed while running the Python script."
        with open(log_path) as f:
            calls = [int(line.strip()) for line in f if line.strip()]
        worker_calls = [pid for pid in calls if pid != proc.pid]
        counts = Counter(worker_calls)
        assert len(counts) == 4, \
            f"Expected norm.ppf row computations in exactly 4 worker processes, observed {len(counts)}."
        assert sum(counts.values()) >= 200, \
            f"Expected at least 200 row computations in workers, observed {sum(counts.values())}."
        assert all(count > 0 for count in counts.values()), \
            "Each of the four worker processes must process data."
    finally:
        shutil.rmtree(monitor_dir, ignore_errors=True)


def run_r_script():
    if os.path.exists(PVALUE_PATH):
        os.remove(PVALUE_PATH)
    proc = subprocess.run(
        ['Rscript', R_SCRIPT], cwd=HOME,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
    )
    assert proc.returncode == 0, \
        f"R script failed.\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    assert os.path.isfile(PVALUE_PATH), \
        f"The R script did not produce {PVALUE_PATH}."


def test_python_script_exists_and_uses_multiprocessing():
    assert os.path.isfile(PY_SCRIPT), f"Python script {PY_SCRIPT} is missing."
    with open(PY_SCRIPT) as f:
        content = f.read()
    assert 'multiprocessing' in content or 'ProcessPoolExecutor' in content, \
        "The Python script must use the multiprocessing library."


def test_r_script_exists():
    assert os.path.isfile(R_SCRIPT), f"R script {R_SCRIPT} is missing."


def test_scripts_execute_and_generate_outputs():
    with h5py.File(DATA_PATH, 'r') as f:
        original_data = f['empirical_data'][:]

    probe_data = original_data.copy()
    scales = np.linspace(0.65, 1.35, probe_data.shape[0])[:, None]
    offsets = np.linspace(-0.4, 0.4, probe_data.shape[0])[:, None]
    probe_data = probe_data * scales + offsets
    probe_expected = golden_distances(probe_data)
    probe_pvalue = golden_pvalue(probe_expected)

    backup = tempfile.NamedTemporaryFile(prefix='data_backup_', suffix='.h5', delete=False)
    backup.close()
    shutil.copy2(DATA_PATH, backup.name)
    try:
        with h5py.File(DATA_PATH, 'r+') as f:
            f['empirical_data'][:] = probe_data
        run_python_and_check_parallelism()
        probe_actual = read_distances()
        assert_distances(probe_actual, probe_expected)
        run_r_script()
        actual_probe_pvalue = read_pvalue()
        assert math.isclose(actual_probe_pvalue, probe_pvalue, rel_tol=1e-3, abs_tol=1e-4), \
            f"Probe p-value does not match. Expected ~{probe_pvalue}, got {actual_probe_pvalue}."
    finally:
        shutil.copy2(backup.name, DATA_PATH)
        os.remove(backup.name)

    final_expected = golden_distances(original_data)
    final_pvalue = golden_pvalue(final_expected)
    run_python_and_check_parallelism()
    final_actual = read_distances()
    assert_distances(final_actual, final_expected)
    run_r_script()
    actual_final_pvalue = read_pvalue()
    assert math.isclose(actual_final_pvalue, final_pvalue, rel_tol=1e-3, abs_tol=1e-4), \
        f"p-value does not match. Expected ~{final_pvalue}, got {actual_final_pvalue}."


def test_distances_csv():
    values = read_distances()
    assert len(values) == 200


def test_pvalue_txt():
    value = read_pvalue()
    assert math.isfinite(value), f"The p-value is not finite: {value}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
