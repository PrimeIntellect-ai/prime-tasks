#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import os
import re
import socket
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

ROOT = Path('/home/user/microservices')
CFG = ROOT / 'lb/haproxy.cfg'
GENERATOR = ROOT / 'generate_base.py'
SOCKET_PATH = ROOT / 'legacy.sock'


def query_port(path):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(3)
        client.connect(str(path))
        prompt = client.recv(1024)
        assert prompt == b'Enter PIN: ', f'Unexpected legacy prompt: {prompt!r}'
        client.sendall(b'8472\n')
        response = client.recv(1024).decode('utf-8', errors='replace')
    match = re.fullmatch(r'Backend port is ([0-9]+)\n?', response)
    assert match, f'Unexpected legacy response: {response!r}'
    return int(match.group(1))


def verify_generator():
    assert GENERATOR.is_file(), f'Missing generator: {GENERATOR}'
    with tempfile.TemporaryDirectory() as directory:
        target = Path(directory) / 'generated.cfg'
        env = os.environ.copy()
        env['LB_CONF_PATH'] = str(target)
        result = subprocess.run(
            [sys.executable, str(GENERATOR)], env=env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=10
        )
        assert result.returncode == 0, result.stderr
        assert target.is_file(), 'generate_base.py did not honor LB_CONF_PATH'
        return target.read_text()


def exercise_socket_scripts(cfg_bytes, cfg_stat, cfg_mtime_ns):
    candidates = []
    for path in ROOT.rglob('*.py'):
        if path.resolve() == GENERATOR.resolve() or not path.is_file() or path.is_symlink():
            continue
        if path.stat().st_mtime_ns <= cfg_mtime_ns:
            candidates.append(path)

    assert candidates, (
        'No socket-interaction Python script was created before the final '
        'configuration was assembled'
    )

    challenge_port = 10000 + int.from_bytes(os.urandom(2), 'big') % 50000
    backup = ROOT / ('.legacy.sock.verifier.' + os.urandom(6).hex())
    os.rename(SOCKET_PATH, backup)
    passed = []

    try:
        for candidate in candidates:
            try:
                if SOCKET_PATH.exists() or SOCKET_PATH.is_socket():
                    SOCKET_PATH.unlink()
            except FileNotFoundError:
                pass

            server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            server.bind(str(SOCKET_PATH))
            server.listen(5)
            server.settimeout(0.25)
            stop = threading.Event()
            authenticated = threading.Event()

            def serve():
                while not stop.is_set():
                    try:
                        conn, _ = server.accept()
                    except socket.timeout:
                        continue
                    except OSError:
                        return
                    with conn:
                        try:
                            conn.sendall(b'Enter PIN: ')
                            supplied = conn.recv(1024).decode('utf-8', errors='replace').strip()
                            if supplied == '8472':
                                authenticated.set()
                                conn.sendall(f'Backend port is {challenge_port}\n'.encode())
                            else:
                                conn.sendall(b'Invalid PIN\n')
                        except OSError:
                            pass

            thread = threading.Thread(target=serve, daemon=True)
            thread.start()
            try:
                result = subprocess.run(
                    [sys.executable, str(candidate)], cwd=str(candidate.parent),
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    text=True, timeout=10
                )
                combined = result.stdout + '\n' + result.stderr
                output_has_port = re.search(rf'(?<![0-9]){challenge_port}(?![0-9])', combined) is not None
                cfg_has_port = False
                if CFG.exists():
                    current = CFG.read_text(errors='replace')
                    cfg_has_port = re.search(
                        rf'^\s*server\s+legacy\s+127\.0\.0\.1:{challenge_port}\s*$',
                        current, re.MULTILINE
                    ) is not None
                if result.returncode == 0 and authenticated.is_set() and (output_has_port or cfg_has_port):
                    passed.append(str(candidate))
            except (subprocess.TimeoutExpired, OSError):
                pass
            finally:
                stop.set()
                server.close()
                thread.join(timeout=1)
                CFG.write_bytes(cfg_bytes)
                os.chmod(CFG, cfg_stat.st_mode & 0o7777)
                os.utime(CFG, ns=(cfg_stat.st_atime_ns, cfg_stat.st_mtime_ns))

        assert passed, (
            'No created Python script successfully authenticated to the Unix '
            'socket and extracted a verifier-selected backend port'
        )
    finally:
        try:
            if SOCKET_PATH.exists() or SOCKET_PATH.is_socket():
                SOCKET_PATH.unlink()
        except FileNotFoundError:
            pass
        os.rename(backup, SOCKET_PATH)


def main():
    assert CFG.is_file(), f'The file {CFG} does not exist'
    cfg_bytes = CFG.read_bytes()
    cfg_stat = CFG.stat()

    base = verify_generator()
    legacy_port = query_port(SOCKET_PATH)

    registry_servers = []
    with open(ROOT / 'registry.txt', encoding='utf-8') as registry:
        for raw in registry:
            fields = raw.split()
            if len(fields) == 3 and fields[1] == 'UP':
                registry_servers.append(f'    server {fields[0]} 127.0.0.1:{fields[2]}')

    expected = base + 'backend web_cluster\n' + '\n'.join(
        registry_servers + [f'    server legacy 127.0.0.1:{legacy_port}']
    )
    content = cfg_bytes.decode('utf-8')
    content_lines = [line.rstrip() for line in content.splitlines() if line.strip()]
    expected_lines = [line.rstrip() for line in expected.splitlines() if line.strip()]
    assert content_lines == expected_lines, (
        f'The contents of {CFG} are incorrect.\nExpected:\n' +
        '\n'.join(expected_lines) + '\n\nGot:\n' + '\n'.join(content_lines)
    )

    exercise_socket_scripts(cfg_bytes, cfg_stat, cfg_stat.st_mtime_ns)


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
