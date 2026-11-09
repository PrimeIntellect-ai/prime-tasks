#!/bin/bash
set -e
mkdir -p /logs/verifier

if python3 - <<'PY'
import hashlib
import os
import shutil
import stat
import subprocess
import tempfile

SCRIPT = '/home/user/audit_and_fix.sh'
COMPROMISED = '/home/user/compromised_files.txt'
VIOLATIONS = '/home/user/permission_violations.txt'
q = chr(34)
CSP = 'Header set Content-Security-Policy ' + q + "default-src 'self';" + q


def read_report(path):
    assert os.path.isfile(path), f'Expected report {path} does not exist'
    with open(path, 'r') as f:
        lines = f.read().splitlines()
    assert all(lines), f'{path} contains blank lines'
    assert lines == sorted(lines), f'{path} is not sorted alphabetically: {lines}'
    return lines


# Preserve all original final-state assertions.
assert os.path.isfile(COMPROMISED), f'Expected log file {COMPROMISED} does not exist.'
original_compromised = read_report(COMPROMISED)
expected_compromised = '/home/user/app_env/bin/deploy.sh'
assert expected_compromised in original_compromised, f'{expected_compromised} was not found in {COMPROMISED}.'
assert original_compromised == [expected_compromised], f'Unexpected compromised-file report: {original_compromised}'

assert os.path.isfile(VIOLATIONS), f'Expected log file {VIOLATIONS} does not exist.'
original_violations = read_report(VIOLATIONS)
original_expected_violations = sorted([
    '/home/user/app_env/bin/deploy.sh',
    '/home/user/app_env/bin/start.sh',
    '/home/user/app_env/bin/suid_tool',
    '/home/user/app_env/config/app.conf',
    '/home/user/app_env/config/settings.json',
    '/home/user/app_env/known_hashes.txt',
    '/home/user/app_env/logs/access.log',
    '/home/user/app_env/logs/error.log',
])
for path in ['/home/user/app_env/bin/suid_tool', '/home/user/app_env/config/settings.json']:
    assert path in original_violations, f'Expected violation {path} not found in {VIOLATIONS}.'
    assert os.path.exists(path), f'File {path} is missing.'
    mode = os.stat(path).st_mode
    assert not mode & stat.S_ISUID, f'SUID bit is still set on {path}.'
    assert not mode & stat.S_ISGID, f'SGID bit is still set on {path}.'
    assert not mode & stat.S_IWOTH, f'World-writable bit is still set on {path}.'
assert original_violations == original_expected_violations, f'Not every original permission violation was reported: {original_violations}'
for path in original_expected_violations:
    mode = os.stat(path).st_mode
    assert not mode & (stat.S_ISUID | stat.S_ISGID | stat.S_IWOTH), f'Dangerous permission remains on {path}'

access_log = '/home/user/app_env/logs/access.log'
error_log = '/home/user/app_env/logs/error.log'
assert os.path.isfile(access_log), f'{access_log} does not exist.'
assert os.path.isfile(error_log), f'{error_log} does not exist.'
with open(access_log, 'r') as f:
    access_content = f.read()
with open(error_log, 'r') as f:
    error_content = f.read()
assert 'API_KEY=REDACTED' in access_content, f'Redacted API key not found in {access_log}.'
assert 'API_KEY=REDACTED' in error_content, f'Redacted API key not found in {error_log}.'
assert '1234567890abcdef' not in access_content, f'Original 16-char API key still present in {access_log}.'
assert 'ABCDEF1234567890' not in error_content, f'Original 16-char API key still present in {error_log}.'
assert 'API_KEY=short' in access_content, f'Short API key was incorrectly redacted in {access_log}.'

app_conf = '/home/user/app_env/config/app.conf'
assert os.path.isfile(app_conf), f'{app_conf} does not exist.'
with open(app_conf, 'r') as f:
    original_conf = f.read()
assert CSP in original_conf, f'CSP header line not found in {app_conf}.'
assert CSP in original_conf.splitlines(), f'CSP header is not present as an exact line in {app_conf}.'

assert os.path.isfile(SCRIPT), f'Script {SCRIPT} does not exist.'
script_mode = os.stat(SCRIPT).st_mode
assert script_mode & stat.S_IXUSR, f'Script {SCRIPT} is not executable by the owner.'
assert stat.S_ISREG(script_mode), f'{SCRIPT} is not a regular file.'

