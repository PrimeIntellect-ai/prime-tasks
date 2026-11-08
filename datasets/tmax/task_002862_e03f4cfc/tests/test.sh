#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import http.client
import http.server
import json
import os
import pwd
import re
import signal
import socket
import stat
import subprocess
import tempfile
import threading
import time

import pytest

USER = pwd.getpwnam('user')


def demote():
    os.setgroups([])
    os.setgid(USER.pw_gid)
    os.setuid(USER.pw_uid)


def assert_script(path):
    assert os.path.exists(path), f'File {path} does not exist'
    assert stat.S_ISREG(os.stat(path).st_mode), f'{path} is not a regular file'
    assert os.stat(path).st_mode & 0o111, f'{path} is not executable'


def read(path):
    with open(path, 'r') as f:
        return f.read()


def test_init_api_script():
    filepath = '/home/user/init_api.py'
    assert_script(filepath)
    content = read(filepath)

    # Preserve the original assertions.
    assert '8080' in content, f'{filepath} does not contain port 8080'
    assert 'http.server' in content or 'HTTPServer' in content, f'{filepath} does not use http.server'
    assert '/home/user/api_data' in content, f'{filepath} does not reference the correct api_data directory'
    compile(content, filepath, 'exec')

    marker = f'verifier-{os.getpid()}-{time.time_ns()}.txt'
    payload = os.urandom(48)
    marker_path = os.path.join('/home/user/api_data', marker)
    with open(marker_path, 'wb') as f:
        f.write(payload)
    os.chmod(marker_path, 0o644)

    probe = socket.socket()
    try:
        assert probe.connect_ex(('127.0.0.1', 8080)) != 0, 'port 8080 was already occupied before init_api.py ran'
    finally:
        probe.close()

    proc = subprocess.Popen(
        ['python3', filepath], cwd='/tmp', stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, preexec_fn=demote, start_new_session=True)
    try:
        body = None
        deadline = time.time() + 6
        while time.time() < deadline:
            if proc.poll() is not None:
                out, err = proc.communicate()
                pytest.fail(f'init_api.py exited early: {out!r} {err!r}')
            try:
                conn = http.client.HTTPConnection('127.0.0.1', 8080, timeout=0.4)
                conn.request('GET', '/' + marker)
                response = conn.getresponse()
                body = response.read()
                status = response.status
                conn.close()
                if status == 200:
                    break
            except OSError:
                time.sleep(0.1)
        assert body == payload, 'init_api.py did not serve files from /home/user/api_data'

        # A server bound to 127.0.0.1:8080 appears as 0100007F:1F90.
        with open('/proc/net/tcp', 'r') as f:
            tcp_entries = f.read().splitlines()[1:]
        assert any(line.split()[1].upper() == '0100007F:1F90' for line in tcp_entries), \
            'HTTP server is not bound specifically to 127.0.0.1:8080'
        time.sleep(0.15)
        assert proc.poll() is None, 'init_api.py did not keep the HTTP server running'
    finally:
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGTERM)
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait()
        os.unlink(marker_path)


def run_captured_shell(filepath, command):
    subprocess.run(['bash', '-n', filepath], check=True)
    tempdir = tempfile.mkdtemp(prefix='verifier-command-')
    os.chmod(tempdir, 0o777)
    capture = os.path.join(tempdir, 'capture.jsonl')
    stub = os.path.join(tempdir, command)
    with open(stub, 'w') as f:
        f.write("#!/usr/bin/python3\nimport json, os, sys\nwith open(os.environ['CAPTURE'], 'a') as out:\n    out.write(json.dumps(sys.argv[1:]) + '\\n')\n")
    os.chmod(stub, 0o755)
    env = os.environ.copy()
    env.update({'PATH': tempdir + ':/usr/bin:/bin', 'CAPTURE': capture, 'HOME': '/home/user'})
    result = subprocess.run([filepath], cwd='/home/user', env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=6, preexec_fn=demote)
    assert result.returncode == 0, f'{filepath} failed: {result.stdout!r} {result.stderr!r}'
    deadline = time.time() + 1
    while not os.path.exists(capture) and time.time() < deadline:
        time.sleep(0.02)
    assert os.path.exists(capture), f'{filepath} did not execute {command}'
    with open(capture) as f:
        calls = [json.loads(line) for line in f if line.strip()]
    assert calls, f'{filepath} did not execute {command}'
    return calls[-1]


def option_values(args, name):
    values = []
    for i, arg in enumerate(args):
        if arg == name and i + 1 < len(args):
            values.append(args[i + 1])
        elif arg.startswith(name + '='):
            values.append(arg[len(name) + 1:])
    return values


