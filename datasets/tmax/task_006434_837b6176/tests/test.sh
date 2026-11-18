#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shlex
import stat
import subprocess
import tempfile

ERROR = 'Observability Policy Violation: Null UID found.'
REPO = '/home/user/dashboards.git'
HOOK = os.path.join(REPO, 'hooks', 'pre-receive')
ZERO = '0' * 40


def git_bare(*args, input=None, env=None):
    return subprocess.run(
        ['git', '--git-dir=' + REPO, *args], input=input,
        capture_output=True, text=True, check=True, env=env
    ).stdout.strip()


def make_commit(files, parent=None, message=None):
    with tempfile.TemporaryDirectory() as td:
        env = os.environ.copy()
        env.update({
            'GIT_INDEX_FILE': os.path.join(td, 'index'),
            'GIT_AUTHOR_NAME': 'Verifier',
            'GIT_AUTHOR_EMAIL': 'verifier@example.invalid',
            'GIT_COMMITTER_NAME': 'Verifier',
            'GIT_COMMITTER_EMAIL': 'verifier@example.invalid',
        })
        if parent:
            git_bare('read-tree', parent, env=env)
        else:
            git_bare('read-tree', '--empty', env=env)
        for path, content in files.items():
            blob = git_bare('hash-object', '-w', '--stdin', input=content, env=env)
            git_bare('update-index', '--add', '--cacheinfo', '100644,' + blob + ',' + path, env=env)
        tree = git_bare('write-tree', env=env)
        args = ['commit-tree', tree]
        if parent:
            args += ['-p', parent]
        return git_bare(*args, input=(message or secrets.token_hex(12)) + '\n', env=env)


def run_hook(lines):
    return subprocess.run(
        [HOOK], cwd=REPO, input=''.join(lines), capture_output=True, text=True
    )


def test_task1_git_hook_exists_language_and_permissions():
    assert os.path.isfile(HOOK), f'pre-receive hook not found at {HOOK}'
    assert stat.S_ISREG(os.lstat(HOOK).st_mode), 'pre-receive hook must be a regular file'
    assert os.access(HOOK, os.X_OK), 'pre-receive hook is not executable'
    mode = stat.S_IMODE(os.stat(HOOK).st_mode)
    assert mode & 0o100, 'pre-receive hook must be executable by its owner'
    assert not mode & 0o022, 'pre-receive hook must not be group- or world-writable'

    with open(HOOK, 'r', errors='replace') as f:
        first = f.readline().strip()
    assert first.startswith('#!'), 'pre-receive hook must have a shebang'
    words = shlex.split(first[2:].strip())
    assert words, 'pre-receive hook has an invalid shebang'
    program = os.path.basename(words[0])
    if program == 'env':
        words = [w for w in words[1:] if not w.startswith('-')]
        assert words, 'pre-receive hook has an invalid env shebang'
        program = os.path.basename(words[0])
    assert program == 'bash' or program.startswith('python'), 'pre-receive hook must be written in Bash or Python'


def test_task1_randomized_hook_behavior_and_exact_stderr():
    token = secrets.token_hex(10)
    bad_path = 'generated/' + token + '.json'
    marker = 'prefix-' + secrets.token_hex(7) + '-"uid": null-suffix'
    bad = make_commit({bad_path: marker, 'notes-' + token + '.txt': secrets.token_hex(20)})
    result = run_hook([f'{ZERO} {bad} refs/heads/new-{token}\n'])
    assert result.returncode != 0, 'A newly pushed JSON file containing the forbidden exact string was accepted'
    assert result.stderr == ERROR + '\n', f'Hook stderr must be exactly {ERROR!r}; got {result.stderr!r}'

    good = make_commit({
        'generated/' + token + '-valid.json': '{"uid":"' + secrets.token_hex(8) + '"}',
        'generated/' + token + '.txt': marker,
        'generated/' + token + '-spacing.json': '{"uid" : null}',
    })
    result = run_hook([f'{ZERO} {good} refs/heads/good-{token}\n'])
    assert result.returncode == 0, f'Valid/non-JSON content was rejected: {result.stderr}'

    changed_path = 'nested/' + secrets.token_hex(8) + '.json'
    base = make_commit({changed_path: '{"uid":"' + secrets.token_hex(8) + '"}'})
    modified = make_commit({changed_path: '{"other":1,"uid": null}'}, parent=base)
    result = run_hook([f'{base} {modified} refs/heads/modified-{token}\n'])
    assert result.returncode != 0, 'A modified JSON file containing the forbidden exact string was accepted'
    assert result.stderr == ERROR + '\n', f'Hook stderr must be exactly {ERROR!r}; got {result.stderr!r}'


