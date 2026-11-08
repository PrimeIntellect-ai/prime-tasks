#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import pathlib
import pwd
import secrets
import shutil
import signal
import socket
import ssl
import subprocess
import tarfile
import time
import urllib.parse
import urllib.request

import pytest

HOME = pathlib.Path('/home/user')
PORT = 8443


def test_required_scripts_exist_and_deploy_uses_expect_automation():
    server_path = HOME / 'server.py'
    deploy_path = HOME / 'deploy.py'
    assert server_path.is_file(), f'{server_path} is missing.'
    assert deploy_path.is_file(), f'{deploy_path} is missing.'

    source = deploy_path.read_text(errors='replace')
    tree = ast.parse(source, filename=str(deploy_path))
    imports_pexpect = any(
        (isinstance(node, ast.Import) and any(alias.name == 'pexpect' for alias in node.names))
        or isinstance(node, ast.ImportFrom) and node.module == 'pexpect'
        for node in ast.walk(tree)
    )
    called_attributes = {
        node.func.attr
        for node in ast.walk(tree)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
    }
    uses_pexpect = imports_pexpect and {'spawn', 'expect', 'sendline'} <= called_attributes
    uses_expect_script = 'expect' in source and any(
        isinstance(node, ast.Import) and any(alias.name == 'subprocess' for alias in node.names)
        for node in ast.walk(tree)
    )
    assert uses_pexpect or uses_expect_script, 'deploy.py does not implement the required pexpect/expect interaction.'


def test_certificates_exist():
    cert_path = '/home/user/certs/cert.pem'
    key_path = '/home/user/certs/key.pem'
    assert os.path.isfile(cert_path), f'Certificate file {cert_path} is missing.'
    assert os.path.isfile(key_path), f'Key file {key_path} is missing.'

    subprocess.run(['openssl', 'x509', '-in', cert_path, '-noout'], check=True, capture_output=True)
    key_info = subprocess.run(
        ['openssl', 'pkey', '-in', key_path, '-noout', '-text'],
        check=True, capture_output=True, text=True, timeout=5
    ).stdout
    assert '2048 bit' in key_info, 'The private key is not 2048 bits.'
    cert_pub = subprocess.run(
        ['openssl', 'x509', '-in', cert_path, '-pubkey', '-noout'],
        check=True, capture_output=True
    ).stdout
    key_pub = subprocess.run(
        ['openssl', 'pkey', '-in', key_path, '-pubout'],
        check=True, capture_output=True, timeout=5
    ).stdout
    assert cert_pub == key_pub, 'Certificate and private key do not match.'


def test_deployment_symlink_and_target():
    symlink_path = '/home/user/webroot/latest'
    target_dir = '/home/user/deployments/app-v1.0'

    assert os.path.islink(symlink_path), f'{symlink_path} is not a symlink.'
    assert os.path.isdir(target_dir), f'Deployment directory {target_dir} is missing.'
    assert os.path.realpath(symlink_path) == target_dir, f'{symlink_path} does not point to {target_dir}.'

    index_file = os.path.join(symlink_path, 'index.html')
    assert os.path.isfile(index_file), f'index.html not found through symlink at {index_file}.'


def test_deploy_log():
    log_path = '/home/user/deploy.log'
    assert os.path.isfile(log_path), f'Log file {log_path} is missing.'
    with open(log_path, 'r') as f:
        content = f.read()
    assert 'SUCCESS: app-v1.0 deployed' in content, 'Log file does not contain the required success message.'


def pid_owns_listening_port(pid, port):
    socket_inodes = set()
    fd_dir = pathlib.Path(f'/proc/{pid}/fd')
    try:
        for fd in fd_dir.iterdir():
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith('socket:['):
                socket_inodes.add(target[8:-1])
    except OSError:
        return False

    wanted = f'{port:04X}'
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = pathlib.Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].rsplit(':', 1)[-1] == wanted and fields[3] == '0A' and fields[9] in socket_inodes:
                return True
    return False


def pid_runs_server_script(pid):
    try:
        raw = pathlib.Path(f'/proc/{pid}/cmdline').read_bytes()
        cwd = pathlib.Path(f'/proc/{pid}/cwd').resolve()
    except OSError:
        return False
    args = [part.decode(errors='replace') for part in raw.split(b'\0') if part]
    for arg in args:
        if arg.endswith('server.py'):
            candidate = pathlib.Path(arg)
            if not candidate.is_absolute():
                candidate = cwd / candidate
            try:
                if candidate.resolve() == (HOME / 'server.py').resolve():
                    return True
            except OSError:
                pass
    return False


def test_server_pid_and_process():
    pid_path = '/home/user/server.pid'
    assert os.path.isfile(pid_path), f'PID file {pid_path} is missing.'
    with open(pid_path, 'r') as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), 'PID file does not contain a valid integer.'
    pid = int(pid_str)
    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f'Process with PID {pid_str} is not running.')
    assert pid_runs_server_script(pid), 'The PID file does not identify /home/user/server.py.'
    assert pid_owns_listening_port(pid, PORT), 'The server.py process is not listening on port 8443.'


def fetch(path):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return urllib.request.urlopen(f'https://127.0.0.1:{PORT}/{path}', context=ctx, timeout=5).read().decode('utf-8')


def test_https_server_serving_content():
    try:
        content = fetch('index.html')
    except Exception as e:
        pytest.fail(f'Failed to fetch content from https://127.0.0.1:8443/index.html: {e}')
    assert 'Hello World!' in content, 'The HTTPS server did not serve the expected content.'


