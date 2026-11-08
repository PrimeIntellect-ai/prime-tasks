#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import string
import subprocess
import tempfile
from pathlib import Path

import pytest

APP = Path('/home/user/app')
SCRIPT = APP / 'build_and_test.sh'
BIN = APP / 'bin' / 'sanitize'
LOG = APP / 'test_results.log'
SANITIZE_SRC = APP / 'src' / 'sanitize.c'
UTILS_SRC = APP / 'src' / 'utils.cpp'


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=120, **kwargs)


@pytest.fixture(scope='session', autouse=True)
def build_submission(tmp_path_factory):
    assert SCRIPT.is_file(), f'Build script {SCRIPT} does not exist.'
    assert os.access(SCRIPT, os.X_OK), f'Build script {SCRIPT} is not executable.'

    # Require the submitted script to recreate both deliverables itself.
    BIN.unlink(missing_ok=True)
    LOG.unlink(missing_ok=True)

    temp = tmp_path_factory.mktemp('build_checks')
    marker = temp / 'pytest-ran'
    token = secrets.token_hex(24)
    trace = temp / 'compiler-trace'

    # A temporary pytest plugin proves that the build script really invokes the
    # requested integration suite rather than merely fabricating its log.
    conftest = APP / 'conftest.py'
    old_conftest = conftest.read_bytes() if conftest.exists() else None
    conftest.write_text(
        'from pathlib import Path\n'
        'def pytest_sessionfinish(session, exitstatus):\n'
        f'    Path({str(marker)!r}).write_text({token!r})\n'
    )

    # Record normal gcc/g++ invocations while transparently running the real tools.
    wrapper_dir = temp / 'tools'
    wrapper_dir.mkdir()
    real_gcc = shutil.which('gcc')
    real_gxx = shutil.which('g++')
    assert real_gcc and real_gxx
    for name, real in [('gcc', real_gcc), ('g++', real_gxx)]:
        wrapper = wrapper_dir / name
        wrapper.write_text(
            '#!/bin/sh\n'
            f'printf "%s\\n" "{name} $*" >> {str(trace)!r}\n'
            f'exec {real!r} "$@"\n'
        )
        wrapper.chmod(0o755)

    env = os.environ.copy()
    env['PATH'] = str(wrapper_dir) + os.pathsep + env.get('PATH', '')
    try:
        result = run([str(SCRIPT)], cwd=str(APP), env=env)
    finally:
        if old_conftest is None:
            conftest.unlink(missing_ok=True)
        else:
            conftest.write_bytes(old_conftest)

    assert result.returncode == 0, (
        f'build_and_test.sh failed with {result.returncode}\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert marker.is_file() and marker.read_text() == token, (
        'build_and_test.sh did not actually run the requested pytest suite'
    )

    compiler_calls = trace.read_text() if trace.exists() else ''
    assert any(line.startswith('gcc ') and 'sanitize.c' in line
               for line in compiler_calls.splitlines()), (
        'build_and_test.sh did not compile sanitize.c using gcc'
    )
    assert any(line.startswith('g++ ') and 'utils.cpp' in line
               for line in compiler_calls.splitlines()), (
        'build_and_test.sh did not compile utils.cpp using g++'
    )


def test_build_script_exists_and_executable():
    assert SCRIPT.is_file(), f'Build script {SCRIPT} does not exist.'
    assert os.access(SCRIPT, os.X_OK), f'Build script {SCRIPT} is not executable.'


def test_binary_exists_and_executable():
    assert BIN.is_file(), f'Binary {BIN} does not exist.'
    assert os.access(BIN, os.X_OK), f'Binary {BIN} is not executable.'
    with BIN.open('rb') as f:
        magic = f.read(4)
    assert magic == b'\x7fELF', f'File {BIN} is not a valid ELF executable.'


def test_test_results_log():
    assert LOG.is_file(), f'Test results log {LOG} does not exist.'
    content = LOG.read_text()
    assert '2 passed' in content, 'test_results.log does not indicate that 2 tests passed.'


def assert_sanitizes(executable, value, env=None):
    result = subprocess.run(
        [str(executable), value], capture_output=True, text=True,
        timeout=5, env=env
    )
    assert result.returncode == 0, (
        f'Binary failed for input of length {len(value)} with code '
        f'{result.returncode}: {result.stderr}'
    )
    assert result.stdout == f'CLEAN: {value}\n', (
        f'Incorrect stdout for input {value!r}: {result.stdout!r}'
    )
    assert 'LOG: Data processed' in result.stderr, (
        'The linked C++ logging function was not invoked'
    )


def test_sanitize_binary_execution():
    long_string = 'this_is_a_very_long_string_that_needs_to_be_sanitized_without_crashing_the_backend_service'
    result = subprocess.run([str(BIN), long_string], capture_output=True, text=True, timeout=2)
    assert result.returncode == 0, f'Binary crashed or exited with non-zero code: {result.returncode}'
    expected_output = f'CLEAN: {long_string}'
    stdout_lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    assert expected_output in stdout_lines, (
        f"Expected output '{expected_output}' not found in binary stdout: {result.stdout}"
    )


def test_binary_handles_derived_inputs_through_100_characters():
    alphabet = string.ascii_letters + string.digits + ' _-.:/@+'
    values = ['', 'x', 'A' * 15, 'B' * 16, 'C' * 17]
    for length in (31, 63, 99, 100):
        values.append(''.join(secrets.choice(alphabet) for _ in range(length)))
    for value in values:
        assert_sanitizes(BIN, value)


def test_submitted_source_is_memory_safe_when_recompiled():
    assert SANITIZE_SRC.is_file()
    assert UTILS_SRC.is_file()
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        c_obj = td / 'sanitize.o'
        cpp_obj = td / 'utils.o'
        checked_bin = td / 'sanitize_asan'
        commands = [
            ['gcc', '-fsanitize=address', '-fno-omit-frame-pointer', '-g',
             '-c', str(SANITIZE_SRC), '-o', str(c_obj)],
            ['g++', '-fsanitize=address', '-fno-omit-frame-pointer', '-g',
             '-c', str(UTILS_SRC), '-o', str(cpp_obj)],
            ['g++', '-fsanitize=address', str(c_obj), str(cpp_obj),
             '-o', str(checked_bin)],
        ]
        for command in commands:
            result = run(command)
            assert result.returncode == 0, (
                f'Failed to compile submitted sources: {result.stderr}'
            )

        asan_env = os.environ.copy()
        asan_env['ASAN_OPTIONS'] = 'abort_on_error=1:detect_leaks=0'
        alphabet = string.ascii_letters + string.digits + ' _-.:/@+'
        for length in (16, 17, 48, 100):
            value = ''.join(secrets.choice(alphabet) for _ in range(length))
            assert_sanitizes(checked_bin, value, env=asan_env)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
