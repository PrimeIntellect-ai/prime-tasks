#!/bin/bash
set -e
mkdir -p /logs/verifier

# Stop any process already listening on 8080 so the submitted server.py itself
# is what the verifier executes.
python3 - <<'PY'
import glob
import os
import signal
import time

inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        with open(table, 'r', encoding='ascii') as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) > 9 and fields[1].rsplit(':', 1)[-1].upper() == '1F90' and fields[3] == '0A':
                    inodes.add(fields[9])
    except OSError:
        pass

pids = set()
for fd in glob.glob('/proc/[0-9]*/fd/*'):
    try:
        target = os.readlink(fd)
    except OSError:
        continue
    if target.startswith('socket:[') and target[8:-1] in inodes:
        pids.add(int(fd.split('/')[2]))

for pid in pids:
    try:
        os.kill(pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        pass
if pids:
    time.sleep(0.3)
PY

python3 /home/user/polybuild/server.py >/tmp/polybuild_server.log 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT

# Give the submitted artifact a brief opportunity to bind the required port.
for _ in $(seq 1 30); do
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        break
    fi
    if python3 - <<'PY'
import socket
s = socket.socket()
s.settimeout(0.1)
try:
    s.connect(('127.0.0.1', 8080))
except OSError:
    raise SystemExit(1)
finally:
    s.close()
PY
    then
        break
    fi
    sleep 0.1
done

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import base64
import json
import os
import secrets
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import zlib

import pytest

APP_FILE = "/home/user/polybuild/src/app.py"
SERVER_FILE = "/home/user/polybuild/server.py"


def import_names_from_ast(source):
    tree = ast.parse(source)
    names = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            names.extend(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom):
            names.append(node.module)
    return names


def validation_url(path, crc=None):
    target_bytes = path.encode('iso-8859-1')
    if crc is None:
        crc = zlib.crc32(target_bytes)
    query = urllib.parse.urlencode({
        'target': base64.b64encode(target_bytes).decode('ascii'),
        'crc': str(crc),
    })
    return f"http://127.0.0.1:8080/validate?{query}"


def assert_pass_response(path):
    try:
        with urllib.request.urlopen(validation_url(path), timeout=3) as response:
            assert response.status == 200, f"Expected 200 OK, got {response.status}"
            data = json.loads(response.read().decode('utf-8'))
    except urllib.error.URLError as e:
        pytest.fail(f"Server is not running or unreachable on 127.0.0.1:8080. Error: {e}")

    assert data.get('status') == 'pass', f"Expected status 'pass', got {data.get('status')}"
    assert 'peak_memory_bytes' in data, "Missing 'peak_memory_bytes' in response"
    assert isinstance(data['peak_memory_bytes'], int), "'peak_memory_bytes' must be an integer"
    assert data['peak_memory_bytes'] > 0, "Peak memory must reflect active AST parsing"
    assert set(data) == {'status', 'peak_memory_bytes'}, f"Unexpected JSON payload: {data}"


def assert_rejected_unsorted(path):
    try:
        urllib.request.urlopen(validation_url(path), timeout=3)
        pytest.fail("Expected HTTP 406 Not Acceptable for unsorted imports, but request succeeded.")
    except urllib.error.HTTPError as e:
        assert e.code == 406, f"Expected HTTP 406, got {e.code}"
    except urllib.error.URLError as e:
        pytest.fail(f"Server is not running or unreachable on 127.0.0.1:8080. Error: {e}")


def test_app_py_imports_sorted():
    """Check that the imports in app.py are sorted alphabetically."""
    assert os.path.exists(APP_FILE), f"Target file {APP_FILE} is missing."
    with open(APP_FILE, 'r', encoding='utf-8') as f:
        tree = ast.parse(f.read())

    imports = []
    for node in tree.body:
        if isinstance(node, ast.Import):
            for alias in node.names:
                imports.append(alias.name)
        elif isinstance(node, ast.ImportFrom):
            imports.append(node.module)

    assert imports == sorted(imports), f"Imports in {APP_FILE} are not strictly alphabetical. Found: {imports}"


def test_server_file_exists():
    """Check that the server.py file exists."""
    assert os.path.exists(SERVER_FILE), f"Server file {SERVER_FILE} is missing."
    assert os.path.isfile(SERVER_FILE), f"Server path {SERVER_FILE} is not a regular file."


def test_server_valid_request():
    """Test the server with a valid request for the fixed app.py."""
    assert_pass_response(APP_FILE)


def test_server_invalid_crc():
    """Test the server with an invalid CRC."""
    target_bytes = APP_FILE.encode('iso-8859-1')
    crc = zlib.crc32(target_bytes) + 1

    try:
        urllib.request.urlopen(validation_url(APP_FILE, crc), timeout=3)
        pytest.fail("Expected HTTP 400 Bad Request for invalid CRC, but request succeeded.")
    except urllib.error.HTTPError as e:
        assert e.code == 400, f"Expected HTTP 400, got {e.code}"
    except urllib.error.URLError as e:
        pytest.fail(f"Server is not running or unreachable on 127.0.0.1:8080. Error: {e}")


def test_server_unsorted_imports():
    """Keep the original unsorted-file behavioral assertion."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as f:
        f.write("import sys\nimport os\n")
        temp_path = f.name

    try:
        assert_rejected_unsorted(temp_path)
    finally:
        os.remove(temp_path)


def test_server_handles_unpredictable_files_and_content_changes():
    """Exercise AST validation on paths and module names unknown before verification."""
    modules = sorted('m_' + secrets.token_hex(6) for _ in range(5))

    with tempfile.TemporaryDirectory(prefix='validate_' + secrets.token_hex(5) + '_') as directory:
        path = os.path.join(directory, secrets.token_hex(7) + '.py')

        # Sorted imports using both Import and ImportFrom, with lexical decoys.
        sorted_source = (
            '"""import zzz_decoy\nfrom aaa_decoy import value"""\n'
            f'import {modules[0]}\n'
            f'from {modules[1]} import value\n'
            f'import {modules[2]}, {modules[3]}\n'
            f'from {modules[4]} import other\n'
            '# import another_decoy\n'
        )
        assert import_names_from_ast(sorted_source) == sorted(import_names_from_ast(sorted_source))
        with open(path, 'w', encoding='utf-8') as f:
            f.write(sorted_source)
        assert_pass_response(path)

        # Rewrite the same unpredictable path with an AST-visible reverse order.
        unsorted_source = '\n'.join(f'import {name}' for name in reversed(modules)) + '\n'
        assert import_names_from_ast(unsorted_source) != sorted(import_names_from_ast(unsorted_source))
        with open(path, 'w', encoding='utf-8') as f:
            f.write(unsorted_source)
        assert_rejected_unsorted(path)

        # Rewrite it again to ensure results are not cached by path.
        nested_sorted = (
            'def generated_function():\n'
            f'    import {modules[0]}\n'
            f'    from {modules[1]} import item\n'
            f'    import {modules[2]}\n'
            f'    from {modules[3]} import item\n'
            f'    import {modules[4]}\n'
        )
        assert import_names_from_ast(nested_sorted) == sorted(import_names_from_ast(nested_sorted))
        with open(path, 'w', encoding='utf-8') as f:
            f.write(nested_sorted)
        assert_pass_response(path)


def test_server_random_invalid_crc_and_latin1_target():
    """Check CRC handling and Latin-1 path decoding on a fresh non-ASCII path."""
    names = sorted('n_' + secrets.token_hex(5) for _ in range(3))
    with tempfile.TemporaryDirectory(prefix='latin1_' + secrets.token_hex(4) + '_') as directory:
        path = os.path.join(directory, 'caf\u00e9_' + secrets.token_hex(5) + '.py')
        with open(path, 'w', encoding='utf-8') as f:
            f.write('\n'.join(f'import {name}' for name in names) + '\n')

        assert_pass_response(path)

        target_bytes = path.encode('iso-8859-1')
        bad_crc = zlib.crc32(target_bytes) ^ secrets.randbits(31) ^ 1
        if bad_crc == zlib.crc32(target_bytes):
            bad_crc += 1
        try:
            urllib.request.urlopen(validation_url(path, bad_crc), timeout=3)
            pytest.fail("Expected HTTP 400 Bad Request for randomized invalid CRC.")
        except urllib.error.HTTPError as e:
            assert e.code == 400, f"Expected HTTP 400, got {e.code}"
        except urllib.error.URLError as e:
            pytest.fail(f"Server is unreachable. Error: {e}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
