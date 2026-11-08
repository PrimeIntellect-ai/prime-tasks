#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shlex
import subprocess
from pathlib import Path

import pytest

HOME = Path('/home/user')


def run(command, *, env=None):
    return subprocess.run(
        command,
        env=env,
        text=True,
        capture_output=True,
        timeout=10,
        check=True,
    )


def read_json(path):
    with open(path, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'{path} is not valid JSON')


def test_extracted_directories():
    assert os.path.isdir('/home/user/app_restored/config'), 'The config directory was not extracted to /home/user/app_restored/config'
    assert os.path.isdir('/home/user/app_restored/system'), 'The system directory was not extracted to /home/user/app_restored/system'


def test_symlink_active_config():
    link_path = '/home/user/active_config'
    expected_target = '/home/user/app_restored/config'
    assert os.path.islink(link_path), f'{link_path} is not a symbolic link'
    assert os.readlink(link_path) == expected_target, f'Symlink {link_path} does not point to {expected_target}'


def test_setup_env_script():
    script_path = '/home/user/setup_env.sh'
    assert os.path.isfile(script_path), f'Setup script {script_path} does not exist'
    with open(script_path, 'r') as f:
        content = f.read()
    assert 'APP_RESTORE_MODE' in content or '.env' in content, f'Setup script {script_path} does not seem to export variables from .env'


def test_bashrc_sourcing():
    bashrc_path = '/home/user/.bashrc'
    assert os.path.isfile(bashrc_path), f'{bashrc_path} does not exist'
    with open(bashrc_path, 'r') as f:
        content = f.read()
    assert 'setup_env.sh' in content, f'{bashrc_path} does not source setup_env.sh'


def test_identity_map_json():
    json_path = '/home/user/identity_map.json'
    assert os.path.isfile(json_path), f'Identity map {json_path} does not exist'
    data = read_json(json_path)
    expected_map = {
        'root': 'root',
        'svc_app': 'app_group',
        'bkp_admin': 'bkp_operators',
    }
    assert data == expected_map, f'Identity map content {data} does not match expected {expected_map}'


def test_restore_report_json():
    report_path = '/home/user/restore_report.json'
    assert os.path.isfile(report_path), f'Restore report {report_path} does not exist'
    data = read_json(report_path)
    expected_report = {
        'config_link_valid': True,
        'app_mode': 'dry_run_validation',
        'mapped_users': {
            'root': 'root',
            'svc_app': 'app_group',
            'bkp_admin': 'bkp_operators',
        },
    }
    assert data == expected_report, f'Restore report content {data} does not match expected {expected_report}'


def test_environment_setup_behavior_and_bashrc_loading():
    env_file = HOME / 'app_restored/config/.env'
    setup_script = HOME / 'setup_env.sh'
    bashrc = HOME / '.bashrc'
    original_env = env_file.read_bytes()
    token = secrets.token_hex(8)
    expected = {
        'APP_RESTORE_MODE': f'mode_{token}',
        'DB_HOST': f'host_{token}',
        'DB_PORT': str(10000 + secrets.randbelow(50000)),
        'RESTORE_TEST_EXTRA': f'extra_{token}',
    }
    env_file.write_text(''.join(f'{key}={value}\n' for key, value in expected.items()))
    python_dump = "import json,os; print(json.dumps({k: os.environ.get(k) for k in " + repr(list(expected)) + '}))'
    try:
        direct = run([
            '/bin/bash', '--noprofile', '--norc', '-c',
            f'source {shlex.quote(str(setup_script))} && python3 -c {shlex.quote(python_dump)}',
        ], env={'HOME': str(HOME), 'PATH': os.environ.get('PATH', '')})
        assert json.loads(direct.stdout.strip()) == expected, 'Sourcing setup_env.sh did not export every variable currently defined in .env'

        via_bashrc = run([
            '/bin/bash', '--noprofile', '--rcfile', str(bashrc), '-i', '-c',
            f'python3 -c {shlex.quote(python_dump)}',
        ], env={'HOME': str(HOME), 'PATH': os.environ.get('PATH', ''), 'TERM': 'dumb'})
        assert json.loads(via_bashrc.stdout.strip()) == expected, '.bashrc did not actually source setup_env.sh'
    finally:
        env_file.write_bytes(original_env)


