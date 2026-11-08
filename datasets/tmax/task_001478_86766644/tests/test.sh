#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import ctypes
import math
import os
import shutil
import stat
import subprocess
from pathlib import Path

HOME = Path('/home/user')
LIB = HOME / 'libintegrator.so'
SOURCE = HOME / 'integrator.c'
DATA = HOME / 'data.csv'
RESULT = HOME / 'result.txt'
LOG = Path('/tmp/integrator_calls.log')


def read_result():
    assert RESULT.is_file(), f'Result file not found: {RESULT}'
    content = RESULT.read_text().strip()
    assert content == '2.50', f"Incorrect result. Expected '2.50', got '{content}'"


def test_01_libintegrator_so_exists():
    assert LIB.is_file(), f'Shared library not found: {LIB}'
    with LIB.open('rb') as f:
        magic = f.read(4)
    assert magic == b'\x7fELF', f'File {LIB} is not a valid ELF shared object.'


def test_02_result_txt_content():
    read_result()


def expected_integral(x, step):
    if step >= 0.1:
        return math.inf
    total = 0.0
    t = 0.0
    while t < x:
        total += math.exp(-t * t) * step
        t += step
    return total


def test_03_shared_object_implements_supplied_integrator():
    try:
        library = ctypes.CDLL(str(LIB))
        integrate = library.integrate
    except Exception as exc:
        raise AssertionError(f'{LIB} is not a loadable shared library exporting integrate: {exc}')

    integrate.argtypes = [ctypes.c_double, ctypes.c_double]
    integrate.restype = ctypes.c_double

    for x, step in [(0.0, 0.01), (0.23, 0.05), (0.71, 0.02), (1.13, 0.007)]:
        actual = integrate(x, step)
        expected = expected_integral(x, step)
        assert math.isfinite(actual)
        assert math.isclose(actual, expected, rel_tol=2e-12, abs_tol=2e-12), \
            f'integrate({x}, {step}) returned {actual}, expected {expected}'

    assert math.isinf(integrate(0.5, 0.1)), 'The compiled library does not preserve the source instability threshold'
    assert math.isinf(integrate(0.5, 0.5)), 'The compiled library does not preserve the source behavior at step_size=0.5'


def candidate_scripts():
    candidates = []
    excluded = {SOURCE.resolve(), DATA.resolve(), RESULT.resolve()}
    for path in HOME.rglob('*'):
        if not path.is_file() or path.resolve() in excluded or path == LIB:
            continue
        try:
            if path.stat().st_size > 2_000_000:
                continue
            raw = path.read_bytes()
            if b'\x00' in raw:
                continue
            text = raw.decode('utf-8')
        except (OSError, UnicodeDecodeError):
            continue

        lower = text.lower()
        # The optimization script itself must reference both the C integration
        # artifact/API and the dataset it optimizes.
        has_library_call = ('libintegrator' in lower or 'integrate' in lower) and (
            'ctypes' in lower or 'cdll' in lower or 'ffi' in lower or 'dlopen' in lower
        )
        has_data = 'data.csv' in lower or 'read_csv' in lower
        if not (has_library_call and has_data):
            continue

        score = sum(token in lower for token in ('optimize', 'minimize', 'mse', 'step_size', 'converg'))
        candidates.append((-score, str(path), text))
    candidates.sort(key=lambda item: (item[0], item[1]))
    return candidates


def command_for(path, text):
    p = Path(path)
    first = text.splitlines()[0] if text.splitlines() else ''
    if p.suffix == '.py' or 'python' in first:
        return ['python3', path]
    if p.suffix in ('.sh', '.bash') or 'sh' in first:
        return ['bash', path]
    if os.access(path, os.X_OK):
        return [path]
    return None


def write_instrumented_source():
    SOURCE.write_text(r'''#include <math.h>
#include <stdio.h>
#include <stdlib.h>

double integrate(double x, double step_size) {
    const char *log_path = getenv("INTEGRATOR_CALL_LOG");
    if (log_path) {
        FILE *f = fopen(log_path, "a");
        if (f) {
            fprintf(f, "%.17g,%.17g\n", x, step_size);
            fclose(f);
        }
    }
    if (step_size >= 0.1) return INFINITY;
    double sum = 0.0;
    for (double t = 0.0; t < x; t += step_size)
        sum += exp(-t * t) * step_size;
    return sum;
}
''')
    subprocess.run(
        ['gcc', '-shared', '-fPIC', '-O2', '-o', str(LIB), str(SOURCE), '-lm'],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )


