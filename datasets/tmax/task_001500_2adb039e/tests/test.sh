#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import pathlib
import random
import shutil
import stat
import subprocess
import tempfile

HOME = pathlib.Path('/home/user')
EXPECTED_INITIAL = [
    '1 + 1 = 2.0',
    '10 + 20 = 30.0',
    '100 + 200 = 300.0',
]


def read_nonempty_results():
    path = HOME / 'results.log'
    assert path.is_file(), f'Results log {path} is missing. Did you execute your Rust program?'
    return [line.strip() for line in path.read_text().splitlines() if line.strip()]


def test_libcalc_so_exists():
    path = HOME / 'libcalc.so'
    assert path.is_file(), f'Shared library {path} is missing. Did you compile calc.c?'


def test_processor_rs_exists():
    path = HOME / 'processor.rs'
    assert path.is_file(), f'Rust source file {path} is missing.'


def test_results_log_exists():
    path = HOME / 'results.log'
    assert path.is_file(), f'Results log {path} is missing. Did you execute your Rust program?'


def test_results_log_content():
    lines = read_nonempty_results()
    assert len(lines) == len(EXPECTED_INITIAL), (
        f'Expected {len(EXPECTED_INITIAL)} lines in results.log, but found {len(lines)}. '
        'Check your rate limiting and validation logic.'
    )
    for i, (actual, expected) in enumerate(zip(lines, EXPECTED_INITIAL)):
        assert actual == expected, (
            f"Line {i + 1} in results.log does not match expected output. "
            f"Expected '{expected}', got '{actual}'."
        )


def test_compiled_artifacts_and_dynamic_execution():
    calc_path = HOME / 'calc.c'
    requests_path = HOME / 'requests.txt'
    lib_path = HOME / 'libcalc.so'
    source_path = HOME / 'processor.rs'
    results_path = HOME / 'results.log'

    expected_calc = b'''#include <stdio.h>\n#include <stdlib.h>\n\ndouble evaluate_addition(const char* expr) {\n    int a = 0, b = 0;\n    if (sscanf(expr, "%d + %d", &a, &b) == 2) {\n        return (double)(a + b);\n    }\n    return 0.0;\n}\n'''
    expected_requests = b'''1 + 1\n# This is a comment\n10 + 20\n100 + 200\n1000 + 20000000 # Invalid: longer than 15 characters\n5 + 5\n8 + 8\n'''
    assert calc_path.read_bytes() == expected_calc, '/home/user/calc.c was modified.'
    assert requests_path.read_bytes() == expected_requests, '/home/user/requests.txt was modified.'
    assert lib_path.read_bytes().startswith(b'\x7fELF'), 'libcalc.so is not an ELF shared library.'

    # Exercise the submitted shared library on values selected only at verification time.
    lib = ctypes.CDLL(str(lib_path))
    evaluate = lib.evaluate_addition
    evaluate.argtypes = [ctypes.c_char_p]
    evaluate.restype = ctypes.c_double
    rng = random.SystemRandom()
    for _ in range(8):
        a = rng.randint(-50000, 50000)
        b = rng.randint(-50000, 50000)
        expression = f'{a} + {b}'.encode()
        assert evaluate(expression) == float(a + b), (
            f'libcalc.so returned the wrong result for {expression!r}.'
        )

    executable = pathlib.Path('/tmp/processor_verified')
    compile_result = subprocess.run(
        ['rustc', str(source_path), '-L', f'native={HOME}', '-o', str(executable)],
        cwd=str(HOME), text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert compile_result.returncode == 0, f'processor.rs did not compile with rustc:\n{compile_result.stdout}'
    assert executable.is_file(), 'rustc did not produce the processor executable.'

    dynamic_info = subprocess.run(
        ['readelf', '-d', str(executable)], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10,
    )
    assert dynamic_info.returncode == 0, f'Could not inspect the Rust executable:\n{dynamic_info.stdout}'
    assert 'libcalc.so' in dynamic_info.stdout, 'The Rust executable is not linked against libcalc.so.'

    env = os.environ.copy()
    env['LD_LIBRARY_PATH'] = str(HOME)

    # Re-run the compiled program on the original files, rather than trusting a prewritten log.
    if results_path.exists():
        results_path.unlink()
    run = subprocess.run(
        [str(executable)], cwd=str(HOME), env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15,
    )
    assert run.returncode == 0, f'The compiled Rust processor failed:\n{run.stdout}'
    assert read_nonempty_results() == EXPECTED_INITIAL, 'Executing the Rust processor produced incorrect original results.'

    saved_requests = requests_path.read_bytes()
    saved_library = lib_path.read_bytes()
    saved_library_mode = stat.S_IMODE(lib_path.stat().st_mode)
    saved_results = results_path.read_bytes() if results_path.exists() else None

    try:
        # Build a verifier-only replacement library with deliberately different semantics.
        # Correct output therefore requires the Rust executable to use its C FFI return value.
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = pathlib.Path(temp_dir)
            sentinel_c = temp / 'sentinel.c'
            sentinel_so = temp / 'libcalc.so'
            sentinel_c.write_text(r'''#include <stdio.h>
double evaluate_addition(const char *expr) {
    long a = 0, b = 0;
    if (sscanf(expr, "%ld + %ld", &a, &b) == 2)
        return (double)(a + b) + 1000.5;
    return -7777.5;
}
''')
            build = subprocess.run(
                ['gcc', '-shared', '-fPIC', str(sentinel_c), '-o', str(sentinel_so)],
                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20,
            )
            assert build.returncode == 0, f'Verifier could not build its test library:\n{build.stdout}'
            shutil.copyfile(sentinel_so, lib_path)
            os.chmod(lib_path, saved_library_mode)

        values = [(rng.randint(10, 99), rng.randint(10, 99)) for _ in range(4)]
        valid_lines = [f'{a} + {b}' for a, b in values]
        assert all(len(line) <= 15 for line in valid_lines)
        long_line = '7 + 8 # too long'
        assert len(long_line) > 15
        requests_path.write_text(
            '# verifier comment\n'
            + long_line + '\n'
            + valid_lines[0] + '\n'
            + '# another comment\n'
            + valid_lines[1] + '\n'
            + valid_lines[2] + '\n'
            + valid_lines[3] + '\n'
        )
        if results_path.exists():
            results_path.unlink()

        run = subprocess.run(
            [str(executable)], cwd=str(HOME), env=env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15,
        )
        assert run.returncode == 0, f'The processor failed on verifier-generated requests:\n{run.stdout}'
        actual = read_nonempty_results()
        expected = [
            f'{valid_lines[i]} = {values[i][0] + values[i][1] + 1000.5:.1f}'
            for i in range(3)
        ]
        assert actual == expected, (
            'Verifier-generated execution failed FFI use, validation, formatting, or the three-request limit. '
            f'Expected {expected!r}, got {actual!r}.'
        )
    finally:
        requests_path.write_bytes(saved_requests)
        lib_path.write_bytes(saved_library)
        os.chmod(lib_path, saved_library_mode)
        if saved_results is None:
            if results_path.exists():
                results_path.unlink()
        else:
            results_path.write_bytes(saved_results)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
