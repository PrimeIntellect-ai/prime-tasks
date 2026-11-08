#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import pathlib
import pwd
import re
import subprocess
import tempfile

HOME = pathlib.Path('/home/user')
FFTW = HOME / 'fftw'
SOURCE = HOME / 'wave_profiler.c'
RESULT = HOME / 'result.txt'


def run(cmd, **kwargs):
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       text=True, **kwargs)
    assert p.returncode == 0, f"Command failed ({p.returncode}): {' '.join(map(str, cmd))}\n{p.stdout}"
    return p


def test_fftw_installed_and_functional():
    """Verify that the local FFTW installation is genuine and functional."""
    include_file = FFTW / 'include' / 'fftw3.h'
    lib_file_a = FFTW / 'lib' / 'libfftw3.a'
    lib_file_so = FFTW / 'lib' / 'libfftw3.so'

    assert include_file.exists(), f"FFTW include file not found at {include_file}"
    assert lib_file_a.exists() or lib_file_so.exists(), \
        "FFTW library file (libfftw3.a or libfftw3.so) not found in /home/user/fftw/lib/"
    assert include_file.is_file(), 'fftw3.h is not a regular file'

    probe = r'''
#include <fftw3.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
int main(void) {
    enum { N = 7 };
    const double pi = 3.14159265358979323846264338327950288;
    fftw_complex *in = fftw_malloc(sizeof(fftw_complex) * N);
    fftw_complex *out = fftw_malloc(sizeof(fftw_complex) * N);
    if (!in || !out) return 2;
    for (int j = 0; j < N; ++j) {
        in[j][0] = 0.25 + 0.17*j - 0.03*j*j;
        in[j][1] = -0.4 + 0.11*j;
    }
    fftw_plan p = fftw_plan_dft_1d(N, in, out, FFTW_FORWARD, FFTW_ESTIMATE);
    if (!p) return 3;
    fftw_execute(p);
    for (int k = 0; k < N; ++k) {
        double er = 0.0, ei = 0.0;
        for (int j = 0; j < N; ++j) {
            double a = -2.0*pi*j*k/N;
            er += in[j][0]*cos(a) - in[j][1]*sin(a);
            ei += in[j][0]*sin(a) + in[j][1]*cos(a);
        }
        if (fabs(out[k][0]-er) > 1e-9 || fabs(out[k][1]-ei) > 1e-9) return 4;
    }
    if (strncmp(fftw_version, "fftw-3.3.10", 11) != 0) {
        fprintf(stderr, "wrong FFTW version: %s\n", fftw_version);
        return 5;
    }
    fftw_destroy_plan(p);
    fftw_free(in);
    fftw_free(out);
    return 0;
}
'''
    with tempfile.TemporaryDirectory() as td:
        src = pathlib.Path(td) / 'probe.c'
        exe = pathlib.Path(td) / 'probe'
        src.write_text(probe)
        run(['gcc', '-O2', str(src), '-I/home/user/fftw/include',
             '-L/home/user/fftw/lib', '-Wl,-rpath,/home/user/fftw/lib',
             '-lfftw3', '-lm', '-o', str(exe)], timeout=120)
        env = os.environ.copy()
        env['LD_LIBRARY_PATH'] = '/home/user/fftw/lib' + (':' + env['LD_LIBRARY_PATH'] if env.get('LD_LIBRARY_PATH') else '')
        run([str(exe)], env=env, timeout=30)


def test_compile_execute_and_result():
    """Compile the submitted C source, execute it, and validate its regenerated output."""
    assert SOURCE.exists(), f"C program not found at {SOURCE}"
    assert SOURCE.is_file(), f"C program at {SOURCE} is not a regular file"

    text = SOURCE.read_text(errors='replace')
    assert re.search(r'#\s*pragma\s+omp\b', text, re.I), \
        'wave_profiler.c does not contain an OpenMP pragma'
    assert re.search(r'\bfftw_[A-Za-z0-9_]+\b', text), \
        'wave_profiler.c does not use the FFTW API'

    with tempfile.TemporaryDirectory() as td:
        os.chmod(td, 0o755)
        exe = pathlib.Path(td) / 'wave_profiler'
        run(['gcc', '-O2', '-std=c11', '-fopenmp', str(SOURCE),
             '-I/home/user/fftw/include', '-L/home/user/fftw/lib',
             '-Wl,-rpath,/home/user/fftw/lib', '-lfftw3', '-lm',
             '-o', str(exe)], timeout=180)
        os.chmod(exe, 0o755)

        symbols = run(['nm', '-a', str(exe)], timeout=30).stdout
        assert re.search(r'\bfftw_(?:plan|execute|malloc|free)', symbols), \
            'compiled program does not reference FFTW transform functionality'
        assert re.search(r'\b(?:GOMP_parallel|omp_get_|omp_set_)', symbols), \
            'compiled program does not contain an OpenMP runtime reference'

        if RESULT.lexists():
            RESULT.unlink()

        env = os.environ.copy()
        env['OMP_NUM_THREADS'] = '2'
        env['LD_LIBRARY_PATH'] = '/home/user/fftw/lib' + (':' + env['LD_LIBRARY_PATH'] if env.get('LD_LIBRARY_PATH') else '')
        account = pwd.getpwnam('user')
        def demote():
            os.setgid(account.pw_gid)
            os.setuid(account.pw_uid)
        run([str(exe)], cwd='/home/user', env=env, timeout=420, preexec_fn=demote)

    assert RESULT.exists(), f"Result file not found at {RESULT}"
    assert RESULT.is_file(), 'result.txt is not a regular file'
    raw = RESULT.read_bytes()
    assert re.fullmatch(rb'[-+]?\d+\.\d{6}\n?', raw), \
        'result.txt must contain only one number formatted to exactly 6 decimal places'
    content = raw.decode().strip()
    assert content != '', 'Result file is empty.'
    try:
        val = float(content)
    except ValueError:
        assert False, f"Result file content '{content}' is not a valid float."

    expected_val = 3.023402
    assert math.isclose(val, expected_val, abs_tol=1e-5), \
        f"Expected result to be close to {expected_val}, but got {val}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
