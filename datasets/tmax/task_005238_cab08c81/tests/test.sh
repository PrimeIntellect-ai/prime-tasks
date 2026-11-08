#!/bin/bash
mkdir -p /logs/verifier

# Stop the image's service so the verifier can observe requests itself.
pkill -f '^python3 /tmp/server.py$' >/dev/null 2>&1 || true
sleep 0.5

VERIFY_DIR=$(mktemp -d /tmp/retrieve-verifier.XXXXXX)
chmod 700 "$VERIFY_DIR"
RESULTS="$VERIFY_DIR/results.json"

cat > "$VERIFY_DIR/run_behavioral.py" <<'PY_EOF'
import json
import os
import secrets
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

SCRIPT = Path('/home/user/retrieve.py')
EVIDENCE = Path('/home/user/evidence.txt')
RESULTS = Path(os.environ['RESULTS_PATH'])
EXPECTED_FLAG = 'FLAG{byp4ss3d_l0c4l_4uth_9921}'
EXPECTED_METHOD = 'GET'
EXPECTED_PATH = '/admin/flag'
EXPECTED_HEADERS = {
    'User-Agent': 'IR-Ops-Tool/1.0',
    'X-Incident-Auth': 'Alpha-99-Bravo',
}
EXPECTED_COOKIE = 'session=valid_admin_77812'

class ReusableHTTPServer(HTTPServer):
    allow_reuse_address = True

def run_once(response_text):
    state = {'matching_requests': 0}

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            matches = (
                self.command == EXPECTED_METHOD
                and self.path == EXPECTED_PATH
                and all(self.headers.get(k) == v for k, v in EXPECTED_HEADERS.items())
                and self.headers.get('Cookie') == EXPECTED_COOKIE
            )
            if matches:
                state['matching_requests'] += 1
                body = response_text.encode('utf-8')
                self.send_response(200)
                self.send_header('Content-Type', 'text/plain')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            else:
                body = b'Forbidden'
                self.send_response(403)
                self.send_header('Content-Type', 'text/plain')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        def log_message(self, *args):
            pass

    server = ReusableHTTPServer(('127.0.0.1', 13337), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    try:
        try:
            EVIDENCE.unlink()
        except FileNotFoundError:
            pass

        try:
            completed = subprocess.run(
                ['runuser', '-u', 'user', '--', 'python3', str(SCRIPT)],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=20,
            )
            returncode = completed.returncode
            error = completed.stderr
        except subprocess.TimeoutExpired:
            returncode = 124
            error = 'retrieve.py timed out'

        try:
            evidence = EVIDENCE.read_text()
        except Exception as exc:
            evidence = None
            error = error + f'\nCould not read evidence: {exc}'

        return {
            'returncode': returncode,
            'stderr': error,
            'matching_requests': state['matching_requests'],
            'evidence': evidence,
            'expected_response': response_text,
        }
    finally:
        server.shutdown()
        thread.join(timeout=5)
        server.server_close()

results = {}
try:
    # A randomized response proves the script writes the actual HTTP response
    # rather than a flag copied from the image.
    random_response = 'VERIFIER_RESPONSE_' + secrets.token_hex(24)
    results['randomized'] = run_once(random_response)

    # Run again with the real service response, leaving evidence.txt in the
    # final state required by the original task and its assertions.
    results['original'] = run_once(EXPECTED_FLAG)
except Exception as exc:
    results['orchestration_error'] = repr(exc)

RESULTS.write_text(json.dumps(results))
PY_EOF
chmod 700 "$VERIFY_DIR/run_behavioral.py"

RESULTS_PATH="$RESULTS" python3 "$VERIFY_DIR/run_behavioral.py" >/dev/null 2>&1 || true

cat > "$VERIFY_DIR/test_final_state.py" <<PYTEST_EOF
import json
import os

RESULTS_PATH = ${RESULTS@Q}


def load_results():
    assert os.path.isfile(RESULTS_PATH), 'Behavioral verification did not complete.'
    with open(RESULTS_PATH, 'r') as f:
        results = json.load(f)
    assert 'orchestration_error' not in results, results.get('orchestration_error')
    return results


def test_retrieve_script_exists():
    script_path = "/home/user/retrieve.py"
    assert os.path.exists(script_path), f"The script {script_path} does not exist. You must create it."
    assert os.path.isfile(script_path), f"{script_path} is not a file."


def test_script_executes_and_reproduces_request():
    results = load_results()
    for phase in ('randomized', 'original'):
        result = results[phase]
        assert result['returncode'] == 0, f"retrieve.py failed during {phase} run: {result['stderr']}"
        assert result['matching_requests'] >= 1, (
            f"retrieve.py did not make the successful GET request with the exact path, "
            f"headers, user-agent, and cookie during the {phase} run."
        )


def test_script_writes_raw_server_response():
    result = load_results()['randomized']
    assert result['evidence'] == result['expected_response'], (
        'retrieve.py did not write the raw response returned by the server.'
    )


def test_evidence_file_contains_flag():
    evidence_path = "/home/user/evidence.txt"
    assert os.path.exists(evidence_path), f"The evidence file {evidence_path} does not exist. Ensure your script writes to it."
    assert os.path.isfile(evidence_path), f"{evidence_path} is not a file."

    with open(evidence_path, 'r') as f:
        content = f.read().strip()

    expected_flag = "FLAG{byp4ss3d_l0c4l_4uth_9921}"
    assert content == expected_flag, f"The evidence file does not contain the correct flag. Found: '{content}'"
PYTEST_EOF

if python3 -m pytest "$VERIFY_DIR/test_final_state.py" -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

rm -rf "$VERIFY_DIR"
