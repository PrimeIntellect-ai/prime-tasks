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

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import datetime
import hashlib
import os
import secrets
import socket
import ssl
import struct
import subprocess
import time
from pathlib import Path

import cv2
import requests
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

MANIFEST = Path('/home/user/manifests/nginx.yaml')
CRT = Path('/home/user/certs/server.crt')
KEY = Path('/home/user/certs/server.key')
URL = 'https://127.0.0.1:8443/api/v1/manifest'


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def black_frame_count():
    cap = cv2.VideoCapture('/app/deploy_sequence.mp4')
    assert cap.isOpened(), 'Could not open deploy_sequence.mp4'
    count = 0
    frames = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frames += 1
        if frame is not None and frame.size and not frame.any():
            count += 1
    cap.release()
    assert frames > 0, 'Video contained no decodable frames'
    return count


def strip_yaml_comment(text):
    quote = None
    escaped = False
    for i, ch in enumerate(text):
        if escaped:
            escaped = False
            continue
        if ch == '\\' and quote == '"':
            escaped = True
        elif ch in ('"', "'"):
            if quote is None:
                quote = ch
            elif quote == ch:
                quote = None
        elif ch == '#' and quote is None and (i == 0 or text[i - 1].isspace()):
            return text[:i].rstrip()
    return text.rstrip()


def scalar(value):
    value = value.strip()
    if not value:
        return ''
    if value in ('{}', '[]'):
        return {} if value == '{}' else []
    low = value.lower()
    if low in ('true', 'false'):
        return low == 'true'
    if low in ('null', '~'):
        return None
    try:
        return int(value)
    except ValueError:
        pass
    if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
        try:
            return ast.literal_eval(value)
        except Exception:
            return value[1:-1]
    return value


def parse_basic_yaml(text):
    lines = []
    for raw in text.splitlines():
        assert '\t' not in raw[:len(raw) - len(raw.lstrip())], 'Tabs are not valid YAML indentation'
        cleaned = strip_yaml_comment(raw)
        if not cleaned.strip() or cleaned.strip() in ('---', '...'):
            continue
        lines.append((len(cleaned) - len(cleaned.lstrip(' ')), cleaned.lstrip(' ')))
    assert lines, 'Manifest is empty'

    def split_pair(value):
        assert ':' in value, f'Expected YAML mapping entry: {value}'
        key, rest = value.split(':', 1)
        key = key.strip()
        assert key, 'Empty YAML key'
        return key, rest.strip()

    def parse_block(pos, indent):
        assert pos < len(lines) and lines[pos][0] == indent, 'Invalid YAML indentation'
        is_list = lines[pos][1] == '-' or lines[pos][1].startswith('- ')
        out = [] if is_list else {}
        while pos < len(lines) and lines[pos][0] == indent:
            text_value = lines[pos][1]
            if is_list:
                assert text_value == '-' or text_value.startswith('- '), 'Mixed sequence and mapping'
                item = text_value[1:].strip()
                pos += 1
                if not item:
                    assert pos < len(lines) and lines[pos][0] > indent, 'Empty sequence item'
                    value, pos = parse_block(pos, lines[pos][0])
                elif ':' in item:
                    key, rest = split_pair(item)
                    value = {}
                    if rest:
                        value[key] = scalar(rest)
                    else:
                        assert pos < len(lines) and lines[pos][0] > indent, 'Missing nested value'
                        value[key], pos = parse_block(pos, lines[pos][0])
                    if pos < len(lines) and lines[pos][0] > indent:
                        extra_indent = lines[pos][0]
                        extra, pos = parse_block(pos, extra_indent)
                        assert isinstance(extra, dict), 'Sequence mapping continuation must be a mapping'
                        value.update(extra)
                else:
                    value = scalar(item)
                out.append(value)
            else:
                assert not text_value.startswith('-'), 'Mixed mapping and sequence'
                key, rest = split_pair(text_value)
                assert key not in out, f'Duplicate YAML key: {key}'
                pos += 1
                if rest:
                    out[key] = scalar(rest)
                else:
                    assert pos < len(lines) and lines[pos][0] > indent, f'Missing value for {key}'
                    out[key], pos = parse_block(pos, lines[pos][0])
        return out, pos

    result, end = parse_block(0, lines[0][0])
    assert end == len(lines), 'Could not parse complete YAML document'
    return result


def load_manifest(content):
    try:
        import yaml
        return yaml.safe_load(content)
    except ImportError:
        return parse_basic_yaml(content)


