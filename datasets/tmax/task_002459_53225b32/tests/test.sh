#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import json
import os
import pwd
import subprocess
import tarfile
import tempfile
import uuid


def test_backup_img_exists_and_ext4():
    img_path = '/home/user/backup.img'
    assert os.path.isfile(img_path), f"File {img_path} does not exist"

    # Check size
    size = os.path.getsize(img_path)
    assert size == 20971520, f"Expected {img_path} size to be 20971520 bytes, got {size}"

    # Check ext4 format
    try:
        output = subprocess.check_output(['file', img_path], text=True)
        assert 'ext4' in output.lower(), f"Expected {img_path} to be formatted as ext4, got: {output}"
    except subprocess.CalledProcessError:
        pytest.fail(f"Failed to run 'file' command on {img_path}")


def test_system_fstab_configured():
    fstab_path = '/home/user/system_fstab'
    assert os.path.isfile(fstab_path), f"File {fstab_path} does not exist"

    with open(fstab_path, 'r') as f:
        lines = f.readlines()

    found = False
    for line in lines:
        parts = line.strip().split()
        if len(parts) >= 6:
            if parts[0] == '/home/user/backup.img' and parts[1] == '/home/user/mnt_backup' and parts[2] == 'ext4':
                if parts[3] == 'loop,defaults' and parts[4] == '0' and parts[5] == '2':
                    found = True
                    break

    assert found, "The fstab entry for /home/user/backup.img is missing or incorrect in /home/user/system_fstab"


