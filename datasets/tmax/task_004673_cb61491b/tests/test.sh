#!/bin/bash
mkdir -p /logs/verifier

cleanup() {
    [ -f /tmp/original_sim_matrix.h5 ] && cp -f /tmp/original_sim_matrix.h5 /home/user/sim_matrix.h5
    [ -f /tmp/original_reference_sv.txt ] && cp -f /tmp/original_reference_sv.txt /home/user/reference_sv.txt
    [ -f /tmp/original_top_sv.txt ] && cp -f /tmp/original_top_sv.txt /home/user/top_sv.txt
    [ -f /tmp/original_sv_error.txt ] && cp -f /tmp/original_sv_error.txt /home/user/sv_error.txt
}
trap cleanup EXIT

verify() {
    python3 - <<'PY'
import os

path = '/home/user/top_sv.txt'
assert os.path.isfile(path), f"Expected file {path} does not exist."
with open(path) as f:
    lines = [line.strip() for line in f if line.strip()]
assert len(lines) == 3, f"Expected exactly 3 lines in {path}, found {len(lines)}."
expected_values = ["18.239300", "2.502985", "2.434674"]
for i, (actual, expected) in enumerate(zip(lines, expected_values)):
    assert actual == expected, f"Line {i+1} in {path} is '{actual}', expected '{expected}'."

path = '/home/user/sv_error.txt'
assert os.path.isfile(path), f"Expected file {path} does not exist."
with open(path) as f:
    content = f.read().strip()
expected_mae = "0.056667"
assert content == expected_mae, f"Expected MAE in {path} to be '{expected_mae}', got '{content}'."
PY

    test -f /home/user/analyze.c
    h5cc /home/user/analyze.c -o /tmp/analyze_verify -lgsl -lgslcblas -lm

    nm -D /tmp/analyze_verify | grep -Eq ' U gsl_linalg_SV_decomp(_mod|_jacobi)?(@|$)'
    nm -D /tmp/analyze_verify | grep -Eq ' U H5Dread(@|$)'

    cat > /tmp/trace_calls.c <<'EOF'
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <unistd.h>
#include <hdf5.h>
#include <gsl/gsl_linalg.h>

static void mark(const char *s, size_t n) {
    int fd = open("/tmp/analyze_calls.log", O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd >= 0) { write(fd, s, n); close(fd); }
}

herr_t H5Dread(hid_t d, hid_t mt, hid_t ms, hid_t fs, hid_t p, void *b) {
    static herr_t (*real_fn)(hid_t,hid_t,hid_t,hid_t,hid_t,void *);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "H5Dread");
    mark("H5Dread\n", 8);
    return real_fn(d, mt, ms, fs, p, b);
}

int gsl_linalg_SV_decomp(gsl_matrix *A, gsl_matrix *V, gsl_vector *S, gsl_vector *w) {
    static int (*real_fn)(gsl_matrix *,gsl_matrix *,gsl_vector *,gsl_vector *);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "gsl_linalg_SV_decomp");
    mark("GSL_SVD\n", 8);
    return real_fn(A, V, S, w);
}

int gsl_linalg_SV_decomp_mod(gsl_matrix *A, gsl_matrix *X, gsl_matrix *V, gsl_vector *S, gsl_vector *w) {
    static int (*real_fn)(gsl_matrix *,gsl_matrix *,gsl_matrix *,gsl_vector *,gsl_vector *);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "gsl_linalg_SV_decomp_mod");
    mark("GSL_SVD\n", 8);
    return real_fn(A, X, V, S, w);
}

int gsl_linalg_SV_decomp_jacobi(gsl_matrix *A, gsl_matrix *V, gsl_vector *S) {
    static int (*real_fn)(gsl_matrix *,gsl_matrix *,gsl_vector *);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "gsl_linalg_SV_decomp_jacobi");
    mark("GSL_SVD\n", 8);
    return real_fn(A, V, S);
}
EOF
    h5cc -shared -fPIC /tmp/trace_calls.c -o /tmp/libtrace_calls.so -ldl -lgsl -lgslcblas

    cp /home/user/sim_matrix.h5 /tmp/original_sim_matrix.h5
    cp /home/user/reference_sv.txt /tmp/original_reference_sv.txt
    cp /home/user/top_sv.txt /tmp/original_top_sv.txt
    cp /home/user/sv_error.txt /tmp/original_sv_error.txt

    python3 - <<'PY'
import h5py
import numpy as np
m = np.zeros((100, 50), dtype=np.float64)
m[0, 0] = 9.25
m[1, 1] = 5.50
m[2, 2] = 2.75
m[3, 3] = 1.25
with h5py.File('/home/user/sim_matrix.h5', 'w') as f:
    f.create_dataset('matrix_data', data=m, dtype='float64')
with open('/home/user/reference_sv.txt', 'w') as f:
    f.write('9.100000\n5.800000\n2.700000\n')
PY

    rm -f /tmp/analyze_calls.log /home/user/top_sv.txt /home/user/sv_error.txt
    (cd /home/user && LD_PRELOAD=/tmp/libtrace_calls.so /tmp/analyze_verify)

    grep -qx 'H5Dread' /tmp/analyze_calls.log
    grep -qx 'GSL_SVD' /tmp/analyze_calls.log

    python3 - <<'PY'
import os

path = '/home/user/top_sv.txt'
assert os.path.isfile(path)
with open(path) as f:
    lines = [line.rstrip('\n') for line in f]
assert lines == ['9.250000', '5.500000', '2.750000'], lines

path = '/home/user/sv_error.txt'
assert os.path.isfile(path)
with open(path) as f:
    content = f.read()
assert content == '0.166667\n' or content == '0.166667', repr(content)
PY
}

if verify; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