def validate_deployment(content):
    obj = load_manifest(content)
    assert isinstance(obj, dict), 'Manifest must be a YAML mapping'
    assert obj.get('apiVersion') == 'apps/v1', 'Deployment apiVersion must be apps/v1'
    assert obj.get('kind') == 'Deployment', "Manifest does not contain 'kind: Deployment'"
    metadata = obj.get('metadata')
    assert isinstance(metadata, dict) and metadata.get('name') == 'nginx-deployment', 'Deployment name must be nginx-deployment'
    spec = obj.get('spec')
    assert isinstance(spec, dict), 'Deployment spec is missing'
    assert spec.get('replicas') == 2, 'Manifest does not contain 2 replicas'
    selector = spec.get('selector')
    template = spec.get('template')
    assert isinstance(selector, dict) and isinstance(selector.get('matchLabels'), dict) and selector['matchLabels'], 'Deployment selector.matchLabels is missing'
    assert isinstance(template, dict), 'Deployment pod template is missing'
    template_meta = template.get('metadata')
    labels = template_meta.get('labels') if isinstance(template_meta, dict) else None
    assert isinstance(labels, dict), 'Pod template labels are missing'
    assert all(labels.get(k) == v for k, v in selector['matchLabels'].items()), 'Deployment selector does not match pod labels'
    pod_spec = template.get('spec')
    containers = pod_spec.get('containers') if isinstance(pod_spec, dict) else None
    assert isinstance(containers, list) and containers, 'Pod containers are missing'
    assert any(isinstance(c, dict) and c.get('image') == 'nginx:latest' for c in containers), "Manifest does not contain 'nginx:latest'"


def request(token=None):
    headers = {} if token is None else {'Authorization': 'Bearer ' + token}
    return requests.get(URL, headers=headers, verify=False, timeout=5)


def listener_inode(port):
    wanted_ip = socket.inet_aton('127.0.0.1')[::-1].hex().upper()
    with open('/proc/net/tcp') as f:
        next(f)
        for line in f:
            fields = line.split()
            address, port_hex = fields[1].split(':')
            if address == wanted_ip and int(port_hex, 16) == port and fields[3] == '0A':
                return fields[9]
    raise AssertionError(f'No IPv4 listener on 127.0.0.1:{port}')


def owner_pid(inode):
    target = 'socket:[' + inode + ']'
    owners = []
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / 'fd').iterdir():
                try:
                    if os.readlink(fd) == target:
                        owners.append(int(proc.name))
                        break
                except OSError:
                    pass
        except (OSError, PermissionError):
            pass
    assert len(owners) == 1, f'Expected one process to own listener {inode}, found {owners}'
    return owners[0]


def test_manifests_directory_and_acls():
    manifests_dir = Path('/home/user/manifests')
    assert manifests_dir.is_dir(), f'Directory {manifests_dir} does not exist.'
    assert manifests_dir.stat().st_uid == __import__('pwd').getpwnam('user').pw_uid, 'Manifest directory must be owned by user'
    result = run(['getfacl', '-cp', str(manifests_dir)])
    assert result.returncode == 0, 'Failed to run getfacl.'
    entries = [line.strip() for line in result.stdout.splitlines() if line.strip() and not line.startswith('#')]
    assert 'user::rwx' in entries, 'ACL missing user::rwx'
    assert 'group::---' in entries, 'ACL missing group::---'
    assert 'other::---' in entries, 'ACL missing other::---'
    for entry in entries:
        if entry.startswith('user:') and entry != 'user::rwx':
            assert entry.endswith(':---'), f'Unexpected named-user ACL permission: {entry}'
        if entry.startswith('group:') and entry != 'group::---':
            assert entry.endswith(':---'), f'Unexpected named-group ACL permission: {entry}'


def test_nginx_manifest_file():
    assert MANIFEST.is_file(), f'Manifest file {MANIFEST} does not exist.'
    validate_deployment(MANIFEST.read_text())


def test_fstab_configuration():
    fstab_file = Path('/home/user/operator.fstab')
    assert fstab_file.is_file(), f'File {fstab_file} does not exist.'
    found = False
    for line in fstab_file.read_text().splitlines():
        line = line.split('#', 1)[0].strip()
        parts = line.split()
        if len(parts) >= 6 and parts[0] == '/dev/sdb1' and parts[1] == '/home/user/manifests' and parts[2] == 'ext4':
            opts = set(parts[3].split(','))
            if {'noexec', 'nosuid', 'nodev'} <= opts and parts[4].isdigit() and parts[5].isdigit():
                found = True
                break
    assert found, 'Valid fstab entry for /dev/sdb1 to /home/user/manifests not found in /home/user/operator.fstab'