def test_run_provision_script():
    script_path = '/home/user/run_provision.py'
    assert os.path.isfile(script_path), f"Python script {script_path} does not exist"

    with open(script_path, 'r') as f:
        content = f.read()

    assert 'pexpect' in content, f"The script {script_path} does not seem to import or use 'pexpect'"

    # Add an unpredictable source file and remove the old archive so the submitted
    # script must successfully drive the interactive tool during verification.
    probe_name = 'verifier_probe_' + uuid.uuid4().hex
    probe_path = os.path.join('/home/user/app_data', probe_name)
    probe_data = os.urandom(256)
    with open(probe_path, 'wb') as f:
        f.write(probe_data)
    os.chown(probe_path, pwd.getpwnam('user').pw_uid, pwd.getpwnam('user').pw_gid)

    tarball_path = '/home/user/app_data_backup.tar.gz'
    if os.path.lexists(tarball_path):
        os.remove(tarball_path)

    # Instrument the installed pexpect class at interpreter startup. This records
    # that the submitted program itself spawns the required legacy script and
    # performs the specified expect/send interaction.
    audit_dir = tempfile.mkdtemp(prefix='pexpect_audit_')
    os.chmod(audit_dir, 0o777)
    audit_log = os.path.join(audit_dir, 'events.jsonl')
    sitecustomize = os.path.join(audit_dir, 'sitecustomize.py')
    with open(sitecustomize, 'w') as f:
        f.write(r'''
import json
import os
import pexpect

_LOG = os.environ.get('PEXPECT_AUDIT_LOG')

def _norm(value):
    if isinstance(value, bytes):
        return value.decode('utf-8', 'replace')
    if isinstance(value, (str, int, float, bool)) or value is None:
        return value
    if isinstance(value, (list, tuple)):
        return [_norm(v) for v in value]
    if hasattr(value, 'pattern'):
        return _norm(value.pattern)
    return repr(value)

def _log(*event):
    with open(_LOG, 'a', encoding='utf-8') as out:
        out.write(json.dumps([_norm(v) for v in event]) + '\n')

_orig_init = pexpect.spawn.__init__
def _init(self, command, args=[], *a, **kw):
    _log('spawn', command, args)
    return _orig_init(self, command, args, *a, **kw)
pexpect.spawn.__init__ = _init

for _name in ('expect', 'expect_exact', 'expect_list'):
    if hasattr(pexpect.spawn, _name):
        _original = getattr(pexpect.spawn, _name)
        def _make_expect(name, original):
            def _wrapped(self, patterns, *a, **kw):
                _log(name, patterns)
                return original(self, patterns, *a, **kw)
            return _wrapped
        setattr(pexpect.spawn, _name, _make_expect(_name, _original))

for _name in ('send', 'sendline'):
    if hasattr(pexpect.spawn, _name):
        _original = getattr(pexpect.spawn, _name)
        def _make_send(name, original):
            def _wrapped(self, value='', *a, **kw):
                _log(name, value)
                return original(self, value, *a, **kw)
            return _wrapped
        setattr(pexpect.spawn, _name, _make_send(_name, _original))
''')

    user = pwd.getpwnam('user')
    env = os.environ.copy()
    env['HOME'] = '/home/user'
    env['PYTHONPATH'] = audit_dir
    env['PEXPECT_AUDIT_LOG'] = audit_log

    def demote():
        os.setgroups([])
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    try:
        result = subprocess.run(
            ['python3', script_path],
            cwd='/home/user',
            env=env,
            preexec_fn=demote,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"{script_path} failed when executed (exit {result.returncode}). "
            f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
        )
        assert os.path.isfile(audit_log), "No pexpect activity was recorded while executing run_provision.py"
        with open(audit_log, encoding='utf-8') as f:
            events = [json.loads(line) for line in f if line.strip()]

        def flattened(value):
            if isinstance(value, list):
                result = []
                for item in value:
                    result.extend(flattened(item))
                return result
            return [str(value)]

        pos = -1
        for i, event in enumerate(events):
            if event and event[0] == 'spawn' and '/home/user/legacy_backup.sh' in json.dumps(event):
                pos = i
                break
        assert pos >= 0, "run_provision.py did not use pexpect to spawn /home/user/legacy_backup.sh"

        interactions = [
            ('expect', 'Password:'),
            ('send', 'SecretPass99'),
            ('expect', 'Source path:'),
            ('send', '/home/user/app_data'),
            ('expect', 'Destination tarball:'),
            ('send', '/home/user/app_data_backup.tar.gz'),
        ]
        for kind, expected in interactions:
            found = False
            for i in range(pos + 1, len(events)):
                event = events[i]
                if not event:
                    continue
                if kind == 'expect' and event[0] not in ('expect', 'expect_exact', 'expect_list'):
                    continue
                if kind == 'send' and event[0] not in ('send', 'sendline'):
                    continue
                values = flattened(event[1:])
                if kind == 'expect' and any(expected in value for value in values):
                    pos = i
                    found = True
                    break
                if kind == 'send' and any(value.rstrip('\r\n') == expected for value in values):
                    pos = i
                    found = True
                    break
            assert found, f"Missing or out-of-order pexpect {kind} operation for {expected!r}"

        assert os.path.isfile(tarball_path), "Executing run_provision.py did not create the tarball"
        with tarfile.open(tarball_path, 'r:gz') as tar:
            member = next((m for m in tar.getmembers() if m.name in (probe_name, './' + probe_name)), None)
            assert member is not None, "The newly generated archive does not contain the verifier's source probe"
            extracted = tar.extractfile(member)
            assert extracted is not None and extracted.read() == probe_data, "The source probe content in the archive is incorrect"
    finally:
        if os.path.exists(probe_path):
            os.remove(probe_path)


def test_tarball_created():
    tarball_path = '/home/user/app_data_backup.tar.gz'
    assert os.path.isfile(tarball_path), f"Tarball {tarball_path} was not created"

    assert tarfile.is_tarfile(tarball_path), f"File {tarball_path} is not a valid tar archive"

    try:
        with tarfile.open(tarball_path, 'r:gz') as tar:
            names = tar.getnames()
            assert 'config.json' in names or './config.json' in names, "Expected config.json in tarball"
            assert 'data.bin' in names or './data.bin' in names, "Expected data.bin in tarball"
    except tarfile.ReadError:
        assert False, f"File {tarball_path} is not a valid gzip compressed tar archive"


def test_provision_summary_log():
    log_path = '/home/user/provision_summary.log'
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist"

    with open(log_path, 'r') as f:
        content = f.read().strip().split('\n')

    assert len(content) == 3, f"Expected exactly 3 lines in {log_path}, got {len(content)}"

    assert content[0] == 'FSTAB_CONFIGURED=true', f"Line 1 incorrect: {content[0]}"
    assert content[1] == 'BACKUP_ARCHIVE_CREATED=true', f"Line 2 incorrect: {content[1]}"
    assert content[2] == 'BACKUP_IMG_SIZE=20971520', f"Line 3 incorrect: {content[2]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
