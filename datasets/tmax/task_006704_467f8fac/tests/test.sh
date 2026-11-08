#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import py_compile
import signal
import stat
import subprocess
import sys
import threading
import time
import uuid
from collections import Counter
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

HOME = '/home/user'
OUTPUT = os.path.join(HOME, 'verified_deps.txt')
PYC = os.path.join(HOME, 'legacy_app.pyc')
REQUIREMENTS = os.path.join(HOME, 'requirements.txt')


def kill_port_8080_holders():
    socket_inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local_address = fields[1]
                    state = fields[3]
                    if int(local_address.rsplit(':', 1)[1], 16) == 8080 and state == '0A':
                        socket_inodes.add(fields[9])
        except OSError:
            pass

    victims = set()
    for pid in os.listdir('/proc'):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        fd_dir = f'/proc/{pid}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in socket_inodes:
                    victims.add(int(pid))
                    break
        except OSError:
            pass

    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    if victims:
        time.sleep(0.2)


def find_python_utilities():
    excluded = {
        os.path.realpath('/home/user/api_server.py'),
        os.path.realpath(OUTPUT),
        os.path.realpath(PYC),
        os.path.realpath(REQUIREMENTS),
    }
    candidates = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if d != '__pycache__']
        for name in files:
            path = os.path.join(root, name)
            if os.path.realpath(path) in excluded or os.path.islink(path):
                continue
            try:
                mode = os.stat(path).st_mode
                with open(path, 'rb') as f:
                    prefix = f.read(256)
            except OSError:
                continue
            if not stat.S_ISREG(mode):
                continue
            if name.endswith('.py') or (prefix.startswith(b'#!') and b'python' in prefix.splitlines()[0].lower()):
                candidates.append(path)
    return sorted(candidates)


def imports_bytecode_module(path):
    try:
        with open(path, encoding='utf-8') as f:
            tree = ast.parse(f.read(), filename=path)
    except (OSError, UnicodeError, SyntaxError):
        return False
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            if any(alias.name.split('.')[0] in {'dis', 'marshal'} for alias in node.names):
                return True
        elif isinstance(node, ast.ImportFrom):
            if node.module and node.module.split('.')[0] in {'dis', 'marshal'}:
                return True
    return False


def test_completed_utility_and_output():
    # Preserve the original verifier's assertion on the requested final state.
    assert os.path.isfile(OUTPUT), f'{OUTPUT} does not exist.'
    with open(OUTPUT) as f:
        original_lines = [line.strip() for line in f if line.strip()]
    original_expected = [
        'click==8.0.0',
        'flask==1.1.2',
        'requests==2.25.1',
        'urllib3==1.26.4',
    ]
    assert original_lines == original_expected, (
        f'Content of {OUTPUT} is incorrect. Expected {original_expected}, got {original_lines}.'
    )

    candidates = find_python_utilities()
    assert candidates, 'No Python utility was written under /home/user.'
    candidates = [path for path in candidates if imports_bytecode_module(path)]
    assert candidates, 'The utility must programmatically analyze bytecode using dis or marshal.'

    token = uuid.uuid4().hex[:10]
    pyc_only = f'alpha{token}'
    shared = f'shared{token}'
    invalid_pyc = f'badpyc{token}'
    req_valid = f'reqvalid{token}'
    req_invalid = f'reqbad{token}'

    source = f'''def get_deps():\n    return [({pyc_only!r}, '3.1.4'), ({shared!r}, '7.7.7'), ({invalid_pyc!r}, '9.9.9')]\n'''
    source_path = f'/tmp/legacy_{token}.py'
    with open(source_path, 'w') as f:
        f.write(source)
    py_compile.compile(source_path, cfile=PYC, doraise=True)
    os.unlink(source_path)

    with open(REQUIREMENTS, 'w') as f:
        f.write(f'{shared}==1.0.0\n')
        f.write(f'{req_valid}==2.0.0\n')
        f.write(f'{req_invalid}==4.0.0\n')

    valid = {
        (pyc_only, '3.1.4'),
        (shared, '7.7.7'),
        (req_valid, '2.0.0'),
    }
    combined = valid | {
        (invalid_pyc, '9.9.9'),
        (req_invalid, '4.0.0'),
    }
    obsolete = (shared, '1.0.0')

    class Handler(BaseHTTPRequestHandler):
        requests = []
        forced_429 = False
        lock = threading.Lock()

        def do_GET(self):
            parsed = urlparse(self.path)
            if parsed.path != '/validate':
                self.send_response(404)
                self.end_headers()
                return
            query = parse_qs(parsed.query)
            pair = (query.get('pkg', [''])[0], query.get('ver', [''])[0])
            with Handler.lock:
                Handler.requests.append(pair)
                if not Handler.forced_429:
                    Handler.forced_429 = True
                    retry = True
                else:
                    retry = False
            if retry:
                self.send_response(429)
                self.send_header('Retry-After', '1')
                self.end_headers()
                self.wfile.write(b'Too Many Requests')
            elif pair in valid:
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'Valid')
            else:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(b'Invalid')

        def log_message(self, *args):
            pass

    class Server(ThreadingHTTPServer):
        allow_reuse_address = True

    kill_port_8080_holders()
    server = Server(('127.0.0.1', 8080), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    expected_lines = sorted(f'{pkg}=={ver}' for pkg, ver in valid)
    successes = []
    try:
        for candidate in candidates:
            Handler.requests = []
            Handler.forced_429 = False
            try:
                os.unlink(OUTPUT)
            except FileNotFoundError:
                pass
            try:
                result = subprocess.run(
                    [sys.executable, candidate],
                    cwd=HOME,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=45,
                )
            except subprocess.TimeoutExpired:
                continue
            if result.returncode != 0 or not os.path.isfile(OUTPUT):
                continue
            with open(OUTPUT) as f:
                lines = [line.strip() for line in f if line.strip()]
            counts = Counter(Handler.requests)
            retried = any(count >= 2 for count in counts.values())
            if (
                lines == expected_lines
                and combined.issubset(counts.keys())
                and obsolete not in counts
                and retried
            ):
                successes.append(candidate)
                break
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)

    assert successes, (
        'No submitted utility correctly extracted randomized .pyc dependencies, applied '
        'pyc precedence, validated every merged dependency through the API, retried the '
        'forced 429 response, and wrote the sorted valid result.'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
