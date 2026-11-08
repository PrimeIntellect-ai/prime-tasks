#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import re
import secrets
import socket
import ssl
import subprocess
import time
from pathlib import Path

import pytest
import requests

requests.packages.urllib3.disable_warnings()


def listener_owners(port, address_hex=None):
    inodes = set()
    with open('/proc/net/tcp', 'r') as f:
        next(f)
        for line in f:
            fields = line.split()
            local_address, state, inode = fields[1], fields[3], fields[9]
            address, hex_port = local_address.split(':')
            if state == '0A' and int(hex_port, 16) == port:
                if address_hex is None or address.upper() == address_hex.upper():
                    inodes.add(inode)

    owners = []
    for proc_entry in Path('/proc').iterdir():
        if not proc_entry.name.isdigit():
            continue
        fd_dir = proc_entry / 'fd'
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                match = re.fullmatch(r'socket:\[(\d+)\]', target)
                if match and match.group(1) in inodes:
                    owners.append(int(proc_entry.name))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return sorted(set(owners))


def proc_exe(pid):
    try:
        return os.path.realpath(f'/proc/{pid}/exe')
    except OSError:
        return ''


def proc_cmdline(pid):
    try:
        return Path(f'/proc/{pid}/cmdline').read_bytes().replace(b'\0', b' ').decode(errors='replace')
    except OSError:
        return ''


def proc_uid(pid):
    return os.stat(f'/proc/{pid}').st_uid


def get_passcode_by_ocr():
    result = subprocess.run(
        ['tesseract', '/app/secret_passcode.png', 'stdout', '--psm', '7'],
        capture_output=True, text=True, timeout=20, check=True
    )
    token = ''.join(result.stdout.split())
    assert re.fullmatch(r'[A-Za-z0-9]+', token), f'OCR did not yield one alphanumeric passcode: {token!r}'
    return token


def wait_for_http(url, headers=None, https=False):
    last_error = None
    for _ in range(20):
        try:
            return requests.get(url, headers=headers, verify=not https, timeout=3)
        except requests.RequestException as exc:
            last_error = exc
            time.sleep(0.25)
    pytest.fail(f'Failed to connect to {url}: {last_error}')


def test_system_timezone():
    result = subprocess.run(['timedatectl', 'show'], capture_output=True, text=True)
    assert 'Timezone=Europe/Helsinki' in result.stdout, 'System timezone is not set to Europe/Helsinki.'


def test_system_locale():
    result = subprocess.run(['localectl', 'show'], capture_output=True, text=True)
    assert 'fi_FI.UTF-8' in result.stdout, 'System locale is not set to fi_FI.UTF-8.'


def test_vault_file_exists_and_content():
    vault_path = '/home/user/secure_fs/vault.txt'
    assert os.path.exists(vault_path), f'Vault file {vault_path} is missing.'
    with open(vault_path, 'r') as f:
        content = f.read().strip()
    assert content == 'CONFIDENTIAL_SYSTEM_DATA', 'Vault file does not contain the expected data.'


def test_cpp_source_binary_and_running_backend():
    source = Path('/home/user/server.cpp')
    binary = Path('/home/user/server')
    assert source.is_file() and not source.is_symlink(), 'The required server.cpp source file is missing.'
    assert binary.is_file() and not binary.is_symlink(), 'The required compiled server binary is missing.'
    assert os.access(binary, os.X_OK), 'The server binary is not executable.'
    assert binary.read_bytes()[:4] == b'\x7fELF', 'The server artifact is not an ELF executable.'

    compile_result = subprocess.run(
        ['g++', str(source), '-o', '/tmp/verifier_server_build'],
        capture_output=True, text=True, timeout=30
    )
    assert compile_result.returncode == 0, f'server.cpp does not compile: {compile_result.stderr}'

    owners = listener_owners(9000, '0100007F')
    assert owners, 'Nothing is listening on 127.0.0.1:9000.'
    assert any(os.path.samefile(proc_exe(pid), binary) for pid in owners if os.path.exists(proc_exe(pid))), \
        'Port 9000 is not owned by the required /home/user/server executable.'


def test_ssh_tunnel_process_and_binding():
    owners = listener_owners(8080, '0100007F')
    assert owners, 'Nothing is listening on 127.0.0.1:8080.'
    ssh_owners = []
    for pid in owners:
        if os.path.basename(proc_exe(pid)) == 'ssh':
            cmd = proc_cmdline(pid)
            if '-L' in cmd and '8080' in cmd and '9000' in cmd:
                ssh_owners.append(pid)
    assert ssh_owners, 'Port 8080 is not owned by an SSH client configured as the required local forward.'


