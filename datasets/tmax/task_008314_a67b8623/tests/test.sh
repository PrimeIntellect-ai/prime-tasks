#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import stat
import string
import subprocess
from pathlib import Path

import pytest

PROJECT_DIR = Path('/home/user/provision_project')
SRC_DIR = PROJECT_DIR / 'src'
BUILD_DIR = PROJECT_DIR / 'build'
STAGING_DIR = PROJECT_DIR / 'staging'
PRODUCTION_DIR = PROJECT_DIR / 'production'
DAEMON_SOURCE = SRC_DIR / 'daemon.cpp'
BUILD_DAEMON = BUILD_DIR / 'daemon'
STAGING_DAEMON = STAGING_DIR / 'daemon'
PROD_DAEMON = PRODUCTION_DIR / 'daemon'
EXPECT_SCRIPT = PROJECT_DIR / 'test.exp'
SUPERVISOR_SCRIPT = PROJECT_DIR / 'supervisor.sh'
PIPELINE_SCRIPT = PROJECT_DIR / 'pipeline.sh'
DEPLOY_LOG = PROJECT_DIR / 'deploy_status.log'


def run_as_user(command, timeout=60):
    return subprocess.run(
        ['runuser', '-u', 'user', '--'] + [str(x) for x in command],
        cwd=str(PROJECT_DIR),
        capture_output=True,
        timeout=timeout,
    )


def remove_path(path):
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.exists():
        shutil.rmtree(path)


def assert_script(path):
    assert path.exists(), f'{path} not found.'
    assert path.is_file() and not path.is_symlink(), f'{path} is not a regular file.'
    assert os.access(path, os.X_OK), f'{path} is not executable.'


def assert_daemon_behavior(path):
    assert path.exists(), f'Daemon not found at {path}.'
    assert path.is_file() and not path.is_symlink(), f'{path} is not a regular file.'
    assert path.read_bytes().startswith(b'\x7fELF'), f'{path} is not a compiled ELF binary.'

    wrong_keys = ['WRONG', 'PROV-SEC-98']
    wrong_keys.append('BAD-' + ''.join(random.choice(string.ascii_letters) for _ in range(20)))
    for key in wrong_keys:
        proc = subprocess.run([str(path)], input=(key + '\n').encode(), capture_output=True, timeout=10)
        assert proc.returncode == 1, f'{path} returned {proc.returncode} for wrong key {key!r}'
        assert proc.stdout.startswith(b'Enter deployment key: '), f'{path} did not print the required prompt.'
        assert b'AUTH FAIL' in proc.stdout, f'{path} did not print AUTH FAIL.'

    proc = subprocess.run([str(path)], input=b'PROV-SEC-99\n', capture_output=True, timeout=10)
    assert proc.returncode == 0, f'{path} returned {proc.returncode} for the correct key.'
    assert proc.stdout.startswith(b'Enter deployment key: '), f'{path} did not print the required prompt.'
    assert b'INIT OK' in proc.stdout, f'{path} did not print INIT OK.'


@pytest.fixture(scope='session', autouse=True)
def validate_and_run_pipeline(tmp_path_factory):
    for directory in (PROJECT_DIR, SRC_DIR, BUILD_DIR, STAGING_DIR, PRODUCTION_DIR):
        assert directory.is_dir(), f'Required directory {directory} is missing.'

    assert DAEMON_SOURCE.is_file() and not DAEMON_SOURCE.is_symlink(), f'{DAEMON_SOURCE} is missing or not a regular source file.'
    assert_script(EXPECT_SCRIPT)
    assert_script(SUPERVISOR_SCRIPT)
    assert_script(PIPELINE_SCRIPT)

    temp_dir = tmp_path_factory.mktemp('independent_build')
    independent_daemon = temp_dir / 'daemon'
    compile_proc = subprocess.run(
        ['g++', str(DAEMON_SOURCE), '-o', str(independent_daemon)],
        capture_output=True,
        timeout=60,
    )
    assert compile_proc.returncode == 0, (
        f'daemon.cpp did not compile:\n{compile_proc.stdout.decode(errors="replace")}\n'
        f'{compile_proc.stderr.decode(errors="replace")}'
    )
    assert_daemon_behavior(independent_daemon)

    interactive_child = temp_dir / 'interactive_child.py'
    interactive_child.write_text(
        '#!/usr/bin/python3\n'
        'import sys\n'
        'sys.stdout.write("Enter deployment key: ")\n'
        'sys.stdout.flush()\n'
        'key = sys.stdin.readline().rstrip("\\r\\n")\n'
        'if key != "PROV-SEC-99":\n'
        '    print("AUTH FAIL")\n'
        '    raise SystemExit(1)\n'
        'print("INIT OK")\n'
        'raise SystemExit(7)\n'
    )
    interactive_child.chmod(0o700)
    expect_proc = subprocess.run(
        [str(EXPECT_SCRIPT), str(interactive_child)],
        cwd=str(PROJECT_DIR),
        capture_output=True,
        timeout=20,
    )
    assert expect_proc.returncode == 7, (
        f'test.exp did not automate the prompt and propagate the child exit code; got {expect_proc.returncode}. '
        f'stdout={expect_proc.stdout!r}, stderr={expect_proc.stderr!r}'
    )
    assert b'INIT OK' in expect_proc.stdout, 'test.exp did not wait for INIT OK.'

    original_expect = EXPECT_SCRIPT.read_bytes()
    original_mode = stat.S_IMODE(EXPECT_SCRIPT.stat().st_mode)
    try:
        EXPECT_SCRIPT.write_bytes(b'#!/bin/sh\nexit 23\n')
        EXPECT_SCRIPT.chmod(0o755)
        for artifact in (BUILD_DAEMON, STAGING_DAEMON, PROD_DAEMON, DEPLOY_LOG):
            remove_path(artifact)

        failed = run_as_user([PIPELINE_SCRIPT])
        assert failed.returncode != 0, 'pipeline.sh ignored a failing expect test.'
        assert not PROD_DAEMON.exists(), 'pipeline.sh rolled out production even though test.exp failed.'
        assert not DEPLOY_LOG.exists(), 'pipeline.sh recorded SUCCESS even though test.exp failed.'
    finally:
        EXPECT_SCRIPT.write_bytes(original_expect)
        EXPECT_SCRIPT.chmod(original_mode)

    for artifact in (BUILD_DAEMON, STAGING_DAEMON, PROD_DAEMON, DEPLOY_LOG):
        remove_path(artifact)

    deployed = run_as_user([PIPELINE_SCRIPT])
    assert deployed.returncode == 0, (
        f'pipeline.sh failed:\nstdout={deployed.stdout.decode(errors="replace")}\n'
        f'stderr={deployed.stderr.decode(errors="replace")}'
    )

    for artifact in (BUILD_DAEMON, STAGING_DAEMON, PROD_DAEMON):
        assert_daemon_behavior(artifact)
    assert BUILD_DAEMON.read_bytes() == STAGING_DAEMON.read_bytes(), 'Staging daemon is not a copy of the build artifact.'
    assert BUILD_DAEMON.read_bytes() == PROD_DAEMON.read_bytes(), 'Production daemon is not a copy of the build artifact.'

    staging_test = run_as_user([EXPECT_SCRIPT, './staging/daemon'], timeout=20)
    assert staging_test.returncode == 0, (
        f'test.exp failed against staging/daemon: stdout={staging_test.stdout!r}, stderr={staging_test.stderr!r}'
    )


