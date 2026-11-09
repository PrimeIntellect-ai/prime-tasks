#!/bin/bash
set -u
mkdir -p /logs/verifier

cat > /tmp/fftw_probe.c <<'PROBE_EOF'
#define _GNU_SOURCE
#include <dlfcn.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

typedef double fftw_complex[2];
typedef struct fftw_plan_s *fftw_plan;

static fftw_plan watched_plan = NULL;
static int watched_n = 0;
static double *watched_in = NULL;
static fftw_complex *watched_out = NULL;

static void record_and_optionally_force(int n, double *in, fftw_complex *out) {
    if (n <= 0 || !out) return;

    double lo = INFINITY, hi = -INFINITY;
    int finite = 1;
    if (!in) {
        finite = 0;
    } else {
        for (int i = 0; i < n; ++i) {
            if (!isfinite(in[i])) finite = 0;
            if (in[i] < lo) lo = in[i];
            if (in[i] > hi) hi = in[i];
        }
    }

    const char *forced = getenv("VERIFY_FORCE_BIN");
    if (forced && *forced) {
        int k = atoi(forced);
        for (int i = 0; i <= n / 2; ++i) {
            out[i][0] = 0.0;
            out[i][1] = 0.0;
        }
        if (k > 0 && k <= n / 2) out[k][0] = 1.0e100;
    }

    int best = 1;
    double best_power = -1.0;
    for (int i = 1; i <= n / 2; ++i) {
        double power = out[i][0] * out[i][0] + out[i][1] * out[i][1];
        if (power > best_power) {
            best_power = power;
            best = i;
        }
    }

    const char *path = getenv("VERIFY_FFT_TRACE");
    if (path && *path) {
        FILE *f = fopen(path, "a");
        if (f) {
            fprintf(f, "%d %d %.17g %.17g %d\n", n, best, lo, hi, finite);
            fclose(f);
        }
    }
}

fftw_plan fftw_plan_dft_r2c_1d(int n, double *in, fftw_complex *out, unsigned flags) {
    typedef fftw_plan (*fn_t)(int, double *, fftw_complex *, unsigned);
    static fn_t real_fn = NULL;
    if (!real_fn) real_fn = (fn_t)dlsym(RTLD_NEXT, "fftw_plan_dft_r2c_1d");
    if (!real_fn) return NULL;
    fftw_plan p = real_fn(n, in, out, flags);
    watched_plan = p;
    watched_n = n;
    watched_in = in;
    watched_out = out;
    return p;
}

void fftw_execute(const fftw_plan p) {
    typedef void (*fn_t)(const fftw_plan);
    static fn_t real_fn = NULL;
    if (!real_fn) real_fn = (fn_t)dlsym(RTLD_NEXT, "fftw_execute");
    if (!real_fn) return;
    real_fn(p);
    if (p == watched_plan) record_and_optionally_force(watched_n, watched_in, watched_out);
}

void fftw_execute_dft_r2c(const fftw_plan p, double *in, fftw_complex *out) {
    typedef void (*fn_t)(const fftw_plan, double *, fftw_complex *);
    static fn_t real_fn = NULL;
    if (!real_fn) real_fn = (fn_t)dlsym(RTLD_NEXT, "fftw_execute_dft_r2c");
    if (!real_fn) return;
    real_fn(p, in, out);
    int n = (p == watched_plan) ? watched_n : 0;
    record_and_optionally_force(n, in, out);
}
PROBE_EOF

cat > /tmp/verify_task.py <<'PY_EOF'
import math
import os
import re
import subprocess
from pathlib import Path

ROOT = Path('/home/user/repressilator')
RESULT = Path('/home/user/result.txt')
SIM = ROOT / 'sim'
PROBE = '/tmp/fftw_probe.so'
TRACE = Path('/tmp/fftw_trace.txt')


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, **kwargs)


def assert_elf_and_fftw(path):
    path = Path(path)
    assert path.is_file(), f'{path} does not exist'
    assert os.access(path, os.X_OK), f'{path} is not executable'
    with path.open('rb') as f:
        assert f.read(4) == b'\x7fELF', f'{path} is not an ELF compiled binary'
    linked = run(['ldd', str(path)]).stdout
    assert re.search(r'libfftw3\.so', linked), f'{path} is not dynamically linked to FFTW3'


def read_result():
    assert RESULT.is_file(), 'The program did not generate /home/user/result.txt'
    content = RESULT.read_text()
    assert re.fullmatch(r'[+-]?\d+\.\d{4}\n?', content), \
        f'result must contain one fixed-point number with exactly 4 decimal places, got {content!r}'
    return float(content)


