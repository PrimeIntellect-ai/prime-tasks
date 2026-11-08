#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import signal
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

import pytest

HOME = Path('/home/user')
EXPECTED_V1 = b'HTTP/1.1 200 OK\r\n\r\nOK_V1\n'
EXPECTED_V2 = b'HTTP/1.1 200 OK\r\n\r\nOK_V2\n'


def free_port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


def raw_response(port, timeout=5):
    data = bytearray()
    with socket.create_connection(('127.0.0.1', port), timeout=timeout) as s:
        s.settimeout(timeout)
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            data.extend(chunk)
    return bytes(data)


def wait_response(port, expected, timeout=6):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            last = raw_response(port, 0.5)
            if last == expected:
                return
        except OSError as exc:
            last = exc
        time.sleep(0.1)
    raise AssertionError(f'port {port} did not return the exact expected response; last={last!r}')


def listener_pids(port):
    result = subprocess.run(
        ['lsof', '-t', f'-iTCP:{port}', '-sTCP:LISTEN'],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL
    )
    return [int(x) for x in result.stdout.split() if x.isdigit()]


def stop_port(port):
    pids = listener_pids(port)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while listener_pids(port) and time.time() < deadline:
        time.sleep(0.05)
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def start_binary(binary, port):
    proc = subprocess.Popen(
        [str(binary), str(port)], stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, start_new_session=True
    )
    return proc


def terminate(proc):
    if proc is None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait(timeout=2)