def test_deploy_status_log():
    assert os.path.exists(DEPLOY_LOG), f'{DEPLOY_LOG} was not created.'
    with open(DEPLOY_LOG, 'r') as f:
        content = f.read().strip()
    assert content == 'SUCCESS', f"{DEPLOY_LOG} does not contain 'SUCCESS', got '{content}'"


def test_production_daemon_permissions():
    assert os.path.exists(PROD_DAEMON), f'Production binary not found at {PROD_DAEMON}.'
    st = os.stat(PROD_DAEMON)
    mode = stat.S_IMODE(st.st_mode)
    assert mode == 0o500, f'Permissions on production daemon are not 500, got {oct(mode)}'


def test_daemon_behavior_wrong_key():
    assert os.path.exists(PROD_DAEMON), f'Production binary not found at {PROD_DAEMON}.'
    proc = subprocess.run([PROD_DAEMON], input=b'WRONG\n', capture_output=True)
    assert proc.returncode == 1, f'Daemon did not exit with code 1 on wrong input, got {proc.returncode}'
    assert b'AUTH FAIL' in proc.stdout, 'Daemon did not print AUTH FAIL on wrong input'


def test_daemon_behavior_correct_key():
    assert os.path.exists(PROD_DAEMON), f'Production binary not found at {PROD_DAEMON}.'
    proc = subprocess.run([PROD_DAEMON], input=b'PROV-SEC-99\n', capture_output=True)
    assert proc.returncode == 0, f'Daemon did not exit with code 0 on correct input, got {proc.returncode}'
    assert b'INIT OK' in proc.stdout, 'Daemon did not print INIT OK on correct input'


def test_supervisor_success_behavior(tmp_path):
    assert os.path.exists(SUPERVISOR_SCRIPT), f'{SUPERVISOR_SCRIPT} not found.'

    dummy_succ = tmp_path / 'dummy_succ.sh'
    dummy_succ.write_text('#!/bin/bash\nexit 0\n')
    dummy_succ.chmod(0o700)

    proc = subprocess.run([SUPERVISOR_SCRIPT, str(dummy_succ)], capture_output=True, timeout=10)
    assert b'STOPPING' in proc.stdout, 'Supervisor did not print STOPPING on successful execution of the child process'
    assert proc.returncode == 0, 'Supervisor did not exit successfully after the child succeeded.'


def test_supervisor_restarting_logic():
    assert os.path.exists(SUPERVISOR_SCRIPT), f'{SUPERVISOR_SCRIPT} not found.'
    with open(SUPERVISOR_SCRIPT, 'r') as f:
        content = f.read()
    assert 'RESTARTING' in content, 'Supervisor script does not contain RESTARTING logic'


def test_supervisor_actually_restarts(tmp_path):
    counter = tmp_path / 'runs.txt'
    child = tmp_path / 'fails_then_succeeds.sh'
    child.write_text(
        '#!/bin/bash\n'
        f'counter={str(counter)!r}\n'
        'n=0\n'
        '[ -f "$counter" ] && n=$(cat "$counter")\n'
        'n=$((n + 1))\n'
        'printf "%s" "$n" > "$counter"\n'
        'if [ "$n" -lt 3 ]; then exit 9; fi\n'
        'exit 0\n'
    )
    child.chmod(0o700)

    proc = subprocess.run([str(SUPERVISOR_SCRIPT), str(child)], capture_output=True, timeout=15)
    assert proc.returncode == 0, f'Supervisor returned {proc.returncode} after the child eventually succeeded.'
    assert counter.read_text() == '3', 'Supervisor did not rerun the failed child until it succeeded.'
    assert proc.stdout.count(b'RESTARTING') == 2, f'Supervisor did not print RESTARTING for each failure: {proc.stdout!r}'
    assert b'STOPPING' in proc.stdout, 'Supervisor did not print STOPPING after eventual success.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