def calls_show_convergence_and_optimization():
    assert LOG.is_file(), 'The executed script never called the compiled integrate function'
    calls = []
    for line in LOG.read_text().splitlines():
        try:
            x, step = map(float, line.split(','))
            calls.append((x, step))
        except ValueError:
            pass
    assert len(calls) >= 20, 'Too few C integration calls to demonstrate an optimization run'
    steps = {round(step, 12) for _, step in calls}
    assert len(steps) >= 2, 'No convergence test using multiple step sizes was observed'
    assert any(0.0 < step < 0.1 for _, step in calls), 'No stable step size below 0.1 was used'
    xs = {round(x, 8) for x, _ in calls}
    assert len(xs) >= 5, 'The C integrator was not exercised over the dataset/model inputs'


def run_candidate(path, text, expected):
    command = command_for(path, text)
    if command is None:
        return False, 'not an executable supported script'
    RESULT.unlink(missing_ok=True)
    LOG.unlink(missing_ok=True)
    env = os.environ.copy()
    env['HOME'] = str(HOME)
    env['INTEGRATOR_CALL_LOG'] = str(LOG)
    try:
        completed = subprocess.run(
            command, cwd=str(HOME), env=env, timeout=90,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
    except Exception as exc:
        return False, str(exc)
    if completed.returncode != 0:
        return False, f'exited {completed.returncode}: {completed.stderr[-500:]}'
    if not RESULT.is_file() or RESULT.read_text().strip() != expected:
        got = RESULT.read_text().strip() if RESULT.is_file() else '<missing>'
        return False, f'produced {got}, expected {expected}'
    try:
        calls_show_convergence_and_optimization()
    except AssertionError as exc:
        return False, str(exc)
    return True, ''


def test_04_script_executes_library_convergence_and_optimization():
    candidates = candidate_scripts()
    assert candidates, 'No optimization script that loads libintegrator.so and reads data.csv was found'

    source_backup = SOURCE.read_bytes()
    lib_backup = LIB.read_bytes()
    data_backup = DATA.read_bytes()
    result_backup = RESULT.read_bytes() if RESULT.exists() else None
    failures = []
    accepted = None

    try:
        # Keep y fixed but double every x. The same model arguments are then
        # obtained at half the original optimum, so the derived answer is 1.25.
        rows = list(csv.DictReader(data_backup.decode().splitlines()))
        hidden = ['x,y']
        for row in rows:
            hidden.append(f"{float(row['x']) * 2.0:.12g},{row['y']}")
        hidden_data = ('\n'.join(hidden) + '\n').encode()

        for _, path, text in candidates:
            SOURCE.write_bytes(source_backup)
            DATA.write_bytes(hidden_data)
            write_instrumented_source()
            ok, reason = run_candidate(path, text, '1.25')
            if ok:
                accepted = (path, text)
                break
            failures.append(f'{path}: {reason}')

        assert accepted is not None, 'No script correctly optimized the derived dataset and called the C library. ' + '; '.join(failures)

        # Run the accepted artifact on the real dataset and require it to
        # regenerate the originally asserted answer as well.
        DATA.write_bytes(data_backup)
        SOURCE.write_bytes(source_backup)
        write_instrumented_source()
        ok, reason = run_candidate(accepted[0], accepted[1], '2.50')
        assert ok, f'The optimization script failed on the supplied dataset: {reason}'
    finally:
        SOURCE.write_bytes(source_backup)
        LIB.write_bytes(lib_backup)
        DATA.write_bytes(data_backup)
        LOG.unlink(missing_ok=True)
        if accepted is None:
            if result_backup is None:
                RESULT.unlink(missing_ok=True)
            else:
                RESULT.write_bytes(result_backup)

    read_result()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