def rootless_container_found():
    user = pwd.getpwnam('user')
    env_prefix = [
        'runuser', '-u', user.pw_name, '--', 'env',
        f'HOME={user.pw_dir}', f'XDG_RUNTIME_DIR=/run/user/{user.pw_uid}'
    ]

    for engine in ('podman', 'docker'):
        try:
            ids_result = subprocess.run(
                env_prefix + [engine, 'ps', '-q'], capture_output=True, text=True, timeout=15
            )
        except (FileNotFoundError, subprocess.TimeoutExpired):
            continue
        if ids_result.returncode != 0:
            continue
        for cid in ids_result.stdout.split():
            try:
                top = subprocess.run(
                    env_prefix + [engine, 'top', cid, 'args'], capture_output=True, text=True, timeout=10
                )
                ports = subprocess.run(
                    env_prefix + [engine, 'port', cid], capture_output=True, text=True, timeout=10
                )
            except subprocess.TimeoutExpired:
                continue
            if top.returncode == 0 and ports.returncode == 0:
                if 'nginx' in top.stdout.lower() and re.search(r'(?:0\.0\.0\.0|127\.0\.0\.1|\[::\]):8443\b', ports.stdout):
                    return True

    # Fallback for rootless Podman installations whose storage can no longer be
    # queried from a fresh verifier session. Require a non-root nginx process
    # carrying a real container cgroup marker.
    for proc_entry in Path('/proc').iterdir():
        if not proc_entry.name.isdigit():
            continue
        pid = int(proc_entry.name)
        try:
            if proc_uid(pid) == 0 or 'nginx' not in proc_cmdline(pid).lower():
                continue
            cgroup = Path(f'/proc/{pid}/cgroup').read_text(errors='replace').lower()
            if 'libpod' in cgroup or 'docker' in cgroup or 'containerd' in cgroup:
                return True
        except (OSError, ProcessLookupError):
            continue
    return False


def test_rootless_nginx_container_tls_and_binding():
    cert = Path('/home/user/certs/server.crt')
    key = Path('/home/user/certs/server.key')
    assert cert.is_file() and not cert.is_symlink(), 'server.crt is missing.'
    assert key.is_file() and not key.is_symlink(), 'server.key is missing.'

    cert_check = subprocess.run(['openssl', 'x509', '-in', str(cert), '-noout'], capture_output=True, text=True)
    key_check = subprocess.run(['openssl', 'pkey', '-in', str(key), '-noout'], capture_output=True, text=True)
    assert cert_check.returncode == 0, 'server.crt is not a valid X.509 certificate.'
    assert key_check.returncode == 0, 'server.key is not a valid private key.'

    cert_pub = subprocess.run(['openssl', 'x509', '-in', str(cert), '-pubkey', '-noout'], capture_output=True, check=True).stdout
    key_pub = subprocess.run(['openssl', 'pkey', '-in', str(key), '-pubout'], capture_output=True, check=True).stdout
    assert cert_pub == key_pub, 'The TLS certificate and private key do not match.'

    owners = listener_owners(8443, '00000000')
    assert owners, 'HTTPS is not bound to IPv4 0.0.0.0:8443.'
    assert all(proc_uid(pid) != 0 for pid in owners), 'The published HTTPS listener is not rootless.'
    assert rootless_container_found(), 'No running rootless Nginx container publishing port 8443 was found.'

    live_pem = ssl.get_server_certificate(('127.0.0.1', 8443))
    live_der = ssl.PEM_cert_to_DER_cert(live_pem)
    file_der = ssl.PEM_cert_to_DER_cert(cert.read_text())
    assert live_der == file_der, 'Port 8443 is not serving the required server.crt certificate.'


def test_https_endpoint_success():
    url = 'https://127.0.0.1:8443/vault'
    headers = {'Authorization': 'Bearer A9b3FkL2'}
    try:
        response = requests.get(url, headers=headers, verify=False, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f'Failed to connect to the HTTPS endpoint: {e}')
    assert response.status_code == 200, f'Expected status code 200, got {response.status_code}. Response: {response.text}'
    assert 'CONFIDENTIAL_SYSTEM_DATA' in response.text, 'Response body does not contain the expected vault data.'


def test_https_endpoint_forbidden():
    url = 'https://127.0.0.1:8443/vault'
    headers = {'Authorization': 'Bearer BADTOKEN'}
    try:
        response = requests.get(url, headers=headers, verify=False, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f'Failed to connect to the HTTPS endpoint: {e}')
    assert response.status_code == 403, f'Expected status code 403, got {response.status_code}.'


def test_https_endpoint_missing_token():
    url = 'https://127.0.0.1:8443/vault'
    try:
        response = requests.get(url, verify=False, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f'Failed to connect to the HTTPS endpoint: {e}')
    assert response.status_code == 403, f'Expected status code 403, got {response.status_code}.'


def test_derived_authorization_and_live_full_chain():
    token = get_passcode_by_ocr()
    invalid_token = token + secrets.token_hex(8)
    dynamic_value = 'VERIFIER_' + secrets.token_hex(16)
    vault = Path('/home/user/secure_fs/vault.txt')
    original = vault.read_bytes()

    try:
        vault.write_text(dynamic_value)
        headers = {'Authorization': f'Bearer {token}'}

        direct = wait_for_http('http://127.0.0.1:9000/vault', headers=headers)
        assert direct.status_code == 200 and direct.text.strip() == dynamic_value, \
            'The compiled backend did not read and return the current vault file.'

        tunneled = wait_for_http('http://127.0.0.1:8080/vault', headers=headers)
        assert tunneled.status_code == 200 and tunneled.text.strip() == dynamic_value, \
            'Traffic through port 8080 does not reach the backend.'

        proxied = wait_for_http('https://127.0.0.1:8443/vault', headers=headers, https=True)
        assert proxied.status_code == 200 and proxied.text.strip() == dynamic_value, \
            'The TLS reverse proxy does not traverse the SSH tunnel to the live backend.'

        for url, https in (
            ('http://127.0.0.1:9000/vault', False),
            ('http://127.0.0.1:8080/vault', False),
            ('https://127.0.0.1:8443/vault', True),
        ):
            denied = wait_for_http(url, headers={'Authorization': f'Bearer {invalid_token}'}, https=https)
            assert denied.status_code == 403, f'{url} accepted a verifier-generated invalid passcode.'
    finally:
        vault.write_bytes(original)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
