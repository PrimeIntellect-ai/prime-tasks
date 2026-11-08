#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import http.client
import json
import os
import subprocess
import threading
import time
import urllib.error
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer


def read_report(path):
    assert os.path.isfile(path), f"{path} was not generated"
    with open(path, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            assert False, f"{path} does not contain valid JSON"


def test_pipeline_and_server_logic():
    pipeline_script = '/home/user/run_pipeline.sh'
    e2e_script = '/home/user/tests/e2e_test.js'
    test_report = '/home/user/test_report.json'
    server_script = '/home/user/api/server.py'

    assert os.path.isfile(pipeline_script), f"{pipeline_script} does not exist"
    assert os.access(pipeline_script, os.X_OK), f"{pipeline_script} is not executable"
    assert os.path.isfile(server_script), f"{server_script} does not exist"
    assert os.path.isfile(e2e_script), f"{e2e_script} does not exist"

    # Remove existing report if any
    if os.path.exists(test_report):
        os.remove(test_report)

    # Run the pipeline script
    result = subprocess.run([pipeline_script], cwd='/home/user', capture_output=True, text=True, timeout=45)
    assert result.returncode == 0, f"run_pipeline.sh failed with exit code {result.returncode}. Output: {result.stdout}\n{result.stderr}"

    # Verify test report
    report_data = read_report(test_report)
    assert report_data.get("validation_passed") is True, "Test report indicates validation failed"
    assert report_data.get("rate_limit_passed") is True, "Test report indicates rate limit failed"

    # Independently execute the required Node suite against a controlled endpoint.
    # This verifies that the suite itself issues all six specified requests in order
    # and computes a strict report, rather than the pipeline merely fabricating one.
    observed = []
    response_codes = [400, 400, 200, 200, 200, 429]

    class ControlledHandler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get('Content-Length', '0'))
            raw = self.rfile.read(length)
            try:
                payload = json.loads(raw.decode('utf-8'))
            except Exception:
                payload = None
            observed.append({
                'method': self.command,
                'path': self.path,
                'content_type': self.headers.get('Content-Type', ''),
                'payload': payload,
            })
            idx = len(observed) - 1
            code = response_codes[idx] if idx < len(response_codes) else 500
            body = json.dumps({'status': code}).encode('utf-8')
            self.send_response(code)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    controlled = HTTPServer(('127.0.0.1', 8080), ControlledHandler)
    controlled_thread = threading.Thread(target=controlled.serve_forever, daemon=True)
    controlled_thread.start()
    try:
        if os.path.exists(test_report):
            os.remove(test_report)
        node_result = subprocess.run(
            ['node', e2e_script], cwd='/home/user', capture_output=True, text=True, timeout=30
        )
        assert node_result.returncode == 0, (
            f"e2e_test.js failed with exit code {node_result.returncode}. "
            f"Output: {node_result.stdout}\n{node_result.stderr}"
        )
        isolated_report = read_report(test_report)
        assert isolated_report == {
            'validation_passed': True,
            'rate_limit_passed': True,
        }, f"e2e_test.js produced an incorrect report: {isolated_report!r}"
    finally:
        controlled.shutdown()
        controlled.server_close()
        controlled_thread.join(timeout=5)

    assert len(observed) == 6, f"Expected e2e_test.js to send exactly 6 requests, got {len(observed)}"
    assert all(item['method'] == 'POST' and item['path'] == '/process' for item in observed), observed
    assert all('application/json' in item['content_type'].lower() for item in observed), observed

    first = observed[0]['payload']
    second = observed[1]['payload']
    assert isinstance(first, dict) and 'batch_id' not in first and isinstance(first.get('records'), list), (
        f"First E2E request must omit batch_id and contain records array, got {first!r}"
    )
    assert isinstance(second, dict) and isinstance(second.get('batch_id'), str) and 'records' not in second, (
        f"Second E2E request must omit records and contain string batch_id, got {second!r}"
    )
    for index, item in enumerate(observed[2:], start=3):
        payload = item['payload']
        assert isinstance(payload, dict), f"E2E request {index} was not a JSON object"
        assert isinstance(payload.get('batch_id'), str), f"E2E request {index} has invalid batch_id"
        assert isinstance(payload.get('records'), list), f"E2E request {index} has invalid records"

    # Now verify the server logic independently.
    server_proc = subprocess.Popen(
        ['python3', server_script], cwd='/home/user/api',
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )

    server_up = False
    for _ in range(30):
        if server_proc.poll() is not None:
            break
        try:
            req = urllib.request.Request('http://127.0.0.1:8080/process', method='OPTIONS')
            urllib.request.urlopen(req, timeout=1)
            server_up = True
            break
        except urllib.error.HTTPError:
            server_up = True
            break
        except Exception:
            time.sleep(0.5)

    if not server_up:
        server_proc.terminate()
        assert False, 'Independent server failed to start on port 8080'

    try:
        def send_raw(raw, content_type='application/json', source_ip='127.0.0.1'):
            conn = http.client.HTTPConnection(
                '127.0.0.1', 8080, timeout=3, source_address=(source_ip, 0)
            )
            headers = {'Content-Type': content_type, 'Content-Length': str(len(raw))}
            try:
                conn.request('POST', '/process', body=raw, headers=headers)
                response = conn.getresponse()
                response.read()
                return response.status
            finally:
                conn.close()

        def send_post(payload, source_ip='127.0.0.1'):
            raw = json.dumps(payload).encode('utf-8')
            return send_raw(raw, 'application/json', source_ip)

        # Test missing batch_id
        code = send_post({'records': []})
        assert code == 400, f"Expected 400 for missing batch_id, got {code}"

        # Test missing records
        code = send_post({'batch_id': '123'})
        assert code == 400, f"Expected 400 for missing records, got {code}"

        # Additional validation: only JSON, parseable JSON, and exact field types.
        assert send_raw(b'not-json', 'text/plain') == 400, 'Expected 400 for non-JSON content type'
        assert send_raw(b'{broken', 'application/json') == 400, 'Expected 400 for malformed JSON'
        assert send_post({'batch_id': 42, 'records': []}) == 400, 'Expected 400 for non-string batch_id'
        assert send_post({'batch_id': 'x', 'records': {}}) == 400, 'Expected 400 for non-array records'
        assert send_post({'batch_id': None, 'records': []}) == 400, 'Expected 400 for null batch_id'
        assert send_post({'batch_id': 'x', 'records': None}) == 400, 'Expected 400 for null records'

        # Test rate limiting with verifier-generated payload data.
        valid_payload = {'batch_id': uuid.uuid4().hex, 'records': [uuid.uuid4().hex]}
        codes = []
        for _ in range(4):
            codes.append(send_post(valid_payload))

        assert codes[:3] == [200, 200, 200], f"Expected first 3 requests to be 200, got {codes[:3]}"
        assert codes[3] == 429, f"Expected 4th request to be 429, got {codes[3]}"

        # A different source IP must have an independent allowance.
        other_payload = {'batch_id': uuid.uuid4().hex, 'records': []}
        other_codes = [send_post(other_payload, '127.0.0.2') for _ in range(4)]
        assert other_codes == [200, 200, 200, 429], (
            f"Expected independent per-IP limit [200, 200, 200, 429], got {other_codes}"
        )

        third_ip_code = send_post(
            {'batch_id': uuid.uuid4().hex, 'records': [1, 2]}, '127.0.0.3'
        )
        assert third_ip_code == 200, f"Expected fresh IP to be allowed, got {third_ip_code}"

        # Requests must become eligible again after the 10-second window expires.
        time.sleep(10.5)
        expired_code = send_post(
            {'batch_id': uuid.uuid4().hex, 'records': []}, '127.0.0.2'
        )
        assert expired_code == 200, f"Expected rate limit to expire after 10 seconds, got {expired_code}"

    finally:
        server_proc.terminate()
        try:
            server_proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            server_proc.kill()
            server_proc.wait(timeout=5)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
