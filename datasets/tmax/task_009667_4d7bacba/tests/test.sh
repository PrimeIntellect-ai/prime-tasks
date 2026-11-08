#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import socket
import subprocess
import urllib.request

EXPECTED_SOURCE = r'''#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>

#define SOCKET_PATH "/home/user/app/health.sock"

int main() {
    int server_fd, client_fd;
    struct sockaddr_un address;

    unlink(SOCKET_PATH);
    if ((server_fd = socket(AF_UNIX, SOCK_STREAM, 0)) == 0) {
        perror("Socket failed");
        exit(EXIT_FAILURE);
    }

    address.sun_family = AF_UNIX;
    strncpy(address.sun_path, SOCKET_PATH, sizeof(address.sun_path) - 1);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("Bind failed");
        exit(EXIT_FAILURE);
    }

    if (listen(server_fd, 5) < 0) {
        perror("Listen failed");
        exit(EXIT_FAILURE);
    }

    char buffer[1024] = {0};
    char *http_response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\nMAIL_HEALTH_OK\n";

    while(1) {
        if ((client_fd = accept(server_fd, NULL, NULL)) < 0) {
            perror("Accept failed");
            continue;
        }
        read(client_fd, buffer, 1024);
        write(client_fd, http_response, strlen(http_response));
        close(client_fd);
    }
    return 0;
}
'''


def all_pids():
    return [name for name in os.listdir('/proc') if name.isdigit()]


def pid_owns_inode(pid, inode):
    fd_dir = f'/proc/{pid}/fd'
    try:
        for fd in os.listdir(fd_dir):
            try:
                if os.readlink(os.path.join(fd_dir, fd)) == f'socket:[{inode}]':
                    return True
            except (FileNotFoundError, PermissionError, OSError):
                pass
    except (FileNotFoundError, PermissionError):
        pass
    return False


def pids_with_executable(path):
    result = []
    for pid in all_pids():
        try:
            if os.path.samefile(f'/proc/{pid}/exe', path):
                result.append(pid)
        except (FileNotFoundError, PermissionError, OSError):
            pass
    return result


def unix_listener_inode(path):
    with open('/proc/net/unix', 'r') as f:
        for line in f:
            fields = line.split()
            if len(fields) >= 8 and fields[7] == path:
                # Flags 00010000 identifies a listening Unix socket.
                if fields[3] == '00010000':
                    return fields[6]
    return None


def tcp_listener_inodes(port):
    result = set()
    wanted = f'{port:04X}'
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table, 'r') as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].split(':')[-1].upper() == wanted and fields[3] == '0A':
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def read_cmdline(pid):
    try:
        with open(f'/proc/{pid}/cmdline', 'rb') as f:
            return f.read().replace(b'\0', b' ').decode('utf-8', 'replace')
    except (FileNotFoundError, PermissionError):
        return ''


def test_backup_nginx_config():
    backup_path = '/home/user/backup/nginx.conf.bak'
    assert os.path.isfile(backup_path), f'Backup file {backup_path} does not exist'
    with open(backup_path, 'r') as f:
        content = f.read()
    assert 'wrong_health_path.sock' in content, 'Backup file does not contain the original wrong socket path'


