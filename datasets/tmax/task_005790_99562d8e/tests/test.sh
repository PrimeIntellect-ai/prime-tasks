#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pathlib
import pwd
import re
import subprocess
import time
import urllib.error
import urllib.request
import uuid

import pytest

USER = pwd.getpwnam('user')
HOME = '/home/user'
WORKSPACE = '/home/user/workspace'
BARE_REPO = '/home/user/backend.git'
MONITOR_OUTPUT = '/home/user/monitor_output.json'


def run_as_user(argv, timeout=30, stdout=subprocess.PIPE, stderr=subprocess.PIPE):
    def demote():
        os.setgroups([])
        os.setgid(USER.pw_gid)
        os.setuid(USER.pw_uid)

    env = os.environ.copy()
    env['HOME'] = HOME
    env['USER'] = 'user'
    env['LOGNAME'] = 'user'
    return subprocess.run(
        argv,
        cwd=WORKSPACE if os.path.isdir(WORKSPACE) else HOME,
        env=env,
        preexec_fn=demote,
        stdout=stdout,
        stderr=stderr,
        timeout=timeout,
        text=True,
    )


def run_git(*args, timeout=30):
    result = run_as_user(['git', '-C', WORKSPACE, *args], timeout=timeout)
    assert result.returncode == 0, (
        f"git {' '.join(args)} failed:\nstdout={result.stdout}\nstderr={result.stderr}"
    )
    return result.stdout.strip()


def write_workspace_server(data):
    path = os.path.join(WORKSPACE, 'server.py')
    with open(path, 'wb') as f:
        f.write(data)
    os.chown(path, USER.pw_uid, USER.pw_gid)


def request_body(url, timeout=2):
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    req = urllib.request.Request(url)
    with opener.open(req, timeout=timeout) as response:
        assert response.status == 200, f"{url} returned status {response.status}"
        return response.read().decode('utf-8').strip()


def listener_pids(port):
    inodes = set()
    wanted = f'{port:04X}'
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].split(':')[-1].upper() == wanted and fields[3] == '0A':
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for proc in pathlib.Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / 'fd').iterdir():
                target = os.readlink(fd)
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    pids.add(int(proc.name))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return pids


def wait_for_body(port, path, expected, timeout=15):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            last = request_body(f'http://127.0.0.1:{port}{path}', timeout=1)
            if last == expected:
                return
        except Exception as exc:
            last = repr(exc)
        time.sleep(0.25)
    pytest.fail(f'Port {port}{path} did not return {expected!r}; last result was {last!r}')


def run_monitor():
    assert os.path.isfile('/home/user/monitor.py'), 'Monitoring script /home/user/monitor.py is missing.'
    try:
        os.remove(MONITOR_OUTPUT)
    except FileNotFoundError:
        pass
    started = time.time()
    result = run_as_user(['python3', '/home/user/monitor.py'], timeout=20)
    assert result.returncode == 0, (
        f'monitor.py failed:\nstdout={result.stdout}\nstderr={result.stderr}'
    )
    assert os.path.isfile(MONITOR_OUTPUT), 'monitor.py did not create monitor_output.json.'
    assert os.path.getmtime(MONITOR_OUTPUT) >= started - 1, 'monitor_output.json was not freshly generated.'
    with open(MONITOR_OUTPUT) as f:
        return json.load(f)


