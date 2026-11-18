#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import stat
import subprocess
import tempfile
import uuid
from pathlib import Path

import pytest

ROOT = Path('/home/user/microservice')
SOURCE = ROOT / 'auth_daemon.c'
EXPECT_SCRIPT = ROOT / 'test_auth.exp'
PIPELINE = ROOT / 'ci_pipeline.sh'
BUILT = ROOT / 'auth_daemon'
DEPLOYED = Path('/home/user/deploy/bin/auth_daemon')
LOG = Path('/home/user/deploy/deploy.log')
USERS = Path('/home/user/data/users.txt')
PROMPT = 'Enter username: '


def run(cmd, **kwargs):
    kwargs.setdefault('text', True)
    kwargs.setdefault('capture_output', True)
    kwargs.setdefault('timeout', 15)
    return subprocess.run(cmd, **kwargs)


def test_deployed_executable_exists():
    """Retain the original deployed-artifact assertion."""
    assert DEPLOYED.is_file(), f'Executable {DEPLOYED} does not exist.'
    assert os.access(DEPLOYED, os.X_OK), f'File {DEPLOYED} is not executable.'


def test_deploy_log_contents():
    """Retain the original deploy-log assertion."""
    assert LOG.is_file(), f'Log file {LOG} does not exist.'
    content = LOG.read_text().strip()
    assert content == 'CI pipeline passed', (
        "Log file content is incorrect. Expected 'CI pipeline passed', "
        f"got '{content}'."
    )


def test_bashrc_path_modification():
    """Retain the original PATH assertion."""
    bashrc = Path('/home/user/.bashrc')
    assert bashrc.is_file(), f'{bashrc} does not exist.'
    expected = 'export PATH=$PATH:/home/user/deploy/bin'
    assert expected in bashrc.read_text().splitlines(), (
        f'{bashrc} does not contain the expected PATH export line.'
    )


def test_required_inputs_exist_and_are_real_scripts_and_source():
    for path in (SOURCE, EXPECT_SCRIPT, PIPELINE):
        assert path.is_file(), f'Missing required file: {path}'
        assert path.stat().st_size > 0, f'Required file is empty: {path}'

    assert os.access(EXPECT_SCRIPT, os.X_OK), 'test_auth.exp is not executable'
    assert os.access(PIPELINE, os.X_OK), 'ci_pipeline.sh is not executable'

    syntax = run(['bash', '-n', str(PIPELINE)])
    assert syntax.returncode == 0, syntax.stderr

    # The submitted source itself must compile with gcc.
    with tempfile.TemporaryDirectory() as td:
        output = Path(td) / 'auth_daemon'
        compiled = run(['gcc', str(SOURCE), '-o', str(output)])
        assert compiled.returncode == 0, compiled.stderr
        assert output.is_file() and os.access(output, os.X_OK)

    pipeline_text = PIPELINE.read_text()
    assert re.search(r'\bgcc\b', pipeline_text), 'Pipeline does not invoke gcc'
    assert 'auth_daemon.c' in pipeline_text and 'auth_daemon' in pipeline_text
    assert 'AUTH_STORE' in pipeline_text
    assert 'test_auth.exp' in pipeline_text
    assert '/home/user/deploy/bin' in pipeline_text
    assert 'CI pipeline passed' in pipeline_text

    expect_text = EXPECT_SCRIPT.read_text()
    required_tokens = [
        './auth_daemon', 'Enter username: ', 'service_account',
        'Access Granted', 'hacker', 'Access Denied', 'QUIT'
    ]
    positions = []
    for token in required_tokens:
        pos = expect_text.find(token)
        assert pos >= 0, f'test_auth.exp is missing {token!r}'
        positions.append(pos)
    assert positions == sorted(positions), 'Expect interactions are not in the required order'
    assert expect_text.count('Enter username: ') >= 3, 'Expect script must wait for three prompts'


def test_pipeline_failure_stops_deployment_then_successfully_rebuilds():
    original = EXPECT_SCRIPT.read_bytes()
    original_mode = stat.S_IMODE(EXPECT_SCRIPT.stat().st_mode)
    deploy_root = Path('/home/user/deploy')

    try:
        # Force the required test stage to fail and ensure the pipeline does not deploy.
        EXPECT_SCRIPT.write_text('#!/usr/bin/expect -f\nexit 1\n')
        EXPECT_SCRIPT.chmod(original_mode | stat.S_IXUSR)
        shutil.rmtree(deploy_root, ignore_errors=True)
        failed = run(['bash', str(PIPELINE)], cwd='/tmp', timeout=30)
        assert failed.returncode != 0, 'Pipeline succeeded even though its expect test failed'
        assert not DEPLOYED.exists(), 'Pipeline deployed a binary after a failed expect test'
        assert not LOG.exists(), 'Pipeline wrote a success log after a failed expect test'
    finally:
        EXPECT_SCRIPT.write_bytes(original)
        EXPECT_SCRIPT.chmod(original_mode)

    # Run the actual submitted pipeline from outside the project directory.
    successful = run(['bash', str(PIPELINE)], cwd='/tmp', timeout=30)
    assert successful.returncode == 0, (
        f'Pipeline failed. stdout={successful.stdout!r} stderr={successful.stderr!r}'
    )
    assert USERS.is_file(), 'Pipeline did not create users.txt'
    assert USERS.read_bytes() == b'admin\nservice_account\n', (
        'users.txt must contain exactly admin and service_account on separate lines'
    )
    assert BUILT.is_file() and os.access(BUILT, os.X_OK), 'Pipeline did not compile auth_daemon'
    assert DEPLOYED.is_file() and os.access(DEPLOYED, os.X_OK), 'Pipeline did not deploy auth_daemon'
    assert BUILT.read_bytes() == DEPLOYED.read_bytes(), 'Deployed binary is not the compiled binary'
    assert LOG.is_file() and LOG.read_text().strip() == 'CI pipeline passed'


