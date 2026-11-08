#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
from pathlib import Path

import pytest

SOURCE = Path('/home/user/compute_negatives.c')
SCRIPT = Path('/home/user/track_experiment.sh')
EMBEDDINGS = Path('/home/user/data/embeddings.csv')
OUTPUT = Path('/home/user/data/hard_negatives.csv')
LOG = Path('/home/user/experiment.log')

ORIGINAL_INPUT = '''id,v1,v2,v3
1,1.0,0.0,0.0
2,0.9,0.1,0.0
3,0.0,1.0,0.0
4,0.0,0.9,0.1
'''

DYNAMIC_INPUT = '''id,v1,v2,v3
10,-0.2,0.5,1.1
2,1.0,0.2,-0.1
20,-1.0,0.1,0.2
7,0.4,1.0,0.3
'''


def run(command, **kwargs):
    return subprocess.run(
        command,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
        **kwargs,
    )


def expected_output(csv_text):
    lines = [line.strip() for line in csv_text.strip().splitlines()]
    rows = []
    for line in lines[1:]:
        fields = line.split(',')
        rows.append((int(fields[0]), [float(x) for x in fields[1:]]))

    result = ['id,hard_negative_id,score']
    for item_id, vector in sorted(rows):
        candidates = []
        for other_id, other_vector in rows:
            if other_id == item_id:
                continue
            score = sum(a * b for a, b in zip(vector, other_vector))
            candidates.append((score, other_id))
        score, other_id = max(candidates, key=lambda value: value[0])
        result.append(f'{item_id},{other_id},{score:.4f}')
    return '\n'.join(result)


def clean_generated_files():
    for path in (OUTPUT, LOG):
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def test_submission_end_to_end():
    # Preserve the original artifact assertions.
    assert SOURCE.exists(), f'The file {SOURCE} is missing.'
    assert SOURCE.is_file(), f'The path {SOURCE} is not a file.'
    assert SCRIPT.exists(), f'The file {SCRIPT} is missing.'
    assert SCRIPT.is_file(), f'The path {SCRIPT} is not a file.'
    assert bool(os.stat(SCRIPT).st_mode & stat.S_IXUSR), f'The file {SCRIPT} is not executable.'

    # Execute the requested script from a clean state on the original input.
    EMBEDDINGS.write_text(ORIGINAL_INPUT)
    clean_generated_files()
    run([str(SCRIPT)], cwd='/home/user')

    assert OUTPUT.exists(), f'The file {OUTPUT} is missing.'
    expected_original = (
        'id,hard_negative_id,score\n'
        '1,2,0.9000\n'
        '2,1,0.9000\n'
        '3,4,0.9000\n'
        '4,3,0.9000'
    )
    content = OUTPUT.read_text().strip()
    assert content == expected_original, (
        f'The content of {OUTPUT} is incorrect. Expected:\n'
        f'{expected_original}\nGot:\n{content}'
    )

    assert LOG.exists(), f'The file {LOG} is missing.'
    expected_line = '[Experiment CL-01] AvgScore=0.9000'
    lines = LOG.read_text().splitlines(True)
    assert any(expected_line in line for line in lines), (
        f"The file {LOG} does not contain the expected line: '{expected_line}'"
    )

    # Compile the submitted C source independently and verify that the resulting
    # executable imports and actually calls cblas_ddot.
    executable = Path('/tmp/submitted_compute_negatives')
    run([
        'gcc', str(SOURCE), '-O0', '-o', str(executable),
        '-lopenblas', '-lm'
    ])
    symbols = run(['nm', '-D', str(executable)]).stdout
    assert re.search(r'\b[Uw]\s+cblas_ddot(?:@|$)', symbols, re.MULTILINE), (
        'The compiled C program does not reference cblas_ddot.'
    )

    audit_source = Path('/tmp/cblas_audit.c')
    audit_library = Path('/tmp/libcblas_audit.so')
    audit_marker = Path('/tmp/cblas_ddot_called')
    audit_source.write_text(r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

typedef double (*ddot_fn)(const int, const double *, const int,
                          const double *, const int);

double cblas_ddot(const int n, const double *x, const int incx,
                  const double *y, const int incy) {
    static ddot_fn real_ddot = NULL;
    if (!real_ddot) real_ddot = (ddot_fn)dlsym(RTLD_NEXT, "cblas_ddot");
    const char *marker = getenv("CBLAS_AUDIT_MARKER");
    if (marker) {
        FILE *f = fopen(marker, "a");
        if (f) { fputs("called\n", f); fclose(f); }
    }
    if (!real_ddot) abort();
    return real_ddot(n, x, incx, y, incy);
}
''')
    run(['gcc', '-shared', '-fPIC', str(audit_source), '-o', str(audit_library), '-ldl'])

    EMBEDDINGS.write_text(DYNAMIC_INPUT)
    try:
        OUTPUT.unlink()
    except FileNotFoundError:
        pass
    try:
        audit_marker.unlink()
    except FileNotFoundError:
        pass

    env = os.environ.copy()
    env['LD_PRELOAD'] = str(audit_library)
    env['CBLAS_AUDIT_MARKER'] = str(audit_marker)
    run([str(executable)], cwd='/home/user', env=env)

    assert audit_marker.exists() and audit_marker.read_text().strip(), (
        'The compiled C program did not call cblas_ddot while computing the result.'
    )
    expected_dynamic = expected_output(DYNAMIC_INPUT)
    assert OUTPUT.exists(), 'The compiled C program did not create hard_negatives.csv.'
    assert OUTPUT.read_text().strip() == expected_dynamic

    # Run the submitted script again on unseen data. This ensures the script
    # performs the end-to-end work rather than relying on pre-created files.
    clean_generated_files()
    run([str(SCRIPT)], cwd='/home/user')
    assert OUTPUT.exists(), 'track_experiment.sh did not create hard_negatives.csv.'
    assert OUTPUT.read_text().strip() == expected_dynamic

    output_lines = expected_dynamic.splitlines()[1:]
    average = sum(float(line.rsplit(',', 1)[1]) for line in output_lines) / len(output_lines)
    expected_dynamic_log = f'[Experiment CL-01] AvgScore={average:.4f}'
    assert LOG.exists(), 'track_experiment.sh did not create experiment.log.'
    assert any(line.strip() == expected_dynamic_log for line in LOG.read_text().splitlines()), (
        f'experiment.log does not contain the expected line {expected_dynamic_log!r}'
    )

    # Every emitted score must have exactly four digits after the decimal point.
    for line in OUTPUT.read_text().strip().splitlines()[1:]:
        assert re.fullmatch(r'-?\d+\.\d{4}', line.rsplit(',', 1)[1])
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
