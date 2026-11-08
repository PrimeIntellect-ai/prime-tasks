#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import secrets
import shutil
import subprocess
import tempfile

import pytest

ROOT = '/home/user/token_gen'


def run(command, **kwargs):
    kwargs.setdefault('cwd', ROOT)
    kwargs.setdefault('stdout', subprocess.PIPE)
    kwargs.setdefault('stderr', subprocess.PIPE)
    kwargs.setdefault('text', True)
    kwargs.setdefault('timeout', 20)
    result = subprocess.run(command, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {command}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def expected_token(username, secure):
    value = sum(username.encode('ascii')) * 17
    if secure:
        value *= 31
    return f"TOKEN-{value}-{'SEC' if secure else 'STD'}"


def assert_binary_output(username, secure):
    result = run(['./token_bin', username])
    assert result.stdout == expected_token(username, secure) + '\n'
    assert result.stderr == ''


def expected_wrapper_output(username, token):
    return f"Generating token for user: {username}\nGenerated: {token}\n"


def test_migration_result_exists_and_correct():
    result_path = '/home/user/token_gen/migration_result.txt'
    assert os.path.isfile(result_path), f"The file {result_path} does not exist. Did you save the output?"

    with open(result_path, 'r') as f:
        content = f.read().strip()

    expected_line1 = "Generating token for user: test_user_123"
    expected_line2 = "Generated: TOKEN-667709-SEC"

    assert expected_line1 in content, f"Expected '{expected_line1}' to be in migration_result.txt"
    assert expected_line2 in content, f"Expected '{expected_line2}' to be in migration_result.txt. Ensure the secure build was used and the C logic is correct."


def test_python_wrapper_is_python3():
    py_path = '/home/user/token_gen/wrapper.py'
    assert os.path.isfile(py_path), f"The file {py_path} is missing."

    with open(py_path, 'r') as f:
        source = f.read()

    try:
        ast.parse(source)
    except SyntaxError as e:
        pytest.fail(f"wrapper.py is not valid Python 3 syntax: {e}")


def test_makefile_has_secure_target():
    makefile_path = '/home/user/token_gen/Makefile'
    assert os.path.isfile(makefile_path), f"The file {makefile_path} is missing."

    with open(makefile_path, 'r') as f:
        content = f.read()

    assert 'secure:' in content, "The Makefile is missing the 'secure' target."
    assert 'SECURE_MODE' in content, "The Makefile secure target does not seem to define SECURE_MODE."


def test_token_bin_is_executable():
    bin_path = '/home/user/token_gen/token_bin'
    assert os.path.isfile(bin_path), f"The compiled binary {bin_path} is missing."
    assert os.access(bin_path, os.X_OK), f"The file {bin_path} is not executable."


def test_builds_program_and_wrapper_end_to_end():
    usernames = [
        'audit_' + secrets.token_hex(6),
        'mixed_A9_' + secrets.token_hex(5),
    ]

    # The default target and the explicit all target must each build the C program.
    run(['make', 'clean'])
    run(['make'])
    bin_path = os.path.join(ROOT, 'token_bin')
    assert os.path.isfile(bin_path) and os.access(bin_path, os.X_OK)
    with open(bin_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'token_bin is not a compiled ELF executable'
    for username in usernames:
        assert_binary_output(username, secure=False)

    run(['make', 'clean'])
    run(['make', 'all'])
    assert_binary_output(usernames[0], secure=False)

    # A clean secure build must produce the secure algorithm's independently
    # calculated answers for inputs not known until verification time.
    run(['make', 'clean'])
    run(['make', 'secure'])
    with open(bin_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'secure target did not produce a compiled ELF executable'
    for username in usernames:
        assert_binary_output(username, secure=True)

    # Compile the submitted C source under sanitizers as well. This exercises the
    # linked-list traversal and detects the original uninitialized next pointer.
    with tempfile.TemporaryDirectory() as td:
        sanitized = os.path.join(td, 'token_sanitized')
        run([
            'gcc', '-fsanitize=address,undefined', '-fno-omit-frame-pointer',
            '-DSECURE_MODE=1', '-o', sanitized,
            os.path.join(ROOT, 'token_algo.c'),
        ])
        env = os.environ.copy()
        env['ASAN_OPTIONS'] = 'detect_leaks=0'
        checked = run([sanitized, usernames[0]], env=env)
        assert checked.stdout == expected_token(usernames[0], True) + '\n'

    # Execute the Python 3 wrapper on unpredictable inputs and verify decoded text.
    for username in usernames:
        wrapped = run(['python3', os.path.join(ROOT, 'wrapper.py'), username])
        assert wrapped.stdout == expected_wrapper_output(
            username, expected_token(username, True)
        )
        assert wrapped.stderr == ''

    # Confirm that the wrapper actually invokes token_bin instead of duplicating
    # or hardcoding the algorithm in Python.
    backup = bin_path + '.verifier-backup'
    os.replace(bin_path, backup)
    try:
        probe_user = 'probe_' + secrets.token_hex(6)
        with open(bin_path, 'w') as f:
            f.write('#!/bin/sh\nprintf "PROBE-%s\\n" "$1"\n')
        os.chmod(bin_path, 0o755)
        probed = run(['python3', os.path.join(ROOT, 'wrapper.py'), probe_user])
        assert probed.stdout == expected_wrapper_output(probe_user, 'PROBE-' + probe_user)
        assert probed.stderr == ''
    finally:
        if os.path.exists(bin_path):
            os.unlink(bin_path)
        os.replace(backup, bin_path)

    # The saved result must be exactly the stdout produced by the requested command
    # against the freshly built secure binary, including line endings.
    requested = run(['python3', os.path.join(ROOT, 'wrapper.py'), 'test_user_123'])
    assert requested.stdout == expected_wrapper_output(
        'test_user_123', expected_token('test_user_123', True)
    )
    with open(os.path.join(ROOT, 'migration_result.txt'), 'rb') as f:
        saved = f.read()
    assert saved == requested.stdout.encode(), (
        'migration_result.txt is not the exact stdout of the requested Python command'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
