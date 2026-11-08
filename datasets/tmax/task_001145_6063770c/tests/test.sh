#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import shutil
import subprocess
import sys
import tempfile

import numpy as np
from sklearn.decomposition import NMF

HOME = '/home/user'
LIB = os.path.join(HOME, 'libsmooth.so')
SCRIPT = os.path.join(HOME, 'analyze.py')
SPECTRA = os.path.join(HOME, 'spectra.csv')
RESULT = os.path.join(HOME, 'result.txt')


def smooth_python(X):
    out = np.empty_like(X, dtype=np.float64)
    if X.shape[1] == 0:
        return out
    out[:, 0] = X[:, 0]
    if X.shape[1] > 2:
        out[:, 1:-1] = (X[:, :-2] + X[:, 1:-1] + X[:, 2:]) / 3.0
    if X.shape[1] > 1:
        out[:, -1] = X[:, -1]
    return out


def expected_result(X):
    X_smooth = smooth_python(np.asarray(X, dtype=np.float64))
    for alpha_int in range(11):
        alpha = alpha_int / 10.0
        nmf = NMF(
            n_components=2,
            init='random',
            random_state=42,
            max_iter=500,
            solver='cd',
            alpha_W=alpha,
            alpha_H=alpha,
            l1_ratio=1.0,
        )
        nmf.fit(X_smooth)
        if nmf.n_iter_ < 500:
            return f'alpha={alpha:.1f}, iter={nmf.n_iter_}'
    return ''


def read_result():
    with open(RESULT, 'r') as f:
        return f.read().strip()


def run_analyze(env=None):
    completed = subprocess.run(
        [sys.executable, SCRIPT],
        cwd=HOME,
        env=env,
        capture_output=True,
        text=True,
        timeout=240,
    )
    assert completed.returncode == 0, (
        'analyze.py failed when executed:\n'
        + completed.stdout + '\n' + completed.stderr
    )


def test_libsmooth_exists():
    assert os.path.isfile(LIB), 'Shared library /home/user/libsmooth.so is missing.'


def test_analyze_script_exists():
    assert os.path.isfile(SCRIPT), 'Python script /home/user/analyze.py is missing.'


def test_result_txt_content():
    assert os.path.isfile(RESULT), 'Result file /home/user/result.txt is missing.'
    X = np.loadtxt(SPECTRA, delimiter=',', ndmin=2)
    expected = expected_result(X)
    actual = read_result()
    assert actual == expected, (
        f"Expected result '{expected}', but got '{actual}' in /home/user/result.txt"
    )


def test_submitted_library_implements_smooth():
    lib = ctypes.CDLL(LIB)
    lib.smooth.argtypes = [
        ctypes.POINTER(ctypes.c_double),
        ctypes.POINTER(ctypes.c_double),
        ctypes.c_int,
    ]
    lib.smooth.restype = None

    for values in ([7.5], [2.0, 9.0], [1.0, 4.0, 10.0, 7.0, 2.0]):
        inp = np.ascontiguousarray(values, dtype=np.float64)
        out = np.full(inp.shape, np.nan, dtype=np.float64)
        lib.smooth(
            inp.ctypes.data_as(ctypes.POINTER(ctypes.c_double)),
            out.ctypes.data_as(ctypes.POINTER(ctypes.c_double)),
            inp.size,
        )
        expected = smooth_python(inp.reshape(1, -1))[0]
        np.testing.assert_allclose(out, expected, rtol=0, atol=1e-12)


def test_analyze_executes_full_pipeline():
    original_X = np.loadtxt(SPECTRA, delimiter=',', ndmin=2)
    original_expected = expected_result(original_X)

    # First execute the submitted script with the submitted shared library and
    # the provided data, then verify that it regenerates the required result.
    run_analyze()
    assert os.path.isfile(RESULT), 'analyze.py did not create /home/user/result.txt'
    assert read_result() == original_expected

    work = tempfile.mkdtemp(prefix='pipeline_check_', dir='/tmp')
    saved_lib = os.path.join(work, 'submitted_libsmooth.so')
    saved_spectra = os.path.join(work, 'spectra.csv')
    saved_result = os.path.join(work, 'result.txt')
    probe_c = os.path.join(work, 'probe.c')
    probe_so = os.path.join(work, 'probe.so')
    probe_log = os.path.join(work, 'calls.log')

    had_result = os.path.exists(RESULT)
    if had_result:
        shutil.copy2(RESULT, saved_result)

    # The probe has the required smoothing behavior and records every call. It
    # lets the verifier establish that analyze.py loads /home/user/libsmooth.so
    # and invokes smooth for the rows it reads, rather than merely hardcoding a
    # result that happens to be correct for the provided CSV.
    with open(probe_c, 'w') as f:
        f.write(r'''
#include <stdio.h>
#include <stdlib.h>
void smooth(double* input, double* output, int n) {
    const char *path = getenv("SMOOTH_PROBE_LOG");
    if (path) {
        FILE *fp = fopen(path, "a");
        if (fp) { fprintf(fp, "%d\n", n); fclose(fp); }
    }
    if (n == 0) return;
    output[0] = input[0];
    for (int i = 1; i < n - 1; i++)
        output[i] = (input[i-1] + input[i] + input[i+1]) / 3.0;
    if (n > 1) output[n-1] = input[n-1];
}
''')
    subprocess.check_call(['gcc', '-shared', '-fPIC', '-o', probe_so, probe_c])

    rng = np.random.RandomState(7319)
    synthetic = np.abs(rng.normal(size=(14, 21)))
    synthetic += np.linspace(0.01, 0.4, synthetic.shape[1])[None, :]
    synthetic_expected = expected_result(synthetic)

    try:
        os.replace(LIB, saved_lib)
        os.replace(probe_so, LIB)
        os.replace(SPECTRA, saved_spectra)
        np.savetxt(SPECTRA, synthetic, delimiter=',')
        if os.path.exists(RESULT):
            os.remove(RESULT)

        env = os.environ.copy()
        env['SMOOTH_PROBE_LOG'] = probe_log
        run_analyze(env)

        assert os.path.isfile(RESULT), 'analyze.py did not create result.txt on test data'
        assert read_result() == synthetic_expected, (
            f"On verifier-generated data expected '{synthetic_expected}', "
            f"but analyze.py wrote '{read_result()}'"
        )
        assert os.path.isfile(probe_log), (
            'analyze.py did not call smooth from /home/user/libsmooth.so'
        )
        with open(probe_log, 'r') as f:
            calls = [int(line.strip()) for line in f if line.strip()]
        matching_calls = [n for n in calls if n == synthetic.shape[1]]
        assert len(matching_calls) >= synthetic.shape[0], (
            'analyze.py did not apply the C smooth function to every input row'
        )
    finally:
        if os.path.exists(LIB):
            os.remove(LIB)
        if os.path.exists(saved_lib):
            os.replace(saved_lib, LIB)
        if os.path.exists(SPECTRA):
            os.remove(SPECTRA)
        if os.path.exists(saved_spectra):
            os.replace(saved_spectra, SPECTRA)
        if os.path.exists(RESULT):
            os.remove(RESULT)
        if had_result and os.path.exists(saved_result):
            shutil.copy2(saved_result, RESULT)
        shutil.rmtree(work, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
