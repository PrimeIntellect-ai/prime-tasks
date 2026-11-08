#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import cmath
import ctypes
import json
import math
import os
import pathlib
import random
import shutil
import subprocess

import pytest

WORKSPACE = pathlib.Path('/home/user/workspace')
BINARY = WORKSPACE / 'bin' / 'fftapp'
LIBRARY = WORKSPACE / 'lib' / 'libkissfft.so'
METRICS = WORKSPACE / 'metrics.json'
TRACE_FILE = pathlib.Path('/tmp/kiss_fft_calls.txt')


@pytest.fixture(scope='session', autouse=True)
def build_and_run_pipeline():
    makefile = WORKSPACE / 'Makefile'
    assert makefile.is_file(), f'Makefile missing at {makefile}'

    # Require the submitted Makefile to recreate all deliverables.
    shutil.rmtree(WORKSPACE / 'bin', ignore_errors=True)
    shutil.rmtree(WORKSPACE / 'lib', ignore_errors=True)
    METRICS.unlink(missing_ok=True)

    build = subprocess.run(
        ['make'], cwd=WORKSPACE, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180
    )
    assert build.returncode == 0, f'make failed:\n{build.stdout}'
    assert BINARY.is_file(), f'Go binary missing after make: {BINARY}'
    assert LIBRARY.is_file(), f'Shared library missing after make: {LIBRARY}'

    # Interpose kiss_fft while running the application, proving that the Go/CGO
    # execution path actually invokes the shared C implementation.
    tracer_c = pathlib.Path('/tmp/trace_kissfft.c')
    tracer_so = pathlib.Path('/tmp/trace_kissfft.so')
    tracer_c.write_text(r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include "kiss_fft.h"

static unsigned long long calls = 0;

typedef void (*real_kiss_fft_t)(kiss_fft_cfg, const kiss_fft_cpx *, kiss_fft_cpx *);

void kiss_fft(kiss_fft_cfg cfg, const kiss_fft_cpx *fin, kiss_fft_cpx *fout) {
    real_kiss_fft_t real_fn = (real_kiss_fft_t)dlsym(RTLD_NEXT, "kiss_fft");
    __sync_fetch_and_add(&calls, 1);
    if (!real_fn) {
        fprintf(stderr, "unable to resolve real kiss_fft\n");
        _Exit(125);
    }
    real_fn(cfg, fin, fout);
}

__attribute__((destructor)) static void save_calls(void) {
    const char *path = getenv("KISSFFT_TRACE_FILE");
    if (path) {
        FILE *f = fopen(path, "a");
        if (f) {
            fprintf(f, "%llu\n", calls);
            fclose(f);
        }
    }
}
''')
    cc = subprocess.run(
        ['gcc', '-shared', '-fPIC', '-I/app/kissfft-1.3.1',
         str(tracer_c), '-ldl', '-o', str(tracer_so)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert cc.returncode == 0, f'failed to compile FFT call tracer:\n{cc.stdout}'

    METRICS.unlink(missing_ok=True)
    TRACE_FILE.unlink(missing_ok=True)
    env = os.environ.copy()
    env['LD_LIBRARY_PATH'] = str(WORKSPACE / 'lib') + ':' + env.get('LD_LIBRARY_PATH', '')
    env['LD_PRELOAD'] = str(tracer_so)
    env['KISSFFT_TRACE_FILE'] = str(TRACE_FILE)
    run = subprocess.run(
        [str(BINARY)], cwd=WORKSPACE, env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=240
    )
    assert run.returncode == 0, f'fftapp failed:\n{run.stdout}'
    assert METRICS.is_file(), 'fftapp did not generate metrics.json'
    assert TRACE_FILE.is_file(), 'fftapp did not load/invoke the traced FFT symbol'
    counts = [int(x) for x in TRACE_FILE.read_text().split()]
    assert sum(counts) > 0, 'fftapp never called kiss_fft through CGO'


def test_patch_was_fixed_and_applied():
    patch_file = WORKSPACE / 'patches' / 'kiss_opt.patch'
    source_file = pathlib.Path('/app/kissfft-1.3.1/kiss_fft.c')
    assert patch_file.is_file(), f'Patch missing at {patch_file}'
    assert b'\r' not in patch_file.read_bytes(), 'kiss_opt.patch still has CRLF line endings'
    assert '// optimized' in source_file.read_text(), 'performance patch is not present in kiss_fft.c'

    reverse_check = subprocess.run(
        ['patch', '--dry-run', '--batch', '-R', '-p0', '-i', str(patch_file)],
        cwd='/app/kissfft-1.3.1', text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert reverse_check.returncode == 0, (
        'kiss_opt.patch is not recognizably applied to the vendored source:\n'
        + reverse_check.stdout
    )


def test_binaries_and_libraries_exist():
    go_binary = '/home/user/workspace/bin/fftapp'
    assert os.path.isfile(go_binary), f'Go binary missing at {go_binary}'
    assert os.access(go_binary, os.X_OK), f'Go binary {go_binary} is not executable'

    lib_dir = '/home/user/workspace/lib'
    assert os.path.isdir(lib_dir), f'Library directory missing at {lib_dir}'
    lib_path = os.path.join(lib_dir, 'libkissfft.so')
    assert os.path.isfile(lib_path), f'Shared library missing at {lib_path}'

    with open(go_binary, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'bin/fftapp is not a compiled ELF binary'
    with open(lib_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'libkissfft.so is not an ELF shared library'

    go_info = subprocess.run(
        ['go', 'version', '-m', go_binary], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert go_info.returncode == 0 and 'path\t' in go_info.stdout, (
        f'bin/fftapp is not a recognizable Go executable:\n{go_info.stdout}'
    )

    dynamic = subprocess.run(
        ['readelf', '-d', go_binary], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert dynamic.returncode == 0, f'cannot inspect fftapp dynamic links:\n{dynamic.stdout}'
    assert 'libkissfft.so' in dynamic.stdout, 'fftapp is not dynamically linked to libkissfft.so'


def test_shared_library_computes_fft_on_derived_inputs():
    class ComplexFloat(ctypes.Structure):
        _fields_ = [('r', ctypes.c_float), ('i', ctypes.c_float)]

    lib = ctypes.CDLL(str(LIBRARY))
    lib.kiss_fft_alloc.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p,
                                   ctypes.POINTER(ctypes.c_size_t)]
    lib.kiss_fft_alloc.restype = ctypes.c_void_p
    lib.kiss_fft.argtypes = [ctypes.c_void_p,
                             ctypes.POINTER(ComplexFloat),
                             ctypes.POINTER(ComplexFloat)]
    lib.kiss_fft.restype = None

    rng = random.Random(0xC0FFEE)
    for n in (7, 16):
        values = [complex(rng.uniform(-1, 1), rng.uniform(-1, 1)) for _ in range(n)]
        input_array = (ComplexFloat * n)(*[ComplexFloat(z.real, z.imag) for z in values])
        output_array = (ComplexFloat * n)()
        needed = ctypes.c_size_t(0)
        cfg = lib.kiss_fft_alloc(n, 0, None, ctypes.byref(needed))
        assert cfg, f'kiss_fft_alloc returned NULL for size {n}'
        lib.kiss_fft(cfg, input_array, output_array)

        expected = [
            sum(values[t] * cmath.exp(-2j * math.pi * k * t / n) for t in range(n))
            for k in range(n)
        ]
        actual = [complex(output_array[k].r, output_array[k].i) for k in range(n)]
        mse = sum(abs(a - e) ** 2 for a, e in zip(actual, expected)) / n
        assert math.isfinite(mse), 'shared-library FFT produced non-finite values'
        assert mse <= 1e-4, f'libkissfft.so is numerically incorrect for n={n}: MSE={mse}'


def test_metrics_json_exists_and_meets_thresholds():
    metrics_file = '/home/user/workspace/metrics.json'
    assert os.path.isfile(metrics_file), f'Metrics file missing at {metrics_file}'

    try:
        with open(metrics_file, 'r') as f:
            data = json.load(f)
    except Exception as e:
        pytest.fail(f'Failed to read or parse metrics JSON: {e}')

    assert 'mse' in data, "Key 'mse' missing in metrics.json"
    assert 'speedup_ratio' in data, "Key 'speedup_ratio' missing in metrics.json"

    try:
        mse = float(data['mse'])
        speedup = float(data['speedup_ratio'])
    except (ValueError, TypeError) as e:
        pytest.fail(f'Failed to convert metrics to float: {e}')

    assert math.isfinite(mse), f'FAIL: MSE {mse} is not finite'
    assert math.isfinite(speedup), f'FAIL: Speedup {speedup} is not finite'
    assert mse <= 1e-4, f'FAIL: MSE {mse} is above threshold 1e-4'
    assert speedup >= 1.2, f'FAIL: Speedup {speedup} is below threshold 1.2'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