# Verify exact argument-count handling. A valid first target prevents an
# implementation that merely ignores the extra argument from passing.
probe = tempfile.mkdtemp(prefix='audit-arity-')
try:
    os.makedirs(os.path.join(probe, 'bin'))
    os.makedirs(os.path.join(probe, 'logs'))
    os.makedirs(os.path.join(probe, 'config'))
    open(os.path.join(probe, 'known_hashes.txt'), 'w').close()
    with open(os.path.join(probe, 'config', 'app.conf'), 'w') as f:
        f.write(CSP + '\n')
    zero = subprocess.run([SCRIPT], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
    assert zero.returncode != 0, 'Script accepted zero arguments'
    two = subprocess.run([SCRIPT, probe, 'extra'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
    assert two.returncode != 0, 'Script accepted more than one argument'
finally:
    shutil.rmtree(probe, ignore_errors=True)

# Build an unpredictable supplied target and execute the submitted artifact.
target = tempfile.mkdtemp(prefix='audit-target-')
try:
    bin_dir = os.path.join(target, 'bin')
    logs_dir = os.path.join(target, 'logs')
    nested_logs = os.path.join(logs_dir, 'nested')
    config_dir = os.path.join(target, 'config')
    nested_files = os.path.join(target, 'deep', 'more')
    for directory in [bin_dir, nested_logs, config_dir, nested_files]:
        os.makedirs(directory, exist_ok=True)

    valid_path = os.path.join(bin_dir, 'valid.sh')
    bad_path = os.path.join(bin_dir, 'changed.sh')
    valid_original = b'#!/bin/bash\necho valid\n'
    bad_original = b'#!/bin/bash\necho original\n'
    with open(valid_path, 'wb') as f:
        f.write(valid_original)
    with open(bad_path, 'wb') as f:
        f.write(bad_original)
    with open(os.path.join(target, 'known_hashes.txt'), 'w') as f:
        f.write(hashlib.sha256(valid_original).hexdigest() + '  valid.sh\n')
        f.write(hashlib.sha256(bad_original).hexdigest() + '  changed.sh\n')
    with open(bad_path, 'ab') as f:
        f.write(b'echo tampered\n')

    suid_path = os.path.join(target, 'deep', 'suid-item')
    sgid_path = os.path.join(nested_files, 'sgid-item')
    world_path = os.path.join(nested_files, 'world-item')
    for path in [suid_path, sgid_path, world_path]:
        with open(path, 'w') as f:
            f.write('permission fixture\n')
    os.chmod(suid_path, 0o4751)
    os.chmod(sgid_path, 0o2750)
    os.chmod(world_path, 0o606)

    dynamic_access = os.path.join(logs_dir, 'access.log')
    dynamic_nested = os.path.join(nested_logs, 'events.log')
    with open(dynamic_access, 'w') as f:
        f.write('one API_KEY=aB3dE6gH1jK2mN4p end\n')
        f.write('keep API_KEY=short and API_KEY=1234567890ABCDEFG\n')
    with open(dynamic_nested, 'w') as f:
        f.write('API_KEY=abcdefghijklmnop/API_KEY=ABCDEFGHIJKLMNOP\n')

    dynamic_conf = os.path.join(config_dir, 'app.conf')
    with open(dynamic_conf, 'w') as f:
        f.write('Header set X-Frame-Options DENY\n')

    for report in [COMPROMISED, VIOLATIONS]:
        try:
            os.unlink(report)
        except FileNotFoundError:
            pass

    result = subprocess.run([SCRIPT, target], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    assert result.returncode == 0, 'Script failed on supplied target:\n' + result.stdout.decode(errors='replace') + result.stderr.decode(errors='replace')

    dynamic_compromised = read_report(COMPROMISED)
    assert dynamic_compromised == [bad_path], f'Incorrect supplied-target integrity report: {dynamic_compromised}'

    expected_dynamic_violations = sorted([suid_path, sgid_path, world_path])
    dynamic_violations = read_report(VIOLATIONS)
    assert dynamic_violations == expected_dynamic_violations, f'Incorrect recursive permission report: {dynamic_violations}'

    expected_modes = {suid_path: 0o751, sgid_path: 0o750, world_path: 0o604}
    for path, expected_mode in expected_modes.items():
        actual = stat.S_IMODE(os.stat(path).st_mode)
        assert actual == expected_mode, f'{path} has mode {oct(actual)}, expected {oct(expected_mode)}'

    with open(dynamic_access, 'r') as f:
        redacted_access = f.read()
    assert redacted_access == 'one API_KEY=REDACTED end\nkeep API_KEY=short and API_KEY=1234567890ABCDEFG\n', 'Top-level log redaction was incorrect'
    with open(dynamic_nested, 'r') as f:
        redacted_nested = f.read()
    assert redacted_nested == 'API_KEY=REDACTED/API_KEY=REDACTED\n', 'Recursive or multiple-key redaction was incorrect'

    with open(dynamic_conf, 'r') as f:
        conf_lines = f.read().splitlines()
    assert conf_lines[-1] == CSP, 'Missing CSP was not appended as the exact final line'
    assert conf_lines.count(CSP) == 1, 'CSP line was added more than once'
finally:
    shutil.rmtree(target, ignore_errors=True)
PY
then
    echo '1' > /logs/verifier/reward.txt
else
    echo '0' > /logs/verifier/reward.txt
fi
