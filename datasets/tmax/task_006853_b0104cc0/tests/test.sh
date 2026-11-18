#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import stat
import subprocess
import tarfile
import tokenize
import uuid
from pathlib import Path

import pytest

REPO = Path('/home/user/backup_vault.git')
HOOK = REPO / 'hooks/post-receive'
LATEST = Path('/home/user/restores/latest')
FSTAB = Path('/home/user/mock_fstab')
SCRIPT = Path('/home/user/verify_restore.py')
LOG = Path('/home/user/restore_test.log')
PROMPT = 'Verify latest restore? [y/N]: '


def git_env():
    env = os.environ.copy()
    env['GIT_CONFIG_COUNT'] = '1'
    env['GIT_CONFIG_KEY_0'] = 'safe.directory'
    env['GIT_CONFIG_VALUE_0'] = '*'
    return env


def run(cmd, cwd=None, input_text=None):
    return subprocess.run(
        cmd,
        cwd=cwd,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=git_env(),
        check=True,
    )


def test_bare_repo_exists():
    """Verify that the bare Git repository was created."""
    repo_config = '/home/user/backup_vault.git/config'
    assert os.path.exists(repo_config), 'Bare repository not found at /home/user/backup_vault.git.'
    result = run(['git', '--git-dir', str(REPO), 'rev-parse', '--is-bare-repository'])
    assert result.stdout.strip() == 'true', f'{REPO} is not a bare Git repository.'


def test_post_receive_hook():
    """Verify that the post-receive hook exists, is executable, and is Python 3."""
    hook_path = '/home/user/backup_vault.git/hooks/post-receive'
    assert os.path.exists(hook_path), f'post-receive hook not found at {hook_path}.'
    assert os.access(hook_path, os.X_OK), f'post-receive hook at {hook_path} is not executable.'
    assert os.path.isfile(hook_path), f'post-receive hook at {hook_path} is not a regular file.'
    with tokenize.open(hook_path) as f:
        source = f.read()
    first_line = source.splitlines()[0] if source.splitlines() else ''
    assert first_line.startswith('#!') and 'python3' in first_line, 'post-receive must use a Python 3 shebang.'
    compile(source, hook_path, 'exec')


def test_restores_latest_symlink():
    """Verify that the latest restore symlink exists and points to a directory."""
    latest_link = '/home/user/restores/latest'
    assert os.path.islink(latest_link), f'{latest_link} is not a symlink.'
    target_dir = os.readlink(latest_link)
    assert target_dir
    resolved_target = os.path.realpath(latest_link)
    assert os.path.isdir(resolved_target), f'Symlink {latest_link} does not point to a valid directory.'


def test_manifest_in_latest_restore():
    """Verify that the manifest exists in the latest restore directory and has correct contents."""
    manifest_path = '/home/user/restores/latest/restore_manifest.json'
    assert os.path.exists(manifest_path), f'restore_manifest.json not found at {manifest_path}.'
    with open(manifest_path, 'r') as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail('restore_manifest.json is not valid JSON.')
    assert manifest.get('archive') == 'db_backup_v9.tar.gz', 'Incorrect archive value in manifest.'
    assert manifest.get('mount_target') == '/home/user/mnt/recovery_db', 'Incorrect mount_target value in manifest.'


def test_mock_fstab_updated():
    """Verify that mock_fstab contains the expected entry."""
    fstab_path = '/home/user/mock_fstab'
    assert os.path.exists(fstab_path), f'mock_fstab not found at {fstab_path}.'
    with open(fstab_path, 'r') as f:
        fstab_contents = f.read()
    expected_entry = 'db_backup_v9.tar.gz /home/user/mnt/recovery_db auto defaults 0 0'
    assert expected_entry in fstab_contents, f"mock_fstab does not contain the expected mount entry: '{expected_entry}'"


def test_verification_script_exists():
    """Verify the interactive verification script exists."""
    script_path = '/home/user/verify_restore.py'
    assert os.path.exists(script_path), f'verify_restore.py not found at {script_path}.'
    assert os.path.isfile(script_path), f'{script_path} is not a regular file.'


