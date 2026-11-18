#!/bin/bash
set +e
mkdir -p /logs/verifier

BUILD_DIR=$(mktemp -d /tmp/verifier-build.XXXXXX)
C_BUILD="$BUILD_DIR/c"
C_ASAN_BUILD="$BUILD_DIR/c_asan"
RUST_TARGET="$BUILD_DIR/rust-target"
mkdir -p "$C_BUILD" "$C_ASAN_BUILD" "$RUST_TARGET"

EXT_SUFFIX=$(python3 -c 'import sysconfig; print(sysconfig.get_config_var("EXT_SUFFIX") or ".so")')
C_MODULE="$C_BUILD/fast_sec${EXT_SUFFIX}"
C_ASAN_MODULE="$C_ASAN_BUILD/fast_sec${EXT_SUFFIX}"
RUST_MODULE="$BUILD_DIR/rust_sec${EXT_SUFFIX}"
ASAN_LIB=$(gcc -print-file-name=libasan.so)

build_ok=1

gcc -shared -fPIC -O2 $(python3-config --includes) \
    /home/user/project/c_ext/fast_sec.c -o "$C_MODULE" || build_ok=0

gcc -shared -fPIC -O0 -g -fsanitize=address,undefined -fno-omit-frame-pointer \
    $(python3-config --includes) /home/user/project/c_ext/fast_sec.c \
    -o "$C_ASAN_MODULE" || build_ok=0

CARGO_TARGET_DIR="$RUST_TARGET" cargo build --release --offline \
    --manifest-path /home/user/project/rust_ext/Cargo.toml || build_ok=0

if [ -f "$RUST_TARGET/release/librust_sec.so" ]; then
    cp "$RUST_TARGET/release/librust_sec.so" "$RUST_MODULE" || build_ok=0
else
    build_ok=0
fi

export VERIFIER_BUILD_DIR="$BUILD_DIR"
export VERIFIER_C_ASAN_DIR="$C_ASAN_BUILD"
export VERIFIER_ASAN_LIB="$ASAN_LIB"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import importlib
import importlib.machinery
import json
import os
from pathlib import Path
import random
import re
import shutil
import subprocess
import sys
import tempfile

import pytest

PROJECT = Path('/home/user/project')
BUILD_DIR = Path(os.environ['VERIFIER_BUILD_DIR'])


def test_test_results_log_exists_and_passed():
    log_path = "/home/user/project/test_results.log"
    assert os.path.isfile(log_path), f"Test results log missing at {log_path}"

    with open(log_path, "r") as f:
        content = f.read()

    # Check that tests were collected and passed
    assert re.search(r"collected \d+ items", content, re.IGNORECASE) or "test session starts" in content, \
        "The test_results.log does not appear to contain pytest output."

    assert "failed" not in content.lower() or "0 failed" in content.lower(), \
        "The test_results.log indicates that some tests failed."
    assert "passed" in content.lower(), \
        "The test_results.log does not indicate that tests passed."


def test_c_ext_fixed():
    c_file_path = "/home/user/project/c_ext/fast_sec.c"
    assert os.path.isfile(c_file_path), f"C extension file missing at {c_file_path}"

    with open(c_file_path, "r") as f:
        content = f.read()

    # The original bug was a 64-byte buffer and an unsafe strcpy.
    # The fix should either increase the buffer size (>= 256) or use safe string functions like strncpy.
    has_unsafe_strcpy = "strcpy(buffer, input_str);" in content
    has_small_buffer = "char buffer[64];" in content

    assert not (has_unsafe_strcpy and has_small_buffer), \
        "The C extension still contains the original buffer overflow bug."


def test_rust_ext_fixed():
    rust_file_path = "/home/user/project/rust_ext/src/lib.rs"
    assert os.path.isfile(rust_file_path), f"Rust extension file missing at {rust_file_path}"

    with open(rust_file_path, "r") as f:
        content = f.read()

    # The original bug returned PyResult<&'static str>
    assert "PyResult<&'static str>" not in content, \
        "The Rust extension still returns a static string reference, which causes a borrow checker error."

    # The fix should return an owned String
    assert "PyResult<String>" in content or "PyResult<std::string::String>" in content, \
        "The Rust extension should return an owned String (PyResult<String>)."

    # Check that the unsafe transmute was removed
    assert "std::mem::transmute" not in content, \
        "The Rust extension still contains the unsafe lifetime transmute."


def test_test_parser_implemented():
    test_file_path = "/home/user/project/tests/test_parser.py"
    assert os.path.isfile(test_file_path), f"Test parser file missing at {test_file_path}"

    with open(test_file_path, "r") as f:
        content = f.read()

    # Ensure the test file actually imports the modules and reads the json
    assert "json" in content or "data.json" in content, "The test file does not appear to read data.json."
    assert "fast_sec" in content, "The test file does not appear to test the C extension."
    assert "rust_sec" in content, "The test file does not appear to test the Rust extension."


