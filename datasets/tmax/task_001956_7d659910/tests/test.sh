#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import http.cookies
import os
import stat
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def derive_expected_payload():
    with open('/home/user/hash.txt', 'r', encoding='utf-8') as f:
        target_hash = f.read().strip().lower()

    matches = []
    with open('/home/user/words.txt', 'r', encoding='utf-8') as f:
        for line in f:
            candidate = line.rstrip('\r\n')
            digest = hashlib.sha256(candidate.encode('utf-8')).hexdigest()
            if digest == target_hash:
                matches.append(candidate)

    assert len(matches) == 1, 'Expected exactly one wordlist entry to match the supplied hash.'
    xor_bytes = bytes(b ^ 0x5A for b in matches[0].encode('utf-8'))
    return base64.b64encode(xor_bytes).decode('ascii')


def test_send_payload_script():
    script_path = '/home/user/send_payload.sh'

    # Preserve the original artifact and static assertions.
    assert os.path.isfile(script_path), f'Script {script_path} does not exist.'
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f'Script {script_path} is not executable.'

    with open(script_path, 'r', encoding='utf-8') as f:
        content = f.read()

    assert 'curl' in content, "The script does not contain the 'curl' command."
    assert 'http://localhost:8000/admin' in content, 'The script does not contain the correct target URL.'
    assert 'X-Evasion-Mode: Active' in content, "The script does not contain the expected 'X-Evasion-Mode: Active' header."

    expected_payload = derive_expected_payload()
    expected_cookie = f'Session-Token={expected_payload}'
    assert expected_cookie in content, f"The script does not contain the correct cookie payload. Expected to find '{expected_cookie}'."

    requests = []
    request_seen = threading.Event()

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            requests.append({
                'path': self.path,
                'header': self.headers.get('X-Evasion-Mode'),
                'cookies': self.headers.get_all('Cookie') or [],
            })
            request_seen.set()
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'OK')

        def log_message(self, format, *args):
            pass

    try:
        server = ThreadingHTTPServer(('127.0.0.1', 8000), Handler)
    except OSError as exc:
        raise AssertionError(f'Could not start the mock endpoint on port 8000: {exc}')

    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        subprocess.run(
            ['/bin/bash', script_path],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
            env=os.environ.copy(),
        )
        request_seen.wait(3)
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=3)

    assert requests, 'Executing the script did not send an HTTP GET request to the mock endpoint.'

    valid_request = False
    for request in requests:
        if request['path'] != '/admin' or request['header'] != 'Active':
            continue

        jar = http.cookies.SimpleCookie()
        try:
            jar.load('; '.join(request['cookies']))
        except http.cookies.CookieError:
            continue

        token = jar.get('Session-Token')
        if token is not None and token.value == expected_payload:
            valid_request = True
            break

    assert valid_request, (
        'The executed script did not issue GET /admin with exactly '
        "'X-Evasion-Mode: Active' and the correctly encoded Session-Token cookie."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
