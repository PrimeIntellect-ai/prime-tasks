#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import socket
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest


def test_c_source_exists():
    path = "/home/user/telemetry_client.c"
    assert os.path.isfile(path), f"Missing C source file at {path}"


def test_compiled_client_exists():
    path = "/home/user/client"
    assert os.path.isfile(path), f"Missing compiled client executable at {path}"
    assert os.access(path, os.X_OK), f"Compiled client at {path} is not executable"


def test_benchmark_script_exists():
    path = "/home/user/benchmark.sh"
    assert os.path.isfile(path), f"Missing benchmark script at {path}"
    assert os.access(path, os.X_OK), f"Benchmark script at {path} is not executable"


def test_benchmark_result():
    path = "/home/user/benchmark_result.txt"
    assert os.path.isfile(path), f"Missing benchmark result file at {path}"

    with open(path, "r") as f:
        content = f.read().strip()

    expected = "Total Time: 1500"
    assert content == expected, f"Expected '{expected}' in {path}, but got '{content}'"


def find_build_inputs():
    build = Path('/home/user/cjson_build')
    assert build.is_dir(), 'Missing /home/user/cjson_build'

    artifacts = []
    for pattern in ('cJSON.o', 'libcjson.a', 'libcjson.so', 'libcjson.so.*'):
        artifacts.extend(p for p in build.rglob(pattern) if p.is_file())
    artifacts = list(dict.fromkeys(artifacts))
    assert artifacts, 'No built cJSON object or library found in /home/user/cjson_build'

    headers = list(Path('/home/user').rglob('cJSON.h'))
    assert headers, 'Unable to find extracted cJSON.h'
    return artifacts, headers


def rebuild_source():
    artifacts, headers = find_build_inputs()
    include_dirs = set()
    for header in headers:
        parent = header.parent
        include_dirs.add(str(parent))
        include_dirs.add(str(parent.parent))

    errors = []
    output = '/tmp/telemetry_client_rebuilt'
    for artifact in artifacts:
        cmd = ['gcc', '-std=c11', '/home/user/telemetry_client.c', str(artifact)]
        for directory in sorted(include_dirs):
            cmd.extend(['-I', directory])
        cmd.extend(['-lcurl', '-lm', '-o', output])
        proc = subprocess.run(cmd, text=True, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE)
        if proc.returncode == 0:
            symbols = subprocess.run(['nm', output], text=True,
                                     stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT,
                                     check=True).stdout
            assert re.search(r'\bcurl_easy_', symbols), 'Rebuilt source does not reference libcurl APIs'
            assert re.search(r'\bcJSON_', symbols), 'Rebuilt source does not reference cJSON APIs'
            return output, str(artifact.parent)
        errors.append(f'{artifact}: {proc.stderr}')
    pytest.fail('Could not compile telemetry_client.c with the built cJSON artifact:\n' + '\n'.join(errors))


class ReusableHTTPServer(ThreadingHTTPServer):
    allow_reuse_address = True


class TelemetryHandler(BaseHTTPRequestHandler):
    records = []
    lock = threading.Lock()

    def do_POST(self):
        try:
            length = int(self.headers.get('Content-Length', '-1'))
            body = self.rfile.read(length)
            data = json.loads(body.decode('utf-8'))
        except Exception:
            data = None

        expected_payload = {
            'device_id': 808,
            'measurements': [10, 20, 30, 40, 50, 60],
        }
        valid = (
            self.path == '/telemetry'
            and self.headers.get_content_type() == 'application/json'
            and data == expected_payload
        )
        with self.lock:
            response_value = 11 + 7 * (len(self.records) + 1)
            self.records.append({'valid': valid, 'value': response_value})

        if not valid:
            self.send_response(400)
            self.end_headers()
            return

        payload = json.dumps({
            'status': 'success',
            'processing_time_ms': response_value,
        }).encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, format, *args):
        pass


def run_client(path, env):
    before = len(TelemetryHandler.records)
    proc = subprocess.run([path], text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=15, env=env)
    assert proc.returncode == 0, f'{path} failed: {proc.stderr}'
    assert len(TelemetryHandler.records) == before + 1, f'{path} did not make exactly one request'
    record = TelemetryHandler.records[-1]
    assert record['valid'], f'{path} sent the wrong endpoint, content type, or JSON payload'
    assert proc.stdout == f"{record['value']}\n", (
        f'{path} must print only processing_time_ms; got {proc.stdout!r}'
    )


def test_z_execute_client_and_benchmark():
    assert Path('/home/user/client').read_bytes()[:4] == b'\x7fELF', '/home/user/client is not a compiled ELF executable'
    rebuilt, library_dir = rebuild_source()

    subprocess.run(['pkill', '-f', '/home/user/mock_server.py'],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    TelemetryHandler.records = []
    server = ReusableHTTPServer(('127.0.0.1', 9090), TelemetryHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    env = os.environ.copy()
    env['LD_LIBRARY_PATH'] = library_dir + ':' + env.get('LD_LIBRARY_PATH', '')
    client = Path('/home/user/client')
    benchmark = Path('/home/user/benchmark.sh')
    result = Path('/home/user/benchmark_result.txt')
    backup = Path('/tmp/client_under_test')
    counter = Path('/tmp/client_invocation_count')
    original_result = result.read_bytes()
    moved = False

    try:
        run_client(rebuilt, env)
        run_client(str(client), env)

        if backup.exists():
            backup.unlink()
        shutil.move(str(client), str(backup))
        moved = True
        counter.write_text('0\n')
        client.write_text(
            '#!/bin/bash\n'
            'n=$(cat /tmp/client_invocation_count)\n'
            'echo $((n + 1)) > /tmp/client_invocation_count\n'
            'exec /tmp/client_under_test "$@"\n'
        )
        client.chmod(0o755)

        start = len(TelemetryHandler.records)
        proc = subprocess.run([str(benchmark)], text=True, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, timeout=120, env=env)
        assert proc.returncode == 0, f'benchmark.sh failed: {proc.stderr}'
        assert int(counter.read_text().strip()) == 50, 'benchmark.sh did not execute /home/user/client exactly 50 times'

        benchmark_records = TelemetryHandler.records[start:]
        assert len(benchmark_records) == 50, f'Expected exactly 50 benchmark requests, got {len(benchmark_records)}'
        assert all(r['valid'] for r in benchmark_records), 'A benchmark request used the wrong endpoint, content type, or payload'
        expected_total = sum(r['value'] for r in benchmark_records)
        assert result.read_text().strip() == f'Total Time: {expected_total}', (
            'benchmark_result.txt is not the sum of the 50 client responses'
        )
    finally:
        if moved:
            try:
                client.unlink()
            except FileNotFoundError:
                pass
            shutil.move(str(backup), str(client))
        result.write_bytes(original_result)
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