def run_as_user(command, timeout):
    account = pwd.getpwnam('user')
    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)
    return subprocess.run(
        command, cwd=str(HOME), env={'HOME': str(HOME), 'PATH': '/usr/local/bin:/usr/bin:/bin'},
        text=True, capture_output=True, timeout=timeout, preexec_fn=demote
    )


def test_deploy_script_interactively_approves_and_extracts_fresh_archive():
    token = secrets.token_hex(16)
    random_name = f'proof-{token}.txt'
    random_content = f'deployment-proof-{token}'
    approval_tool = HOME / 'bin/approve_release.sh'
    archive = HOME / 'staging/app-v1.0.tar.gz'
    marker = pathlib.Path(f'/tmp/approval-{token}.txt')
    tool_backup = approval_tool.read_bytes()
    archive_backup = archive.read_bytes()

    try:
        approval_tool.write_text(f'''#!/bin/bash
printf "Approve deployment of %s? (yes/no): " "$1"
IFS= read -r answer
printf "%s\\n%s\\n" "$1" "$answer" > "{marker}"
if [ "$answer" = "yes" ]; then
  echo "Approved."
  exit 0
fi
echo "Rejected."
exit 1
''')
        approval_tool.chmod(0o755)

        build_root = pathlib.Path(f'/tmp/archive-{token}')
        payload = build_root / 'app-v1.0'
        payload.mkdir(parents=True)
        (payload / 'index.html').write_text(f'index-{token}\n')
        (payload / random_name).write_text(random_content)
        with tarfile.open(archive, 'w:gz') as tf:
            tf.add(payload, arcname='app-v1.0')
        account = pwd.getpwnam('user')
        os.chown(archive, account.pw_uid, account.pw_gid)

        shutil.rmtree(HOME / 'deployments/app-v1.0', ignore_errors=True)
        latest = HOME / 'webroot/latest'
        if latest.is_symlink() or latest.exists():
            if latest.is_dir() and not latest.is_symlink():
                shutil.rmtree(latest)
            else:
                latest.unlink()
        log = HOME / 'deploy.log'
        if log.exists():
            log.unlink()

        result = run_as_user(['python3', str(HOME / 'deploy.py')], timeout=20)
        assert result.returncode == 0, f'deploy.py failed:\nstdout={result.stdout}\nstderr={result.stderr}'
        assert marker.is_file(), 'deploy.py did not invoke the approval tool.'
        lines = marker.read_text().splitlines()
        assert lines == [str(archive), 'yes'], 'deploy.py did not pass the staging filename and exact approval response.'
        assert latest.is_symlink(), 'deploy.py did not create the latest symlink.'
        assert latest.resolve() == (HOME / 'deployments/app-v1.0').resolve(), 'latest points to the wrong deployment.'
        deployed_proof = HOME / 'deployments/app-v1.0' / random_name
        assert deployed_proof.is_file(), 'deploy.py did not extract the fresh archive into the deployment directory.'
        assert deployed_proof.read_text() == random_content, 'Extracted content does not match the fresh archive.'
        assert log.is_file() and 'SUCCESS: app-v1.0 deployed' in log.read_text(), 'deploy.py did not write the success log.'
    finally:
        approval_tool.write_bytes(tool_backup)
        approval_tool.chmod(0o755)
        archive.write_bytes(archive_backup)
        if marker.exists():
            marker.unlink()
        shutil.rmtree(f'/tmp/archive-{token}', ignore_errors=True)


def listener_pids(port):
    inodes = set()
    wanted = f'{port:04X}'
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = pathlib.Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].rsplit(':', 1)[-1] == wanted and fields[3] == '0A':
                inodes.add(fields[9])
    found = set()
    for proc in pathlib.Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / 'fd').iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    found.add(int(proc.name))
        except OSError:
            pass
    return found


def test_server_script_itself_serves_fresh_deployment_with_configured_certificate():
    for pid in listener_pids(PORT):
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            pass
    deadline = time.time() + 5
    while listener_pids(PORT) and time.time() < deadline:
        time.sleep(0.1)
    for pid in listener_pids(PORT):
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass

    account = pwd.getpwnam('user')
    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)
    output = open('/tmp/submitted-server.log', 'wb')
    proc = subprocess.Popen(
        ['python3', str(HOME / 'server.py')], cwd=str(HOME), stdout=output, stderr=subprocess.STDOUT,
        env={'HOME': str(HOME), 'PATH': '/usr/local/bin:/usr/bin:/bin'}, preexec_fn=demote
    )
    try:
        proof_files = list((HOME / 'deployments/app-v1.0').glob('proof-*.txt'))
        assert len(proof_files) == 1, 'Fresh deployment proof file is missing.'
        expected = proof_files[0].read_text()
        deadline = time.time() + 8
        last_error = None
        while time.time() < deadline:
            if proc.poll() is not None:
                break
            try:
                served = fetch(urllib.parse.quote(proof_files[0].name))
                if served == expected:
                    break
            except Exception as exc:
                last_error = exc
            time.sleep(0.2)
        else:
            pytest.fail(f'server.py did not serve the fresh deployment: {last_error}')
        assert proc.poll() is None, 'server.py exited instead of running the HTTPS server.'
        assert pid_owns_listening_port(proc.pid, PORT), 'The executed server.py is not the port 8443 listener.'
        assert served == expected, 'server.py served content from the wrong directory.'

        context = ssl.create_default_context()
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE
        with socket.create_connection(('127.0.0.1', PORT), timeout=5) as raw:
            with context.wrap_socket(raw, server_hostname='localhost') as tls:
                served_der = tls.getpeercert(binary_form=True)
        configured_der = ssl.PEM_cert_to_DER_cert((HOME / 'certs/cert.pem').read_text())
        assert served_der == configured_der, 'server.py is not using /home/user/certs/cert.pem.'
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
        output.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