def test_fixed_nginx_config():
    config_path = '/home/user/nginx/nginx.conf'
    assert os.path.isfile(config_path), f'Nginx config {config_path} does not exist'
    with open(config_path, 'r') as f:
        content = f.read()
    assert 'proxy_pass http://unix:/home/user/app/health.sock;' in content, 'Nginx config does not contain the correct socket path'
    check = subprocess.run(
        ['/usr/sbin/nginx', '-t', '-c', config_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    assert check.returncode == 0, f'Fixed Nginx configuration is invalid: {check.stdout}'


def test_health_service_compiled_and_running():
    source_path = '/home/user/app/health_service.c'
    bin_path = '/home/user/app/health_service'

    with open(source_path, 'r') as f:
        assert f.read() == EXPECTED_SOURCE, 'The supplied C source was replaced or modified'

    assert os.path.isfile(bin_path), f'Compiled executable {bin_path} does not exist'
    assert os.access(bin_path, os.X_OK), f'File {bin_path} is not executable'
    with open(bin_path, 'rb') as f:
        artifact = f.read()
    assert artifact.startswith(b'\x7fELF'), 'health_service is not a compiled ELF executable'
    assert b'/home/user/app/health.sock' in artifact, 'Executable does not contain the daemon socket path from the supplied source'
    assert b'MAIL_HEALTH_OK' in artifact, 'Executable does not contain the health response from the supplied source'

    # Keep the original process-name assertion.
    try:
        output = subprocess.check_output(['pgrep', '-f', 'health_service']).decode('utf-8')
        assert output.strip(), 'health_service is not running'
    except subprocess.CalledProcessError:
        assert False, 'health_service is not running'

    service_pids = pids_with_executable(bin_path)
    assert service_pids, 'No running process is executing the submitted health_service artifact'

    socket_path = '/home/user/app/health.sock'
    inode = unix_listener_inode(socket_path)
    assert inode is not None, 'The expected Unix socket is not listening'
    assert any(pid_owns_inode(pid, inode) for pid in service_pids), 'The submitted health_service executable does not own the expected listening socket'

    # Exercise the submitted daemon directly, independently of Nginx.
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(2)
    try:
        client.connect(socket_path)
        client.sendall(b'GET /health HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n')
        chunks = []
        while True:
            chunk = client.recv(4096)
            if not chunk:
                break
            chunks.append(chunk)
    finally:
        client.close()
    response = b''.join(chunks)
    assert response.startswith(b'HTTP/1.1 200 OK\r\n'), f'Daemon returned an invalid HTTP response: {response!r}'
    assert response.split(b'\r\n\r\n', 1)[1] == b'MAIL_HEALTH_OK\n', 'Daemon returned the wrong response body'


def test_nginx_running_and_owns_port():
    # Keep the original process-name assertion.
    try:
        output = subprocess.check_output(['pgrep', '-f', 'nginx']).decode('utf-8')
        assert output.strip(), 'nginx is not running'
    except subprocess.CalledProcessError:
        assert False, 'nginx is not running'

    nginx_path = '/usr/sbin/nginx'
    assert os.path.isfile(nginx_path), 'System Nginx executable is missing'
    nginx_pids = pids_with_executable(nginx_path)
    assert nginx_pids, 'The real Nginx executable is not running'

    config_path = '/home/user/nginx/nginx.conf'
    assert any(config_path in read_cmdline(pid) and '-c' in read_cmdline(pid) for pid in nginx_pids), 'Real Nginx was not started with the required configuration file'

    listener_inodes = tcp_listener_inodes(8080)
    assert listener_inodes, 'Nothing is listening on TCP port 8080'
    assert any(pid_owns_inode(pid, inode) for pid in nginx_pids for inode in listener_inodes), 'Port 8080 is not owned by the real Nginx process'


def test_health_result_log():
    log_path = '/home/user/health_result.log'
    assert os.path.isfile(log_path), f'Result log {log_path} does not exist'
    with open(log_path, 'r') as f:
        content = f.read()
    assert content == 'MAIL_HEALTH_OK\n', f'Result log contains incorrect output: {content!r}'


def test_health_endpoint_live():
    try:
        req = urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=2)
        response = req.read().decode('utf-8')
        assert req.status == 200, f'Live health endpoint returned status {req.status}'
        assert response == 'MAIL_HEALTH_OK\n', 'Live health endpoint returned incorrect response'
        assert req.headers.get('Server', '').lower().startswith('nginx'), 'Live endpoint response was not served by Nginx'
    except Exception as e:
        assert False, f'Failed to reach health endpoint: {e}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