def test_tls_certificates_and_server_identity():
    assert CRT.is_file(), f'Certificate file {CRT} does not exist.'
    assert KEY.is_file(), f'Private key file {KEY} does not exist.'
    cert_info = run(['openssl', 'x509', '-in', str(CRT), '-noout', '-subject', '-issuer', '-startdate', '-enddate', '-checkhost', 'localhost'])
    assert cert_info.returncode == 0, cert_info.stderr or 'Certificate is not valid for localhost'
    values = {}
    for line in cert_info.stdout.splitlines():
        if '=' in line:
            k, v = line.split('=', 1)
            values[k.strip()] = v.strip()
    assert values.get('subject') == values.get('issuer'), 'Certificate is not self-issued'
    fmt = '%b %d %H:%M:%S %Y GMT'
    not_before = datetime.datetime.strptime(values['notBefore'], fmt).replace(tzinfo=datetime.timezone.utc)
    not_after = datetime.datetime.strptime(values['notAfter'], fmt).replace(tzinfo=datetime.timezone.utc)
    assert not_after - not_before >= datetime.timedelta(days=365), 'Certificate validity is less than 365 days'
    now = datetime.datetime.now(datetime.timezone.utc)
    assert not_before <= now + datetime.timedelta(minutes=5) < not_after, 'Certificate is not currently valid'
    verified = run(['openssl', 'verify', '-CAfile', str(CRT), str(CRT)])
    assert verified.returncode == 0, 'Certificate is not cryptographically self-signed'
    cert_pub = subprocess.check_output(['openssl', 'x509', '-in', str(CRT), '-pubkey', '-noout'])
    key_pub = subprocess.check_output(['openssl', 'pkey', '-in', str(KEY), '-pubout'])
    assert cert_pub == key_pub, 'Private key does not match certificate'
    context = ssl._create_unverified_context()
    with socket.create_connection(('127.0.0.1', 8443), timeout=5) as raw:
        with context.wrap_socket(raw, server_hostname='localhost') as tls:
            served_der = tls.getpeercert(binary_form=True)
    file_der = ssl.PEM_cert_to_DER_cert(CRT.read_text())
    assert served_der == file_der, 'HTTPS server is not using /home/user/certs/server.crt'


def test_https_server_auth_and_raw_dynamic_file():
    n = black_frame_count()
    valid_token = f'op-secret-{n}'
    original = MANIFEST.read_bytes()
    response = request(valid_token)
    assert response.status_code == 200, f'Expected HTTP 200, got {response.status_code}'
    assert response.content == original, 'Response is not the raw manifest file contents'
    validate_deployment(response.content.decode())

    for bad in (None, 'op-secret-99', f'op-secret-{n + 1}', 'wrong-' + secrets.token_hex(8)):
        rejected = request(bad)
        assert rejected.status_code == 403, f'Expected HTTP 403 for invalid token, got {rejected.status_code}'
        assert rejected.content == b'', 'Expected empty body for HTTP 403'

    nonce = secrets.token_hex(16).encode()
    changed = original + (b'' if original.endswith(b'\n') else b'\n') + b'# verifier-nonce: ' + nonce + b'\n'
    try:
        MANIFEST.write_bytes(changed)
        changed_response = request(valid_token)
        assert changed_response.status_code == 200
        assert changed_response.content == changed, 'Server does not read and return the current raw manifest file'
    finally:
        MANIFEST.write_bytes(original)


def test_tcp_trap():
    for payload in (b'X', b'SSH-2.0-OpenSSH_8.4p1\r\n', os.urandom(37)):
        with socket.create_connection(('127.0.0.1', 8022), timeout=5) as s:
            s.settimeout(0.25)
            try:
                unsolicited = s.recv(1024)
                assert False, f'Trap closed early or sent unsolicited data: {unsolicited!r}'
            except socket.timeout:
                pass
            s.settimeout(5)
            s.sendall(payload)
            try:
                data = s.recv(1024)
                assert data == b'', f'Expected silent close, received {data!r}'
            except ConnectionResetError:
                pass


def test_go_source_binary_and_process_provenance():
    source = Path('/home/user/operator/main.go')
    assert source.is_file() and source.stat().st_size > 0, 'Go source /home/user/operator/main.go is missing or empty'
    built = run(['go', 'build', '-o', '/tmp/verifier-operator-build', str(source)], timeout=60)
    assert built.returncode == 0, f'main.go does not compile: {built.stderr}'

    https_pid = owner_pid(listener_inode(8443))
    trap_pid = owner_pid(listener_inode(8022))
    assert https_pid == trap_pid, 'HTTPS server and TCP trap are not run by the same Go application'
    exe = os.readlink(f'/proc/{https_pid}/exe')
    assert not exe.endswith(' (deleted)') and Path(exe).is_file(), 'Running compiled binary is missing from disk'
    with open(exe, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'Running service is not a compiled ELF binary'
    info = run(['go', 'version', '-m', exe])
    assert info.returncode == 0 and ('go1.' in info.stdout or '\tgo\t' in info.stdout), 'Running service is not a compiled Go binary'

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
