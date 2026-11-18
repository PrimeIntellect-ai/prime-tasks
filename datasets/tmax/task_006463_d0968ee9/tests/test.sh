#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shlex
import stat
import subprocess
import tempfile
import uuid

import pytest

PROJECT = '/home/user/fstab-fixer'
BARE_REPO = '/home/user/iot-repo.git'
LOCAL_REPO = '/home/user/local-repo'
HOOK = '/home/user/iot-repo.git/hooks/post-receive'
FSTAB = '/home/user/latest_deployment.fstab'
LOG = '/home/user/deploy_status.log'

ORIGINAL_LINES = [
    '/dev/vdb /mnt/data/logs ext4 defaults 0 2',
    '/dev/vdc /mnt/data/logs/archive ext4 defaults 0 2',
    '/dev/vda /mnt/data ext4 defaults 0 2',
]
SORTED_ORIGINAL_LINES = [
    '/dev/vda /mnt/data ext4 defaults 0 2',
    '/dev/vdb /mnt/data/logs ext4 defaults 0 2',
    '/dev/vdc /mnt/data/logs/archive ext4 defaults 0 2',
]

_built_binaries = None


def run(cmd, cwd=None, check=True, env=None, timeout=180):
    return subprocess.run(
        cmd, cwd=cwd, check=check, env=env, timeout=timeout,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )


def normalized_fstab(path):
    with open(path, 'r') as f:
        return [' '.join(line.split()) for line in f if line.strip()]


def build_rust_project():
    global _built_binaries
    if _built_binaries is not None:
        return _built_binaries

    manifest = os.path.join(PROJECT, 'Cargo.toml')
    assert os.path.isfile(manifest), f'Missing Rust manifest: {manifest}'

    metadata_result = run(
        ['cargo', 'metadata', '--format-version=1', '--no-deps'], cwd=PROJECT
    )
    metadata = json.loads(metadata_result.stdout)
    project_real = os.path.realpath(PROJECT) + os.sep
    bin_targets = []
    for package in metadata.get('packages', []):
        manifest_path = os.path.realpath(package.get('manifest_path', ''))
        if manifest_path != os.path.realpath(manifest):
            continue
        for target in package.get('targets', []):
            if 'bin' in target.get('kind', []):
                source = os.path.realpath(target.get('src_path', ''))
                assert source.startswith(project_real) and source.endswith('.rs'), \
                    'The CLI binary target must be backed by Rust source in the project'
                bin_targets.append(target.get('name'))
    assert bin_targets, 'The Cargo project has no Rust binary target'

    run(['cargo', 'clean'], cwd=PROJECT)
    built = run(
        ['cargo', 'build', '--release', '--message-format=json'], cwd=PROJECT
    )

    executables = []
    for line in built.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        target = message.get('target', {})
        executable = message.get('executable')
        if executable and 'bin' in target.get('kind', []):
            executable = os.path.realpath(executable)
            if executable not in executables:
                executables.append(executable)

    assert executables, 'cargo build --release did not produce a binary executable'
    for executable in executables:
        assert os.path.isfile(executable), f'Missing release binary: {executable}'
        assert os.access(executable, os.X_OK), f'Release binary is not executable: {executable}'
        with open(executable, 'rb') as f:
            assert f.read(4) == b'\x7fELF', f'Release artifact is not a native binary: {executable}'

    _built_binaries = executables
    return executables


def test_latest_deployment_fstab():
    """Retain the original exact deployment-output assertion."""
    assert os.path.exists(FSTAB), f'File not found: {FSTAB}'
    actual_fstab = normalized_fstab(FSTAB)
    assert actual_fstab == SORTED_ORIGINAL_LINES, \
        f'Fstab content is incorrect. Expected: {SORTED_ORIGINAL_LINES}; got: {actual_fstab}'


def test_git_repo_and_deploy_status():
    """Retain the original repository HEAD and status-log assertion."""
    assert os.path.isdir(BARE_REPO), f'Git repo not found: {BARE_REPO}'
    try:
        latest_commit = run(['git', 'rev-parse', 'HEAD'], cwd=BARE_REPO).stdout.strip()
    except subprocess.CalledProcessError as e:
        pytest.fail(f'Failed to get latest commit from {BARE_REPO}: {e.stderr}')

    assert os.path.exists(LOG), f'Log file not found: {LOG}'
    expected_log_entry = f'DEPLOY_SUCCESS: {latest_commit}'
    with open(LOG, 'r') as f:
        log_content = f.read()
    assert expected_log_entry in log_content, \
        f"Log file does not contain expected entry: '{expected_log_entry}'"


def test_rust_release_cli_on_independent_input():
    binaries = build_rust_project()

    input_text = (
        '# verifier-generated configuration\n'
        '\n'
        '/dev/test3 /opt/data/logs ext4 defaults 0 2\n'
        '/dev/test1 /opt ext4 defaults 0 2\n'
        '/dev/test2 /opt/data ext4 defaults 0 2\n'
    )
    expected = [
        '/dev/test1 /opt ext4 defaults 0 2',
        '/dev/test2 /opt/data ext4 defaults 0 2',
        '/dev/test3 /opt/data/logs ext4 defaults 0 2',
    ]

    working_binary = None
    errors = []
    with tempfile.TemporaryDirectory(prefix='fstab-cli-') as td:
        source = os.path.join(td, 'input.fstab')
        with open(source, 'w') as f:
            f.write(input_text)

        for binary in binaries:
            output = os.path.join(td, 'output.fstab')
            try:
                if os.path.exists(output):
                    os.unlink(output)
                run([binary, source, output])
                if os.path.isfile(output) and normalized_fstab(output) == expected:
                    working_binary = binary
                    break
                errors.append(f'{binary}: incorrect output')
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
                errors.append(f'{binary}: {e}')

    assert working_binary is not None, \
        'No release Rust binary implemented the required CLI behavior: ' + '; '.join(errors)


