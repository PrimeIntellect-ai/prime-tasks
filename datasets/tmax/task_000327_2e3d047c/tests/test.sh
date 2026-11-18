#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_task.py
import csv
import ctypes
import os
import re
import subprocess
import tempfile

LIBDIR = '/app/libstatboot-1.2'
SO_PATH = os.path.join(LIBDIR, 'libstatboot.so')
C_PATH = '/home/user/etl_pipeline.c'
CSV_PATH = '/home/user/sensor_data.csv'
RESULT_PATH = '/home/user/bootstrap_result.txt'

# Preserve the original verifier's assertions.
assert os.path.isfile(SO_PATH), f"Shared library {SO_PATH} does not exist. Did you fix the Makefile and compile?"
assert os.path.isfile(C_PATH), f"Source file {C_PATH} does not exist."
assert os.path.isfile(RESULT_PATH), f"Output file {RESULT_PATH} does not exist. Did you run your pipeline?"
assert os.path.isfile(CSV_PATH), f"Data file {CSV_PATH} is missing."

valid_temps = []
with open(CSV_PATH, 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        temp_str = row.get('temperature', '').strip()
        if not temp_str:
            continue
        try:
            temp = float(temp_str)
        except ValueError:
            continue
        if -50.0 <= temp <= 100.0:
            valid_temps.append(temp)

assert valid_temps, 'No valid temperatures found in the dataset to compute expected mean.'
expected_mean = sum(valid_temps) / len(valid_temps)
with open(RESULT_PATH, 'r') as f:
    agent_val_str = f.read().strip()
try:
    agent_val = float(agent_val_str)
except ValueError as exc:
    raise AssertionError(f"Could not parse the result in {RESULT_PATH} as a float. Found: '{agent_val_str}'") from exc

diff = abs(agent_val - expected_mean)
assert diff <= 0.5, (
    'Computed bootstrap mean is inaccurate.\n'
    f'Agent value: {agent_val}\nReference mean: {expected_mean}\n'
    f'Absolute difference: {diff} (Threshold is <= 0.5)'
)

# The repaired Makefile must really rebuild a loadable shared library.
subprocess.run(['make', 'clean'], cwd=LIBDIR, check=True, timeout=30)
subprocess.run(['make', 'all'], cwd=LIBDIR, check=True, timeout=30)
assert os.path.isfile(SO_PATH), 'make did not produce libstatboot.so'
elf_info = subprocess.run(
    ['readelf', '-h', SO_PATH], text=True, stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT, check=True, timeout=10
).stdout
assert 'DYN (Shared object file)' in elf_info, 'libstatboot.so is not an ELF shared object'
lib = ctypes.CDLL(SO_PATH)
assert hasattr(lib, 'compute_bootstrap_mean'), 'libstatboot.so does not export compute_bootstrap_mean'

# Compile the submitted source and require a dynamic dependency on the rebuilt library.
exe_path = '/tmp/etl_pipeline_verified'
subprocess.run([
    'gcc', C_PATH, '-I', LIBDIR, '-L', LIBDIR,
    '-Wl,-rpath,' + LIBDIR, '-o', exe_path, '-lstatboot'
], check=True, timeout=30)
assert os.path.isfile(exe_path) and os.access(exe_path, os.X_OK), 'Submitted C source did not produce an executable'
dynamic_info = subprocess.run(
    ['readelf', '-d', exe_path], text=True, stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT, check=True, timeout=10
).stdout
assert re.search(r'NEEDED.*\[libstatboot\.so\]', dynamic_info), (
    'The compiled ETL program is not dynamically linked against libstatboot.so'
)

# Interpose the required function while exercising fresh datasets. This verifies that
# the executable passes the cleaned array and num_samples=10000, rather than merely
# writing a precomputed answer.
shim_source = r'''
#include <stdio.h>
#include <stdlib.h>

static double absdiff(double a, double b) {
    double d = a - b;
    return d < 0 ? -d : d;
}

double compute_bootstrap_mean(double *data, int n, int num_samples) {
    const char *expected_text = getenv("VERIFY_EXPECTED");
    const char *return_text = getenv("VERIFY_RETURN");
    const char *log_path = getenv("VERIFY_LOG");
    double expected[256];
    int used[256] = {0};
    int count = 0;
    int ok = expected_text && return_text && log_path && data;

    if (expected_text) {
        const char *p = expected_text;
        while (*p && count < 256) {
            char *end = NULL;
            expected[count] = strtod(p, &end);
            if (end == p) { ok = 0; break; }
            count++;
            if (*end == ',') p = end + 1;
            else if (*end == '\0') p = end;
            else { ok = 0; break; }
        }
    }

    if (n != count || num_samples != 10000) ok = 0;
    if (ok) {
        for (int i = 0; i < n; i++) {
            int found = -1;
            for (int j = 0; j < count; j++) {
                if (!used[j] && absdiff(data[i], expected[j]) <= 1e-9) {
                    found = j;
                    break;
                }
            }
            if (found < 0) { ok = 0; break; }
            used[found] = 1;
        }
    }

    if (log_path) {
        FILE *f = fopen(log_path, "a");
        if (f) {
            fprintf(f, "%s n=%d samples=%d\n", ok ? "OK" : "BAD", n, num_samples);
            fclose(f);
        }
    }
    return return_text ? strtod(return_text, NULL) : 0.0;
}
'''
with tempfile.TemporaryDirectory() as td:
    shim_c = os.path.join(td, 'audit_statboot.c')
    shim_so = os.path.join(td, 'audit_statboot.so')
    log_path = os.path.join(td, 'calls.log')
    with open(shim_c, 'w') as f:
        f.write(shim_source)
    subprocess.run(['gcc', '-shared', '-fPIC', shim_c, '-o', shim_so], check=True, timeout=30)

    original_csv = open(CSV_PATH, 'rb').read()
    original_result = open(RESULT_PATH, 'rb').read()
    cases = [
        (
            'timestamp,temperature\n1,10.0\n2,\n3,-50.0\n4,100.0\n5,100.1\n6,-50.1\n',
            [10.0, -50.0, 100.0],
            '17.4321'
        ),
        (
            'timestamp,temperature\n10,1.25\n11,999.0\n12,2.5\n13,\n14,3.75\n',
            [1.25, 2.5, 3.75],
            '-4.25'
        ),
    ]
    try:
        for csv_text, expected, return_value in cases:
            with open(CSV_PATH, 'w') as f:
                f.write(csv_text)
            if os.path.exists(RESULT_PATH):
                os.remove(RESULT_PATH)
            if os.path.exists(log_path):
                os.remove(log_path)

            env = os.environ.copy()
            env['LD_LIBRARY_PATH'] = LIBDIR
            env['LD_PRELOAD'] = shim_so
            env['VERIFY_EXPECTED'] = ','.join(repr(x) for x in expected)
            env['VERIFY_RETURN'] = return_value
            env['VERIFY_LOG'] = log_path
            subprocess.run([exe_path], cwd='/home/user', env=env, check=True, timeout=30)

            assert os.path.isfile(RESULT_PATH), 'Executed pipeline did not create bootstrap_result.txt'
            with open(log_path, 'r') as f:
                calls = [line.strip() for line in f if line.strip()]
            assert calls and all(line.startswith('OK ') for line in calls), (
                'Pipeline did not call compute_bootstrap_mean with the cleaned data and num_samples=10000'
            )
            assert len(calls) == 1, 'Pipeline must call compute_bootstrap_mean once per run'

            with open(RESULT_PATH, 'r') as f:
                rendered = f.read().strip()
            assert re.fullmatch(r'[+-]?\d+\.\d{4}', rendered), 'Result is not formatted to exactly 4 decimal places'
            assert rendered == f'{float(return_value):.4f}', (
                'Pipeline did not write the value returned by compute_bootstrap_mean'
            )
    finally:
        with open(CSV_PATH, 'wb') as f:
            f.write(original_csv)
        with open(RESULT_PATH, 'wb') as f:
            f.write(original_result)
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
