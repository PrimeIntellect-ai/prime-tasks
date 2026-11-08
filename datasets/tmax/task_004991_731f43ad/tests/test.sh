#!/bin/bash
mkdir -p /logs/verifier

# Replace the task's API with a verifier-controlled API whose allowlist can be
# changed for derived test inputs.
pkill -f '[f]lask_api.py' >/dev/null 2>&1 || true
cat > /tmp/verifier_config_api.py <<'PYAPI'
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

ALLOW_FILE = '/tmp/verifier_allowed_crc.json'

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != '/config':
            self.send_response(404)
            self.end_headers()
            return
        try:
            with open(ALLOW_FILE, 'r') as f:
                allowed = json.load(f)
        except Exception:
            allowed = []
        body = json.dumps({'allowed_crc32': allowed}, separators=(',', ':')).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass

HTTPServer(('127.0.0.1', 5000), Handler).serve_forever()
PYAPI
printf '[]' > /tmp/verifier_allowed_crc.json
python3 /tmp/verifier_config_api.py >/tmp/verifier_config_api.log 2>&1 &
API_PID=$!

redis-server --daemonize yes >/dev/null 2>&1 || true

cat > /tmp/test_final_state.py <<'PYTEST'
import base64
import json
import os
import secrets
import shutil
import socket
import subprocess
import tempfile
import time
import urllib.request
import zlib

WORKSPACE = '/home/user/workspace'
CLEAN_DIR = os.path.join(WORKSPACE, 'corpus', 'clean')
EVIL_DIR = os.path.join(WORKSPACE, 'corpus', 'evil')
OUT_DIR = os.path.join(WORKSPACE, 'out_clean')
BINARY = os.path.join(WORKSPACE, 'bin', 'telemetry_sanitizer')
ALLOW_FILE = '/tmp/verifier_allowed_crc.json'


def redis_command(*parts):
    payload = ('*%d\r\n' % len(parts)).encode()
    for part in parts:
        b = str(part).encode()
        payload += ('$%d\r\n' % len(b)).encode() + b + b'\r\n'
    with socket.create_connection(('127.0.0.1', 6379), timeout=3) as s:
        s.sendall(payload)
        data = s.recv(4096)
    return data


def redis_count():
    data = redis_command('GET', 'processed_files')
    lines = data.split(b'\r\n')
    if not lines or lines[0] == b'$-1':
        return 0
    assert lines[0].startswith(b'$') and len(lines) >= 2, data
    return int(lines[1])


def wait_for_services():
    deadline = time.time() + 8
    last = None
    while time.time() < deadline:
        try:
            with urllib.request.urlopen('http://127.0.0.1:5000/config', timeout=1) as r:
                assert json.load(r) == {'allowed_crc32': []}
            redis_command('PING')
            return
        except Exception as exc:
            last = exc
            time.sleep(0.2)
    raise AssertionError('Verifier API or Redis did not start: %r' % (last,))


def canonical_encoded(kind, i):
    return base64.b64encode(f'{kind}_data_{i}\n'.encode()) + b'\n'


def verify_original_corpus():
    assert os.path.isdir(CLEAN_DIR), 'Clean corpus directory is missing'
    assert os.path.isdir(EVIL_DIR), 'Evil corpus directory is missing'
    expected_names = {f'file_{i}.txt' for i in range(1, 51)}

    for directory, kind in ((CLEAN_DIR, 'clean'), (EVIL_DIR, 'evil')):
        actual_names = {
            name for name in os.listdir(directory)
            if os.path.isfile(os.path.join(directory, name))
        }
        assert actual_names == expected_names, (
            f'{directory} was modified: expected exactly 50 canonical files'
        )
        for i in range(1, 51):
            path = os.path.join(directory, f'file_{i}.txt')
            with open(path, 'rb') as f:
                assert f.read() == canonical_encoded(kind, i), f'{path} was modified'


def verify_agent_final_output():
    assert os.path.isdir(OUT_DIR), f'Output directory {OUT_DIR} does not exist'
    expected_names = {f'file_{i}.txt' for i in range(1, 51)}
    actual_names = {
        name for name in os.listdir(OUT_DIR)
        if os.path.isfile(os.path.join(OUT_DIR, name))
    }
    assert actual_names == expected_names, 'out_clean must contain exactly the clean corpus filenames'
    for i in range(1, 51):
        path = os.path.join(OUT_DIR, f'file_{i}.txt')
        with open(path, 'rb') as f:
            actual = f.read()
        expected = f'clean_data_{i}\n'.encode()
        assert actual == expected, f'{path} is missing, modified, or contains evil data'


