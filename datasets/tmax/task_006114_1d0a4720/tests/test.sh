#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import binascii
import json
import os
import re
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

HOME = Path('/home/user')
KEY_PATH = HOME / 'key.txt'
TRAFFIC_PATH = HOME / 'traffic.json'
BLOCKED_PATH = HOME / 'blocked_ip.txt'
FILENAME_PATH = HOME / 'malicious_filename.txt'


def test_blocked_ip_file():
    file_path = '/home/user/blocked_ip.txt'

    assert os.path.exists(file_path), f'Error: The file {file_path} does not exist. Did the script run successfully?'
    assert os.path.isfile(file_path), f'Error: {file_path} is not a valid file.'

    with open(file_path, 'r') as f:
        content = f.read().strip()

    expected_ip = '10.5.22.114'
    assert content == expected_ip, f"Error: The blocked IP is incorrect. Expected '{expected_ip}', but found '{content}'."


def test_malicious_filename_file():
    file_path = '/home/user/malicious_filename.txt'

    assert os.path.exists(file_path), f'Error: The file {file_path} does not exist. Did the script extract the filename?'
    assert os.path.isfile(file_path), f'Error: {file_path} is not a valid file.'

    with open(file_path, 'r') as f:
        content = f.read().strip()

    expected_filename = '../../../../etc/shadow'
    assert content == expected_filename, f"Error: The extracted malicious filename is incorrect. Expected '{expected_filename}', but found '{content}'."


def discover_candidates():
    roots = [Path('/home/user'), Path('/root'), Path('/tmp')]
    excluded_parts = {'.cache', '.git', 'pkg', 'vendor', 'testdata'}
    groups = {}

    for root in roots:
        if not root.exists():
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            current = Path(dirpath)
            dirnames[:] = [d for d in dirnames if d not in excluded_parts and not d.startswith('.go-build')]
            if any(part in excluded_parts for part in current.parts):
                continue

            files = []
            main_files = []
            for name in filenames:
                if not name.endswith('.go') or name.endswith('_test.go'):
                    continue
                path = current / name
                try:
                    text = path.read_text(errors='ignore')
                except OSError:
                    continue
                if re.search(r'(?m)^\s*package\s+main\b', text):
                    files.append(path)
                    if re.search(r'\bfunc\s+main\s*\(', text):
                        main_files.append(path)

            if main_files:
                groups[str(current)] = (files, main_files)

    candidates = []
    seen = set()
    for directory, (files, main_files) in groups.items():
        all_spec = tuple(sorted(str(p) for p in files))
        if all_spec not in seen:
            candidates.append((Path(directory), list(all_spec)))
            seen.add(all_spec)
        for path in main_files:
            spec = (str(path),)
            if spec not in seen:
                candidates.append((Path(directory), [str(path)]))
                seen.add(spec)
    return candidates


def make_traffic(attacker_ip, malicious_filename, attack_index):
    key = secrets.token_bytes(32)
    aes = AESGCM(key)
    benign = [
        ('192.0.2.' + str(secrets.randbelow(200) + 1), 'quarterly-report.pdf'),
        ('198.51.100.' + str(secrets.randbelow(200) + 1), 'team-photo.png'),
        ('203.0.113.' + str(secrets.randbelow(200) + 1), 'archive.tar.gz'),
    ]
    entries = benign[:]
    entries.insert(attack_index, (attacker_ip, malicious_filename))

    lines = []
    for i, (ip, filename) in enumerate(entries, 1):
        boundary = '----VerifierBoundary' + secrets.token_hex(8)
        body = (
            f'--{boundary}\r\n'
            f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n'
            'Content-Type: application/octet-stream\r\n\r\n'
            f'payload-{secrets.token_hex(12)}\r\n'
            f'--{boundary}--'
        )
        raw = (
            'POST /upload HTTP/1.1\r\n'
            'Host: internal.corp\r\n'
            f'Content-Type: multipart/form-data; boundary={boundary}\r\n'
            f'Content-Length: {len(body.encode())}\r\n\r\n'
            f'{body}'
        ).encode()
        nonce = i.to_bytes(4, 'big') + secrets.token_bytes(8)
        ciphertext = nonce + aes.encrypt(nonce, raw, None)
        lines.append(json.dumps({'ip': ip, 'ciphertext': binascii.hexlify(ciphertext).decode()}))

    return binascii.hexlify(key).decode().encode(), ('\n'.join(lines) + '\n').encode()


