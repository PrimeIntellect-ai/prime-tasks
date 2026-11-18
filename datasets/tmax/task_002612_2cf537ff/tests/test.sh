#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import socket
import subprocess
import tarfile
import tempfile
import time
from pathlib import Path

BACKUP = Path('/home/user/backups/deploy_backup.tar.gz')
DEPLOY = Path('/home/user/deploy')
DEPLOY_SCRIPT = Path('/home/user/deploy.sh')
HOOK = Path('/home/user/repo.git/hooks/post-receive')
REPO = '/home/user/repo.git'


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, timeout=kwargs.pop('timeout', 20), **kwargs)


def wait_http(expected, timeout=10):
    deadline = time.time() + timeout
    last = ''
    while time.time() < deadline:
        p = run(['curl', '-fsS', '--max-time', '1', 'http://127.0.0.1:8080'],
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False, timeout=3)
        last = p.stdout.strip()
        if p.returncode == 0 and last == expected:
            return
        time.sleep(0.2)
    raise AssertionError(f'Proxy did not serve {expected!r}; last response was {last!r}')


def archive_index_text():
    assert BACKUP.is_file(), f'Backup file {BACKUP} does not exist.'
    try:
        with tarfile.open(BACKUP, 'r:gz') as tf:
            candidates = [m for m in tf.getmembers()
                          if m.isfile() and Path(m.name).name == 'index.html'
                          and ('deploy' in Path(m.name).parts or m.name in ('index.html', './index.html'))]
            assert candidates, 'Backup is not a tar.gz archive containing deploy/index.html.'
            data = tf.extractfile(candidates[0]).read().decode('utf-8')
            return data.strip()
    except (tarfile.TarError, OSError, UnicodeError) as exc:
        raise AssertionError(f'{BACKUP} is not a valid deployment tar.gz: {exc}')


def listener_pids(port):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[3] == '0A':
                try:
                    local_port = int(fields[1].rsplit(':', 1)[1], 16)
                except ValueError:
                    continue
                if local_port == port:
                    inodes.add(fields[9])
    found = set()
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / 'fd').iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                m = re.fullmatch(r'socket:\[(\d+)\]', target)
                if m and m.group(1) in inodes:
                    found.add(int(proc.name))
        except OSError:
            pass
    return found


def cmdline(pid):
    try:
        return Path(f'/proc/{pid}/cmdline').read_bytes().replace(b'\0', b' ').decode(errors='replace')
    except OSError:
        return ''


def stop_all_listeners():
    pids = listener_pids(8080) | listener_pids(8081)
    for pid in pids:
        try:
            os.kill(pid, 15)
        except ProcessLookupError:
            pass
    time.sleep(0.5)
    for pid in pids:
        try:
            os.kill(pid, 9)
        except ProcessLookupError:
            pass
    run(['pkill', '-f', '/home/user/proxy.sh'], check=False,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.2)


def assert_service_identities():
    backend = [cmdline(p) for p in listener_pids(8081)]
    proxy = [cmdline(p) for p in listener_pids(8080)]
    assert any('python3' in c and '-m http.server 8081' in c
               and '--bind 127.0.0.1' in c
               and '--directory /home/user/deploy' in c for c in backend), \
        f'Port 8081 is not owned by the required Python backend: {backend}'
    assert any('socat' in c and 'TCP-LISTEN:8080' in c
               and 'TCP:127.0.0.1:8081' in c for c in proxy), \
        f'Port 8080 is not owned by the proxy service: {proxy}'


def test_backup_file_exists_and_has_real_contents():
    assert archive_index_text() == 'Pipeline Active', \
        'The initial backup does not contain the deployed Pipeline Active index.'


def test_git_hook_configured():
    assert HOOK.is_file(), f'Git hook {HOOK} does not exist.'
    assert bool(HOOK.stat().st_mode & stat.S_IXUSR), f'Git hook {HOOK} is not executable.'
    text = HOOK.read_text(errors='replace')
    assert 'master' in text and '/home/user/deploy' in text, \
        'The hook does not handle master and the deployment work tree.'
    assert re.search(r'(?:^|[;&|\s])(?:/bin/(?:ba)?sh\s+)?/home/user/deploy\.sh(?:\s|$)', text, re.M), \
        'The hook does not execute /home/user/deploy.sh.'


def test_success_txt_content():
    success = Path('/home/user/success.txt')
    assert success.is_file(), f'File {success} does not exist.'
    assert success.read_text().strip() == 'Pipeline Active', \
        'success.txt does not contain Pipeline Active.'


def test_repository_and_workspace_state():
    bare_value = run(['git', '--git-dir', REPO, 'show', 'refs/heads/master:index.html'],
                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True).stdout.strip()
    assert bare_value == 'Pipeline Active', 'master in the bare repository has the wrong index.html.'
    assert Path('/home/user/workspace/.git').is_dir(), '/home/user/workspace is not a Git clone.'
    workspace_value = run(['git', '-C', '/home/user/workspace', 'show', 'HEAD:index.html'],
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True).stdout.strip()
    assert workspace_value == 'Pipeline Active', 'The workspace commit has the wrong index.html.'
    origin = run(['git', '-C', '/home/user/workspace', 'remote', 'get-url', 'origin'],
                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True).stdout.strip()
    assert os.path.realpath(origin) == os.path.realpath(REPO), 'Workspace origin is not /home/user/repo.git.'


