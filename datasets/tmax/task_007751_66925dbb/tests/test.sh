#!/bin/bash
set -u
mkdir -p /logs/verifier

if python3 - <<'PY'
import json
import os
import pwd
import random
import re
import shutil
import stat
import subprocess
import tempfile
import time
from pathlib import Path

import jwt
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

POLICY = Path('/home/user/run_policy.sh')
RESULTS = Path('/home/user/enforcement_results.json')
PROJECTS_ROOT = Path('/home/user/projects')
PUBKEY = Path('/home/user/platform_pub.pem')
PROJECT_NAMES = ['project_alpha', 'project_beta', 'project_gamma']
SECRET_RE = re.compile(rb'MOCK_SEC_[a-zA-Z0-9]{16}')
USER = pwd.getpwnam('user')

assert POLICY.exists(), f'{POLICY} does not exist'
assert POLICY.is_file(), f'{POLICY} is not a regular file'
assert not POLICY.is_symlink(), f'{POLICY} must not be a symbolic link'


def remove_path(path):
    path = Path(path)
    if path.is_symlink() or (path.exists() and not path.is_dir()):
        path.unlink()
    elif path.exists():
        shutil.rmtree(path)


def run_policy():
    remove_path(RESULTS)

    def become_user():
        os.setgid(USER.pw_gid)
        os.setuid(USER.pw_uid)

    completed = subprocess.run(
        ['/bin/bash', str(POLICY)],
        cwd='/home/user',
        env={**os.environ, 'HOME': '/home/user', 'USER': 'user', 'LOGNAME': 'user'},
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=30,
        preexec_fn=become_user,
    )
    assert completed.returncode == 0, f'run_policy.sh exited with status {completed.returncode}'
    assert RESULTS.exists() and RESULTS.is_file() and not RESULTS.is_symlink(), \
        f'The expected output file {RESULTS} was not written as a regular file.'
    try:
        with RESULTS.open() as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'{RESULTS} does not contain valid JSON: {exc}')


def check_original_results(results):
    # Preserve the original verifier's fixture assertions.
    assert 'project_alpha' in results, 'project_alpha is missing from the results.'
    alpha = results['project_alpha']
    assert alpha.get('status') == 'pass', "project_alpha status should be 'pass'."
    alpha_reasons = alpha.get('reasons', [])
    assert isinstance(alpha_reasons, list), 'project_alpha reasons should be a list.'
    assert len(alpha_reasons) == 0, f'project_alpha reasons should be empty, got {alpha_reasons}.'

    assert 'project_beta' in results, 'project_beta is missing from the results.'
    beta = results['project_beta']
    assert beta.get('status') == 'fail', "project_beta status should be 'fail'."
    beta_reasons = beta.get('reasons', [])
    assert isinstance(beta_reasons, list), 'project_beta reasons should be a list.'
    assert sorted(beta_reasons) == ['hardcoded_secrets_found', 'invalid_token'], \
        f'Unexpected project_beta reasons: {beta_reasons}'

    assert 'project_gamma' in results, 'project_gamma is missing from the results.'
    gamma = results['project_gamma']
    assert gamma.get('status') == 'fail', "project_gamma status should be 'fail'."
    gamma_reasons = gamma.get('reasons', [])
    assert isinstance(gamma_reasons, list), 'project_gamma reasons should be a list.'
    assert sorted(gamma_reasons) == ['privilege_escalation_risk'], \
        f'Unexpected project_gamma reasons: {gamma_reasons}'


def expected_from_inputs():
    public_key = PUBKEY.read_bytes()
    expected = {}
    for name in PROJECT_NAMES:
        project = PROJECTS_ROOT / name
        reasons = []

        try:
            token = (project / 'deploy_token.jwt').read_text().strip()
            payload = jwt.decode(token, public_key, algorithms=['RS256'])
            if payload.get('deploy_role') != 'platform_admin':
                raise ValueError('wrong role')
        except Exception:
            reasons.append('invalid_token')

        found_secret = False
        for root, _, files in os.walk(project / 'source_code'):
            for filename in files:
                try:
                    if SECRET_RE.search((Path(root) / filename).read_bytes()):
                        found_secret = True
                        break
                except OSError:
                    pass
            if found_secret:
                break
        if found_secret:
            reasons.append('hardcoded_secrets_found')

        deploy_data = (project / 'deploy.sh').read_bytes()
        if b'chmod 777' in deploy_data or b'sudo su' in deploy_data or b'sudo bash' in deploy_data:
            reasons.append('privilege_escalation_risk')

        reasons.sort()
        expected[name] = {
            'status': 'fail' if reasons else 'pass',
            'reasons': reasons,
        }
    return expected


