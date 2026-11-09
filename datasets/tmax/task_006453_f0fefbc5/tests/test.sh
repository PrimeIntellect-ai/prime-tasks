#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import re
import shutil
import subprocess
import time

import pytest

SANDBOX_SOURCE = '/home/user/sandbox.c'
SANDBOX_BINARY = '/home/user/sandbox'
COMPILED_SOURCE = '/tmp/sandbox_from_source'
TARGET = '/home/user/target_bin'
TARGET_BACKUP = '/tmp/original_target_bin'
PROBE_SOURCE = '/tmp/target_probe.c'

PROBE_C = r'''
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

int main(int argc, char **argv) {
    const char *expected = getenv("EXPECTED_PAYLOAD");
    const char *verifier_pid = getenv("VERIFIER_PID");
    const char *mode = getenv("PROBE_MODE");
    struct rlimit limit;

    if (!expected || !verifier_pid || !mode)
        return 90;
    if (argc != 2 || strcmp(argv[1], expected) != 0)
        return 91;
    if (getppid() == (pid_t)strtol(verifier_pid, NULL, 10))
        return 92;
    if (getrlimit(RLIMIT_FSIZE, &limit) != 0)
        return 93;
    if (limit.rlim_cur != 0 || limit.rlim_max != 0)
        return 94;

    if (strcmp(mode, "exit0") == 0)
        return 0;
    if (strcmp(mode, "exit37") == 0)
        return 37;
    if (strcmp(mode, "delay23") == 0) {
        struct timespec delay = {0, 400000000};
        while (nanosleep(&delay, &delay) != 0 && errno == EINTR) {}
        return 23;
    }
    if (strcmp(mode, "sigterm") == 0) {
        raise(SIGTERM);
        return 95;
    }
    if (strcmp(mode, "sigsegv") == 0) {
        raise(SIGSEGV);
        return 96;
    }
    return 97;
}
'''


def run_checked(command, **kwargs):
    return subprocess.run(command, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=5, **kwargs)


def valid_payload_from_inputs():
    ca = '/home/user/certs/ca.pem'
    valid_leaves = []
    for name in ('leaf_A.pem', 'leaf_B.pem', 'leaf_C.pem'):
        path = os.path.join('/home/user/certs', name)
        result = run_checked(['openssl', 'verify', '-CAfile', ca, path])
        if result.returncode == 0:
            valid_leaves.append(name)

    assert len(valid_leaves) == 1, f'expected exactly one valid leaf, got {valid_leaves}'
    valid_leaf = valid_leaves[0]

    with open('/home/user/security.log', 'r') as log_file:
        matching = [line for line in log_file if valid_leaf in line]
    assert len(matching) == 1, f'expected one log entry for {valid_leaf}'

    match = re.search(r'Payload:\s*([A-Za-z0-9+/=]+)\s*$', matching[0])
    assert match, 'valid certificate log entry has no Base64 payload'
    return base64.b64decode(match.group(1), validate=True).decode('utf-8')


@pytest.fixture(scope='session', autouse=True)
def install_instrumented_target():
    assert os.path.isfile(TARGET), '/home/user/target_bin is missing'
    shutil.copy2(TARGET, TARGET_BACKUP)
    with open(PROBE_SOURCE, 'w') as probe_file:
        probe_file.write(PROBE_C)
    build = run_checked(['gcc', '-std=c11', '-O2', PROBE_SOURCE, '-o', TARGET])
    assert build.returncode == 0, f'failed to build verifier target: {build.stderr}'
    os.chmod(TARGET, 0o755)
    try:
        yield
    finally:
        shutil.copy2(TARGET_BACKUP, TARGET)


@pytest.fixture(scope='session')
def sandbox_executables():
    build = run_checked(['gcc', '-std=c11', SANDBOX_SOURCE, '-o', COMPILED_SOURCE])
    assert build.returncode == 0, f'sandbox.c does not compile: {build.stderr}'
    os.chmod(COMPILED_SOURCE, 0o755)
    return [SANDBOX_BINARY, COMPILED_SOURCE]


def invoke_sandbox(executable, payload, mode):
    env = os.environ.copy()
    env['EXPECTED_PAYLOAD'] = payload
    env['VERIFIER_PID'] = str(os.getpid())
    env['PROBE_MODE'] = mode
    return run_checked([executable, payload], env=env, cwd='/tmp')