def test_ports_listening():
    for port in (8080, 8081):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(1)
            assert s.connect_ex(('127.0.0.1', port)) == 0, f'Port {port} is not listening.'
    assert_service_identities()


def test_deploy_script_lifecycle_and_wait():
    assert DEPLOY_SCRIPT.is_file() and os.access(DEPLOY_SCRIPT, os.X_OK), 'deploy.sh is missing or not executable.'
    text = DEPLOY_SCRIPT.read_text(errors='replace')
    backend_pos = text.find('python3 -m http.server 8081')
    proxy_matches = list(re.finditer(r'^\s*(?:nohup\s+)?/home/user/proxy\.sh(?:\s|&|$)', text, re.M))
    assert backend_pos >= 0 and proxy_matches, 'deploy.sh does not launch the required backend and proxy commands.'
    proxy_pos = proxy_matches[-1].start()
    assert backend_pos < proxy_pos, 'deploy.sh starts the proxy before the backend.'
    between = text[backend_pos:proxy_pos]
    assert re.search(r'\b(until|while|for)\b|nc\s+-z|curl\b|wait[^\n]*(port|backend|ready)', between, re.I), \
        'No backend readiness wait is present between backend and proxy startup.'
    tar_pos = text.find('/home/user/backups/deploy_backup.tar.gz')
    stop_positions = [p for p in (text.find('pkill'), text.find('killall')) if p >= 0]
    assert tar_pos >= 0 and (not stop_positions or tar_pos < min(stop_positions)), \
        'deploy.sh must create the specified backup before terminating services.'

    stop_all_listeners()
    wrapper_dir = tempfile.mkdtemp(prefix='delayed-python-')
    marker = Path(wrapper_dir) / 'args'
    Path(wrapper_dir, 'python3').write_text(
        '#!/bin/bash\nprintf "%s\\n" "$*" > ' + str(marker) + '\nsleep 2\nexec /usr/bin/python3 "$@"\n')
    os.chmod(Path(wrapper_dir, 'python3'), 0o755)
    env = os.environ.copy()
    env['PATH'] = wrapper_dir + ':' + env.get('PATH', '')
    p = run(['/bin/bash', str(DEPLOY_SCRIPT)], env=env, check=False, timeout=15,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    assert p.returncode == 0, f'deploy.sh exited with status {p.returncode}.'
    deadline = time.time() + 8
    while time.time() < deadline and not listener_pids(8080):
        time.sleep(0.2)
    assert listener_pids(8080), 'Proxy did not survive a deliberately delayed backend startup.'
    assert marker.exists(), 'deploy.sh did not invoke the required python3 backend command.'
    args = marker.read_text().strip()
    assert args == '-m http.server 8081 --bind 127.0.0.1 --directory /home/user/deploy', \
        f'Backend was started with incorrect arguments: {args!r}'
    wait_http('Pipeline Active')
    assert archive_index_text() == 'Pipeline Active'
    assert_service_identities()


def test_master_push_triggers_real_pipeline():
    nonce = 'Verifier Pipeline ' + os.urandom(8).hex()
    with tempfile.TemporaryDirectory(prefix='pipeline-clone-') as clone:
        p = run(['git', 'clone', REPO, clone], check=False,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)
        assert p.returncode == 0, 'Could not clone the submitted bare repository.'
        run(['git', '-C', clone, 'config', 'user.name', 'Verifier'], check=True)
        run(['git', '-C', clone, 'config', 'user.email', 'verifier@example.invalid'], check=True)

        Path(clone, 'index.html').write_text(nonce + '\n')
        run(['git', '-C', clone, 'add', 'index.html'], check=True)
        run(['git', '-C', clone, 'commit', '-m', 'verifier pipeline probe'], check=True,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        p = run(['git', '-C', clone, 'push', 'origin', 'HEAD:master'], check=False, timeout=25,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        assert p.returncode == 0, 'A push to master failed; the post-receive deployment is not functional.'
        wait_http(nonce)
        assert (DEPLOY / 'index.html').read_text().strip() == nonce, \
            'The hook did not extract the pushed master content into /home/user/deploy.'
        assert archive_index_text() == nonce, \
            'deploy.sh did not create a real backup of the content extracted by the hook.'
        assert_service_identities()

        Path(clone, 'index.html').write_text('Pipeline Active\n')
        run(['git', '-C', clone, 'add', 'index.html'], check=True)
        run(['git', '-C', clone, 'commit', '-m', 'restore requested final content'], check=True,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        p = run(['git', '-C', clone, 'push', 'origin', 'HEAD:master'], check=False, timeout=25,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        assert p.returncode == 0, 'The restoration push to master failed.'
        wait_http('Pipeline Active')
        assert archive_index_text() == 'Pipeline Active'
        assert_service_identities()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