def test_map_identities_script_executes_and_derives_mapping():
    script = HOME / 'map_identities.py'
    passwd_file = HOME / 'app_restored/system/passwd.mock'
    group_file = HOME / 'app_restored/system/group.mock'
    output_file = HOME / 'identity_map.json'
    assert script.is_file(), f'{script} does not exist'

    original_passwd = passwd_file.read_bytes()
    original_group = group_file.read_bytes()
    original_output = output_file.read_bytes() if output_file.exists() else None
    token = secrets.token_hex(5)
    users = [f'user_a_{token}', f'user_b_{token}', f'user_c_{token}']
    groups = [f'group_x_{token}', f'group_y_{token}', f'group_z_{token}']
    gids = [str(31000 + secrets.randbelow(1000)), str(33000 + secrets.randbelow(1000)), str(35000 + secrets.randbelow(1000))]
    expected = dict(zip(users, groups))

    passwd_file.write_text(''.join(
        f'{user}:x:{41000 + i}:{gid}:Test User:/tmp/{user}:/bin/sh\n'
        for i, (user, gid) in enumerate(zip(users, gids))
    ))
    group_file.write_text(''.join(f'{group}:x:{gid}:\n' for group, gid in zip(groups, gids)))
    try:
        if output_file.exists():
            output_file.unlink()
        run(['python3', str(script)])
        assert output_file.is_file(), 'map_identities.py did not generate identity_map.json'
        assert read_json(output_file) == expected, 'map_identities.py did not derive usernames and primary groups from the mock identity files'
    finally:
        passwd_file.write_bytes(original_passwd)
        group_file.write_bytes(original_group)
        if original_output is None:
            output_file.unlink(missing_ok=True)
        else:
            output_file.write_bytes(original_output)


def test_verify_restore_script_executes_and_uses_live_inputs():
    script = HOME / 'verify_restore.py'
    identity_file = HOME / 'identity_map.json'
    report_file = HOME / 'restore_report.json'
    link = HOME / 'active_config'
    assert script.is_file(), f'{script} does not exist'

    original_identity = identity_file.read_bytes() if identity_file.exists() else None
    original_report = report_file.read_bytes() if report_file.exists() else None
    original_target = os.readlink(link)
    token = secrets.token_hex(8)
    dynamic_map = {f'dynamic_user_{token}': f'dynamic_group_{token}'}
    dynamic_mode = f'dynamic_mode_{token}'

    try:
        identity_file.write_text(json.dumps(dynamic_map))
        report_file.unlink(missing_ok=True)
        env = os.environ.copy()
        env['APP_RESTORE_MODE'] = dynamic_mode
        run(['python3', str(script)], env=env)
        assert report_file.is_file(), 'verify_restore.py did not generate restore_report.json'
        assert read_json(report_file) == {
            'config_link_valid': True,
            'app_mode': dynamic_mode,
            'mapped_users': dynamic_map,
        }, 'verify_restore.py did not use the live symlink, environment, and identity map'

        link.unlink()
        link.symlink_to('/home/user/app_restored/system')
        report_file.unlink(missing_ok=True)
        run(['python3', str(script)], env=env)
        invalid_report = read_json(report_file)
        assert invalid_report == {
            'config_link_valid': False,
            'app_mode': dynamic_mode,
            'mapped_users': dynamic_map,
        }, 'verify_restore.py did not detect an incorrect active_config symlink'
    finally:
        if link.is_symlink() or link.exists():
            link.unlink()
        link.symlink_to(original_target)
        if original_identity is None:
            identity_file.unlink(missing_ok=True)
        else:
            identity_file.write_bytes(original_identity)
        if original_report is None:
            report_file.unlink(missing_ok=True)
        else:
            report_file.write_bytes(original_report)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
