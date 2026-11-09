#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import base64
import ctypes
import json
import math
import os
import shutil
import stat
import subprocess
import tempfile
from pathlib import Path

import pytest

HOME = Path('/home/user')
ENGINE = HOME / 'engine'
LIB_RS = ENGINE / 'src/lib.rs'
SO = ENGINE / 'target/release/libengine.so'
API = HOME / 'api_test.py'
CI = HOME / 'ci_run.sh'
DATA = HOME / 'data.txt'
REPORT = HOME / 'benchmark_report.json'


def expected_rle(text):
    if not text:
        return ''
    out = []
    previous = text[0]
    count = 1
    for character in text[1:]:
        if character == previous:
            count += 1
        else:
            out.append(previous + str(count))
            previous = character
            count = 1
    out.append(previous + str(count))
    return ''.join(out)


def read_and_check_report():
    assert REPORT.is_file(), f'{REPORT} was not created.'
    try:
        data = json.loads(REPORT.read_text(encoding='utf-8'))
    except json.JSONDecodeError:
        pytest.fail(f'{REPORT} does not contain valid JSON.')

    # Preserve the original report assertions.
    assert 'match' in data, "JSON missing 'match' key."
    assert data['match'] is True, "'match' key in JSON is not true."
    assert 'rust_time' in data, "JSON missing 'rust_time' key."
    assert isinstance(data['rust_time'], (int, float)), "'rust_time' is not a number."
    assert 'python_time' in data, "JSON missing 'python_time' key."
    assert isinstance(data['python_time'], (int, float)), "'python_time' is not a number."

    assert set(data) == {'match', 'rust_time', 'python_time'}
    for key in ('rust_time', 'python_time'):
        assert not isinstance(data[key], bool)
        assert math.isfinite(data[key]) and data[key] >= 0
    return data