def test_sandbox_c_exists():
    assert os.path.isfile('/home/user/sandbox.c'), '/home/user/sandbox.c is missing'


def test_sandbox_compiled_and_executable():
    assert os.path.isfile('/home/user/sandbox'), '/home/user/sandbox is missing'
    assert os.access('/home/user/sandbox', os.X_OK), '/home/user/sandbox is not executable'
    with open('/home/user/sandbox', 'rb') as executable:
        assert executable.read(4) == b'\x7fELF', '/home/user/sandbox is not an ELF executable'


def test_sandbox_c_logic():
    with open('/home/user/sandbox.c', 'r') as f:
        content = f.read()

    assert 'fork' in content, 'sandbox.c does not contain a call to fork()'
    assert 'setrlimit' in content, 'sandbox.c does not contain a call to setrlimit()'
    assert 'RLIMIT_FSIZE' in content, 'sandbox.c does not reference RLIMIT_FSIZE'
    assert re.search(r'wait|waitpid', content), 'sandbox.c does not contain a call to wait() or waitpid()'

    assert 'VULNERABLE: SIGNAL' in content, "sandbox.c does not contain the required string 'VULNERABLE: SIGNAL'"
    assert 'SECURE: EXIT' in content, "sandbox.c does not contain the required string 'SECURE: EXIT'"


def test_requires_exactly_one_argument(sandbox_executables):
    env = os.environ.copy()
    env['EXPECTED_PAYLOAD'] = 'unused'
    env['VERIFIER_PID'] = str(os.getpid())
    env['PROBE_MODE'] = 'sigsegv'
    for executable in sandbox_executables:
        no_arg = run_checked([executable], env=env, cwd='/tmp')
        two_args = run_checked([executable, 'one', 'two'], env=env, cwd='/tmp')
        assert no_arg.returncode != 0, f'{executable} accepted no payload argument'
        assert two_args.returncode != 0, f'{executable} accepted more than one argument'
        assert 'VULNERABLE: SIGNAL' not in no_arg.stdout
        assert 'VULNERABLE: SIGNAL' not in two_args.stdout


def test_fork_exec_limits_and_normal_status(sandbox_executables):
    payload = 'probe_' + os.urandom(12).hex()
    for executable in sandbox_executables:
        result = invoke_sandbox(executable, payload, 'exit0')
        assert result.stdout == 'SECURE: EXIT 0\n', (executable, result.stdout, result.stderr)

        result = invoke_sandbox(executable, payload, 'exit37')
        assert result.stdout == 'SECURE: EXIT 37\n', (executable, result.stdout, result.stderr)


def test_waits_for_child(sandbox_executables):
    payload = 'wait_' + os.urandom(12).hex()
    for executable in sandbox_executables:
        start = time.monotonic()
        result = invoke_sandbox(executable, payload, 'delay23')
        elapsed = time.monotonic() - start
        assert elapsed >= 0.30, f'{executable} returned before its child finished'
        assert result.stdout == 'SECURE: EXIT 23\n', (executable, result.stdout, result.stderr)


def test_signal_status_handling(sandbox_executables):
    payload = 'signal_' + os.urandom(12).hex()
    for executable in sandbox_executables:
        term = invoke_sandbox(executable, payload, 'sigterm')
        assert term.stdout == 'VULNERABLE: SIGNAL 15\n', (executable, term.stdout, term.stderr)

        segv = invoke_sandbox(executable, payload, 'sigsegv')
        assert segv.stdout == 'VULNERABLE: SIGNAL 11\n', (executable, segv.stdout, segv.stderr)


def test_real_payload_execution(sandbox_executables):
    payload = valid_payload_from_inputs()
    for executable in sandbox_executables:
        result = invoke_sandbox(executable, payload, 'sigsegv')
        assert result.stdout == 'VULNERABLE: SIGNAL 11\n', (executable, result.stdout, result.stderr)


def test_final_report_content():
    report_path = '/home/user/final_report.txt'
    assert os.path.isfile(report_path), f'{report_path} is missing'

    with open(report_path, 'r') as f:
        content = f.read().strip()

    assert content == 'VULNERABLE: SIGNAL 11', f"final_report.txt contains incorrect output: expected 'VULNERABLE: SIGNAL 11', got '{content}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
