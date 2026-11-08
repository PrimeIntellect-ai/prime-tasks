#!/bin/bash
set -e
mkdir -p /logs/verifier

# Stop the setup server if the agent started it; verification uses a trusted server.
pkill -f '/home/user/[s]erver.py' 2>/dev/null || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import shutil
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

UPLOAD_DIR = '/home/user/server_uploads'
UPLOAD_FILE = os.path.join(UPLOAD_DIR, 'authorized_keys')
RECORDS = []


def get_expected_key() -> str:
    """Decrypt the key using openssl to get the expected content."""
    enc_file = '/home/user/new_key.pub.enc'
    if not os.path.exists(enc_file):
        pytest.fail(f"Encrypted key file {enc_file} is missing.")

    result = subprocess.run(
        ['openssl', 'enc', '-d', '-aes-256-cbc', '-pbkdf2', '-in', enc_file,
         '-pass', 'pass:SecureRotate2024!'],
        capture_output=True,
        text=True
    )
    if result.returncode != 0:
        pytest.fail("Failed to decrypt the key using openssl internally for test verification.")
    return result.stdout


def prepare_secure_upload_dir():
    if os.path.lexists(UPLOAD_DIR):
        if os.path.islink(UPLOAD_DIR) or not os.path.isdir(UPLOAD_DIR):
            os.unlink(UPLOAD_DIR)
        else:
            shutil.rmtree(UPLOAD_DIR)
    os.mkdir(UPLOAD_DIR, 0o755)
    os.chown(UPLOAD_DIR, 0, 0)


class TrustedSecureHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        cookie_values = self.headers.get_all('Cookie') or []
        length_value = self.headers.get('Content-Length')
        try:
            content_length = int(length_value)
        except (TypeError, ValueError):
            content_length = -1

        body = self.rfile.read(content_length) if content_length >= 0 else b''
        record = {
            'path': self.path,
            'cookies': cookie_values,
            'content_length': content_length,
            'body': body,
        }
        RECORDS.append(record)

        expected = get_expected_key().encode()
        valid = (
            self.path == '/upload?file=authorized_keys'
            and cookie_values == ['auth=admin_rotate']
            and content_length == len(expected)
            and body == expected
        )
        if not valid:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b'Invalid request')
            return

        with open(UPLOAD_FILE, 'wb') as f:
            f.write(body)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'Key rotated securely')

    def log_message(self, format, *args):
        pass


@pytest.fixture(scope='session', autouse=True)
def trusted_rotation_service():
    prepare_secure_upload_dir()
    try:
        server = HTTPServer(('127.0.0.1', 9090), TrustedSecureHandler)
    except OSError as exc:
        pytest.fail(f'Could not start trusted rotation service on port 9090: {exc}')
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    yield
    server.shutdown()
    server.server_close()
    thread.join(timeout=2)


def run_as_user(command):
    account = pwd.getpwnam('user')

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    return subprocess.run(
        command,
        cwd='/home/user',
        capture_output=True,
        text=True,
        timeout=10,
        preexec_fn=demote,
    )


def assert_client_performs_authenticated_upload(binary):
    before = len(RECORDS)
    result = run_as_user([binary])
    assert result.returncode == 0, (
        f'{binary} exited with status {result.returncode}. '
        f'stdout={result.stdout!r}, stderr={result.stderr!r}'
    )

    deadline = time.time() + 2
    while len(RECORDS) == before and time.time() < deadline:
        time.sleep(0.02)

    assert len(RECORDS) == before + 1, (
        f'{binary} did not send exactly one HTTP POST request to the trusted service.'
    )
    request = RECORDS[-1]
    expected = get_expected_key().encode()
    assert request['path'] == '/upload?file=authorized_keys', 'Client used an incorrect or unsafe upload URI.'
    assert request['cookies'] == ['auth=admin_rotate'], 'Client did not send the required authentication Cookie header.'
    assert request['content_length'] == len(expected), 'Client sent an incorrect Content-Length header.'
    assert request['body'] == expected, 'Client did not send the decrypted key as the request body.'


def test_decrypted_key_exists_and_correct():
    """Verify that the decrypted key file exists and has correct content."""
    dec_file = '/home/user/new_key.pub'
    assert os.path.isfile(dec_file), f"Decrypted key file {dec_file} is missing. Did you decrypt it?"

    expected_content = get_expected_key()
    with open(dec_file, 'r') as f:
        actual_content = f.read()

    assert actual_content == expected_content, "The content of the decrypted key file does not match the expected decrypted content."


def test_cpp_client_fixed():
    """Verify that the C++ client has been modified correctly."""
    cpp_file = '/home/user/upload_client.cpp'
    assert os.path.isfile(cpp_file), f"C++ source file {cpp_file} is missing."

    with open(cpp_file, 'r') as f:
        content = f.read()

    assert "../../../home/user/.ssh/authorized_keys" not in content, "The path traversal vulnerability is still present in the C++ code."
    assert "file=authorized_keys" in content, "The file parameter in the HTTP URI should be strictly 'authorized_keys'."
    assert "Cookie: auth=admin_rotate" in content, "The required 'Cookie: auth=admin_rotate' header is missing from the HTTP request."


def test_client_compiled():
    """Verify that the client was compiled."""
    bin_file = '/home/user/upload_client'
    assert os.path.isfile(bin_file), f"Compiled client binary {bin_file} is missing. Did you compile the code?"
    assert os.access(bin_file, os.X_OK), f"The file {bin_file} is not executable."


def test_clients_execute_authenticated_rotation():
    """Execute both the submitted artifact and a fresh build of the submitted source."""
    assert_client_performs_authenticated_upload('/home/user/upload_client')

    verified_binary = '/tmp/upload_client_verified'
    compile_result = subprocess.run(
        ['g++', '-o', verified_binary, '/home/user/upload_client.cpp'],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        'The submitted C++ source does not compile successfully: '
        + compile_result.stderr
    )
    os.chmod(verified_binary, 0o755)
    assert_client_performs_authenticated_upload(verified_binary)


def test_server_upload_successful():
    """Verify that the key was successfully uploaded to the server."""
    assert os.path.isfile(UPLOAD_FILE), f"The uploaded file {UPLOAD_FILE} is missing. The client may not have successfully uploaded the key."

    expected_content = get_expected_key()
    with open(UPLOAD_FILE, 'r') as f:
        actual_content = f.read()

    assert actual_content == expected_content, "The content of the uploaded key on the server does not match the expected decrypted key."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