def test_monitor_output():
    """Execute the monitor, then retain the original output assertions."""
    run_monitor()
    output_path = '/home/user/monitor_output.json'
    assert os.path.exists(output_path), f"Monitor output file {output_path} does not exist."

    with open(output_path, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("monitor_output.json is not valid JSON.")

    assert isinstance(results, list), "monitor_output.json should contain a JSON array."
    assert len(results) == 10, f"monitor_output.json contains {len(results)} responses instead of 10."

    node1_count = results.count('Node 9001')
    node2_count = results.count('Node 9002')

    assert node1_count > 0, "Load balancing is not distributing requests to Node 9001."
    assert node2_count > 0, "Load balancing is not distributing requests to Node 9002."
    assert node1_count + node2_count == 10, "Unexpected responses found in monitor_output.json."


def test_haproxy_live():
    """Verify that HAProxy is running and load balancing requests."""
    req = urllib.request.Request('http://127.0.0.1:8080/')
    try:
        with urllib.request.urlopen(req, timeout=2) as response:
            assert response.status == 200, f"HAProxy returned status {response.status}"
            body = response.read().decode('utf-8').strip()
            assert body in ['Node 9001', 'Node 9002'], f"HAProxy root returned unexpected body: {body}"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to HAProxy on 8080: {e}")


@pytest.mark.parametrize("port", [9001, 9002])
def test_backend_health_live(port):
    """Verify that backend nodes are running and responding to health checks."""
    req = urllib.request.Request(f'http://127.0.0.1:{port}/health')
    try:
        with urllib.request.urlopen(req, timeout=2) as response:
            assert response.status == 200, f"Node {port} /health returned status {response.status}"
            body = response.read().decode('utf-8').strip()
            assert body == 'OK', f"Node {port} /health returned unexpected body: {body}"
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to backend health check on {port}: {e}")


def test_git_post_receive_hook():
    """Verify the git post-receive hook exists and is executable."""
    hook_path = '/home/user/backend.git/hooks/post-receive'
    assert os.path.exists(hook_path), f"Git post-receive hook is missing at {hook_path}."
    assert os.path.isfile(hook_path), f"{hook_path} is not a file."
    assert os.access(hook_path, os.X_OK), f"Git post-receive hook at {hook_path} is not executable."


def test_git_deployment_layout():
    assert os.path.isdir(BARE_REPO), 'Bare repository /home/user/backend.git is missing.'
    bare = subprocess.run(
        ['git', '-C', BARE_REPO, 'rev-parse', '--is-bare-repository'],
        capture_output=True, text=True, timeout=10
    )
    assert bare.returncode == 0 and bare.stdout.strip() == 'true', f'{BARE_REPO} is not a bare Git repository.'

    assert os.path.isdir(os.path.join(WORKSPACE, '.git')), '/home/user/workspace is not a Git clone.'
    assert run_git('rev-parse', '--is-inside-work-tree') == 'true'
    assert run_git('branch', '--show-current') == 'main', 'The workspace must be on the main branch.'
    remote = run_git('remote', 'get-url', 'origin')
    resolved_remote = os.path.realpath(os.path.join(WORKSPACE, remote) if not os.path.isabs(remote) else remote)
    assert resolved_remote == os.path.realpath(BARE_REPO), 'workspace origin does not point to backend.git.'
    assert run_git('rev-parse', 'HEAD') == run_git('--git-dir=' + BARE_REPO, 'rev-parse', 'refs/heads/main')

    for node in ('node1', 'node2'):
        directory = f'/home/user/deploy/{node}'
        assert os.path.isdir(directory), f'Deployment directory {directory} is missing.'
        assert os.path.isfile(os.path.join(directory, 'server.py')), f'{directory}/server.py is missing.'


def test_port_8080_is_configured_and_served_by_haproxy():
    cfg_path = '/home/user/haproxy.cfg'
    assert os.path.isfile(cfg_path), 'HAProxy configuration /home/user/haproxy.cfg is missing.'
    validation = subprocess.run(
        ['haproxy', '-c', '-f', cfg_path], capture_output=True, text=True, timeout=10
    )
    assert validation.returncode == 0, f'Invalid HAProxy configuration: {validation.stdout}\n{validation.stderr}'

    with open(cfg_path) as f:
        cfg = '\n'.join(line.split('#', 1)[0] for line in f)
    assert re.search(r'(?im)^\s*bind\s+127\.0\.0\.1:8080(?:\s|$)', cfg), 'HAProxy must bind 127.0.0.1:8080.'
    assert re.search(r'(?im)^\s*balance\s+roundrobin\s*$', cfg), 'HAProxy must use round-robin balancing.'
    for port in (9001, 9002):
        assert re.search(rf'(?im)^\s*server\s+\S+\s+127\.0\.0\.1:{port}\b[^\n]*\bcheck\b', cfg), \
            f'HAProxy backend 127.0.0.1:{port} with health checking is missing.'
    assert (
        re.search(r'(?im)^\s*option\s+httpchk(?:\s+GET)?\s+/health(?:\s|$)', cfg)
        or re.search(r'(?im)^\s*http-check\s+send\b[^\n]*\buri\s+/health(?:\s|$)', cfg)
    ), 'HAProxy health checks must request /health.'

    pids = listener_pids(8080)
    assert pids, 'No process is listening on port 8080.'
    matched = []
    for pid in pids:
        try:
            exe = os.path.realpath(f'/proc/{pid}/exe')
            cmdline = open(f'/proc/{pid}/cmdline', 'rb').read().replace(b'\0', b' ').decode(errors='replace')
            status = open(f'/proc/{pid}/status').read()
            uid_match = re.search(r'^Uid:\s+(\d+)', status, re.MULTILINE)
            if os.path.basename(exe).startswith('haproxy') and cfg_path in cmdline and uid_match and int(uid_match.group(1)) == USER.pw_uid:
                matched.append(pid)
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    assert matched, 'Port 8080 is not owned by the local-user HAProxy process using /home/user/haproxy.cfg.'


def test_push_redeploys_and_restarts_both_nodes_and_monitor_observes_live_responses():
    original_path = os.path.join(WORKSPACE, 'server.py')
    assert os.path.isfile(original_path), 'workspace/server.py is missing.'
    with open(original_path, 'rb') as f:
        original_source = f.read()

    token = uuid.uuid4().hex
    dynamic_source = f'''import http.server
import os
import sys

PORT = int(sys.argv[1] if len(sys.argv) > 1 else os.environ.get("PORT", "8000"))
TOKEN = "verify-{token}"

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            body = "OK"
            status = 200
        elif self.path == "/":
            body = TOKEN + "-" + str(PORT)
            status = 200
        else:
            body = "Not Found"
            status = 404
        data = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    def log_message(self, *args):
        pass

http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
'''.encode()

    old_pids = {port: listener_pids(port) for port in (9001, 9002)}
    assert all(old_pids.values()), 'Both backend listeners must exist before testing a redeployment.'
    dynamic_committed = False

    try:
        write_workspace_server(dynamic_source)
        run_git('config', 'user.name', 'Verifier Deployment Test')
        run_git('config', 'user.email', 'verifier@localhost')
        run_git('add', 'server.py')
        run_git('commit', '-m', 'verifier: exercise post-receive deployment')
        dynamic_committed = True
        pushed = run_as_user(
            ['git', '-C', WORKSPACE, 'push', 'origin', 'HEAD:main'],
            timeout=30, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        assert pushed.returncode == 0, 'Pushing a new main revision to backend.git failed.'

        for port in (9001, 9002):
            wait_for_body(port, '/', f'verify-{token}-{port}')
            wait_for_body(port, '/health', 'OK')
            new_pids = listener_pids(port)
            assert new_pids, f'No listener remained on port {port} after the push.'
            assert old_pids[port].isdisjoint(new_pids), f'The process on port {port} was not restarted by the push.'

        expected_head = run_git('rev-parse', 'HEAD')
        bare_head = subprocess.run(
            ['git', '--git-dir=' + BARE_REPO, 'rev-parse', 'refs/heads/main'],
            capture_output=True, text=True, timeout=10, check=True
        ).stdout.strip()
        assert bare_head == expected_head, 'The pushed main revision did not reach backend.git.'
        for node in ('node1', 'node2'):
            deployed = f'/home/user/deploy/{node}/server.py'
            with open(deployed, 'rb') as f:
                assert f.read() == dynamic_source, f'{deployed} was not checked out from the pushed revision.'

        proxy_results = [request_body('http://127.0.0.1:8080/') for _ in range(10)]
        expected_values = {f'verify-{token}-9001', f'verify-{token}-9002'}
        assert set(proxy_results) == expected_values, 'HAProxy did not round-robin across both newly deployed nodes.'

        monitor_results = run_monitor()
        assert isinstance(monitor_results, list) and len(monitor_results) == 10
        assert set(monitor_results) == expected_values, \
            'monitor.py did not collect the live, unpredictable responses from the redeployed backends.'
    finally:
        write_workspace_server(original_source)
        if dynamic_committed:
            run_git('add', 'server.py')
            status = run_git('status', '--porcelain', '--', 'server.py')
            if status:
                run_git('commit', '-m', 'verifier: restore submitted server')
                restored = run_as_user(
                    ['git', '-C', WORKSPACE, 'push', 'origin', 'HEAD:main'],
                    timeout=30, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
                )
                assert restored.returncode == 0, 'Failed to restore the submitted server after deployment testing.'
                wait_for_body(9001, '/', 'Node 9001')
                wait_for_body(9002, '/', 'Node 9002')
                restored_results = run_monitor()
                assert len(restored_results) == 10
                assert set(restored_results) == {'Node 9001', 'Node 9002'}
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