def execute_and_observe(binary, forced_bin=None, require_expected_range=False):
    RESULT.unlink(missing_ok=True)
    TRACE.unlink(missing_ok=True)
    env = os.environ.copy()
    env['LD_PRELOAD'] = PROBE
    env['VERIFY_FFT_TRACE'] = str(TRACE)
    if forced_bin is not None:
        env['VERIFY_FORCE_BIN'] = str(forced_bin)
    else:
        env.pop('VERIFY_FORCE_BIN', None)

    subprocess.run([str(binary)], cwd=str(ROOT), env=env, check=True,
                   timeout=45, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    value = read_result()
    assert TRACE.is_file(), 'No FFTW real-to-complex transform was executed'

    records = []
    for line in TRACE.read_text().splitlines():
        fields = line.split()
        if len(fields) == 5:
            n, best, lo, hi, finite = fields
            records.append((int(n), int(best), float(lo), float(hi), int(finite)))
    assert records, 'No usable FFT execution trace was produced'

    grid_records = [r for r in records if r[0] == 9001]
    assert grid_records, 'FFT input must contain the uniform inclusive grid t=100..1000 at dt=0.1 (9001 samples)'
    n, best, lo, hi, finite = grid_records[-1]
    assert finite == 1 and math.isfinite(lo) and math.isfinite(hi), 'FFT input contains non-finite values'
    assert hi - lo > 1e-4, 'FFT input is constant; no p1 oscillation was simulated/interpolated'

    if forced_bin is not None:
        assert best == forced_bin, f'probe failed to force FFT bin {forced_bin}; observed {best}'
        expected = forced_bin / (n * 0.1)
        assert abs(value - expected) <= 5.1e-5, \
            f'program output {value:.4f} does not come from FFT bin {forced_bin} (expected {expected:.4f})'
    else:
        expected = best / (n * 0.1)
        assert abs(value - expected) <= 5.1e-5, \
            f'program output {value:.4f} does not match its FFT dominant bin {best} (expected {expected:.4f})'
        if require_expected_range:
            assert abs(value - 0.0385) < 0.005, \
                f'frequency {value} is incorrect, expected approximately 0.0385 Hz'
    return value


# Preserve and strengthen the integrator source assertion.
integrator = ROOT / 'integrator.cpp'
assert integrator.is_file(), f'{integrator} does not exist'
content = integrator.read_text().replace(' ', '')
assert 'tol/err' in content, "integrator.cpp does not contain the required 'tol / err' fix"

# Exercise adapt_step rather than accepting the expression in a comment.
Path('/tmp/test_adapt.cpp').write_text(r'''
#include <cmath>
#include <iostream>
double adapt_step(double, double, double, bool);
int main() {
    double got = adapt_step(2.0, 0.25, 1.0, true);
    double want = 2.0 * 0.9 * std::pow(1.0 / 0.25, 0.2);
    if (!std::isfinite(got) || std::fabs(got - want) > 1e-12) return 1;
    return 0;
}
''')
run(['g++', '-std=c++17', '/tmp/test_adapt.cpp', str(integrator), '-o', '/tmp/test_adapt'])
run(['/tmp/test_adapt'])

# Preserve the dependency assertion and build the observation shim.
assert Path('/usr/include/fftw3.h').is_file(), 'FFTW3 development headers are not installed'
run(['gcc', '-shared', '-fPIC', '-O2', '/tmp/fftw_probe.c', '-ldl', '-o', PROBE])

# Rebuild submitted source independently, allowing either normal separate translation
# units or a main.cpp that directly includes integrator.cpp.
rebuilt = '/tmp/rebuilt_sim'
first = subprocess.run(['g++', '-std=c++17', '-O2', str(ROOT/'main.cpp'), str(integrator),
                        '-Wl,--no-as-needed', '-lfftw3', '-lm', '-o', rebuilt],
                       text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
if first.returncode != 0:
    second = subprocess.run(['g++', '-std=c++17', '-O2', str(ROOT/'main.cpp'),
                             '-Wl,--no-as-needed', '-lfftw3', '-lm', '-o', rebuilt],
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert second.returncode == 0, 'submitted C++ sources do not compile:\n' + first.stderr + '\n' + second.stderr

assert_elf_and_fftw(rebuilt)
assert_elf_and_fftw(SIM)

# Verify the submitted source build computes its answer from a real FFT, and that
# changing the FFT spectrum changes the reported frequency accordingly.
execute_and_observe(rebuilt, require_expected_range=True)
execute_and_observe(rebuilt, forced_bin=137)
execute_and_observe(rebuilt, forced_bin=251)

# Exercise the required final binary too, including a dependency test, then leave
# result.txt containing its normal simulation result.
execute_and_observe(SIM, forced_bin=173)
execute_and_observe(SIM, require_expected_range=True)
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