def test_submission_end_to_end():
    # Preserve the original file/source assertions.
    assert LIB_RS.is_file(), f'{LIB_RS} is missing.'
    source = LIB_RS.read_text(encoding='utf-8')
    assert 'into_raw' in source or 'as_ptr' not in source, (
        'The Rust bug in lib.rs does not appear to be fixed '
        '(still returning a dropped pointer instead of transferring ownership).'
    )
    assert API.is_file(), f'{API} is missing.'
    assert CI.is_file(), f'{CI} is missing.'
    assert os.access(CI, os.X_OK), f'{CI} is not executable.'

    # Verify that ctypes argument and return types are actually configured.
    tree = ast.parse(API.read_text(encoding='utf-8'), filename=str(API))
    assigned_attrs = {
        node.targets[0].attr
        for node in ast.walk(tree)
        if isinstance(node, ast.Assign)
        and len(node.targets) == 1
        and isinstance(node.targets[0], ast.Attribute)
    }
    assert 'argtypes' in assigned_attrs, 'api_test.py does not configure ctypes argtypes.'
    assert 'restype' in assigned_attrs, 'api_test.py does not configure ctypes restype.'

    # A site hook records that the CI script really invokes api_test.py.
    hook_dir = Path(tempfile.mkdtemp(prefix='verifier_hook_'))
    marker = hook_dir / 'ci_api_invoked'
    (hook_dir / 'sitecustomize.py').write_text(r'''
import atexit
import os
import sys

marker = os.environ.get('VERIFIER_CI_MARKER')
if marker and os.path.basename(sys.argv[0]) == 'api_test.py':
    open(marker, 'a').close()

expected_b64 = os.environ.get('VERIFIER_EXPECTED_B64')
counts = {}
if expected_b64:
    import base64
    expected = base64.b64decode(expected_b64).decode('utf-8')
    api_path = os.path.realpath('/home/user/api_test.py')
    def profile(frame, event, arg):
        if (event == 'return' and isinstance(arg, str) and arg == expected
                and os.path.realpath(frame.f_code.co_filename) == api_path
                and frame.f_code.co_name != '<module>'):
            counts[frame.f_code] = counts.get(frame.f_code, 0) + 1
        return profile
    sys.setprofile(profile)
    def finish():
        destination = os.environ.get('VERIFIER_PY_COUNT')
        if destination:
            with open(destination, 'w') as output:
                output.write(str(max(counts.values(), default=0)))
    atexit.register(finish)
''', encoding='utf-8')

    env = os.environ.copy()
    env['PYTHONPATH'] = str(hook_dir) + os.pathsep + env.get('PYTHONPATH', '')
    env['VERIFIER_CI_MARKER'] = str(marker)

    # Remove prior products, so success requires producing a real release build
    # and a fresh report rather than relying on setup artifacts.
    shutil.rmtree(ENGINE / 'target', ignore_errors=True)
    REPORT.unlink(missing_ok=True)
    result = subprocess.run(['/bin/bash', str(CI)], cwd=str(HOME), env=env,
                            capture_output=True, text=True, timeout=180)
    assert result.returncode == 0, (
        f'{CI} failed with exit code {result.returncode}. Stderr: {result.stderr}'
    )
    assert marker.exists(), 'ci_run.sh did not run api_test.py.'
    assert SO.is_file(), 'ci_run.sh did not produce the release shared library.'
    assert SO.read_bytes()[:4] == b'\x7fELF', 'Release output is not an ELF shared library.'
    read_and_check_report()

    # CI must propagate failure from the Python integration step.
    api_bytes = API.read_bytes()
    api_mode = stat.S_IMODE(API.stat().st_mode)
    try:
        API.write_text('raise SystemExit(7)\n', encoding='utf-8')
        failed = subprocess.run(['/bin/bash', str(CI)], cwd=str(HOME), env=env,
                                capture_output=True, text=True, timeout=180)
        assert failed.returncode != 0, 'ci_run.sh ignores failure from api_test.py.'
    finally:
        API.write_bytes(api_bytes)
        os.chmod(API, api_mode)

    # Exercise the compiled Rust artifact on verifier-derived UTF-8 cases.
    rust = ctypes.CDLL(str(SO))
    encode = rust.encode_rle
    encode.argtypes = [ctypes.c_char_p]
    encode.restype = ctypes.c_void_p
    cases = [
        '', 'aaabbc', '🔥🔥🔥❄️❄️', 'ééé中中x',
        'abababab', 'Z' * 137 + '🙂' * 23 + '\n\n'
    ]
    retained = []
    for text in cases:
        pointer = encode(text.encode('utf-8'))
        assert pointer, 'encode_rle returned a null pointer.'
        retained.append((pointer, expected_rle(text).encode('utf-8')))
    # Make many additional calls before reading old pointers. A returned pointer
    # into a dropped CString is normally reused/overwritten and fails this check.
    for i in range(300):
        text = chr(65 + i % 26) * (1 + i % 31) + '🔥' * (i % 7)
        pointer = encode(text.encode('utf-8'))
        assert pointer
        assert ctypes.string_at(pointer).decode('utf-8') == expected_rle(text)
    for pointer, expected in retained:
        assert ctypes.string_at(pointer) == expected, 'Returned Rust string does not retain ownership.'

    # Build a counting replacement with the same ABI. Running api_test.py against
    # it proves that the script calls the Rust function for the benchmark rather
    # than merely fabricating JSON.
    real_library = SO.read_bytes()
    real_mode = stat.S_IMODE(SO.stat().st_mode)
    counter = hook_dir / 'rust_calls'
    shim_c = hook_dir / 'shim.c'
    shim_so = hook_dir / 'libengine.so'
    shim_c.write_text(r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static size_t unit_len(const unsigned char *p) {
    if (*p < 0x80) return 1;
    if ((*p & 0xE0) == 0xC0) return 2;
    if ((*p & 0xF0) == 0xE0) return 3;
    if ((*p & 0xF8) == 0xF0) return 4;
    return 1;
}

char *encode_rle(const char *input) {
    const char *counter = getenv("VERIFIER_RUST_COUNTER");
    if (counter) {
        FILE *f = fopen(counter, "a");
        if (f) { fputs("1\n", f); fclose(f); }
    }
    if (!input) return NULL;
    size_t length = strlen(input), capacity = length * 3 + 64, used = 0;
    char *result = malloc(capacity);
    if (!result) return NULL;
    const unsigned char *p = (const unsigned char *)input;
    while (*p) {
        size_t width = unit_len(p), count = 1;
        const unsigned char *next = p + width;
        while (*next && unit_len(next) == width && memcmp(p, next, width) == 0) {
            count++; next += width;
        }
        char number[64];
        int digits = snprintf(number, sizeof(number), "%zu", count);
        while (used + width + (size_t)digits + 1 > capacity) {
            capacity *= 2;
            result = realloc(result, capacity);
            if (!result) return NULL;
        }
        memcpy(result + used, p, width); used += width;
        memcpy(result + used, number, (size_t)digits); used += (size_t)digits;
        p = next;
    }
    result[used] = '\0';
    return result;
}
''', encoding='utf-8')
    compiled = subprocess.run(['gcc', '-shared', '-fPIC', '-O2', '-o', str(shim_so), str(shim_c)],
                              capture_output=True, text=True)
    assert compiled.returncode == 0, compiled.stderr

    original_data = DATA.read_bytes()
    try:
        shutil.copyfile(shim_so, SO)
        for index, text in enumerate([
            'qqqqqrr🔥🔥🔥sséé\n',
            '中中中AABBBBB🙂🙂🙂🙂xyyyyyyyy\n'
        ]):
            DATA.write_text(text, encoding='utf-8')
            counter.unlink(missing_ok=True)
            py_count = hook_dir / f'python_calls_{index}'
            run_env = env.copy()
            run_env.pop('VERIFIER_CI_MARKER', None)
            run_env['VERIFIER_RUST_COUNTER'] = str(counter)
            run_env['VERIFIER_PY_COUNT'] = str(py_count)
            run_env['VERIFIER_EXPECTED_B64'] = base64.b64encode(
                expected_rle(text).encode('utf-8')).decode('ascii')
            run = subprocess.run(['python3', str(API)], cwd=str(HOME), env=run_env,
                                 capture_output=True, text=True, timeout=180)
            assert run.returncode == 0, f'api_test.py failed: {run.stderr}'
            read_and_check_report()
            rust_calls = len(counter.read_text().splitlines()) if counter.exists() else 0
            python_calls = int(py_count.read_text()) if py_count.exists() else 0
            assert rust_calls >= 1000, f'Rust implementation ran only {rust_calls} times.'
            assert python_calls >= 1000, f'Python RLE implementation ran only {python_calls} times.'
    finally:
        DATA.write_bytes(original_data)
        SO.write_bytes(real_library)
        os.chmod(SO, real_mode)

    # Leave a valid report for the original data, generated using the real library.
    final_run = subprocess.run(['python3', str(API)], cwd=str(HOME),
                               capture_output=True, text=True, timeout=180)
    assert final_run.returncode == 0, final_run.stderr
    read_and_check_report()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
