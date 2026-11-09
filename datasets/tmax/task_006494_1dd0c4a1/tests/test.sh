#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess

ENV_FILE = '/home/user/.alert_env'
PY_SCRIPT = '/home/user/check_deploy.py'
SH_SCRIPT = '/home/user/rotate_alerts.sh'
DEPLOY_LOG = '/home/user/deploy.log'
ALERTS_LOG = '/home/user/alerts.log'
BAK_LOG = '/home/user/alerts.log.bak'


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, **kwargs)


def exported_environment(source_file=None):
    command = '/usr/bin/env -0'
    if source_file is not None:
        command = f'source {source_file} && /usr/bin/env -0'
    result = subprocess.run(
        ['/usr/bin/env', '-i', 'HOME=/home/user', 'PATH=/usr/bin:/bin',
         '/bin/bash', '--noprofile', '--norc', '-c', command],
        check=True,
        capture_output=True,
    )
    entries = result.stdout.split(b'\0')
    return {
        item.split(b'=', 1)[0].decode(): item.split(b'=', 1)[1].decode()
        for item in entries if b'=' in item
    }


def write_deploy(lines):
    with open(DEPLOY_LOG, 'w') as f:
        for line in lines:
            f.write(line + '\n')


def read_lines(path):
    with open(path, 'r') as f:
        return f.read().splitlines()


def test_alert_env_exists_and_exports_exactly_one_variable():
    assert os.path.isfile(ENV_FILE), f'Environment file {ENV_FILE} is missing.'

    result = subprocess.run(
        f'source {ENV_FILE} && echo $ALERT_CODE',
        shell=True,
        executable='/bin/bash',
        capture_output=True,
        text=True,
        check=True,
    )
    assert result.stdout.strip() == 'DEP_FAIL_01', \
        f'ALERT_CODE is not correctly exported in {ENV_FILE}.'

    baseline = exported_environment()
    sourced = exported_environment(ENV_FILE)
    assert sourced.get('ALERT_CODE') == 'DEP_FAIL_01', \
        'ALERT_CODE must be exported with value DEP_FAIL_01.'
    without_alert = dict(sourced)
    without_alert.pop('ALERT_CODE', None)
    assert without_alert == baseline, \
        '.alert_env must export exactly one variable and must not alter other exported variables.'


def test_scripts_executable():
    assert os.path.isfile(PY_SCRIPT), f'Python script {PY_SCRIPT} is missing.'
    assert os.access(PY_SCRIPT, os.X_OK), f'Python script {PY_SCRIPT} is not executable.'
    assert os.path.isfile(SH_SCRIPT), f'Bash script {SH_SCRIPT} is missing.'
    assert os.access(SH_SCRIPT, os.X_OK), f'Bash script {SH_SCRIPT} is not executable.'


def test_original_monitor_behavior():
    write_deploy([
        'INFO: Starting deployment...',
        'INFO: Service A initialization started.',
        'INFO: Service B initialization started.',
        'ERROR: Missing dependency config: Service A not ready.',
        'INFO: Retrying Service B...',
        'ERROR: Missing dependency config: Service A not ready.',
        'INFO: Deployment aborted.',
    ])
    if os.path.exists(ALERTS_LOG):
        os.remove(ALERTS_LOG)

    run(
        f'source {ENV_FILE} && python3 {PY_SCRIPT}',
        shell=True,
        executable='/bin/bash',
    )

    assert os.path.isfile(ALERTS_LOG), f'{ALERTS_LOG} was not created by the script.'
    lines = read_lines(ALERTS_LOG)
    expected = '[DEP_FAIL_01] Alert triggered: Dependency not ready'
    assert len(lines) == 2, f'Expected 2 lines in {ALERTS_LOG}, but found {len(lines)}.'
    assert lines[0] == expected, f'First line in {ALERTS_LOG} is incorrect.'
    assert lines[1] == expected, f'Second line in {ALERTS_LOG} is incorrect.'


