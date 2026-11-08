#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_filesystem_setup():
    v2_dir = '/home/user/deploy/releases/v2.0'
    conf_file = os.path.join(v2_dir, 'mail_server.conf')
    symlink = '/home/user/deploy/current'

    assert os.path.isdir(v2_dir), f"Directory {v2_dir} does not exist."
    assert os.path.isfile(conf_file), f"File {conf_file} does not exist."

    with open(conf_file, 'r') as f:
        content = f.read().strip()
    assert content == 'SMTP_HOST=staging.mail.internal', f"Incorrect content in {conf_file}: {content}"

    assert os.path.islink(symlink), f"{symlink} is not a symbolic link."
    target = os.readlink(symlink)
    # The symlink might be absolute or relative, but it should resolve to v2_dir.
    # The instructions say "Create a symbolic link at /home/user/deploy/current that points to the /home/user/deploy/releases/v2.0 directory."
    assert os.path.abspath(os.path.join(os.path.dirname(symlink), target)) == v2_dir, f"{symlink} does not point to {v2_dir}."

def test_bash_profile():
    profile_path = '/home/user/.bash_profile'
    assert os.path.isfile(profile_path), f"{profile_path} does not exist."

    with open(profile_path, 'r') as f:
        content = f.read()

    assert 'export DEPLOY_ENV=staging' in content, f"'export DEPLOY_ENV=staging' not found in {profile_path}."
    assert 'export MAIL_CONFIG=/home/user/deploy/current/mail_server.conf' in content, f"'export MAIL_CONFIG=/home/user/deploy/current/mail_server.conf' not found in {profile_path}."

def test_ssh_config():
    config_path = '/home/user/.ssh/config'
    assert os.path.isfile(config_path), f"{config_path} does not exist."

    with open(config_path, 'r') as f:
        content = f.read()

    assert 'PubkeyAuthentication yes' in content, f"'PubkeyAuthentication yes' not found in {config_path}."
    assert 'PubkeyAuthentication no' not in content, f"'PubkeyAuthentication no' should have been removed or changed in {config_path}."

def test_deployment_report():
    report_path = '/home/user/deployment_report.log'
    assert os.path.isfile(report_path), f"{report_path} does not exist."

    with open(report_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 2, f"{report_path} does not have at least two lines."
    assert lines[0] == '/home/user/deploy/releases/v2.0', f"First line of {report_path} is incorrect: {lines[0]}"
    assert lines[1] == 'PubkeyAuthentication yes', f"Second line of {report_path} is incorrect: {lines[1]}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
