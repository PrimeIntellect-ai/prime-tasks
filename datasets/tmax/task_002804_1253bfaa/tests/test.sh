#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shlex
import subprocess
import tempfile
from pathlib import Path

HOME = Path('/home/user')


def test_runner_c_exists():
    assert os.path.isfile('/home/user/runner.c'), 'The file /home/user/runner.c does not exist.'


def test_makefile_exists_and_content():
    makefile_path = '/home/user/Makefile'
    assert os.path.isfile(makefile_path), f'The file {makefile_path} does not exist.'

    with open(makefile_path, 'r') as f:
        content = f.read()

    assert '-Wall' in content, "Makefile is missing the '-Wall' flag."
    assert '-Wextra' in content, "Makefile is missing the '-Wextra' flag."
    assert '-O2' in content, "Makefile is missing the '-O2' flag."
    assert re.search(r'^clean:', content, re.MULTILINE), "Makefile is missing the 'clean' target."


def test_execution_log_content():
    log_path = '/home/user/execution.log'
    assert os.path.isfile(log_path), f'The file {log_path} does not exist. Did you run the compiled tool?'

    expected_lines = [
        'Step 1: Linux setup complete',
        'Step 2: Memory check passed',
        'Step 4: Memory limit check passed'
    ]

    with open(log_path, 'r') as f:
        content = f.read().strip()

    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]
    assert actual_lines == expected_lines, f'The contents of {log_path} do not match the expected output. Got:\n{content}'


def test_makefile_builds_ci_runner_and_runner_source_compiles():
    subprocess.run(['make', 'clean'], cwd=HOME, check=True, timeout=20,
                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

    dry = subprocess.run(['make', '-n', '-B', 'all'], cwd=HOME, check=True, timeout=20,
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True).stdout
    assert re.search(r'(^|\s)gcc(\s|$)', dry), 'The all target does not invoke gcc.'
    for flag in ('-Wall', '-Wextra', '-O2'):
        assert flag in dry, f'The gcc command used by the all target is missing {flag}.'
    assert re.search(r'(^|[\s/])runner\.c(\s|$)', dry), 'The all target does not compile runner.c.'
    assert re.search(r'(^|[\s/])ci_runner(\s|$)', dry), 'The all target does not produce ci_runner.'

    built = HOME / 'ci_runner'
    if built.exists() or built.is_symlink():
        built.unlink()
    subprocess.run(['make', 'all'], cwd=HOME, check=True, timeout=30,
                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    assert built.is_file(), 'make did not create /home/user/ci_runner.'
    assert os.access(built, os.X_OK), '/home/user/ci_runner is not executable.'
    assert built.read_bytes()[:4] == b'\x7fELF', 'ci_runner is not a compiled ELF executable.'

    direct = Path('/tmp/ci_runner_from_source')
    subprocess.run([
        'gcc', '-Wall', '-Wextra', '-O2', str(HOME / 'runner.c'), '-o', str(direct)
    ], check=True, timeout=30, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    assert direct.read_bytes()[:4] == b'\x7fELF'


def test_dynamic_pipeline_parsing_and_constraint_evaluation():
    suffix = secrets.token_hex(8).upper()
    env_name = 'VERIFY_VALUE_' + suffix
    missing_name = 'VERIFY_MISSING_' + suffix
    value = 20 + secrets.randbelow(100)
    limit = 1 + secrets.randbelow(20)
    tokens = ['result_' + secrets.token_hex(12) for _ in range(9)]

    with tempfile.TemporaryDirectory(prefix='ci_verify_') as td:
        td = Path(td)
        pipeline = td / 'pipeline.txt'
        output = td / 'commands.log'

        def command(token):
            return "EXEC printf '%s\\n' {} >> {}".format(
                shlex.quote(token), shlex.quote(str(output)))

        pipeline.write_text('\n'.join([
            command(tokens[0]),
            f'REQUIRE {env_name} == {value}',
            command(tokens[1]),
            f'REQUIRE {env_name} > {value}',
            command(tokens[2]),
            f'REQUIRE {missing_name} < {limit}',
            command(tokens[3]),
            f'REQUIRE {missing_name} == 0',
            command(tokens[4]),
            f'REQUIRE {env_name} < {value}',
            command(tokens[5]),
            f'REQUIRE {env_name} > {value - 1}',
            command(tokens[6]),
            f'REQUIRE {env_name} == {value + 1}',
            command(tokens[7]),
            f'REQUIRE {env_name} < {value + 1}',
            command(tokens[8]),
            'THIS LINE MUST BE IGNORED',
            '',
        ]))

        expected = [tokens[0], tokens[1], tokens[3], tokens[4], tokens[6], tokens[8]]
        env = os.environ.copy()
        env[env_name] = str(value)
        env.pop(missing_name, None)

        for executable in (HOME / 'ci_runner', Path('/tmp/ci_runner_from_source')):
            if output.exists():
                output.unlink()
            result = subprocess.run([str(executable), str(pipeline)], env=env, timeout=20,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            assert result.returncode == 0, (
                f'{executable} failed on a valid pipeline: stdout={result.stdout!r}, '
                f'stderr={result.stderr!r}')
            assert output.is_file(), f'{executable} did not execute the enabled commands.'
            assert output.read_text().splitlines() == expected, (
                f'{executable} did not correctly evaluate REQUIRE/EXEC state transitions.')


def test_runner_requires_exactly_one_argument():
    runner = str(HOME / 'ci_runner')
    no_args = subprocess.run([runner], timeout=10, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    extra_args = subprocess.run([runner, '/home/user/pipeline.txt', 'extra'], timeout=10,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert no_args.returncode != 0, 'ci_runner must reject invocation without a pipeline path.'
    assert extra_args.returncode != 0, 'ci_runner must reject invocation with extra arguments.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