def test_submitted_pytest_suite_runs_and_exercises_both_extensions(tmp_path):
    project_copy = tmp_path / 'project'
    tests_copy = project_copy / 'tests'
    tests_copy.mkdir(parents=True)
    shutil.copy2(PROJECT / 'tests/test_parser.py', tests_copy / 'test_parser.py')
    shutil.copy2(PROJECT / 'data.json', project_copy / 'data.json')

    conftest = r'''
import collections
import json
import pytest
import fast_sec
import rust_sec

with open('/home/user/project/data.json', 'r') as f:
    _rows = json.load(f)
_expected = collections.Counter(row['headers']['X-Sec-Token'] for row in _rows)
_calls = {'fast_sec': collections.Counter(), 'rust_sec': collections.Counter()}
_active = False
_fast_native = fast_sec.parse_token
_rust_native = rust_sec.parse_token

def _fast(token, *args, **kwargs):
    if _active:
        _calls['fast_sec'][token] += 1
    return _fast_native(token, *args, **kwargs)

def _rust(token, *args, **kwargs):
    if _active:
        _calls['rust_sec'][token] += 1
    return _rust_native(token, *args, **kwargs)

fast_sec.parse_token = _fast
rust_sec.parse_token = _rust

@pytest.hookimpl(tryfirst=True)
def pytest_runtestloop(session):
    global _active
    _active = True

@pytest.hookimpl(trylast=True)
def pytest_sessionfinish(session, exitstatus):
    missing = []
    for module_name in ('fast_sec', 'rust_sec'):
        for token, needed in _expected.items():
            if _calls[module_name][token] < needed:
                missing.append((module_name, token))
    if missing:
        session.exitstatus = pytest.ExitCode.TESTS_FAILED
'''
    (tests_copy / 'conftest.py').write_text(conftest)

    env = os.environ.copy()
    env['PYTHONPATH'] = str(BUILD_DIR)
    env['PYTEST_DISABLE_PLUGIN_AUTOLOAD'] = '1'
    proc = subprocess.run(
        [sys.executable, '-m', 'pytest', '-q', str(tests_copy / 'test_parser.py'),
         '--confcutdir', str(tests_copy)],
        cwd=str(project_copy), env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120,
    )
    assert proc.returncode == 0, 'Submitted pytest suite failed or did not exercise both extensions:\n' + proc.stdout


def test_c_extension_is_memory_safe_through_256_characters():
    tokens = ['', 'SEC-', 'A' * 256, 'SEC-' + 'B' * 252]
    rng = random.Random(918273)
    alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_'
    for _ in range(50):
        length = rng.randint(0, 256)
        value = ''.join(rng.choice(alphabet) for _ in range(length))
        if length >= 4 and rng.choice([True, False]):
            value = 'SEC-' + value[4:]
        tokens.append(value)

    code = r'''
import json
import fast_sec
for token in json.loads(__import__('os').environ['TOKENS_JSON']):
    expected = token[4:] if token.startswith('SEC-') else token
    actual = fast_sec.parse_token(token)
    assert actual == expected, (token, actual, expected)
'''
    env = os.environ.copy()
    env['PYTHONPATH'] = os.environ['VERIFIER_C_ASAN_DIR']
    env['TOKENS_JSON'] = json.dumps(tokens)
    env['LD_PRELOAD'] = os.environ['VERIFIER_ASAN_LIB']
    env['ASAN_OPTIONS'] = 'detect_leaks=0:halt_on_error=1:abort_on_error=1'
    proc = subprocess.run(
        [sys.executable, '-c', code], cwd='/tmp', env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60,
    )
    assert proc.returncode == 0, 'C extension failed behavioral/memory-safety checks:\n' + proc.stdout


def test_freshly_built_extensions_parse_derived_inputs_identically():
    sys.path.insert(0, str(BUILD_DIR))
    for name in ('fast_sec', 'rust_sec'):
        sys.modules.pop(name, None)
    importlib.invalidate_caches()
    fast_sec = importlib.import_module('fast_sec')
    rust_sec = importlib.import_module('rust_sec')

    suffixes = tuple(importlib.machinery.EXTENSION_SUFFIXES)
    for module in (fast_sec, rust_sec):
        origin = Path(module.__spec__.origin).resolve()
        assert origin.parent == BUILD_DIR.resolve()
        assert str(origin).endswith(suffixes), f'{module.__name__} is not a native extension: {origin}'

    with open(PROJECT / 'data.json', 'r') as f:
        rows = json.load(f)
    tokens = [row['headers']['X-Sec-Token'] for row in rows]

    rng = random.Random(246810)
    alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_'
    tokens += ['', 'SEC-', 'NO-PREFIX', 'SEC-' + 'Z' * 252, 'Q' * 256]
    for _ in range(80):
        length = rng.randint(0, 256)
        token = ''.join(rng.choice(alphabet) for _ in range(length))
        if length >= 4 and rng.randrange(2):
            token = 'SEC-' + token[4:]
        tokens.append(token)

    for token in tokens:
        expected = token[4:] if token.startswith('SEC-') else token
        c_result = fast_sec.parse_token(token)
        rust_result = rust_sec.parse_token(token)
        assert isinstance(c_result, str)
        assert isinstance(rust_result, str)
        assert c_result == expected
        assert rust_result == expected
        assert c_result == rust_result
TEST_EOF

result=1
if [ "$build_ok" -eq 1 ]; then
    PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
    result=$?
fi

if [ "$result" -eq 0 ] && [ "$build_ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

rm -rf "$BUILD_DIR"
exit 0
