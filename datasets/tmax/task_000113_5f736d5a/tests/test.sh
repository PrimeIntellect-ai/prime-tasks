#!/bin/bash
set +e
mkdir -p /logs/verifier

WORKSPACE=/home/user/workspace
BACKUP_DIR=$(mktemp -d)
PROBE_LOG=$(mktemp /tmp/pipeline_probe.XXXXXX.jsonl)
CPP_TOKEN="CPP_$(cat /proc/sys/kernel/random/uuid)"
RUST_TOKEN="RUST_$(cat /proc/sys/kernel/random/uuid)"

cp "$WORKSPACE/src/main.cpp" "$BACKUP_DIR/main.cpp"
cp "$WORKSPACE/src/main.rs" "$BACKUP_DIR/main.rs"
cp "$WORKSPACE/server.py" "$BACKUP_DIR/server.py"

restore_inputs() {
    cp "$BACKUP_DIR/main.cpp" "$WORKSPACE/src/main.cpp"
    cp "$BACKUP_DIR/main.rs" "$WORKSPACE/src/main.rs"
    cp "$BACKUP_DIR/server.py" "$WORKSPACE/server.py"
    chown user:user "$WORKSPACE/src/main.cpp" "$WORKSPACE/src/main.rs" "$WORKSPACE/server.py" 2>/dev/null || true
}
trap restore_inputs EXIT

export WORKSPACE PROBE_LOG CPP_TOKEN RUST_TOKEN
python3 <<'PY'
import os
from pathlib import Path

workspace = Path(os.environ['WORKSPACE'])
probe_log = os.environ['PROBE_LOG']
cpp_token = os.environ['CPP_TOKEN']
rust_token = os.environ['RUST_TOKEN']

(workspace / 'src/main.cpp').write_text(
    '#include <iostream>\nint main() { std::cout << "' + cpp_token + '" << std::endl; return 0; }\n'
)
(workspace / 'src/main.rs').write_text(
    'fn main() { println!("' + rust_token + '"); }\n'
)

probe_server = r'''from http.server import BaseHTTPRequestHandler, HTTPServer
import hashlib
import json
import os
import time

request_times = []
LOG_PATH = __LOG_PATH__
ARTIFACT_PATH = '/home/user/workspace/artifacts/cpp_artifact'

class ArtifactHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_POST(self):
        global request_times
        length = int(self.headers.get('Content-Length', '0'))
        body = self.rfile.read(length)
        now = time.time()
        request_times = [t for t in request_times if now - t < 1.0]

        if self.path != '/upload':
            status = 404
        elif len(request_times) >= 2:
            status = 429
        else:
            request_times.append(now)
            status = 200 if self.headers.get('X-Artifact-Type') in ('cpp', 'rust') else 400

        try:
            artifact = open(ARTIFACT_PATH, 'rb').read()
            has_artifact = bool(artifact) and (body == artifact or artifact in body)
        except OSError:
            has_artifact = False

        entry = {
            'time': now,
            'path': self.path,
            'header': self.headers.get('X-Artifact-Type'),
            'status': status,
            'body_sha256': hashlib.sha256(body).hexdigest(),
            'has_cpp_artifact': has_artifact,
        }
        with open(LOG_PATH, 'a') as f:
            f.write(json.dumps(entry) + '\n')

        self.send_response(status)
        self.end_headers()
        self.wfile.write({200: b'OK', 400: b'Bad Request', 429: b'Too Many Requests'}.get(status, b'Not Found'))

if __name__ == '__main__':
    HTTPServer(('127.0.0.1', 8080), ArtifactHandler).serve_forever()
'''.replace('__LOG_PATH__', repr(probe_log))
(workspace / 'server.py').write_text(probe_server)
PY

chown user:user "$WORKSPACE/src/main.cpp" "$WORKSPACE/src/main.rs" "$WORKSPACE/server.py" "$PROBE_LOG" 2>/dev/null || true
pkill -u user -f 'server.py' 2>/dev/null || true
rm -rf "$WORKSPACE/artifacts"
rm -f "$WORKSPACE/test_results.json"

runuser -u user -- bash -c "cd '$WORKSPACE' && timeout 45s python3 test_pipeline.py" >/tmp/pipeline_stdout.txt 2>/tmp/pipeline_stderr.txt
PIPELINE_RC=$?
sleep 0.3
pkill -u user -f 'server.py' 2>/dev/null || true
restore_inputs
trap - EXIT

export PIPELINE_RC
cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import socket
import subprocess
import time
import urllib.error
import urllib.request

import pytest

WORKSPACE_DIR = '/home/user/workspace'
ARTIFACTS_DIR = os.path.join(WORKSPACE_DIR, 'artifacts')
CPP_ARTIFACT = os.path.join(ARTIFACTS_DIR, 'cpp_artifact')
RUST_ARTIFACT = os.path.join(ARTIFACTS_DIR, 'rust_artifact')
TEST_RESULTS_JSON = os.path.join(WORKSPACE_DIR, 'test_results.json')
TEST_PIPELINE_PY = os.path.join(WORKSPACE_DIR, 'test_pipeline.py')
PROBE_LOG = os.environ['PROBE_LOG']
CPP_TOKEN = os.environ['CPP_TOKEN']
RUST_TOKEN = os.environ['RUST_TOKEN']