def run_one(input_path, output_dir, valgrind=False):
    cmd = [BINARY, input_path, output_dir]
    if valgrind:
        cmd = [
            'valgrind', '--quiet', '--leak-check=full',
            '--errors-for-leak-kinds=definite', '--error-exitcode=99'
        ] + cmd
    try:
        return subprocess.run(
            cmd, cwd=WORKSPACE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=12, check=False
        )
    except subprocess.TimeoutExpired as exc:
        raise AssertionError(f'Sanitizer timed out on {input_path}') from exc


def main():
    wait_for_services()
    verify_original_corpus()
    verify_agent_final_output()

    build = subprocess.run(
        ['make', 'clean', 'all'], cwd=WORKSPACE,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60, check=False
    )
    assert build.returncode == 0, 'make clean all failed:\n' + build.stdout.decode(errors='replace')
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), 'Executable was not built'
    with open(BINARY, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'bin/telemetry_sanitizer is not an ELF executable'

    root = tempfile.mkdtemp(prefix='sanitizer_verify_')
    try:
        inputs = os.path.join(root, 'inputs')
        outputs = os.path.join(root, 'outputs')
        os.mkdir(inputs)
        os.mkdir(outputs)

        clean_payloads = [f'clean_data_{i}\n'.encode() for i in range(1, 51)]
        evil_payloads = [f'evil_data_{i}\n'.encode() for i in range(1, 51)]
        nonce_payload = ('verifier_' + secrets.token_hex(24) + '\n').encode()
        invalid_utf8 = b'\xff\xfe\x80\xc0\xaf'

        allowed = [zlib.crc32(p) & 0xffffffff for p in clean_payloads]
        allowed += [zlib.crc32(nonce_payload) & 0xffffffff,
                    zlib.crc32(invalid_utf8) & 0xffffffff]
        with open(ALLOW_FILE, 'w') as f:
            json.dump(allowed, f)

        # Reset the counter so it can only be satisfied by the executions below.
        redis_command('DEL', 'processed_files')

        accepted = {}
        rejected = []
        cases = []
        for i, payload in enumerate(clean_payloads, 1):
            cases.append((f'clean_{i}.txt', base64.b64encode(payload) + b'\n', payload, True))
        for i, payload in enumerate(evil_payloads, 1):
            cases.append((f'evil_{i}.txt', base64.b64encode(payload) + b'\n', payload, False))
        cases.append(('derived_valid.txt', base64.b64encode(nonce_payload) + b'\n', nonce_payload, True))
        # A permissive decoder would decode this to an allowed payload; strict Base64 must reject it.
        cases.append(('malformed_base64.txt', base64.b64encode(nonce_payload) + b'!!!!\n', b'', False))
        cases.append(('invalid_utf8.txt', base64.b64encode(invalid_utf8) + b'\n', b'', False))

        for name, encoded, decoded, should_accept in cases:
            in_path = os.path.join(inputs, name)
            with open(in_path, 'wb') as f:
                f.write(encoded)
            run_one(in_path, outputs)
            if should_accept:
                accepted[name] = decoded
            else:
                rejected.append(name)

        for name, expected in accepted.items():
            out_path = os.path.join(outputs, name)
            assert os.path.isfile(out_path), f'Valid input {name} was not emitted'
            with open(out_path, 'rb') as f:
                assert f.read() == expected, f'Valid input {name} was decoded incorrectly'
        for name in rejected:
            assert not os.path.exists(os.path.join(outputs, name)), f'Invalid input {name} was accepted'

        expected_processed = len(cases)
        assert redis_count() == expected_processed, (
            f"Redis processed_files is {redis_count()}, expected {expected_processed}"
        )

        # Exercise the repaired decoder under Valgrind as required by the task.
        vg_out = os.path.join(root, 'valgrind_output')
        os.mkdir(vg_out)
        vg_input = os.path.join(inputs, 'derived_valid.txt')
        vg = run_one(vg_input, vg_out, valgrind=True)
        assert vg.returncode != 99, 'Valgrind detected a definite memory error or leak:\n' + vg.stderr.decode(errors='replace')
        assert os.path.isfile(os.path.join(vg_out, 'derived_valid.txt'))
        assert redis_count() == expected_processed + 1, 'Valgrind execution did not increment processed_files'
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == '__main__':
    main()
PYTEST

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

kill "$API_PID" >/dev/null 2>&1 || true