def test_restore_test_log():
    """Verify that the restore test log contains the expected success message."""
    log_path = '/home/user/restore_test.log'
    assert os.path.exists(log_path), f'restore_test.log not found at {log_path}.'
    with open(log_path, 'r') as f:
        log_contents = f.read()
    expected_log = 'SUCCESS: Restore registered for db_backup_v9.tar.gz at /home/user/mnt/recovery_db'
    assert expected_log in log_contents, f"restore_test.log does not contain the expected success message: '{expected_log}'"


def tree_snapshot(root):
    result = {}
    for path in sorted(Path(root).rglob('*')):
        rel = path.relative_to(root).as_posix()
        if path.is_symlink():
            result[rel] = ('symlink', os.readlink(path))
        elif path.is_dir():
            result[rel] = ('dir',)
        elif path.is_file():
            executable = bool(path.stat().st_mode & stat.S_IXUSR)
            result[rel] = ('file', executable, path.read_bytes())
        else:
            result[rel] = ('other',)
    return result


def test_live_push_and_interactive_behavior(tmp_path):
    """Push unpredictable content, exercise the hook, and test exact interactive behavior."""
    token = uuid.uuid4().hex
    archive_name = f'live_backup_{token}.tar.gz'
    mount_target = f'/home/user/mnt/live_{token}'
    expected_fstab_line = f'{archive_name} {mount_target} auto defaults 0 0'

    workspace = tmp_path / 'live_workspace'
    run(['git', 'clone', str(REPO), str(workspace)])
    run(['git', 'config', 'user.email', 'verifier@example.com'], cwd=workspace)
    run(['git', 'config', 'user.name', 'Verifier'], cwd=workspace)

    manifest = {'archive': archive_name, 'mount_target': mount_target}
    (workspace / 'restore_manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    payload = workspace / 'verification_payload'
    payload.mkdir()
    (payload / f'{token}.txt').write_text(f'unpredictable payload {token}\n')
    run(['git', 'add', 'restore_manifest.json', 'verification_payload'], cwd=workspace)
    run(['git', 'commit', '-m', f'Verifier live push {token}'], cwd=workspace)
    commit_hash = run(['git', 'rev-parse', 'HEAD'], cwd=workspace).stdout.strip()

    before_fstab = FSTAB.read_bytes()
    run(['git', 'push', 'origin', 'HEAD:master'], cwd=workspace)

    restore_dir = Path('/home/user/restores') / commit_hash
    assert restore_dir.is_dir(), f'Hook did not create {restore_dir}.'
    assert LATEST.is_symlink(), f'{LATEST} is no longer a symlink.'
    assert LATEST.resolve() == restore_dir.resolve(), 'latest does not point to the newly pushed commit restore.'

    archive_file = tmp_path / 'expected.tar'
    with archive_file.open('wb') as out:
        subprocess.run(
            ['git', 'archive', '--format=tar', 'HEAD'],
            cwd=workspace,
            stdout=out,
            stderr=subprocess.PIPE,
            env=git_env(),
            check=True,
        )
    expected_tree = tmp_path / 'expected_tree'
    expected_tree.mkdir()
    with tarfile.open(archive_file) as tf:
        tf.extractall(expected_tree)
    assert tree_snapshot(restore_dir) == tree_snapshot(expected_tree), 'Restore directory is not the exact pushed commit tree.'

    restored_manifest = json.loads((restore_dir / 'restore_manifest.json').read_text())
    assert restored_manifest == manifest
    after_fstab = FSTAB.read_bytes()
    assert after_fstab == before_fstab + (expected_fstab_line + '\n').encode(), 'Hook did not append exactly one derived mock_fstab line.'

    baseline_log = LOG.read_bytes()
    for refusal in ('n\n', 'yes\n', '\n'):
        result = run(['python3', str(SCRIPT)], input_text=refusal)
        assert result.stdout == PROMPT, 'Interactive script prompt is not exact.'
        assert result.stderr == ''
        assert LOG.read_bytes() == baseline_log, 'A non-y response changed restore_test.log.'

    success_line = f'SUCCESS: Restore registered for {archive_name} at {mount_target}\n'.encode()
    for acceptance in ('y\n', 'Y\n'):
        before = LOG.read_bytes()
        result = run(['python3', str(SCRIPT)], input_text=acceptance)
        assert result.stdout == PROMPT, 'Interactive script prompt is not exact.'
        assert result.stderr == ''
        assert LOG.read_bytes() == before + success_line, 'A y/Y response did not append exactly the derived success line.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