EXPECTED_CPP = '''#include <iostream>
int main() { std::cout << "C++ Artifact" << std::endl; return 0; }
'''
EXPECTED_RUST = '''fn main() { println!("Rust Artifact"); }
'''
EXPECTED_SERVER = '''from http.server import BaseHTTPRequestHandler, HTTPServer
import time

request_times = []

class ArtifactHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        global request_times
        if self.path == '/upload':
            now = time.time()
            # Clean old requests
            request_times = [t for t in request_times if now - t < 1.0]

            if len(request_times) >= 2:
                self.send_response(429)
                self.end_headers()
                self.wfile.write(b"Too Many Requests")
                return

            request_times.append(now)

            artifact_type = self.headers.get('X-Artifact-Type')
            if artifact_type not in ['cpp', 'rust']:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(b"Bad Request: Invalid or missing X-Artifact-Type")
                return

            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"OK")
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8080), ArtifactHandler)
    server.serve_forever()
'''


def status_for(data, header=None):
    headers = {} if header is None else {'X-Artifact-Type': header}
    req = urllib.request.Request('http://127.0.0.1:8080/upload', data=data, headers=headers, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=3) as response:
            return response.status
    except urllib.error.HTTPError as exc:
        return exc.code


def test_pipeline_was_executed_successfully():
    assert int(os.environ['PIPELINE_RC']) == 0, (
        'test_pipeline.py did not exit successfully. stdout/stderr are in '
        '/tmp/pipeline_stdout.txt and /tmp/pipeline_stderr.txt'
    )


def test_supplied_inputs_were_not_modified():
    assert open(os.path.join(WORKSPACE_DIR, 'src/main.cpp')).read() == EXPECTED_CPP
    assert open(os.path.join(WORKSPACE_DIR, 'src/main.rs')).read() == EXPECTED_RUST
    assert open(os.path.join(WORKSPACE_DIR, 'server.py')).read() == EXPECTED_SERVER


def test_test_pipeline_script_exists():
    assert os.path.isfile(TEST_PIPELINE_PY), f"Expected python script {TEST_PIPELINE_PY} is missing."


def test_artifacts_directory_exists():
    assert os.path.isdir(ARTIFACTS_DIR), f"Expected artifacts directory {ARTIFACTS_DIR} is missing."


def test_cpp_artifact_exists_and_executable():
    assert os.path.isfile(CPP_ARTIFACT), f"C++ artifact {CPP_ARTIFACT} is missing."
    assert os.access(CPP_ARTIFACT, os.X_OK), f"C++ artifact {CPP_ARTIFACT} is not executable."
    assert open(CPP_ARTIFACT, 'rb').read(4) == b'\x7fELF'
    output = subprocess.check_output([CPP_ARTIFACT], timeout=5, text=True).strip()
    assert output == CPP_TOKEN, 'C++ artifact was not built from the source supplied for this run.'


def test_rust_artifact_exists_and_executable():
    assert os.path.isfile(RUST_ARTIFACT), f"Rust artifact {RUST_ARTIFACT} is missing."
    assert os.access(RUST_ARTIFACT, os.X_OK), f"Rust artifact {RUST_ARTIFACT} is not executable."
    assert open(RUST_ARTIFACT, 'rb').read(4) == b'\x7fELF'
    output = subprocess.check_output([RUST_ARTIFACT], timeout=5, text=True).strip()
    assert output == RUST_TOKEN, 'Rust artifact was not built from the source supplied for this run.'


def test_pipeline_actually_made_required_requests():
    assert os.path.isfile(PROBE_LOG), 'The pipeline did not contact the server it was required to start.'
    with open(PROBE_LOG) as f:
        entries = [json.loads(line) for line in f if line.strip()]
    entries = [e for e in entries if e.get('path') == '/upload']

    found = False
    for i, missing in enumerate(entries):
        if missing.get('header') is not None or missing.get('status') != 400 or not missing.get('has_cpp_artifact'):
            continue
        for j in range(i + 1, len(entries) - 2):
            burst = entries[j:j + 3]
            if ([e.get('status') for e in burst] == [200, 200, 429]
                    and all(e.get('header') in ('cpp', 'rust') for e in burst)
                    and all(e.get('has_cpp_artifact') for e in burst)
                    and burst[2]['time'] - burst[0]['time'] < 1.0):
                found = True
                break
        if found:
            break
    assert found, 'No real 400 followed by a rapid valid 200/200/429 request sequence was observed.'


def test_server_independently_returns_required_statuses():
    proc = subprocess.Popen(
        ['python3', os.path.join(WORKSPACE_DIR, 'server.py')],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        deadline = time.time() + 5
        while time.time() < deadline:
            try:
                with socket.create_connection(('127.0.0.1', 8080), timeout=0.2):
                    break
            except OSError:
                time.sleep(0.05)
        else:
            pytest.fail('The supplied server did not start on port 8080.')

        body = open(CPP_ARTIFACT, 'rb').read()
        assert status_for(body) == 400
        time.sleep(1.05)
        assert [status_for(body, 'cpp') for _ in range(3)] == [200, 200, 429]
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()


def test_test_results_json():
    assert os.path.isfile(TEST_RESULTS_JSON), f"Test results JSON {TEST_RESULTS_JSON} is missing."

    with open(TEST_RESULTS_JSON, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{TEST_RESULTS_JSON} is not valid JSON.")

    expected_keys = {
        'build_cpp_success',
        'build_rust_success',
        'test_validation_missing_header_success',
        'test_rate_limit_success'
    }

    assert set(data) == expected_keys, f"{TEST_RESULTS_JSON} does not have exactly the required schema."
    for key in expected_keys:
        assert key in data, f"Key '{key}' is missing from {TEST_RESULTS_JSON}."
        assert data[key] is True, f"Key '{key}' in {TEST_RESULTS_JSON} is not True."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

rm -rf "$BACKUP_DIR"
rm -f "$PROBE_LOG"