def test_repository_hook_clone_commit_and_real_push_pipeline():
    binaries = build_rust_project()

    assert run(['git', 'rev-parse', '--is-bare-repository'], cwd=BARE_REPO).stdout.strip() == 'true'
    master_commit = run(['git', 'rev-parse', 'refs/heads/master'], cwd=BARE_REPO).stdout.strip()

    assert os.path.isdir(os.path.join(LOCAL_REPO, '.git')), 'Local repository is not a Git working clone'
    local_head = run(['git', 'rev-parse', 'HEAD'], cwd=LOCAL_REPO).stdout.strip()
    assert local_head == master_commit, 'Local clone HEAD does not match the pushed master commit'
    assert run(['git', 'log', '-1', '--format=%s'], cwd=LOCAL_REPO).stdout.strip() == 'Initial IoT config'
    assert run(['git', 'show', 'HEAD:device_fstab'], cwd=LOCAL_REPO).stdout.splitlines() == ORIGINAL_LINES
    assert run(['git', 'show', 'refs/heads/master:device_fstab'], cwd=BARE_REPO).stdout.splitlines() == ORIGINAL_LINES
    remote_master = run(['git', 'ls-remote', 'origin', 'refs/heads/master'], cwd=LOCAL_REPO).stdout.split()[0]
    assert remote_master == master_commit, 'The local repository origin is not the deployment master repository'

    assert os.path.isfile(HOOK), f'Missing post-receive hook: {HOOK}'
    assert os.access(HOOK, os.X_OK), 'post-receive hook is not executable'
    with open(HOOK, 'r') as f:
        hook_text = f.read()
    assert re.search(r'^\s*set\s+-[A-Za-z]*e[A-Za-z]*\s*(?:#.*)?$', hook_text, re.MULTILINE), \
        'post-receive hook does not enable shell error handling with set -e'

    dynamic_lines = [
        '/dev/verifier3 /srv/iot/data/archive ext4 defaults 0 2',
        '/dev/verifier1 /srv/iot ext4 defaults 0 2',
        '/dev/verifier2 /srv/iot/data ext4 defaults 0 2',
    ]
    expected_dynamic = [dynamic_lines[1], dynamic_lines[2], dynamic_lines[0]]
    dynamic_text = '# generated independently by verifier\n\n' + '\n'.join(dynamic_lines) + '\n'

    with open(LOG, 'r') as f:
        log_before = f.read()

    token = uuid.uuid4().hex
    marker = os.path.join('/tmp', f'fstab-binary-used-{token}')
    replacements = []
    pushed_commit = None

    try:
        # Interpose wrappers at freshly built Cargo artifact paths. The wrappers
        # invoke the original ELF, while recording that the hook really used it.
        for binary in binaries:
            real_binary = binary + '.verifier-real-' + token
            mode = stat.S_IMODE(os.stat(binary).st_mode)
            os.replace(binary, real_binary)
            with open(binary, 'w') as f:
                f.write('#!/bin/sh\n')
                f.write('printf "%s\\n" "$0" >> ' + shlex.quote(marker) + '\n')
                f.write('exec ' + shlex.quote(real_binary) + ' "$@"\n')
            os.chmod(binary, mode | stat.S_IXUSR)
            replacements.append((binary, real_binary, mode))

        with tempfile.TemporaryDirectory(prefix='pipeline-push-') as td:
            clone = os.path.join(td, 'repo')
            run(['git', 'clone', BARE_REPO, clone])
            run(['git', 'config', 'user.name', 'Verifier'], cwd=clone)
            run(['git', 'config', 'user.email', 'verifier@example.invalid'], cwd=clone)
            branch = 'verifier-' + token
            run(['git', 'checkout', '-b', branch], cwd=clone)
            with open(os.path.join(clone, 'device_fstab'), 'w') as f:
                f.write(dynamic_text)
            run(['git', 'add', 'device_fstab'], cwd=clone)
            run(['git', 'commit', '-m', 'Verifier dynamic deployment'], cwd=clone)
            pushed_commit = run(['git', 'rev-parse', 'HEAD'], cwd=clone).stdout.strip()
            run(['git', 'push', 'origin', f'HEAD:refs/heads/{branch}'], cwd=clone)
    finally:
        for binary, real_binary, mode in reversed(replacements):
            if os.path.exists(real_binary):
                if os.path.lexists(binary):
                    os.unlink(binary)
                os.replace(real_binary, binary)
                os.chmod(binary, mode)

    assert os.path.exists(marker), 'The post-receive hook did not execute a freshly built Rust release binary'
    with open(marker, 'r') as f:
        invocations = [line.strip() for line in f if line.strip()]
    os.unlink(marker)
    assert invocations, 'The post-receive hook did not invoke the release utility'

    assert normalized_fstab(FSTAB) == expected_dynamic, \
        'A real push did not generate the independently derived sorted deployment output'

    with open(LOG, 'r') as f:
        log_after = f.read()
    assert log_after == log_before + f'DEPLOY_SUCCESS: {pushed_commit}\n', \
        'The hook did not append exactly one correctly formatted success line for the pushed commit'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