def write_project(name, token, source_files, deploy_text):
    project = PROJECTS_ROOT / name
    remove_path(project)
    (project / 'source_code').mkdir(parents=True)
    (project / 'deploy_token.jwt').write_text(token)
    for relative, content in source_files.items():
        target = project / 'source_code' / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(content, bytes):
            target.write_bytes(content)
        else:
            target.write_text(content)
    deploy = project / 'deploy.sh'
    deploy.write_text(deploy_text)
    deploy.chmod(0o755)
    for root, dirs, files in os.walk(project):
        os.chown(root, USER.pw_uid, USER.pw_gid)
        for entry in dirs + files:
            os.chown(os.path.join(root, entry), USER.pw_uid, USER.pw_gid)


def apply_round(cases):
    names = PROJECT_NAMES[:]
    random.SystemRandom().shuffle(names)
    for name, case in zip(names, cases):
        write_project(name, case['token'], case['sources'], case['deploy'])
    expected = expected_from_inputs()
    actual = run_policy()
    assert actual == expected, f'Dynamic input results were incorrect. Expected {expected}, got {actual}'


backup = Path(tempfile.mkdtemp(prefix='policy-verifier-'))
baseline_output = None
try:
    shutil.copytree(PROJECTS_ROOT, backup / 'projects', symlinks=True)
    shutil.copy2(PUBKEY, backup / 'platform_pub.pem')

    # Execute the submitted artifact against the original fixtures before checking
    # the original assertions, preventing a prewritten JSON file from passing.
    original = run_policy()
    check_original_results(original)
    baseline_output = RESULTS.read_bytes()

    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    private_pem = private_key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    )
    public_pem = private_key.public_key().public_bytes(
        serialization.Encoding.PEM,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    PUBKEY.write_bytes(public_pem)
    os.chown(PUBKEY, USER.pw_uid, USER.pw_gid)
    PUBKEY.chmod(0o644)

    now = int(time.time())
    valid = jwt.encode({'deploy_role': 'platform_admin', 'exp': now + 3600}, private_pem, algorithm='RS256')
    wrong_role = jwt.encode({'deploy_role': 'developer', 'exp': now + 3600}, private_pem, algorithm='RS256')
    expired = jwt.encode({'deploy_role': 'platform_admin', 'exp': now - 3600}, private_pem, algorithm='RS256')
    parts = valid.split('.')
    parts[2] = ('A' if parts[2][0] != 'A' else 'B') + parts[2][1:]
    tampered = '.'.join(parts)
    secret1 = 'MOCK_SEC_' + ''.join(random.SystemRandom().choice('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789') for _ in range(16))
    secret2 = 'MOCK_SEC_' + ''.join(random.SystemRandom().choice('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789') for _ in range(16))

    apply_round([
        {
            'token': valid,
            'sources': {'main.py': 'print("safe")\n', 'nested/readme.txt': 'no credentials here\n'},
            'deploy': '#!/bin/bash\necho safe deployment\n',
        },
        {
            'token': wrong_role,
            'sources': {'deep/config/data.txt': 'prefix ' + secret1 + ' suffix\n'},
            'deploy': '#!/bin/bash\nchmod 777 /srv/application\n',
        },
        {
            'token': expired,
            'sources': {'app.js': 'console.log("safe");\n'},
            'deploy': '#!/bin/bash\nsudo bash -c "echo deploy"\n',
        },
    ])

    apply_round([
        {
            'token': valid,
            'sources': {'a/b/c/secret.bin': b'\x00' + secret2.encode() + b'\xff'},
            'deploy': '#!/bin/bash\necho ordinary\n',
        },
        {
            'token': valid,
            'sources': {'clean.txt': 'MOCK_SEC_too_short\n'},
            'deploy': '#!/bin/bash\nsudo su -c "systemctl restart app"\n',
        },
        {
            'token': tampered,
            'sources': {'clean.py': 'value = 42\n'},
            'deploy': '#!/bin/bash\nchmod 777 /tmp/cache\nsudo bash -c true\n',
        },
    ])
finally:
    remove_path(PROJECTS_ROOT)
    shutil.copytree(backup / 'projects', PROJECTS_ROOT, symlinks=True)
    shutil.copy2(backup / 'platform_pub.pem', PUBKEY)
    if baseline_output is not None:
        remove_path(RESULTS)
        RESULTS.write_bytes(baseline_output)
        os.chown(RESULTS, USER.pw_uid, USER.pw_gid)
    shutil.rmtree(backup, ignore_errors=True)
PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
