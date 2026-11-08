#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
from pathlib import Path

import pytest

SOURCE = Path('/home/user/etl_recommend.c')
EXECUTABLE = Path('/home/user/etl_recommend')
OUTPUT = Path('/home/user/recommendations.csv')
DATA_DIR = Path('/home/user/data')
COMPILED_COPY = Path('/tmp/etl_recommend_from_source')
BLAS_SHIM = Path('/tmp/libblas_verifier_shim.so')
BLAS_MARKER = Path('/tmp/blas_verifier_marker')


def compile_source():
    result = subprocess.run(
        ['gcc', str(SOURCE), '-o', str(COMPILED_COPY), '-lopenblas', '-lm'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, 'The submitted C source does not compile:\n' + result.stderr
    assert COMPILED_COPY.is_file() and os.access(COMPILED_COPY, os.X_OK)


def build_blas_shim():
    shim_source = Path('/tmp/blas_verifier_shim.c')
    shim_source.write_text(r'''
#include <cblas.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>

typedef void (*real_dgemv_t)(const enum CBLAS_ORDER, const enum CBLAS_TRANSPOSE,
                             const int, const int, const double,
                             const double *, const int, const double *, const int,
                             const double, double *, const int);

void cblas_dgemv(const enum CBLAS_ORDER order, const enum CBLAS_TRANSPOSE trans,
                 const int m, const int n, const double alpha,
                 const double *a, const int lda, const double *x, const int incx,
                 const double beta, double *y, const int incy) {
    const char *marker = getenv("BLAS_VERIFIER_MARKER");
    if (marker) {
        int fd = open(marker, O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (fd >= 0) {
            (void)write(fd, "1", 1);
            close(fd);
        }
    }
    real_dgemv_t real_fn = (real_dgemv_t)dlsym(RTLD_NEXT, "cblas_dgemv");
    if (!real_fn) _exit(125);
    real_fn(order, trans, m, n, alpha, a, lda, x, incx,
            beta, y, incy);
}
''')
    result = subprocess.run(
        ['gcc', '-shared', '-fPIC', str(shim_source), '-o', str(BLAS_SHIM), '-ldl'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, 'Could not build BLAS verification shim:\n' + result.stderr


def run_program(binary, expected_lines, require_blas=False):
    if OUTPUT.exists():
        OUTPUT.unlink()

    env = os.environ.copy()
    env['OPENBLAS_NUM_THREADS'] = '1'
    if require_blas:
        build_blas_shim()
        if BLAS_MARKER.exists():
            BLAS_MARKER.unlink()
        env['LD_PRELOAD'] = str(BLAS_SHIM)
        env['BLAS_VERIFIER_MARKER'] = str(BLAS_MARKER)

    result = subprocess.run(
        [str(binary)],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
        timeout=20,
    )
    assert result.returncode == 0, (
        f'{binary} exited with status {result.returncode}. stderr: {result.stderr}'
    )
    assert OUTPUT.is_file(), f'{binary} did not create {OUTPUT}'
    lines = [line.strip() for line in OUTPUT.read_text().splitlines() if line.strip()]
    assert lines == expected_lines, (
        f'Unexpected recommendations from {binary}: expected {expected_lines}, got {lines}'
    )

    if require_blas:
        assert BLAS_MARKER.is_file() and BLAS_MARKER.stat().st_size > 0, (
            f'{binary} did not call cblas_dgemv while processing valid users'
        )


def test_openblas_installed():
    """Verify that libopenblas-dev is installed."""
    try:
        result = subprocess.run(
            ['dpkg', '-s', 'libopenblas-dev'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert result.returncode == 0, 'libopenblas-dev is not installed.'
        assert 'Status: install ok installed' in result.stdout, 'libopenblas-dev is not fully installed.'
    except FileNotFoundError:
        pytest.fail('dpkg command not found, cannot verify libopenblas-dev installation.')


def test_source_code_exists():
    """Verify that the C source code exists."""
    assert os.path.isfile('/home/user/etl_recommend.c'), 'The C source file /home/user/etl_recommend.c does not exist.'


def test_executable_exists():
    """Verify that the compiled executable exists."""
    assert os.path.isfile('/home/user/etl_recommend'), 'The compiled executable /home/user/etl_recommend does not exist.'
    assert os.access('/home/user/etl_recommend', os.X_OK), '/home/user/etl_recommend is not executable.'
    with open('/home/user/etl_recommend', 'rb') as f:
        assert f.read(4) == b'\x7fELF', '/home/user/etl_recommend is not a compiled ELF executable.'


def test_source_compiles_and_links_openblas():
    compile_source()
    source_text = SOURCE.read_text(errors='replace')
    assert re.search(r'\bcblas_dgemv\s*\(', source_text), 'The source does not call cblas_dgemv.'
    linked = subprocess.run(
        ['ldd', str(COMPILED_COPY)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert linked.returncode == 0, 'Could not inspect the compiled program libraries.'
    assert 'openblas' in linked.stdout.lower(), 'The submitted source does not produce a program linked to OpenBLAS.'


def test_recommendations_output():
    """Run the executable and verify that the original recommendations are correct."""
    expected_lines = [
        '1,101',
        '2,103',
        '4,104',
        '6,102',
    ]
    run_program(EXECUTABLE, expected_lines)

    output_file = '/home/user/recommendations.csv'
    assert os.path.isfile(output_file), f'The output file {output_file} does not exist.'
    with open(output_file, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == len(expected_lines), f'Expected {len(expected_lines)} lines in output, but got {len(lines)}.'
    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch: expected '{expected}', got '{actual}'."


def test_changed_inputs_schema_projection_and_search():
    compile_source()

    paths = [DATA_DIR / 'weights.csv', DATA_DIR / 'items.csv', DATA_DIR / 'users.csv']
    backups = {p: p.read_bytes() for p in paths}
    output_backup = OUTPUT.read_bytes() if OUTPUT.exists() else None

    rng = random.SystemRandom()
    try:
        while True:
            weights = [[rng.randint(-5, 5) for _ in range(5)] for _ in range(3)]
            if all(any(v != 0 for v in row) for row in weights):
                break

        users = []
        projections = []
        used_user_ids = set()
        while len(users) < 5:
            uid = rng.randrange(10000, 90000)
            if uid in used_user_ids:
                continue
            vec = [rng.randint(-8, 8) for _ in range(5)]
            projection = [sum(weights[r][c] * vec[c] for c in range(5)) for r in range(3)]
            if projection in projections:
                continue
            used_user_ids.add(uid)
            users.append((uid, vec))
            projections.append(projection)

        item_ids = rng.sample(range(100000, 900000), len(users) + 8)
        valid_items = [(item_ids[i], projections[i]) for i in range(len(users))]
        valid_items.extend([
            (item_ids[-3], [700, -600, 500]),
            (item_ids[-2], [-800, 750, -650]),
            (item_ids[-1], [900, 900, -900]),
        ])
        rng.shuffle(valid_items)

        # Independently derive each expected nearest item from the generated matrix and items.
        expected_lines = []
        for uid, vec in users:
            projected = [sum(weights[r][c] * vec[c] for c in range(5)) for r in range(3)]
            nearest_id = min(
                valid_items,
                key=lambda item: sum((projected[k] - item[1][k]) ** 2 for k in range(3)),
            )[0]
            expected_lines.append(f'{uid},{nearest_id}')

        (DATA_DIR / 'weights.csv').write_text(
            ''.join(','.join(str(x) for x in row) + '\n' for row in weights)
        )

        # Extra-column items are placed first and exactly match projections. A parser that
        # accepts the wrong column count will choose them instead of the valid items.
        malformed_items = []
        for i, projection in enumerate(projections):
            malformed_items.append(
                f'{item_ids[len(users) + (i % 3)]},' + ','.join(map(str, projection)) + ',EXTRA'
            )
        malformed_items.extend([
            'not_an_id,1,2,3',
            '12345,1,2',
            '12346,1,not_a_number,3',
            '12347,,2,3',
        ])
        item_lines = malformed_items + [
            f"{iid},{coords[0]},{coords[1]},{coords[2]}" for iid, coords in valid_items
        ]
        (DATA_DIR / 'items.csv').write_text('\n'.join(item_lines) + '\n')

        valid_user_lines = [
            f"{uid}," + ','.join(map(str, vec)) for uid, vec in users
        ]
        user_lines = [
            'bad_id,1,2,3,4,5',
            valid_user_lines[0],
            '91001,1,2,3,4',
            valid_user_lines[1],
            '91002,1,2,3,4,5,6',
            valid_user_lines[2],
            '91003,1,2,bad,4,5',
            valid_user_lines[3],
            '91004,1,,3,4,5',
            valid_user_lines[4],
        ]
        (DATA_DIR / 'users.csv').write_text('\n'.join(user_lines) + '\n')

        # Exercise both the submitted executable and a fresh build of the submitted source.
        run_program(EXECUTABLE, expected_lines, require_blas=True)
        run_program(COMPILED_COPY, expected_lines, require_blas=True)
    finally:
        for path, contents in backups.items():
            path.write_bytes(contents)
        if output_backup is None:
            if OUTPUT.exists():
                OUTPUT.unlink()
        else:
            OUTPUT.write_bytes(output_backup)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
