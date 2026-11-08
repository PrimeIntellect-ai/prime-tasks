#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.metadata
import json
import os
import secrets
import socket
import subprocess
import sys
import time
import urllib.parse
import zlib

import pytest
from packaging.requirements import Requirement

PROJECT_DIR = '/home/user/qa_env'
APP_PATH = os.path.join(PROJECT_DIR, 'app.py')
RESULT_PATH = os.path.join(PROJECT_DIR, 'test_result.json')


def load_toml(path):
    if sys.version_info >= (3, 11):
        import tomllib
    else:
        try:
            import tomli as tomllib
        except ImportError:
            from pip._vendor import tomli as tomllib
    with open(path, 'rb') as f:
        return tomllib.load(f)


def expected_response(payload):
    data = {
        'id': int(payload['user_id']),
        'name': payload['user_name'],
        'balance_dollars': payload['balance_cents'] / 100,
    }
    encoded = json.dumps(data, separators=(',', ':'), sort_keys=True).encode('utf-8')
    return {'data': data, 'checksum': zlib.crc32(encoded)}


def test_pyproject_toml_fixed():
    """Test that pyproject.toml is fixed and contains Flask dependency."""
    file_path = os.path.join(PROJECT_DIR, 'pyproject.toml')
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    with open(file_path, 'r') as f:
        content = f.read()

    # Preserve the original textual assertion.
    assert 'Flask' in content or 'flask' in content, "pyproject.toml is missing the Flask dependency."

    try:
        parsed = load_toml(file_path)
    except Exception as e:
        assert False, f"pyproject.toml still has a syntax error: {e}"

    dependencies = parsed.get('project', {}).get('dependencies', [])
    dependency_names = {Requirement(item).name.lower() for item in dependencies}
    assert 'flask' in dependency_names, "Flask is not declared as a project dependency."

    try:
        dist = importlib.metadata.distribution('data-processor')
    except importlib.metadata.PackageNotFoundError:
        assert False, "The data-processor project is not installed in the current environment."

    installed_requirements = dist.requires or []
    installed_names = {Requirement(item).name.lower() for item in installed_requirements}
    assert 'flask' in installed_names, "The installed data-processor metadata does not include Flask."

    direct_url_text = dist.read_text('direct_url.json')
    if direct_url_text:
        direct_url = json.loads(direct_url_text).get('url', '')
        source_path = urllib.parse.unquote(urllib.parse.urlparse(direct_url).path)
        assert os.path.realpath(source_path) == os.path.realpath(PROJECT_DIR), \
            "The installed data-processor distribution did not come from /home/user/qa_env."


def test_result_json_correct():
    """Test that test_result.json contains the correct expected output."""
    assert os.path.isfile(RESULT_PATH), f"File {RESULT_PATH} does not exist. Did you run the curl command and save the output?"

    with open(RESULT_PATH, 'r') as f:
        try:
            result = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {RESULT_PATH} does not contain valid JSON."

    assert 'checksum' in result, "Result JSON is missing 'checksum' field."
    assert 'data' in result, "Result JSON is missing 'data' field."

    assert result['checksum'] == 3776263595, f"Expected checksum 3776263595, got {result['checksum']}."

    data = result['data']
    assert data.get('id') == 892, f"Expected data.id to be 892, got {data.get('id')}."
    assert data.get('name') == "Charlie", f"Expected data.name to be 'Charlie', got {data.get('name')}."
    assert data.get('balance_dollars') == 42.5, f"Expected data.balance_dollars to be 42.5, got {data.get('balance_dollars')}."


@pytest.fixture(scope='module')
def running_service():
    assert os.path.isfile(APP_PATH), f"File {APP_PATH} does not exist."

    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]

    runner = """
import importlib.util
import sys
spec = importlib.util.spec_from_file_location('submitted_app', sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert hasattr(module, 'app'), 'app.py does not define app'
module.app.run(host='127.0.0.1', port=int(sys.argv[2]), debug=False, use_reloader=False)
"""
    process = subprocess.Popen(
        [sys.executable, '-c', runner, APP_PATH, str(port)],
        cwd=PROJECT_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )

    deadline = time.time() + 10
    while time.time() < deadline:
        if process.poll() is not None:
            output = process.stdout.read() if process.stdout else ''
            pytest.fail(f"Flask service exited before accepting requests:\n{output}")
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=0.2):
                break
        except OSError:
            time.sleep(0.1)
    else:
        process.terminate()
        pytest.fail("Flask service did not start within 10 seconds.")

    def post(payload):
        raw = subprocess.check_output([
            'curl', '--silent', '--show-error', '--fail',
            '-H', 'Content-Type: application/json',
            '--data', json.dumps(payload, separators=(',', ':')),
            f'http://127.0.0.1:{port}/migrate',
        ], text=True, timeout=5)
        try:
            return json.loads(raw)
        except json.JSONDecodeError as e:
            pytest.fail(f"/migrate returned invalid JSON: {e}; body={raw!r}")

    try:
        yield post
    finally:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)


def test_live_migrate_endpoint(running_service):
    fixed_payload = {'user_id': '892', 'user_name': 'Charlie', 'balance_cents': 4250}
    fixed_response = running_service(fixed_payload)
    assert fixed_response == expected_response(fixed_payload)

    with open(RESULT_PATH, 'r') as f:
        saved_result = json.load(f)
    assert saved_result == fixed_response, "test_result.json does not match the live endpoint response."

    # Exercise unpredictable inputs so a hardcoded response cannot pass.
    cases = []
    for _ in range(3):
        user_id = secrets.randbelow(9_000_000) + 1_000_000
        balance_cents = secrets.randbelow(2_000_001) - 1_000_000
        if balance_cents % 100 == 0:
            balance_cents += 37
        cases.append({
            'user_id': str(user_id),
            'user_name': 'user-' + secrets.token_hex(8),
            'balance_cents': balance_cents,
        })

    for payload in cases:
        response = running_service(payload)
        assert set(response) == {'data', 'checksum'}
        assert set(response['data']) == {'id', 'name', 'balance_dollars'}
        assert response == expected_response(payload)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