def test_task1_actual_randomized_pushes():
    token = secrets.token_hex(10)
    branch = 'verify-' + token
    filename = 'dashboard-' + token + '.json'
    with tempfile.TemporaryDirectory() as tmpdir:
        subprocess.run(['git', 'init'], cwd=tmpdir, check=True, capture_output=True)
        subprocess.run(['git', 'config', 'user.email', 'test@example.com'], cwd=tmpdir, check=True)
        subprocess.run(['git', 'config', 'user.name', 'Test User'], cwd=tmpdir, check=True)
        subprocess.run(['git', 'remote', 'add', 'origin', REPO], cwd=tmpdir, check=True)
        path = os.path.join(tmpdir, filename)
        with open(path, 'w') as f:
            f.write('{"random":"' + secrets.token_hex(8) + '","uid": null}')
        subprocess.run(['git', 'add', filename], cwd=tmpdir, check=True)
        subprocess.run(['git', 'commit', '-m', secrets.token_hex(16)], cwd=tmpdir, check=True, capture_output=True)
        bad = subprocess.run(['git', 'push', 'origin', 'HEAD:refs/heads/' + branch], cwd=tmpdir, capture_output=True, text=True)
        assert bad.returncode != 0, 'Pushing a dashboard with null UID should fail, but it succeeded'
        assert ERROR in bad.stderr, 'The pre-receive hook did not print the required error message'

        with open(path, 'w') as f:
            f.write('{"uid":"' + secrets.token_hex(12) + '"}')
        subprocess.run(['git', 'add', filename], cwd=tmpdir, check=True)
        subprocess.run(['git', 'commit', '-m', secrets.token_hex(16)], cwd=tmpdir, check=True, capture_output=True)
        good = subprocess.run(['git', 'push', 'origin', 'HEAD:refs/heads/' + branch], cwd=tmpdir, capture_output=True, text=True)
        assert good.returncode == 0, f'Pushing a valid dashboard should succeed, but failed with: {good.stderr}'


def test_task2_fstab_configuration():
    fstab_path = '/home/user/dashboard_fstab'
    assert os.path.isfile(fstab_path), f'File {fstab_path} does not exist.'
    mode = stat.S_IMODE(os.stat(fstab_path).st_mode)
    assert mode & 0o600 == 0o600, 'dashboard_fstab must be readable and writable by its owner'
    assert not mode & 0o133, 'dashboard_fstab must not be executable or group/world-writable'

    with open(fstab_path, 'r') as f:
        lines = f.readlines()
    found = False
    for line in lines:
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        parts = line.split()
        if len(parts) >= 6 and (
            parts[0] == 'UUID=9a3b2c1d-8e7f-4a5b-6c7d-8e9f0a1b2c3d' and
            parts[1] == '/home/user/dashboards_backup' and
            parts[2] == 'ext4' and
            parts[3] == 'rw,nosuid,nodev,noexec' and
            parts[4] == '0' and parts[5] == '2'
        ):
            found = True
            break
    assert found, 'The required fstab entry was not found or is formatted incorrectly in /home/user/dashboard_fstab.'


def test_task3_ssh_configuration():
    ssh_dir = '/home/user/.ssh'
    ssh_config_path = os.path.join(ssh_dir, 'config')
    assert os.path.isfile(ssh_config_path), f'SSH config file {ssh_config_path} does not exist.'
    assert stat.S_IMODE(os.stat(ssh_dir).st_mode) == 0o700, '/home/user/.ssh must have mode 700'
    assert stat.S_IMODE(os.stat(ssh_config_path).st_mode) == 0o600, 'SSH config must have mode 600'

    res = subprocess.run(['ssh', '-F', ssh_config_path, '-G', 'obs-jumpbox'], capture_output=True, text=True)
    assert res.returncode == 0, "Failed to parse SSH configuration using 'ssh -G'."
    output = res.stdout.lower().splitlines()
    assert 'hostname 192.168.10.100' in output, 'SSH Hostname/IP is not configured correctly.'
    assert 'user o11y' in output, 'SSH User is not configured correctly.'
    assert 'port 2222' in output, 'SSH Port is not configured correctly.'
    assert 'localforward 8080 dashboard-api.internal:80' in output, 'SSH LocalForward is not configured correctly.'
    assert 'pubkeyauthentication no' in output, 'SSH PubkeyAuthentication must be explicitly disabled (no).'
    assert 'passwordauthentication yes' in output, 'SSH PasswordAuthentication must be explicitly enabled (yes).'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
