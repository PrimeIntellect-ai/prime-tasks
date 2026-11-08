#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import os
import pathlib
import subprocess

SOURCE = pathlib.Path('/home/user/generate_feature.c')
EXECUTABLE = pathlib.Path('/home/user/generate_feature')
OUTPUT = pathlib.Path('/home/user/ml_dataset_feature.txt')

ORACLE_SOURCE = r'''
#include <math.h>
#include <stdio.h>

int main(void) {
    double x = 0.0;
    double next;
    do {
        double f = exp(-x) - x;
        double fp = -exp(-x) - 1.0;
        next = x - f / fp;
        if (fabs(next - x) < 1e-6) {
            x = next;
            break;
        }
        x = next;
    } while (1);

    double values[1000];
    double y1 = x;
    double y2 = 0.0;
    for (int n = 0; n < 1000; ++n) {
        values[n] = y1;
        double new_y1 = y1 + 0.01 * y2;
        double new_y2 = y2 + 0.01 * (-0.1 * y2 - sin(y1));
        y1 = new_y1;
        y2 = new_y2;
    }

    double sum = 0.0;
    double c = 0.0;
    for (int i = 0; i < 1000; ++i) {
        double y = values[i] * values[i] - c;
        double t = sum + y;
        c = (t - sum) - y;
        sum = t;
    }
    printf("Energy: %.6f\n", sum);
    return 0;
}
'''

# The probe replaces sin() with a deterministic sequence that creates one very
# large signal sample followed by small samples. This makes a hard-coded result
# fail and makes Kahan summation observably different from naive accumulation.
PROBE_SOURCE = r'''
#include <stddef.h>
static size_t call_number = 0;
double sin(double x) {
    (void)x;
    size_t n = call_number++;
    if (n == 0) return -1.0e12;
    if (n == 1) return  1.999e12;
    if (n == 2) return -0.999e12;
    return 0.0;
}
'''

def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, timeout=20, **kwargs)

def expected(oracle, env=None):
    result = run([str(oracle)], env=env, stdout=subprocess.PIPE,
                 stderr=subprocess.PIPE, text=True)
    return result.stdout.strip()

def run_submission(env, expected_text):
    if OUTPUT.exists():
        OUTPUT.unlink()
    run([str(EXECUTABLE)], cwd='/home/user', env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert OUTPUT.is_file(), (
        f'The output file {OUTPUT} was not created by the executed program.'
    )
    content = OUTPUT.read_text().strip()
    assert content == expected_text, (
        f'Expected exact output {expected_text!r}, found {content!r}.'
    )
    return content

def test_complete_implementation():
    # Preserve the original source and executable assertions.
    assert SOURCE.is_file(), (
        'The C source file /home/user/generate_feature.c does not exist.'
    )
    assert EXECUTABLE.is_file(), (
        'The executable /home/user/generate_feature does not exist. '
        'Did you compile the C program?'
    )
    assert os.access(EXECUTABLE, os.X_OK), (
        '/home/user/generate_feature is not executable.'
    )

    oracle_source = pathlib.Path('/tmp/feature_oracle.c')
    oracle = pathlib.Path('/tmp/feature_oracle')
    probe_source = pathlib.Path('/tmp/feature_probe.c')
    probe = pathlib.Path('/tmp/feature_probe.so')
    oracle_source.write_text(ORACLE_SOURCE)
    probe_source.write_text(PROBE_SOURCE)

    run(['gcc', '-O2', str(oracle_source), '-o', str(oracle), '-lm'])
    run(['gcc', '-shared', '-fPIC', '-O2', str(probe_source), '-o', str(probe)])

    # Compile the submitted source rather than trusting the preexisting binary.
    run(['gcc', '-O2', str(SOURCE), '-o', str(EXECUTABLE), '-lm'])
    assert EXECUTABLE.is_file() and os.access(EXECUTABLE, os.X_OK)
    assert EXECUTABLE.read_bytes()[:4] == b'\x7fELF', (
        '/home/user/generate_feature is not an ELF executable.'
    )

    clean_env = os.environ.copy()
    clean_env.pop('LD_PRELOAD', None)
    normal_expected = expected(oracle, clean_env)
    # Retain the original known-result assertion, now derived independently too.
    assert normal_expected == 'Energy: 147.227284'

    probe_env = clean_env.copy()
    probe_env['LD_PRELOAD'] = str(probe)
    probe_expected = expected(oracle, probe_env)
    assert probe_expected != normal_expected

    # Exercise the implementation under the probe, then rerun normally so the
    # required final artifact contains the ordinary result.
    run_submission(probe_env, probe_expected)
    final_content = run_submission(clean_env, normal_expected)
    assert 'Energy: 147.227284' in final_content
PY_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
