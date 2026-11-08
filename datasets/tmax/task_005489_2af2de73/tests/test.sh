#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import subprocess
from pathlib import Path
from urllib.parse import unquote, urlparse

import pytest

BARE = Path('/home/user/microservices.git')
CLONE = Path('/home/user/local_clone')
WORKSPACE = Path('/home/user/deploy_workspace')
DEPLOY_OUT = Path('/home/user/deploy_out')
HOOK = BARE / 'hooks' / 'post-receive'
LEGACY = Path('/home/user/legacy_deploy.sh')
TOKEN_FILE = Path('/home/user/.secrets/deploy_token.txt')


def git(*args, cwd=None, check=True):
    cmd = ['git', '-c', 'safe.directory=*']
    if cwd is not None:
        cmd += ['-C', str(cwd)]
    cmd += list(args)
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, check=check)


def test_deploy_out_status_log():
    """Test that status.log exists and contains DEPLOY_SUCCESS."""
    path = '/home/user/deploy_out/status.log'
    assert os.path.isfile(path), f'File {path} does not exist. The deployment hook may not have executed successfully.'

    with open(path, 'r') as f:
        content = f.read().strip()

    assert 'DEPLOY_SUCCESS' in content, f"File {path} does not contain 'DEPLOY_SUCCESS'. Found: {content}"


def test_deploy_out_app_config():
    """Test that app_config.json exists in deploy_out and has the correct content."""
    path = '/home/user/deploy_out/app_config.json'
    assert os.path.isfile(path), f'File {path} does not exist. The files were not synced correctly.'

    with open(path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'File {path} does not contain valid JSON.')

    assert data.get('version') == '2.0', f"File {path} does not contain the expected version '2.0'."


def test_bare_repo_exists():
    """Test that the bare git repository exists."""
    path = '/home/user/microservices.git'
    assert os.path.isdir(path), f'Directory {path} does not exist.'
    assert os.path.isfile(os.path.join(path, 'config')), f'{path} does not appear to be a valid git repository.'


def test_deploy_workspace_exists():
    """Test that the deploy workspace directory exists."""
    path = '/home/user/deploy_workspace'
    assert os.path.isdir(path), f'Directory {path} does not exist.'


def test_local_clone_exists():
    """Test that the local clone exists."""
    path = '/home/user/local_clone'
    assert os.path.isdir(path), f'Directory {path} does not exist.'
    assert os.path.isdir(os.path.join(path, '.git')), f'{path} is not a valid git repository clone.'


def test_repository_hook_and_live_pipeline():
    assert git('--git-dir', str(BARE), 'rev-parse', '--is-bare-repository').stdout.strip() == 'true'
    assert HOOK.is_file(), 'The bare repository has no post-receive hook.'
    hook_mode = HOOK.stat().st_mode
    assert hook_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH), 'The post-receive hook is not executable.'
    assert HOOK.read_bytes().strip(), 'The post-receive hook is empty.'

    assert git('symbolic-ref', '--short', 'HEAD', cwd=CLONE).stdout.strip() == 'main'
    bare_main = git('--git-dir', str(BARE), 'rev-parse', 'refs/heads/main').stdout.strip()
    local_head = git('rev-parse', 'HEAD', cwd=CLONE).stdout.strip()
    assert local_head == bare_main, 'The local clone has not pushed its main commit to the bare repository.'

    remote = git('remote', 'get-url', 'origin', cwd=CLONE).stdout.strip()
    if remote.startswith('file://'):
        remote_path = unquote(urlparse(remote).path)
    elif os.path.isabs(remote):
        remote_path = remote
    else:
        remote_path = str(CLONE / remote)
    assert os.path.realpath(remote_path) == os.path.realpath(BARE), 'local_clone is not connected to microservices.git.'

    committed_config = git('--git-dir', str(BARE), 'show', 'refs/heads/main:app_config.json').stdout
    assert json.loads(committed_config).get('version') == '2.0'

    nonce = secrets.token_hex(16)
    dynamic_token = 'verify_' + secrets.token_hex(24)
    probe_name = f'verifier_probe_{nonce}.txt'
    probe_file = CLONE / probe_name
    workspace_probe = WORKSPACE / probe_name
    deployed_probe = DEPLOY_OUT / probe_name
    marker = DEPLOY_OUT / 'hook_probe.log'

    legacy_bytes = LEGACY.read_bytes()
    legacy_mode = stat.S_IMODE(LEGACY.stat().st_mode)
    token_bytes = TOKEN_FILE.read_bytes()
    token_mode = stat.S_IMODE(TOKEN_FILE.stat().st_mode)

    probe_script = f'''#!/bin/bash
set -e
[ -t 0 ] || exit 71
printf 'Token: '
IFS= read -r input_token
REAL_TOKEN=$(cat /home/user/.secrets/deploy_token.txt)
[ "$input_token" = "$REAL_TOKEN" ] || exit 72
printf 'Proceed with filesystem sync? (yes/no): '
IFS= read -r proceed
[ "$proceed" = "yes" ] || exit 73
[ -f /home/user/deploy_workspace/{probe_name} ] || exit 74
[ "$(cat /home/user/deploy_workspace/{probe_name})" = "{nonce}" ] || exit 75
mkdir -p /home/user/deploy_out
cp /home/user/deploy_workspace/* /home/user/deploy_out/
printf 'DEPLOY_SUCCESS\n' > /home/user/deploy_out/status.log
printf '{nonce}\n' > /home/user/deploy_out/hook_probe.log
'''

    try:
        TOKEN_FILE.write_text(dynamic_token + '\n')
        os.chmod(TOKEN_FILE, token_mode)
        LEGACY.write_text(probe_script)
        os.chmod(LEGACY, legacy_mode | stat.S_IXUSR)

        marker.unlink(missing_ok=True)
        deployed_probe.unlink(missing_ok=True)
        workspace_probe.unlink(missing_ok=True)

        probe_file.write_text(nonce + '\n')
        git('config', 'user.name', 'Verifier', cwd=CLONE)
        git('config', 'user.email', 'verifier@localhost', cwd=CLONE)
        git('add', '--', probe_name, cwd=CLONE)
        git('commit', '-m', f'verifier pipeline probe {nonce}', '--', probe_name, cwd=CLONE)
        pushed_head = git('rev-parse', 'HEAD', cwd=CLONE).stdout.strip()
        result = git('push', 'origin', 'HEAD:refs/heads/main', cwd=CLONE, check=False)
        assert result.returncode == 0, f'Pushing main failed:\n{result.stdout}\n{result.stderr}'

        assert git('--git-dir', str(BARE), 'rev-parse', 'refs/heads/main').stdout.strip() == pushed_head
        assert workspace_probe.is_file(), 'The hook did not check out the newly pushed main revision.'
        assert workspace_probe.read_text().strip() == nonce
        assert marker.is_file(), 'The hook did not successfully invoke and interact with legacy_deploy.sh.'
        assert marker.read_text().strip() == nonce
        assert deployed_probe.is_file(), 'The live hook run did not synchronize the newly pushed file.'
        assert deployed_probe.read_text().strip() == nonce
        assert (DEPLOY_OUT / 'status.log').read_text().strip() == 'DEPLOY_SUCCESS'
        with open(DEPLOY_OUT / 'app_config.json') as f:
            assert json.load(f).get('version') == '2.0'
    finally:
        LEGACY.write_bytes(legacy_bytes)
        os.chmod(LEGACY, legacy_mode)
        TOKEN_FILE.write_bytes(token_bytes)
        os.chmod(TOKEN_FILE, token_mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