def clear_outputs():
    for path in (BLOCKED_PATH, FILENAME_PATH):
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def outputs_equal(ip, filename):
    try:
        return BLOCKED_PATH.read_bytes() == ip.encode() and FILENAME_PATH.read_bytes() == filename.encode()
    except (OSError, UnicodeError):
        return False


def build_candidate(directory, files, output):
    env = os.environ.copy()
    env.setdefault('GO111MODULE', 'auto')
    result = subprocess.run(
        ['go', 'build', '-o', str(output)] + files,
        cwd=str(directory), env=env, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=45
    )
    return result.returncode == 0 and output.is_file()


def run_candidate(executable, directory, scenarios):
    for key_data, traffic_data, expected_ip, expected_filename in scenarios:
        KEY_PATH.write_bytes(key_data)
        TRAFFIC_PATH.write_bytes(traffic_data)
        clear_outputs()
        try:
            result = subprocess.run(
                [str(executable)], cwd=str(directory),
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
            )
        except (subprocess.TimeoutExpired, OSError):
            return False
        if result.returncode != 0 or not outputs_equal(expected_ip, expected_filename):
            return False
    return True


def main():
    # Preserve the original verifier's output assertions.
    test_blocked_ip_file()
    test_malicious_filename_file()

    candidates = discover_candidates()
    assert candidates, 'No submitted Go program with package main and func main was found.'

    original_key = KEY_PATH.read_bytes()
    original_traffic = TRAFFIC_PATH.read_bytes()
    original_outputs = {
        BLOCKED_PATH: BLOCKED_PATH.read_bytes() if BLOCKED_PATH.exists() else None,
        FILENAME_PATH: FILENAME_PATH.read_bytes() if FILENAME_PATH.exists() else None,
    }

    token1 = secrets.token_hex(6)
    token2 = secrets.token_hex(6)
    ip1 = f'100.64.{secrets.randbelow(200) + 1}.{secrets.randbelow(200) + 1}'
    ip2 = f'10.{secrets.randbelow(200) + 20}.{secrets.randbelow(200) + 1}.{secrets.randbelow(200) + 1}'
    name1 = f'../../../var/tmp/{token1}/secret.db'
    name2 = f'uploads/{token2}/../../../../root/.ssh/authorized_keys'
    key1, traffic1 = make_traffic(ip1, name1, 2)
    key2, traffic2 = make_traffic(ip2, name2, 0)

    scenarios = [
        (original_key, original_traffic, '10.5.22.114', '../../../../etc/shadow'),
        (key1, traffic1, ip1, name1),
        (key2, traffic2, ip2, name2),
    ]

    passed = False
    try:
        with tempfile.TemporaryDirectory(prefix='go-verifier-') as td:
            for number, (directory, files) in enumerate(candidates):
                executable = Path(td) / f'candidate-{number}'
                try:
                    if build_candidate(directory, files, executable) and run_candidate(executable, directory, scenarios):
                        passed = True
                        break
                except (OSError, subprocess.TimeoutExpired):
                    continue
    finally:
        KEY_PATH.write_bytes(original_key)
        TRAFFIC_PATH.write_bytes(original_traffic)
        for path, data in original_outputs.items():
            if data is None:
                try:
                    path.unlink()
                except FileNotFoundError:
                    pass
            else:
                path.write_bytes(data)

    assert passed, 'No submitted Go program correctly decrypted and analyzed the original and randomized traffic logs.'


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
