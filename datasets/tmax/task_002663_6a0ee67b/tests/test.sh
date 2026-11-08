#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import socket
import subprocess
import tempfile
import time
import urllib.request
import pytest

AUDITOR = '/home/user/key_auditor.py'
CONFIG = '/home/user/bastion/sshd_config'
EXPECTED_CONFIG = b'''Port 2222
ListenAddress 127.0.0.1
HostKey /home/user/bastion/ssh_host_ed25519_key
AuthorizedKeysFile /home/user/.ssh/authorized_keys
UsePrivilegeSeparation no
StrictModes no
UsePAM no
PidFile /home/user/bastion/sshd.pid
'''


def tcp_rows():
    rows = []
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local_port = int(fields[1].rsplit(':', 1)[1], 16)
                    remote_port = int(fields[2].rsplit(':', 1)[1], 16)
                    rows.append((local_port, remote_port, fields[3], fields[9]))
        except FileNotFoundError:
            pass
    return rows


def owners_of_inode(inode):
    owners = set()
    for proc in glob.glob('/proc/[0-9]*'):
        try:
            for fd in os.listdir(proc + '/fd'):
                try:
                    if os.readlink(proc + '/fd/' + fd) == 'socket:[' + inode + ']':
                        owners.add(int(proc.rsplit('/', 1)[1]))
                        break
                except OSError:
                    pass
        except OSError:
            pass
    return owners


def listener_pids(port):
    result = set()
    for local, remote, state, inode in tcp_rows():
        if local == port and state == '0A':
            result.update(owners_of_inode(inode))
    return result


def process_info(pid):
    try:
        exe = os.path.basename(os.readlink(f'/proc/{pid}/exe'))
        with open(f'/proc/{pid}/cmdline', 'rb') as f:
            args = [x.decode(errors='replace') for x in f.read().split(b'\0') if x]
        return exe, args
    except OSError:
        return '', []


def process_has_ssh_connection(pid):
    try:
        inodes = set()
        for fd in os.listdir(f'/proc/{pid}/fd'):
            try:
                target = os.readlink(f'/proc/{pid}/fd/{fd}')
                if target.startswith('socket:['):
                    inodes.add(target[8:-1])
            except OSError:
                pass
        return any(inode in inodes and state == '01' and remote == 2222
                   for local, remote, state, inode in tcp_rows())
    except OSError:
        return False


def fetch(port):
    with urllib.request.urlopen(f'http://127.0.0.1:{port}/status', timeout=3) as req:
        return json.loads(req.read().decode())


def run_auditor(path):
    return subprocess.run(['python3', AUDITOR, path], stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=8).returncode


def keygen(directory, name, kind, bits=None, comment='generated_user'):
    path = os.path.join(directory, name)
    cmd = ['ssh-keygen', '-q', '-t', kind, '-N', '', '-C', comment, '-f', path]
    if bits:
        cmd[4:4] = ['-b', str(bits)]
    subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return path + '.pub'


def test_backup_exists_and_is_original_copy():
    backup = '/home/user/backup/sshd_config.bak'
    assert os.path.isfile(backup), f'Backup file missing: {backup}'
    assert not os.path.islink(backup), 'Backup must be a real file, not a symlink'
    with open(backup, 'rb') as f:
        assert f.read() == EXPECTED_CONFIG, 'Backup is not the original SSH configuration'
    assert not os.path.samefile(backup, CONFIG), 'Backup must be a separate copy'


def test_key_auditor_corpus():
    assert os.path.isfile(AUDITOR), f'Key auditor script missing: {AUDITOR}'
    evil_corpus = glob.glob('/app/corpus/evil/*.pub')
    clean_corpus = glob.glob('/app/corpus/clean/*.pub')
    assert evil_corpus, 'Evil corpus is empty'
    assert clean_corpus, 'Clean corpus is empty'
    evil_bypassed = [os.path.basename(p) for p in evil_corpus if run_auditor(p) == 0]
    clean_modified = [os.path.basename(p) for p in clean_corpus if run_auditor(p) != 0]
    errors = []
    if evil_bypassed:
        errors.append(f'{len(evil_bypassed)} evil bypassed: {", ".join(evil_bypassed)}')
    if clean_modified:
        errors.append(f'{len(clean_modified)} clean modified: {", ".join(clean_modified)}')
    assert not errors, ' | '.join(errors)


def test_key_auditor_generated_hidden_cases():
    assert os.path.isfile(AUDITOR)
    with tempfile.TemporaryDirectory(prefix='unpredictable-key-tests-') as d:
        clean = [
            keygen(d, 'a-' + os.urandom(5).hex(), 'ed25519', comment='ordinary_user'),
            keygen(d, 'b-' + os.urandom(5).hex(), 'ecdsa', bits=256, comment='team_user'),
            keygen(d, 'c-' + os.urandom(5).hex(), 'rsa', bits=2048, comment='rsa_user'),
            keygen(d, 'd-' + os.urandom(5).hex(), 'rsa', bits=3072, comment='large_key'),
        ]
        weak = keygen(d, 'e-' + os.urandom(5).hex(), 'rsa', bits=1024, comment='ordinary_user')
        cmd_source = keygen(d, 'f-' + os.urandom(5).hex(), 'ed25519', comment='ordinary_user')
        command_key = os.path.join(d, 'g-' + os.urandom(5).hex() + '.pub')
        with open(cmd_source) as src, open(command_key, 'w') as dst:
            dst.write('no-pty,command="/bin/false" ' + src.read())
        admin_key = keygen(d, 'h-' + os.urandom(5).hex(), 'ed25519', comment='team_admin_backup')
        malformed = os.path.join(d, 'i-' + os.urandom(5).hex() + '.pub')
        with open(malformed, 'w') as f:
            f.write('ssh-ed25519 this-is-not-valid-base64 ordinary_user\n')
        for path in clean:
            assert run_auditor(path) == 0, f'Auditor rejected generated clean key {path}'
        for path in (weak, command_key, admin_key, malformed):
            assert run_auditor(path) == 1, f'Auditor accepted generated evil/invalid key {path}'


