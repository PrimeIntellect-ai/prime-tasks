#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_pipeline.py
import json
import os
import re
import secrets
import socket
import stat
import subprocess
import textwrap
import time
from pathlib import Path

HOME = Path('/home/user')
LOG = HOME / 'server_db.log'
PENDING = HOME / 'pending_users.txt'
PARSER_SRC = HOME / 'parser.cpp'
PARSER = HOME / 'parser'
PIPELINE = HOME / 'run_pipeline.sh'
EXPECT = HOME / 'interact.exp'

ORIGINAL_EXPECTED = [
    'ADD_USER jdoe AS editor',
    'ADD_USER asmith AS viewer',
    'ADD_USER tjones AS admin',
]


def noncomment_text(path):
    lines = []
    for line in path.read_text(errors='replace').splitlines():
        stripped = line.lstrip()
        if not stripped.startswith('#'):
            lines.append(line)
    return '\n'.join(lines)


def test_server_db_log_contents():
    assert LOG.exists(), f'Log file {LOG} does not exist. The pipeline may not have run successfully.'
    lines = [line.strip() for line in LOG.read_text().splitlines() if line.strip()]
    assert lines == ORIGINAL_EXPECTED, f'Contents of {LOG} do not match expected output. Got: {lines}'


def test_required_files_exist():
    required_files = [PARSER_SRC, PIPELINE, EXPECT]
    for file_path in required_files:
        assert file_path.exists(), f'Required file {file_path} is missing.'


