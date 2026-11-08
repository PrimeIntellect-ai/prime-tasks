#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import re
import shlex
import shutil
import subprocess
import tempfile
import uuid
from pathlib import Path

MONITOR = Path('/home/user/bin/monitor')
SOURCE = Path('/home/user/src/monitor.c')
WRAPPER = Path('/home/user/bin/run_monitor.sh')
HEALTH = Path('/home/user/bin/health_check.sh')


def run_program(program, env, demote=False):
    preexec = None
    if demote:
        account = pwd.getpwnam('user')
        def drop_privileges():
            os.setgroups([])
            os.setgid(account.pw_gid)
            os.setuid(account.pw_uid)
        preexec = drop_privileges
    return subprocess.run(
        [str(program)], env=env, capture_output=True, text=True,
        timeout=10, preexec_fn=preexec
    )


def exercise_monitor(program):
    token = uuid.uuid4().hex
    base = Path('/tmp') / ('monitor-test-' + token)
    base.mkdir(mode=0o777)
    try:
        # DATA_DIR missing: stderr and exit status 1.
        missing_data_log = base / 'missing-data.log'
        result = run_program(program, {
            'PATH': '/usr/bin:/bin',
            'MONITOR_OUTPUT_PATH': str(missing_data_log),
        })
        assert result.returncode == 1, result
        assert result.stderr.strip(), 'Missing DATA_DIR did not produce an error on stderr'

        # A dynamically named existing directory must append exactly one OK line.
        good_dir = base / ('good-' + uuid.uuid4().hex)
        good_dir.mkdir()
        good_log = base / 'good.log'
        good_log.write_text('PREEXISTING\n')
        result = run_program(program, {
            'PATH': '/usr/bin:/bin',
            'DATA_DIR': str(good_dir),
            'MONITOR_OUTPUT_PATH': str(good_log),
        })
        assert result.returncode == 0, result
        assert good_log.read_text() == f'PREEXISTING\nSTATUS: OK - {good_dir}\n'

        # A dynamically named nonexistent path must log ERROR and return 2.
        absent = base / ('absent-' + uuid.uuid4().hex)
        absent_log = base / 'absent.log'
        result = run_program(program, {
            'PATH': '/usr/bin:/bin',
            'DATA_DIR': str(absent),
            'MONITOR_OUTPUT_PATH': str(absent_log),
        })
        assert result.returncode == 2, result
        assert absent_log.read_text() == f'STATUS: ERROR - {absent}\n'

        # An existing non-directory must also be rejected.
        regular_file = base / 'not-a-directory'
        regular_file.write_text('x')
        file_log = base / 'file.log'
        result = run_program(program, {
            'PATH': '/usr/bin:/bin',
            'DATA_DIR': str(regular_file),
            'MONITOR_OUTPUT_PATH': str(file_log),
        })
        assert result.returncode == 2, result
        assert file_log.read_text() == f'STATUS: ERROR - {regular_file}\n'

        # Verify an inaccessible path while running as the unprivileged user.
        blocked_parent = base / 'blocked'
        blocked_parent.mkdir()
        blocked_child = blocked_parent / 'child'
        blocked_child.mkdir()
        blocked_parent.chmod(0)
        inaccessible_log = base / 'inaccessible.log'
        result = run_program(program, {
            'PATH': '/usr/bin:/bin',
            'DATA_DIR': str(blocked_child),
            'MONITOR_OUTPUT_PATH': str(inaccessible_log),
        }, demote=True)
        assert result.returncode == 2, result
        assert inaccessible_log.read_text() == f'STATUS: ERROR - {blocked_child}\n'
        blocked_parent.chmod(0o755)
    finally:
        blocked = base / 'blocked'
        if blocked.exists():
            blocked.chmod(0o755)
        shutil.rmtree(base, ignore_errors=True)