def test_sshd_configuration_and_services_running():
    result = subprocess.run(['sshd', '-T', '-f', CONFIG, '-C',
                             'user=user,host=localhost,addr=127.0.0.1'],
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert result.returncode == 0, result.stderr
    effective = result.stdout.lower().splitlines()
    assert 'port 2222' in effective
    assert 'strictmodes no' in effective
    assert 'usepam no' in effective
    assert 'hostkey /home/user/bastion/ssh_host_ed25519_key' in effective
    assert 'authorizedkeysfile /home/user/.ssh/authorized_keys' in effective

    data = fetch(5000)
    assert data.get('status') == 'ok', 'API on 5000 returned unexpected status'
    assert data.get('service') == 'internal_api'
    api_owners = listener_pids(5000)
    assert api_owners, 'No process owns the API listener on port 5000'
    assert any(exe.startswith('python') and '/app/api.py' in args
               for pid in api_owners for exe, args in [process_info(pid)]), \
        'Port 5000 is not being served by /app/api.py'

    sshd_owners = listener_pids(2222)
    assert sshd_owners, 'SSH daemon is not listening on 127.0.0.1:2222'
    assert any(exe == 'sshd' and '-f' in args and CONFIG in args
               for pid in sshd_owners for exe, args in [process_info(pid)]), \
        'Port 2222 is not owned by sshd started with the required configuration'


def test_keys_generated_and_used_by_sshd():
    host_key = '/home/user/bastion/ssh_host_ed25519_key'
    user_key = '/home/user/.ssh/id_ed25519'
    user_pub = user_key + '.pub'
    auth_keys = '/home/user/.ssh/authorized_keys'
    for path in (host_key, user_key, user_pub, auth_keys):
        assert os.path.isfile(path), f'Key file missing: {path}'

    host_public = subprocess.run(['ssh-keygen', '-y', '-f', host_key], check=True,
                                 text=True, stdout=subprocess.PIPE).stdout.split()[:2]
    assert host_public[0] == 'ssh-ed25519', 'Host key is not Ed25519'
    scan = subprocess.run(['ssh-keyscan', '-T', '3', '-p', '2222', '127.0.0.1'],
                          text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    scanned = [line.split()[1:3] for line in scan.stdout.splitlines()
               if line and not line.startswith('#') and len(line.split()) >= 3]
    assert host_public in scanned, 'Running sshd is not using the generated host key'

    derived = subprocess.run(['ssh-keygen', '-y', '-f', user_key], check=True,
                             text=True, stdout=subprocess.PIPE).stdout.split()[:2]
    with open(user_pub) as f:
        published = f.read().split()[:2]
    assert derived == published, 'User public and private keys do not match'
    with open(auth_keys) as f:
        tokens = f.read().split()
    assert any(tokens[i:i+2] == published for i in range(max(0, len(tokens) - 1))), \
        'Generated user key is not in authorized_keys'
    assert run_auditor(user_pub) == 0, 'Generated user public key fails the auditor'

    ssh = ['ssh', '-i', user_key, '-p', '2222', '-o', 'BatchMode=yes',
           '-o', 'StrictHostKeyChecking=no', '-o', 'UserKnownHostsFile=/dev/null',
           '-o', 'ConnectTimeout=4', 'user@127.0.0.1', 'true']
    result = subprocess.run(ssh, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=8)
    assert result.returncode == 0, 'Could not authenticate to bastion with generated key: ' + result.stderr.decode(errors='replace')


def test_ssh_tunnel_and_log():
    log_path = '/home/user/api_status.log'
    assert os.path.isfile(log_path), f'Log file missing: {log_path}'
    with open(log_path) as f:
        data = json.load(f)
    assert data.get('service') == 'internal_api', 'Log file does not contain expected API response'
    assert data.get('status') == 'ok'

    live = fetch(8080)
    assert live.get('status') == 'ok', 'API via tunnel on 8080 returned unexpected status'
    tunnel_owners = listener_pids(8080)
    assert tunnel_owners, 'No process owns the listener on port 8080'
    valid = []
    for pid in tunnel_owners:
        exe, args = process_info(pid)
        if exe == 'ssh' and process_has_ssh_connection(pid):
            valid.append(pid)
    assert valid, 'Port 8080 is not an active local forward owned by an SSH connection to port 2222'


def test_fresh_forward_through_bastion():
    sock = socket.socket()
    sock.bind(('127.0.0.1', 0))
    port = sock.getsockname()[1]
    sock.close()
    cmd = ['ssh', '-N', '-i', '/home/user/.ssh/id_ed25519', '-p', '2222',
           '-L', f'127.0.0.1:{port}:127.0.0.1:5000', '-o', 'BatchMode=yes',
           '-o', 'StrictHostKeyChecking=no', '-o', 'UserKnownHostsFile=/dev/null',
           '-o', 'ExitOnForwardFailure=yes', 'user@127.0.0.1']
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        deadline = time.time() + 6
        error = None
        while time.time() < deadline:
            if proc.poll() is not None:
                error = proc.stderr.read().decode(errors='replace')
                break
            try:
                data = fetch(port)
                assert data == {'status': 'ok', 'service': 'internal_api'}
                return
            except Exception:
                time.sleep(0.15)
        pytest.fail('Could not create a fresh SSH forward through the bastion: ' + (error or 'timeout'))
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