def test_launch_node_script():
    filepath = '/home/user/launch_node.sh'
    assert_script(filepath)
    content = read(filepath)

    # Preserve the original assertions.
    assert 'qemu-system-aarch64' in content, f'{filepath} missing qemu-system-aarch64'
    assert '-M virt' in content or '-machine virt' in content, f'{filepath} missing virt machine type'
    assert '-m 512M' in content, f'{filepath} missing 512M memory'
    assert '-vnc :5' in content or '-display vnc=:5' in content, f'{filepath} missing VNC display 5'
    assert ('hostfwd=tcp::2222-:22' in content or 'hostfwd=tcp:127.0.0.1:2222-:22' in content or
            'hostfwd=tcp:localhost:2222-:22' in content), f'{filepath} missing correct hostfwd for SSH'
    assert '/opt/iot_image.img' in content, f'{filepath} missing image path'
    assert 'virtio-net-pci' in content, f'{filepath} missing virtio-net-pci device'

    args = run_captured_shell(filepath, 'qemu-system-aarch64')
    assert 'virt' in option_values(args, '-M') + option_values(args, '-machine'), 'wrong QEMU machine type'
    assert '512M' in option_values(args, '-m'), 'wrong QEMU memory setting'

    drives = option_values(args, '-drive')
    assert any('file=/opt/iot_image.img' in d.split(',') and 'format=qcow2' in d.split(',') for d in drives), \
        'missing qcow2 drive configuration'
    assert ':5' in option_values(args, '-vnc') or 'vnc=:5' in option_values(args, '-display'), 'wrong VNC display'

    netdevs = option_values(args, '-netdev')
    devices = option_values(args, '-device')
    valid_fwd = {'hostfwd=tcp::2222-:22', 'hostfwd=tcp:127.0.0.1:2222-:22',
                 'hostfwd=tcp:localhost:2222-:22'}
    user_nets = [n for n in netdevs if n.split(',')[0] == 'user' and valid_fwd.intersection(n.split(','))]
    assert user_nets, 'executed QEMU command lacks the required user-mode host forwarding'
    ids = [part[3:] for n in user_nets for part in n.split(',') if part.startswith('id=')]
    assert ids, 'user-mode netdev has no id for binding to the NIC'
    assert any(d.split(',')[0] == 'virtio-net-pci' and any('netdev=' + ident in d.split(',') for ident in ids)
               for d in devices), 'virtio-net-pci is not bound to the user-mode netdev'


def test_establish_tunnel_script():
    filepath = '/home/user/establish_tunnel.sh'
    assert_script(filepath)
    content = read(filepath)

    # Preserve the original assertions.
    assert 'ssh ' in content, f'{filepath} does not use ssh'
    assert ('-R 9090:localhost:8080' in content or '-R 9090:127.0.0.1:8080' in content or
            '-R 9090::8080' in content), f'{filepath} missing correct reverse tunnel arguments (-R 9090:localhost:8080)'
    assert '-p 2222' in content, f'{filepath} missing port 2222'
    assert 'iotuser@localhost' in content or 'iotuser@127.0.0.1' in content, \
        f'{filepath} missing target user/host (iotuser@localhost)'
    assert '-N' in content and '-f' in content, f'{filepath} missing background/no-command flags (-N -f)'
    assert 'StrictHostKeyChecking=no' in content, f'{filepath} missing StrictHostKeyChecking bypass'

    args = run_captured_shell(filepath, 'ssh')
    reverse = option_values(args, '-R')
    assert any(v in {'9090:localhost:8080', '9090:127.0.0.1:8080', '9090::8080'} for v in reverse), \
        'executed ssh command lacks the required reverse tunnel'
    assert '2222' in option_values(args, '-p'), 'executed ssh command does not use port 2222'
    assert any(v in args for v in ('iotuser@localhost', 'iotuser@127.0.0.1')), 'wrong SSH target'
    assert '-N' in args and '-f' in args, 'executed ssh command must include separate -N and -f options'
    strict = option_values(args, '-o')
    assert 'StrictHostKeyChecking=no' in strict, 'executed ssh command does not bypass host key checking'


def test_edge_client_script():
    filepath = '/home/user/edge_client.py'
    assert_script(filepath)
    content = read(filepath)

    # Preserve the original assertions.
    assert 'urllib.request' in content, f'{filepath} missing urllib.request'
    assert ('127.0.0.1:9090/config.json' in content or 'localhost:9090/config.json' in content), \
        f'{filepath} missing correct target URL'
    assert '/tmp/local_config.json' in content, f'{filepath} missing output file path'
    compile(content, filepath, 'exec')

    payload = os.urandom(97)
    requested = []

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            requested.append(self.path)
            if self.path != '/config.json':
                self.send_response(404)
                self.end_headers()
                return
            self.send_response(200)
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def log_message(self, *args):
            pass

    class Server(http.server.ThreadingHTTPServer):
        allow_reuse_address = True

    output = '/tmp/local_config.json'
    try:
        os.unlink(output)
    except FileNotFoundError:
        pass
    server = Server(('127.0.0.1', 9090), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        result = subprocess.run(['python3', filepath], cwd='/tmp', stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=6, preexec_fn=demote)
        assert result.returncode == 0, f'edge_client.py failed: {result.stdout!r} {result.stderr!r}'
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
    assert requested == ['/config.json'], 'edge_client.py did not request exactly /config.json'
    assert os.path.isfile(output), 'edge_client.py did not create /tmp/local_config.json'
    with open(output, 'rb') as f:
        assert f.read() == payload, 'edge_client.py did not save the downloaded bytes unchanged'

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