def test_monitor_source_and_compiled_binary():
    assert SOURCE.exists(), f'{SOURCE} does not exist'
    assert SOURCE.is_file(), f'{SOURCE} is not a regular file'
    source_text = SOURCE.read_text()
    without_comments = re.sub(r'/\*.*?\*/|//[^\n]*', '', source_text, flags=re.S)
    assert re.search(r'\bstat\s*\(', without_comments), 'monitor.c does not call stat()'

    assert MONITOR.exists(), f'Binary {MONITOR} does not exist.'
    assert MONITOR.is_file(), f'{MONITOR} is not a file.'
    assert os.access(MONITOR, os.X_OK), f'Binary {MONITOR} is not executable.'
    assert MONITOR.read_bytes()[:4] == b'\x7fELF', 'monitor is not a compiled ELF executable'

    # The submitted source itself must compile and implement the same required behavior.
    with tempfile.TemporaryDirectory(prefix='compile-monitor-') as tmp:
        rebuilt = Path(tmp) / 'monitor-from-source'
        compile_result = subprocess.run(
            ['gcc', str(SOURCE), '-o', str(rebuilt)],
            capture_output=True, text=True, timeout=20
        )
        assert compile_result.returncode == 0, compile_result.stderr
        exercise_monitor(rebuilt)

    # Exercise the installed artifact independently on unpredictable paths.
    exercise_monitor(MONITOR)


def test_run_monitor_script():
    assert WRAPPER.exists(), f'Script {WRAPPER} does not exist.'
    assert WRAPPER.is_file(), f'{WRAPPER} is not a file.'
    assert os.access(WRAPPER, os.X_OK), f'Script {WRAPPER} is not executable.'

    syntax = subprocess.run(['bash', '-n', str(WRAPPER)], capture_output=True, text=True)
    assert syntax.returncode == 0, syntax.stderr

    # Confirm both errexit and nounset are enabled by the script.
    options = set()
    for raw_line in WRAPPER.read_text().splitlines():
        try:
            words = shlex.split(raw_line, comments=True)
        except ValueError:
            continue
        if not words or words[0] != 'set':
            continue
        for word in words[1:]:
            if word.startswith('-') and not word.startswith('--'):
                options.update(word[1:])
        for index in range(1, len(words) - 1):
            if words[index] == '-o':
                if words[index + 1] == 'errexit':
                    options.add('e')
                if words[index + 1] == 'nounset':
                    options.add('u')
    assert 'e' in options, 'run_monitor.sh does not enable fail-on-error (set -e)'
    assert 'u' in options, 'run_monitor.sh does not enable fail-on-unbound-variable (set -u)'

    logs_dir = Path('/home/user/logs')
    shutil.rmtree(logs_dir, ignore_errors=True)
    result = subprocess.run(
        [str(WRAPPER)],
        env={
            'PATH': '/usr/bin:/bin',
            'DATA_DIR': '/definitely/wrong/caller/value',
            'MONITOR_OUTPUT_PATH': '/tmp/definitely-wrong-monitor.log',
        },
        capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, f'run_monitor.sh failed: {result.stderr}'
    log_path = logs_dir / 'monitor_status.log'
    assert log_path.exists(), f'Log file {log_path} was not created.'
    lines = log_path.read_text().splitlines()
    assert lines and lines[-1] == 'STATUS: OK - /home/user/data'


def test_monitor_binary_fallback_behavior():
    fallback_log = Path('/home/user/wrong_logs/fallback.log')
    fallback_log.unlink(missing_ok=True)
    env = os.environ.copy()
    env['DATA_DIR'] = '/home/user/data'
    env.pop('MONITOR_OUTPUT_PATH', None)
    result = subprocess.run([str(MONITOR)], env=env, capture_output=True, text=True)
    assert result.returncode == 0
    assert fallback_log.exists()
    assert 'STATUS: OK - /home/user/data' in fallback_log.read_text()


def test_health_check_script_healthy_and_unhealthy():
    assert HEALTH.exists(), f'Script {HEALTH} does not exist.'
    assert HEALTH.is_file(), f'{HEALTH} is not a file.'
    assert os.access(HEALTH, os.X_OK), f'Script {HEALTH} is not executable.'

    log_path = Path('/home/user/logs/monitor_status.log')
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text('STATUS: ERROR - /random/path\nSTATUS: OK - /home/user/data\n')
    result = subprocess.run([str(HEALTH)], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0
    assert result.stdout.strip() == 'HEALTHY'

    log_path.write_text('STATUS: OK - old\nSTATUS: ERROR - latest\n')
    result = subprocess.run([str(HEALTH)], capture_output=True, text=True, timeout=10)
    assert result.returncode == 1
    assert result.stdout.strip() == 'UNHEALTHY'


def test_bash_profile_configured():
    bash_profile = Path('/home/user/.bash_profile')
    assert bash_profile.exists(), f'{bash_profile} does not exist.'
    content = bash_profile.read_text()
    assert 'export MONITOR_CONFIGURED=true' in content
    lines = [line.strip() for line in content.splitlines()]
    assert 'export MONITOR_CONFIGURED=true' in lines
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