def test_original_rotation_behavior():
    expected = '[DEP_FAIL_01] Alert triggered: Dependency not ready'
    with open(ALERTS_LOG, 'w') as f:
        f.write(expected + '\n' + expected + '\n')
    if os.path.exists(BAK_LOG):
        os.remove(BAK_LOG)

    run(['bash', SH_SCRIPT])
    assert not os.path.exists(BAK_LOG), \
        f'{BAK_LOG} should not be created when lines <= 5.'
    lines = read_lines(ALERTS_LOG)
    assert len(lines) == 2, 'alerts.log was improperly modified when lines <= 5.'

    with open(ALERTS_LOG, 'a') as f:
        for _ in range(4):
            f.write('dummy log\n')
    run(['bash', SH_SCRIPT])

    assert os.path.isfile(BAK_LOG), f'{BAK_LOG} was not created when lines > 5.'
    bak_lines = read_lines(BAK_LOG)
    assert len(bak_lines) == 6, f'Expected 6 lines in {BAK_LOG}, found {len(bak_lines)}.'
    assert os.path.isfile(ALERTS_LOG), \
        f'{ALERTS_LOG} was deleted instead of truncated/recreated.'
    assert len(read_lines(ALERTS_LOG)) == 0, \
        f'{ALERTS_LOG} should be empty after rotation.'


def test_monitor_uses_current_log_and_environment_and_appends_per_occurrence():
    token = secrets.token_hex(12)
    alert_code = 'DYNAMIC_' + secrets.token_hex(10)
    occurrence_count = 1 + secrets.randbelow(7)
    marker = 'ERROR: Missing dependency config'

    log_lines = [
        f'INFO {token}: startup',
        'ERROR: Missing Dependency config',
        'prefix ERROR: Missing dependency: config',
    ]
    for i in range(occurrence_count):
        log_lines.insert((i * 2) % (len(log_lines) + 1),
                         f'{token}-{i} {marker} dynamic detail {secrets.token_hex(4)}')
    write_deploy(log_lines)

    existing = 'existing-' + secrets.token_hex(8)
    with open(ALERTS_LOG, 'w') as f:
        f.write(existing + '\n')

    env = os.environ.copy()
    env['ALERT_CODE'] = alert_code
    run(['python3', PY_SCRIPT], env=env)

    expected_alert = f'[{alert_code}] Alert triggered: Dependency not ready'
    assert read_lines(ALERTS_LOG) == [existing] + [expected_alert] * occurrence_count

    no_match_lines = [
        f'INFO {secrets.token_hex(8)}',
        'ERROR: Missing dependency configs',
        'error: Missing dependency config',
    ]
    write_deploy(no_match_lines)
    before = read_lines(ALERTS_LOG)
    env['ALERT_CODE'] = 'OTHER_' + secrets.token_hex(10)
    run(['python3', PY_SCRIPT], env=env)
    assert read_lines(ALERTS_LOG) == before, \
        'The monitor must not append alerts when the exact error substring is absent.'


def test_rotation_at_dynamic_boundaries_and_overwrites_backup():
    for count in (0, 1, 3, 5):
        content = [f'keep-{secrets.token_hex(8)}-{i}' for i in range(count)]
        with open(ALERTS_LOG, 'w') as f:
            for line in content:
                f.write(line + '\n')
        old_backup = 'old-backup-' + secrets.token_hex(8)
        with open(BAK_LOG, 'w') as f:
            f.write(old_backup + '\n')

        run(['bash', SH_SCRIPT])
        assert read_lines(ALERTS_LOG) == content, \
            f'alerts.log must be unchanged at {count} lines.'
        assert read_lines(BAK_LOG) == [old_backup], \
            f'Existing backup must be unchanged at {count} lines.'

    count = 6 + secrets.randbelow(7)
    content = [f'rotate-{secrets.token_hex(8)}-{i}' for i in range(count)]
    with open(ALERTS_LOG, 'w') as f:
        for line in content:
            f.write(line + '\n')
    with open(BAK_LOG, 'w') as f:
        f.write('stale backup that must be overwritten\n')

    run(['bash', SH_SCRIPT])
    assert os.path.isfile(BAK_LOG)
    assert read_lines(BAK_LOG) == content, \
        'Rotation must rename the complete alerts log and overwrite the old backup.'
    assert os.path.isfile(ALERTS_LOG)
    assert os.path.getsize(ALERTS_LOG) == 0, \
        'Rotation must create a new, empty alerts.log.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
