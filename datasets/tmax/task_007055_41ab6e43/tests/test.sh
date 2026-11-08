#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import stat
import subprocess
import tempfile
import uuid

HOME = '/home/user'
REPO = '/home/user/dash_config'
GIT = '/usr/bin/git'


def run_git(args, check=False, env=None):
    command = [GIT, '-c', f'safe.directory={REPO}'] + args
    return subprocess.run(
        command,
        cwd=REPO,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
        check=check,
        env=env,
    )


def read_bytes(path):
    with open(path, 'rb') as f:
        return f.read()


def assert_single_append(path, before, expected):
    after = read_bytes(path)
    assert after == before + expected, (
        f'{path} did not receive exactly the expected appended line. '
        f'Expected suffix {expected!r}, got {after[len(before):]!r}.'
    )


def exercise_logger(binary, name, value):
    log_path = '/home/user/dashboard_metrics.log'
    before = read_bytes(log_path)
    result = subprocess.run(
        [binary],
        input=f'{name}\n{value}\n',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f'{binary} did not exit cleanly: {result.stderr}'
    assert result.stdout == 'Enter metric name: Enter metric value: ', (
        f'{binary} printed incorrect prompts: {result.stdout!r}'
    )
    expected = f'{{"metric": "{name}", "value": {value}}}\n'.encode()
    assert_single_append(log_path, before, expected)


def test_metric_logger_c_exists():
    path = '/home/user/metric_logger.c'
    assert os.path.isfile(path), f'{path} does not exist.'


def test_metric_logger_executable_exists():
    path = '/home/user/metric_logger'
    assert os.path.isfile(path), f'{path} does not exist.'
    assert os.access(path, os.X_OK), f'{path} is not executable.'
    assert read_bytes(path).startswith(b'\x7fELF'), f'{path} is not a compiled ELF binary.'


def test_push_metric_exp_executable_exists():
    path = '/home/user/push_metric.exp'
    assert os.path.isfile(path), f'{path} does not exist.'
    assert os.access(path, os.X_OK), f'{path} is not executable.'


def test_post_commit_hook_executable_exists():
    path = '/home/user/dash_config/.git/hooks/post-commit'
    assert os.path.isfile(path), f'{path} does not exist.'
    assert os.access(path, os.X_OK), f'{path} is not executable.'


def test_dashboard_metrics_log_contents():
    path = '/home/user/dashboard_metrics.log'
    assert os.path.isfile(path), f'{path} does not exist.'

    with open(path, 'r') as f:
        lines = f.readlines()

    found = False
    for line in lines:
        try:
            data = json.loads(line.strip())
            if data.get('metric') == 'dashboard_updates' and data.get('value') == 1:
                found = True
                break
        except json.JSONDecodeError:
            continue

    assert found, f'Expected JSON log entry not found in {path}.'


def test_dash_json_exists_and_content():
    path = '/home/user/dash_config/dash.json'
    assert os.path.isfile(path), f'{path} does not exist.'

    with open(path, 'r') as f:
        content = f.read().strip()

    try:
        data = json.loads(content)
        assert data.get('refresh') == 5, 'dash.json does not contain the expected content.'
    except json.JSONDecodeError:
        assert False, 'dash.json does not contain valid JSON.'

    assert content == '{"refresh": 5}', 'dash.json does not contain exactly the requested JSON.'


def test_git_commit_made():
    assert os.path.isdir(os.path.join(REPO, '.git')), f'Git repository not initialized in {REPO}.'

    result = run_git(['log', '--oneline'])
    assert result.returncode == 0, 'Failed to run git log. Are there any commits?'
    assert len(result.stdout.strip().split('\n')) >= 1, 'No commits found in the repository.'

    subject = run_git(['log', '-1', '--format=%s'], check=True).stdout.strip()
    assert subject == 'Initial dashboard config', f'Incorrect commit message: {subject!r}'

    committed = run_git(['show', 'HEAD:dash.json'], check=True).stdout.strip()
    assert committed == '{"refresh": 5}', 'dash.json is not committed with the requested content.'

    changed = run_git(['diff-tree', '--no-commit-id', '--name-only', '-r', 'HEAD'], check=True).stdout.splitlines()
    assert 'dash.json' in changed, 'The final commit does not include dash.json.'


def test_metric_logger_source_and_binary_behavior():
    token = uuid.uuid4().hex
    exercise_logger('/home/user/metric_logger', f'metric_{token}', 100000 + int(token[:5], 16))

    fd, compiled = tempfile.mkstemp(prefix='compiled_metric_logger_', dir='/tmp')
    os.close(fd)
    os.unlink(compiled)
    try:
        result = subprocess.run(
            ['/usr/bin/gcc', '/home/user/metric_logger.c', '-o', compiled],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, f'metric_logger.c does not compile: {result.stderr}'
        token = uuid.uuid4().hex
        exercise_logger(compiled, f'source_{token}', -(1000 + int(token[:4], 16)))
    finally:
        if os.path.exists(compiled):
            os.unlink(compiled)


def test_expect_script_drives_metric_logger():
    binary = '/home/user/metric_logger'
    expect_script = '/home/user/push_metric.exp'
    marker = f'/tmp/expect_probe_{uuid.uuid4().hex}'
    original = read_bytes(binary)
    original_mode = stat.S_IMODE(os.stat(binary).st_mode)
    probe = f'''#!/bin/sh
printf 'Enter metric name: '
IFS= read -r metric
printf 'Enter metric value: '
IFS= read -r value
printf '%s\\n%s\\n' "$metric" "$value" > '{marker}'
'''.encode()

    try:
        with open(binary, 'wb') as f:
            f.write(probe)
        os.chmod(binary, 0o755)
        result = subprocess.run(
            [expect_script],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, f'Expect script failed: {result.stderr}'
        assert os.path.isfile(marker), 'Expect script did not execute /home/user/metric_logger.'
        assert read_bytes(marker) == b'dashboard_updates\n1\n', (
            'Expect script did not send the required metric name and value.'
        )
    finally:
        with open(binary, 'wb') as f:
            f.write(original)
        os.chmod(binary, original_mode)
        if os.path.exists(marker):
            os.unlink(marker)


def test_post_commit_hook_and_end_to_end_flow():
    expect_script = '/home/user/push_metric.exp'
    log_path = '/home/user/dashboard_metrics.log'
    marker = f'/tmp/hook_probe_{uuid.uuid4().hex}'
    original_expect = read_bytes(expect_script)
    original_mode = stat.S_IMODE(os.stat(expect_script).st_mode)
    original_head = run_git(['rev-parse', 'HEAD'], check=True).stdout.strip()
    env = os.environ.copy()
    env.update({
        'GIT_AUTHOR_NAME': 'Verifier',
        'GIT_AUTHOR_EMAIL': 'verifier@example.invalid',
        'GIT_COMMITTER_NAME': 'Verifier',
        'GIT_COMMITTER_EMAIL': 'verifier@example.invalid',
    })

    try:
        before = read_bytes(log_path)
        message = f'verifier-e2e-{uuid.uuid4().hex}'
        result = run_git(['commit', '--allow-empty', '-m', message], env=env)
        assert result.returncode == 0, f'Could not create test commit: {result.stderr}'
        assert_single_append(
            log_path,
            before,
            b'{"metric": "dashboard_updates", "value": 1}\n',
        )
        run_git(['reset', '--hard', original_head], check=True)

        probe = f'''#!/bin/sh
printf 'hook-ran\\n' > '{marker}'
'''.encode()
        with open(expect_script, 'wb') as f:
            f.write(probe)
        os.chmod(expect_script, 0o755)

        message = f'verifier-hook-{uuid.uuid4().hex}'
        result = run_git(['commit', '--allow-empty', '-m', message], env=env)
        assert result.returncode == 0, f'Could not create hook probe commit: {result.stderr}'
        assert os.path.isfile(marker), 'The post-commit hook did not execute /home/user/push_metric.exp.'
        assert read_bytes(marker) == b'hook-ran\n', 'The hook probe produced unexpected output.'
    finally:
        with open(expect_script, 'wb') as f:
            f.write(original_expect)
        os.chmod(expect_script, original_mode)
        if os.path.exists(marker):
            os.unlink(marker)
        run_git(['reset', '--hard', original_head])
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
