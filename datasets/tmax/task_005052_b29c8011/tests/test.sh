#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import io
import os
import secrets
import stat

import pytest
import requests
from flask import Flask

TOKEN_FILE = "/home/user/token.txt"
SERVER_FILE = "/home/user/server.py"
EXPECTED_TOKEN = "SECURE99"
BASE_URL = "http://127.0.0.1:8000/upload"
UPLOAD_DIR = "/home/user/uploads"


def mode(path):
    return stat.S_IMODE(os.stat(path).st_mode)


def remove_if_present(path):
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass


def post_live(headers=None, files=None, data=None):
    try:
        return requests.post(BASE_URL, headers=headers, files=files, data=data, timeout=3)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the server: {exc}")


def test_token_file_exists_and_correct():
    assert os.path.exists(TOKEN_FILE), f"Token file {TOKEN_FILE} does not exist."
    with open(TOKEN_FILE, "r") as f:
        content = f.read().strip()
    assert content == EXPECTED_TOKEN, f"Expected token {EXPECTED_TOKEN}, but got {content} in {TOKEN_FILE}."


def test_server_file_exists_and_is_python():
    assert os.path.isfile(SERVER_FILE), f"Patched server file {SERVER_FILE} does not exist."
    with open(SERVER_FILE, "rb") as f:
        source = f.read()
    assert source, "Patched server.py is empty."
    compile(source, SERVER_FILE, "exec")


def test_missing_auth():
    response = post_live(files={'file': ('test.wav', b'dummy data')})
    assert response.status_code == 401, f"Expected HTTP 401 for missing auth, got {response.status_code}. Response: {response.text}"


def test_invalid_auth():
    headers = {'X-Auth-Token': 'FAKE123'}
    response = post_live(headers=headers, files={'file': ('test.wav', b'dummy data')})
    assert response.status_code == 401, f"Expected HTTP 401 for invalid auth, got {response.status_code}. Response: {response.text}"


def test_valid_request_and_permissions():
    saved_file_path = os.path.join(UPLOAD_DIR, 'legit.wav')
    remove_if_present(saved_file_path)
    payload = b'dummy data'
    response = post_live(
        headers={'X-Auth-Token': EXPECTED_TOKEN},
        files={'file': ('legit.wav', payload)},
        data={'filename': 'legit.wav'},
    )
    assert response.status_code in (200, 201), f"Expected HTTP 200/201 for valid request, got {response.status_code}. Response: {response.text}"
    assert os.path.exists(saved_file_path), f"File was not saved at {saved_file_path}."
    with open(saved_file_path, 'rb') as f:
        assert f.read() == payload, "Uploaded file contents were not preserved."
    assert mode(saved_file_path) == 0o600, f"Expected file permissions 0600, got {oct(mode(saved_file_path))}."


def test_path_traversal_mitigation():
    sanitized_target = os.path.join(UPLOAD_DIR, 'hacked.wav')
    traversal_targets = ['/home/user/hacked.wav', '/home/hacked.wav']
    remove_if_present(sanitized_target)
    for path in traversal_targets:
        remove_if_present(path)

    payload = b'dummy data'
    response = post_live(
        headers={'X-Auth-Token': EXPECTED_TOKEN},
        files={'file': ('hacked.wav', payload)},
        data={'filename': '../../hacked.wav'},
    )
    assert response.status_code in (200, 201, 400), f"Expected HTTP 200, 201, or 400 for traversal attempt, got {response.status_code}. Response: {response.text}"
    for path in traversal_targets:
        assert not os.path.exists(path), f"Path traversal vulnerability exists! File was saved to {path}."
    if response.status_code in (200, 201):
        assert os.path.exists(sanitized_target), f"Expected sanitized file to be saved at {sanitized_target}, but it was not found."
        with open(sanitized_target, 'rb') as f:
            assert f.read() == payload, "Sanitized upload has incorrect contents."
        assert mode(sanitized_target) == 0o600


def test_unpredictable_live_upload_and_absolute_path_sanitization():
    nonce = secrets.token_hex(16)
    filename = f"probe_{nonce}.wav"
    payload = secrets.token_bytes(257)
    sanitized_target = os.path.join(UPLOAD_DIR, filename)
    outside_target = os.path.join('/tmp', filename)
    remove_if_present(sanitized_target)
    remove_if_present(outside_target)

    # Authentication must be checked for arbitrary requests, not only fixed cases.
    bad_name = f"unauthorized_{secrets.token_hex(16)}.wav"
    bad_target = os.path.join(UPLOAD_DIR, bad_name)
    remove_if_present(bad_target)
    bad_response = post_live(
        headers={'X-Auth-Token': EXPECTED_TOKEN + '_WRONG'},
        files={'file': (bad_name, secrets.token_bytes(41))},
        data={'filename': bad_name},
    )
    assert bad_response.status_code == 401
    assert not os.path.exists(bad_target), "An unauthorized request created a file."

    response = post_live(
        headers={'X-Auth-Token': EXPECTED_TOKEN},
        files={'file': ('client-name.wav', payload)},
        data={'filename': outside_target},
    )
    assert response.status_code in (200, 201), f"Valid randomized upload failed: {response.status_code} {response.text}"
    assert not os.path.exists(outside_target), "Absolute-path traversal escaped the upload directory."
    assert os.path.isfile(sanitized_target), "Randomized upload was not saved under its base filename."
    with open(sanitized_target, 'rb') as f:
        assert f.read() == payload, "Randomized uploaded bytes do not match the request body."
    assert mode(sanitized_target) == 0o600, "Randomized upload does not have mode 0600."


def test_patched_server_artifact_itself():
    # Import and exercise /home/user/server.py directly so a separate stub process
    # cannot hide an unpatched artifact.
    spec = importlib.util.spec_from_file_location(f"submitted_server_{secrets.token_hex(8)}", SERVER_FILE)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert hasattr(module, 'app') and isinstance(module.app, Flask), "server.py does not expose the Flask application."

    client = module.app.test_client()
    filename = f"artifact_{secrets.token_hex(16)}.wav"
    payload = secrets.token_bytes(193)
    saved_target = os.path.join(UPLOAD_DIR, filename)
    outside_target = os.path.join('/tmp', filename)
    remove_if_present(saved_target)
    remove_if_present(outside_target)

    missing = client.post('/upload', data={'filename': filename, 'file': (io.BytesIO(b'x'), filename)}, content_type='multipart/form-data')
    assert missing.status_code == 401
    invalid = client.post('/upload', headers={'X-Auth-Token': secrets.token_hex(16)}, data={'filename': filename, 'file': (io.BytesIO(b'y'), filename)}, content_type='multipart/form-data')
    assert invalid.status_code == 401
    assert not os.path.exists(saved_target), "Directly imported app saved an unauthorized upload."

    valid = client.post(
        '/upload',
        headers={'X-Auth-Token': EXPECTED_TOKEN},
        data={'filename': outside_target, 'file': (io.BytesIO(payload), 'client.wav')},
        content_type='multipart/form-data',
    )
    assert valid.status_code in (200, 201)
    assert not os.path.exists(outside_target), "Directly imported app permits absolute-path traversal."
    assert os.path.isfile(saved_target), "Directly imported app did not save the sanitized filename."
    with open(saved_target, 'rb') as f:
        assert f.read() == payload
    assert mode(saved_target) == 0o600
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