def compile_source(source, output):
    result = subprocess.run(
        ['gcc', str(source), '-o', str(output)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert result.returncode == 0, f'failed to compile {source}: {result.stderr}'


def check_program(binary, expected):
    port = free_port()
    proc = start_binary(binary, port)
    try:
        wait_response(port, expected)
    finally:
        terminate(proc)


def make_server_source(body, log_path=None):
    response = b'HTTP/1.1 200 OK\r\n\r\n' + body + b'\n'
    literal = ''.join(f'\\x{byte:02x}' for byte in response)
    log_literal = 'NULL' if log_path is None else repr(str(log_path)).replace("'", '"')
    return f'''#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

int main(int argc, char **argv) {{
    if (argc != 2) return 2;
    int port = atoi(argv[1]);
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = htons(port);
    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) || listen(fd, 32)) return 3;
    const char *log_path = {log_literal};
    if (log_path) {{ FILE *f=fopen(log_path,"a"); if(f){{fprintf(f,"START %d\\n",port);fclose(f);}} }}
    const unsigned char response[] = "{literal}";
    for (;;) {{
        int client = accept(fd, NULL, NULL);
        if (client < 0) {{ if (errno == EINTR) continue; return 4; }}
        if (log_path) {{ FILE *f=fopen(log_path,"a"); if(f){{fprintf(f,"REQ %d\\n",port);fclose(f);}} }}
        size_t sent = 0;
        while (sent < sizeof(response)-1) {{
            ssize_t n = send(client, response+sent, sizeof(response)-1-sent, 0);
            if (n <= 0) break;
            sent += (size_t)n;
        }}
        close(client);
    }}
}}
'''


def run_deploy(source, timeout=25):
    try:
        return subprocess.run(
            ['/home/user/deploy.sh', str(source)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            timeout=timeout, start_new_session=True
        )
    except subprocess.TimeoutExpired as exc:
        if exc.pid:
            try:
                os.killpg(exc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        pytest.fail('deploy.sh timed out')


def test_nginx_running():
    """Check if Nginx is running with the specified configuration."""
    try:
        output = subprocess.check_output(['pgrep', '-f', 'nginx.*-c /home/user/nginx.conf'])
        assert output.strip(), 'Nginx is not running with the specified config.'
    except subprocess.CalledProcessError:
        pytest.fail('Nginx is not running with the specified config.')


def test_backend_servers_running():
    """Check if backend C servers are listening on ports 8081 and 8082."""
    def is_listening(port):
        try:
            subprocess.check_output(['lsof', '-i', f':{port}'])
            return True
        except subprocess.CalledProcessError:
            return False

    assert is_listening(8081), 'Backend server is not listening on port 8081.'
    assert is_listening(8082), 'Backend server is not listening on port 8082.'
    assert raw_response(8081) == EXPECTED_V2
    assert raw_response(8082) == EXPECTED_V2


def test_load_balancer_response():
    """Check if the load balancer returns OK_V2."""
    try:
        req = urllib.request.Request('http://127.0.0.1:8080')
        with urllib.request.urlopen(req, timeout=5) as response:
            body = response.read().decode('utf-8')
            assert 'OK_V2' in body, f'Load balancer did not return OK_V2. Got: {body}'
            assert body == 'OK_V2\n', f'Load balancer body was not exact: {body!r}'
    except urllib.error.URLError as e:
        pytest.fail(f'Failed to connect to load balancer on port 8080: {e}')


def test_deploy_test_log():
    """Check if the deploy_test.log contains OK_V2."""
    log_path = '/home/user/deploy_test.log'
    assert os.path.exists(log_path), f'Log file {log_path} does not exist.'
    with open(log_path, 'r') as f:
        content = f.read()
        assert 'OK_V2' in content, 'Log file does not contain OK_V2.'
        assert content == 'OK_V2\n', f'deploy_test.log is not the exact curl output: {content!r}'


def test_sources_and_binary_are_real():
    for name in ('server.c', 'server_v2.c'):
        path = HOME / name
        assert path.is_file(), f'{path} is missing'
    binary = HOME / 'server_bin'
    assert binary.is_file() and os.access(binary, os.X_OK), 'server_bin is missing or not executable'
    assert binary.read_bytes().startswith(b'\x7fELF'), 'server_bin is not an ELF executable'

    with tempfile.TemporaryDirectory() as td:
        v1 = Path(td) / 'v1'
        v2 = Path(td) / 'v2'
        compile_source(HOME / 'server.c', v1)
        compile_source(HOME / 'server_v2.c', v2)
        check_program(v1, EXPECTED_V1)
        check_program(v2, EXPECTED_V2)
        check_program(binary, EXPECTED_V2)


def test_nginx_configuration():
    config_path = HOME / 'nginx.conf'
    assert config_path.is_file(), 'nginx.conf does not exist'
    config = config_path.read_text()
    compact = re.sub(r'\s+', ' ', re.sub(r'#.*', '', config))
    assert re.search(r'listen\s+8080\b', compact), 'nginx does not listen on 8080'
    assert re.search(r'server\s+127\.0\.0\.1:8081\s*;', compact)
    assert re.search(r'server\s+127\.0\.0\.1:8082\s*;', compact)
    assert re.search(r'proxy_pass\s+http://', compact), 'proxy_pass is missing'
    assert re.search(r'pid\s+/home/user/nginx_tmp/', compact), 'PID is not under nginx_tmp'
    assert re.search(r'(client_body|proxy)_temp_path\s+/home/user/nginx_tmp/', compact), 'Nginx temp path is not under nginx_tmp'
    assert (re.search(r'daemon\s+off\s*;', compact) or
            subprocess.run(['pgrep', '-af', 'nginx.*daemon off'], stdout=subprocess.PIPE).returncode == 0), \
        'Nginx was not configured or launched in non-daemon mode'
    assert (HOME / 'nginx_tmp').is_dir(), 'nginx_tmp directory is missing'


def test_backup_presence():
    """Check if backup binaries exist in /home/user/backup/."""
    backup_dir = '/home/user/backup'
    assert os.path.isdir(backup_dir), f'Backup directory {backup_dir} does not exist.'
    backups = glob.glob(os.path.join(backup_dir, 'server_bin_*'))
    assert len(backups) >= 1, 'No backup binaries found in /home/user/backup/'
    genuine = False
    for item in backups:
        path = Path(item)
        if not path.is_file() or not os.access(path, os.X_OK) or not path.read_bytes().startswith(b'\x7fELF'):
            continue
        try:
            check_program(path, EXPECTED_V1)
            genuine = True
            break
        except Exception:
            pass
    assert genuine, 'No backup is a genuine executable V1 server binary'


def test_deploy_script_permissions():
    """Check if deploy.sh is executable."""
    script_path = '/home/user/deploy.sh'
    assert os.path.exists(script_path), f'Deployment script {script_path} does not exist.'
    assert os.access(script_path, os.X_OK), f'Deployment script {script_path} is not executable.'


def test_deploy_script_success_health_checks_and_rollback():
    binary = HOME / 'server_bin'
    original = binary.read_bytes()
    original_mode = binary.stat().st_mode
    token = ('VERIFY_' + os.urandom(12).hex()).encode()

    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        log = td / 'connections.log'
        good_source = td / 'good.c'
        bad_source = td / 'bad.c'
        good_source.write_text(make_server_source(token, log))
        bad_source.write_text('#include <stdlib.h>\nint main(int argc, char **argv) { (void)argc; (void)argv; return 23; }\n')
        expected = b'HTTP/1.1 200 OK\r\n\r\n' + token + b'\n'
        before = binary.read_bytes()

        try:
            result = run_deploy(good_source)
            assert result.returncode == 0, 'deploy.sh failed a valid deployment'
            events = log.read_text().splitlines() if log.exists() else []
            assert 'START 8081' in events and 'START 8082' in events, 'new binary was not started on both ports'
            assert 'REQ 8081' in events and 'REQ 8082' in events, 'deploy.sh did not health-check both staged instances'
            assert raw_response(8081) == expected
            assert raw_response(8082) == expected
            deployed = binary.read_bytes()
            assert deployed != before, 'deploy.sh did not overwrite server_bin with the compiled source'
            assert any(Path(p).read_bytes() == before for p in glob.glob('/home/user/backup/server_bin_*')), \
                'deploy.sh did not create a genuine backup of the pre-deployment binary'

            result = run_deploy(bad_source)
            assert result.returncode != 0, 'deploy.sh reported success for an unhealthy deployment'
            assert binary.read_bytes() == deployed, 'deploy.sh did not restore the last working binary'
            wait_response(8081, expected)
            wait_response(8082, expected)
        finally:
            stop_port(8081)
            stop_port(8082)
            binary.write_bytes(original)
            os.chmod(binary, original_mode)
            start_binary(binary, 8081)
            start_binary(binary, 8082)
            wait_response(8081, EXPECTED_V2)
            wait_response(8082, EXPECTED_V2)


def test_nginx_round_robin_behavior():
    binary = HOME / 'server_bin'
    marker1 = b'RR_' + os.urandom(8).hex().encode()
    marker2 = b'RR_' + os.urandom(8).hex().encode()

    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        source1, source2 = td / 'one.c', td / 'two.c'
        bin1, bin2 = td / 'one', td / 'two'
        source1.write_text(make_server_source(marker1))
        source2.write_text(make_server_source(marker2))
        compile_source(source1, bin1)
        compile_source(source2, bin2)
        p1 = p2 = None
        try:
            stop_port(8081)
            stop_port(8082)
            p1 = start_binary(bin1, 8081)
            p2 = start_binary(bin2, 8082)
            wait_response(8081, b'HTTP/1.1 200 OK\r\n\r\n' + marker1 + b'\n')
            wait_response(8082, b'HTTP/1.1 200 OK\r\n\r\n' + marker2 + b'\n')
            bodies = []
            for _ in range(6):
                with urllib.request.urlopen('http://127.0.0.1:8080/', timeout=5) as response:
                    bodies.append(response.read().rstrip(b'\n'))
            assert set(bodies) == {marker1, marker2}, f'Nginx did not use both upstreams: {bodies!r}'
            assert all(bodies[i] != bodies[i+1] for i in range(len(bodies)-1)), \
                f'Nginx did not alternate upstreams round-robin: {bodies!r}'
        finally:
            terminate(p1)
            terminate(p2)
            stop_port(8081)
            stop_port(8082)
            start_binary(binary, 8081)
            start_binary(binary, 8082)
            wait_response(8081, EXPECTED_V2)
            wait_response(8082, EXPECTED_V2)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