def test_pipeline_artifacts_and_dynamic_execution(tmp_path):
    for path in (PARSER_SRC, PIPELINE, EXPECT):
        assert path.is_file(), f'{path} must be a regular file'
        assert path.stat().st_size > 0, f'{path} must not be empty'

    parser_source = PARSER_SRC.read_text(errors='replace')
    pipeline_text = noncomment_text(PIPELINE)
    expect_text = noncomment_text(EXPECT)

    first_line = PIPELINE.read_text(errors='replace').splitlines()[0]
    assert re.match(r'^#!.*(?:/|\s)bash(?:\s|$)', first_line), 'run_pipeline.sh must be a Bash script'
    assert re.search(r'\b(?:g\+\+|c\+\+)\b', pipeline_text), 'run_pipeline.sh must compile the C++ parser'
    assert re.search(r'\bssh\b', pipeline_text), 'run_pipeline.sh must invoke SSH'
    assert re.search(r'-L(?:\s+)?[^\n]*8888[^\n]*9999', pipeline_text), 'run_pipeline.sh must request the 8888-to-9999 SSH forward'
    assert re.search(r'\btrap\b', pipeline_text), 'run_pipeline.sh must install a cleanup trap'
    assert re.search(r'\bexpect\b', pipeline_text), 'run_pipeline.sh must invoke Expect'
    assert 'interact.exp' in pipeline_text, 'run_pipeline.sh must invoke interact.exp'
    assert re.search(r'(?<![A-Za-z0-9_])(?:/home/user/)?parser(?![A-Za-z0-9_.])', pipeline_text), 'run_pipeline.sh must run the compiled parser'

    assert re.search(r'\bspawn\b[^\n]*\bnc\b', expect_text), 'interact.exp must spawn nc'
    assert re.search(r'\bnc\b[^\n]*(?:localhost|127\.0\.0\.1)[^\n]*8888', expect_text), 'interact.exp must connect nc to local port 8888'
    for token in ('READY>', 'SUCCESS', 'QUIT'):
        assert token in expect_text, f'interact.exp must handle {token}'
    assert re.search(r'\bsend\b', expect_text), 'interact.exp must send commands to the backend'
    assert re.search(r'\b(?:std::|fstream|ifstream|cin|getline)\b', parser_source), 'parser.cpp must contain a C++ input parser'

    original_pending = PENDING.read_bytes()
    original_log = LOG.read_bytes()
    tag = secrets.token_hex(5)
    users = [
        (f'user_{tag}_a', 'auditor'),
        (f'user_{tag}_b', 'operator'),
        (f'user_{tag}_c', 'maintainer'),
        (f'user_{tag}_d', 'reviewer'),
    ]
    expected = [f'ADD_USER {username} AS {role}' for username, role in users]

    private = tmp_path / 'backend-private'
    private.mkdir(mode=0o700)
    transcript = private / 'transcript.json'
    ready = private / 'ready'
    backend = private / 'backend.py'
    backend.write_text(textwrap.dedent(r'''
        import json
        import os
        import socket
        import time

        TRANSCRIPT = os.environ['TRANSCRIPT']
        READY_FILE = os.environ['READY_FILE']

        def socket_owner_chain(peer_port):
            inode = None
            for _ in range(10):
                try:
                    rows = open('/proc/net/tcp').read().splitlines()[1:]
                    for row in rows:
                        fields = row.split()
                        local_port = int(fields[1].split(':')[1], 16)
                        remote_port = int(fields[2].split(':')[1], 16)
                        if local_port == peer_port and remote_port == 9999:
                            inode = fields[9]
                            break
                except OSError:
                    pass
                if inode:
                    break
                time.sleep(0.02)
            if not inode:
                return []
            owner = None
            for pid in os.listdir('/proc'):
                if not pid.isdigit():
                    continue
                fd_dir = f'/proc/{pid}/fd'
                try:
                    for fd in os.listdir(fd_dir):
                        try:
                            if os.readlink(f'{fd_dir}/{fd}') == f'socket:[{inode}]':
                                owner = int(pid)
                                break
                        except OSError:
                            pass
                except OSError:
                    pass
                if owner is not None:
                    break
            chain = []
            pid = owner
            for _ in range(12):
                if not pid or pid <= 1:
                    break
                try:
                    cmd = open(f'/proc/{pid}/cmdline', 'rb').read().replace(b'\0', b' ').decode(errors='replace')
                    chain.append(cmd)
                    fields = open(f'/proc/{pid}/stat').read().split()
                    pid = int(fields[3])
                except (OSError, ValueError, IndexError):
                    break
            return chain

        records = []
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
            server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            server.bind(('127.0.0.1', 9999))
            server.listen(8)
            open(READY_FILE, 'w').write('ready')
            finished = False
            while not finished:
                conn, addr = server.accept()
                chain = socket_owner_chain(addr[1])
                via_sshd = any('sshd' in command for command in chain)
                with conn:
                    conn.sendall(b'READY>')
                    pending = b''
                    while True:
                        data = conn.recv(4096)
                        if not data:
                            break
                        pending += data
                        while b'\n' in pending or b'\r' in pending:
                            positions = [p for p in (pending.find(b'\n'), pending.find(b'\r')) if p >= 0]
                            pos = min(positions)
                            raw, pending = pending[:pos], pending[pos + 1:]
                            pending = pending.lstrip(b'\r\n')
                            line = raw.decode('utf-8', errors='replace').strip()
                            if not line:
                                continue
                            records.append({'line': line, 'via_sshd': via_sshd, 'chain': chain})
                            if line == 'QUIT':
                                finished = True
                                break
                            if line.startswith('ADD_USER '):
                                with open('/home/user/server_db.log', 'a') as log:
                                    log.write(line + '\n')
                                conn.sendall(b'SUCCESS\nREADY>')
                            else:
                                conn.sendall(b'ERROR\nREADY>')
                        if finished:
                            break
        with open(TRANSCRIPT, 'w') as output:
            json.dump(records, output)
    '''))

    server = None
    try:
        PENDING.write_text(''.join(f'{username}:{role}\n' for username, role in users))
        os.chmod(PENDING, 0o644)
        if LOG.exists():
            LOG.unlink()
        if PARSER.exists() or PARSER.is_symlink():
            PARSER.unlink()

        subprocess.run(['pkill', '-f', 'python3 /home/user/backend.py'], check=False)
        subprocess.run(['service', 'ssh', 'start'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        subprocess.run(['/usr/sbin/sshd'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)

        env = os.environ.copy()
        env['TRANSCRIPT'] = str(transcript)
        env['READY_FILE'] = str(ready)
        server = subprocess.Popen(['python3', str(backend)], env=env)
        deadline = time.time() + 5
        while not ready.exists() and time.time() < deadline:
            assert server.poll() is None, 'controlled backend exited before listening'
            time.sleep(0.05)
        assert ready.exists(), 'controlled backend did not start'

        result = subprocess.run(
            ['sudo', '-u', 'user', '-H', 'timeout', '40', 'bash', str(PIPELINE)],
            cwd=str(HOME), text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        assert result.returncode == 0, f'run_pipeline.sh failed ({result.returncode})\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}'

        deadline = time.time() + 5
        while not transcript.exists() and time.time() < deadline:
            time.sleep(0.05)
        assert transcript.exists(), 'backend did not receive a graceful QUIT'

        assert PARSER.is_file(), 'run_pipeline.sh did not produce /home/user/parser'
        mode = PARSER.stat().st_mode
        assert mode & stat.S_IXUSR, '/home/user/parser is not executable'
        assert PARSER.read_bytes()[:4] == b'\x7fELF', '/home/user/parser is not a compiled native executable'
        parsed = subprocess.run([str(PARSER)], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        assert parsed.returncode == 0, f'compiled parser failed: {parsed.stderr}'
        assert parsed.stdout.splitlines() == expected, f'parser output was {parsed.stdout.splitlines()}'

        records = json.loads(transcript.read_text())
        assert [record['line'] for record in records] == expected + ['QUIT'], f'backend transcript was {records}'
        assert all(record['via_sshd'] for record in records), 'backend connection did not originate through the SSH daemon'

        assert LOG.exists(), 'backend log was not created during the dynamic run'
        dynamic_log = [line.strip() for line in LOG.read_text().splitlines() if line.strip()]
        assert dynamic_log == expected, f'dynamic backend log was {dynamic_log}'

        time.sleep(0.5)
        probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        probe.settimeout(0.5)
        try:
            assert probe.connect_ex(('127.0.0.1', 8888)) != 0, 'SSH tunnel on port 8888 was not cleaned up'
        finally:
            probe.close()
    finally:
        if server is not None and server.poll() is None:
            server.terminate()
            try:
                server.wait(timeout=2)
            except subprocess.TimeoutExpired:
                server.kill()
        PENDING.write_bytes(original_pending)
        LOG.write_bytes(original_log)
        os.chmod(PENDING, 0o777)
        os.chmod(LOG, 0o777)
PYTEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_pipeline.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