def _check_daemon(executable):
    valid = 'valid_' + uuid.uuid4().hex
    invalid = valid + '_extra'
    second = 'other_' + uuid.uuid4().hex

    with tempfile.NamedTemporaryFile(mode='w', delete=False) as store:
        store.write(valid + '\n' + second + '\n')
        store_path = store.name

    try:
        env = os.environ.copy()
        env['AUTH_STORE'] = store_path
        proc = run(
            [str(executable)],
            input=f'{valid}\n{invalid}\n{second}\nQUIT\n',
            env=env,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stderr
        expected = (
            PROMPT + 'Access Granted\n' +
            PROMPT + 'Access Denied\n' +
            PROMPT + 'Access Granted\n' +
            PROMPT
        )
        assert proc.stdout == expected, (
            f'Incorrect prompt/response association. Expected {expected!r}, got {proc.stdout!r}'
        )

        env.pop('AUTH_STORE', None)
        no_store = run([str(executable)], input='QUIT\n', env=env, timeout=5)
        assert no_store.returncode == 1, 'auth_daemon must return 1 without AUTH_STORE'

        env['AUTH_STORE'] = store_path + '.missing'
        missing = run([str(executable)], input='QUIT\n', env=env, timeout=5)
        assert missing.returncode == 1, 'auth_daemon must return 1 when AUTH_STORE cannot be opened'
    finally:
        os.unlink(store_path)


def test_auth_daemon_functionality():
    """Retain the original checks and add exact, randomized interaction checks."""
    assert DEPLOYED.is_file(), 'Cannot test auth_daemon: file not found.'

    with tempfile.NamedTemporaryFile(mode='w', delete=False) as temp_store:
        temp_store.write('testuser1\nadmin\n')
        temp_store_path = temp_store.name
    try:
        env = os.environ.copy()
        env['AUTH_STORE'] = temp_store_path
        process = run(
            [str(DEPLOYED)],
            input='testuser1\nbaduser\nQUIT\n',
            env=env,
            timeout=5,
        )
        assert process.returncode == 0
        assert 'Access Granted' in process.stdout
        assert 'Access Denied' in process.stdout

        env.pop('AUTH_STORE', None)
        process_no_store = run([str(DEPLOYED)], input='QUIT\n', env=env, timeout=5)
        assert process_no_store.returncode == 1
    finally:
        os.unlink(temp_store_path)

    _check_daemon(DEPLOYED)

    # Also execute a fresh binary built directly from the submitted C source.
    with tempfile.TemporaryDirectory() as td:
        fresh = Path(td) / 'auth_daemon'
        compiled = run(['gcc', str(SOURCE), '-o', str(fresh)])
        assert compiled.returncode == 0, compiled.stderr
        _check_daemon(fresh)


def test_expect_script_really_checks_the_interaction():
    script_text = EXPECT_SCRIPT.read_text()

    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        copied_expect = td / 'test_auth.exp'
        copied_expect.write_text(script_text)
        copied_expect.chmod(0o755)
        fake = td / 'auth_daemon'

        # A protocol-correct fake proves the expect script can complete its sequence.
        fake.write_text("""#!/usr/bin/env python3
import sys
for expected, answer in [('service_account', 'Access Granted'), ('hacker', 'Access Denied')]:
    sys.stdout.write('Enter username: '); sys.stdout.flush()
    line = sys.stdin.readline().rstrip('\\r\\n')
    if line != expected:
        sys.exit(7)
    print(answer, flush=True)
sys.stdout.write('Enter username: '); sys.stdout.flush()
if sys.stdin.readline().rstrip('\\r\\n') != 'QUIT':
    sys.exit(8)
sys.exit(0)
""")
        fake.chmod(0o755)
        good = run(['expect', str(copied_expect)], cwd=str(td), timeout=15)
        assert good.returncode == 0, (
            f'Expect script failed the required interaction: {good.stdout!r} {good.stderr!r}'
        )

        # It must not report success when the first authorization result is wrong.
        fake.write_text("""#!/usr/bin/env python3
import sys
sys.stdout.write('Enter username: '); sys.stdout.flush()
sys.stdin.readline()
print('Access Denied', flush=True)
sys.exit(0)
""")
        fake.chmod(0o755)
        wrong = run(['expect', str(copied_expect)], cwd=str(td), timeout=15)
        assert wrong.returncode == 1, 'Expect script did not fail on an incorrect response'

        # It must also fail if the exact prompt never appears.
        fake.write_text("""#!/usr/bin/env python3
print('Wrong prompt', flush=True)
""")
        fake.chmod(0o755)
        absent = run(['expect', str(copied_expect)], cwd=str(td), timeout=15)
        assert absent.returncode == 1, 'Expect script did not fail when the prompt was absent'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
