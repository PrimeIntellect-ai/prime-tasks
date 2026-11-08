#!/bin/bash
set -e
mkdir -p /logs/verifier

# Stop any server left on port 8080 so the verifier can prove that the
# submitted legacy_processor.py itself starts the service.
python3 - <<'PY'
import os
import signal

socket_inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                if fields[1].upper().endswith(':1F90') and fields[3] == '0A':
                    socket_inodes.add(fields[9])
    except OSError:
        pass

for entry in os.listdir('/proc'):
    if not entry.isdigit() or int(entry) in (1, os.getpid()):
        continue
    fd_dir = f'/proc/{entry}/fd'
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f'{fd_dir}/{fd}')
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in socket_inodes:
                os.kill(int(entry), signal.SIGKILL)
                break
    except (OSError, ProcessLookupError):
        pass
PY
sleep 1
rm -f /tmp/legacy_ld_debug.*

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import glob
import json
import os
import subprocess
import time
import urllib.request

import pytest

SCRIPT_PATH = '/app/legacy_processor.py'


@pytest.fixture(scope='session', autouse=True)
def submitted_server():
    env = os.environ.copy()
    env['LD_DEBUG'] = 'libs'
    env['LD_DEBUG_OUTPUT'] = '/tmp/legacy_ld_debug'
    proc = subprocess.Popen(
        ['/usr/bin/python3', SCRIPT_PATH],
        cwd='/app',
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    deadline = time.time() + 10
    last_error = None
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f'{SCRIPT_PATH} exited before starting the server (status {proc.returncode})')
        try:
            with urllib.request.urlopen('http://localhost:8080/config', timeout=1) as response:
                if response.status == 200:
                    break
        except Exception as exc:
            last_error = exc
            time.sleep(0.2)
    else:
        proc.terminate()
        pytest.fail(f'{SCRIPT_PATH} did not start /config on port 8080: {last_error}')

    debug_text = ''
    for path in glob.glob('/tmp/legacy_ld_debug.*'):
        try:
            with open(path, errors='replace') as f:
                debug_text += f.read()
        except OSError:
            pass
    assert '/app/libdata.so' in debug_text, \
        f'Executing {SCRIPT_PATH} did not load /app/libdata.so'

    yield proc

    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()


def test_final_config_json_accuracy():
    config_path = '/app/final_config.json'
    assert os.path.isfile(config_path), f"File {config_path} does not exist."

    with open(config_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{config_path} is not valid JSON."

    assert isinstance(data, list), f"Expected JSON array in {config_path}, got {type(data)}."

    ground_truth = [
        {"module": "Auth", "version": "1.2.4"},
        {"module": "Data", "version": "2.0.1"},
        {"module": "Sink", "version": "0.9.4"}
    ]

    matches = 0
    for i in range(min(len(data), len(ground_truth))):
        if isinstance(data[i], dict):
            if data[i].get("module", "").lower() == ground_truth[i]["module"].lower() and \
               data[i].get("version", "") == ground_truth[i]["version"]:
                matches += 1

    accuracy = matches / len(ground_truth)
    assert accuracy >= 1.0, f"Accuracy of extracted data is {accuracy}, expected >= 1.0. Got: {data}"


def test_server_running_and_config():
    try:
        req = urllib.request.Request("http://localhost:8080/config")
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f"Expected status 200, got {response.status}"
            data = json.loads(response.read().decode('utf-8'))
    except Exception as e:
        assert False, f"Failed to fetch /config from server on port 8080: {e}"

    assert isinstance(data, list), f"Expected JSON array from server, got {type(data)}."

    ground_truth = [
        {"module": "Auth", "version": "1.2.4"},
        {"module": "Data", "version": "2.0.1"},
        {"module": "Sink", "version": "0.9.4"}
    ]

    matches = 0
    for i in range(min(len(data), len(ground_truth))):
        if isinstance(data[i], dict):
            if data[i].get("module", "").lower() == ground_truth[i]["module"].lower() and \
               data[i].get("version", "") == ground_truth[i]["version"]:
                matches += 1

    accuracy = matches / len(ground_truth)
    assert accuracy >= 1.0, f"Accuracy of server /config data is {accuracy}, expected >= 1.0. Got: {data}"


def _attr_name(node):
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        prefix = _attr_name(node.value)
        return f'{prefix}.{node.attr}' if prefix else node.attr
    return ''


def _is_bytes_expression(node, byte_names):
    if isinstance(node, ast.Constant) and isinstance(node.value, bytes):
        return True
    if isinstance(node, ast.Name) and node.id in byte_names:
        return True
    if isinstance(node, ast.Call):
        name = _attr_name(node.func)
        return name in ('bytes', 'builtins.bytes') or name.endswith('.encode')
    return False


def test_python3_syntax_and_migration_structure():
    assert os.path.isfile(SCRIPT_PATH), f"File {SCRIPT_PATH} does not exist."

    with open(SCRIPT_PATH, 'r') as f:
        source = f.read()

    try:
        tree = ast.parse(source)
    except SyntaxError as e:
        assert False, f"{SCRIPT_PATH} is not valid Python 3 syntax: {e}"

    imported = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported.update(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported.add(node.module)

    assert 'urllib2' not in imported and 'BaseHTTPServer' not in imported, \
        'Legacy Python 2 HTTP modules are still imported'
    assert any(name == 'http.server' or name.startswith('http.server.') for name in imported), \
        'The migrated script must use Python 3 http.server'

    handler_classes = []
    data_struct_classes = []
    for node in tree.body:
        if not isinstance(node, ast.ClassDef):
            continue
        bases = {_attr_name(base) for base in node.bases}
        if any(base.endswith('BaseHTTPRequestHandler') for base in bases):
            handler_classes.append(node)
        if any(base.endswith('Structure') for base in bases):
            data_struct_classes.append(node)

    assert any(any(isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef)) and item.name == 'do_GET'
                   for item in cls.body) for cls in handler_classes), \
        'No http.server request handler with do_GET was defined'

    valid_struct = False
    struct_names = set()
    for cls in data_struct_classes:
        struct_names.add(cls.name)
        for item in cls.body:
            if isinstance(item, (ast.Assign, ast.AnnAssign)):
                targets = item.targets if isinstance(item, ast.Assign) else [item.target]
                if not any(isinstance(t, ast.Name) and t.id == '_fields_' for t in targets):
                    continue
                value = item.value
                if not isinstance(value, (ast.List, ast.Tuple)) or len(value.elts) < 2:
                    continue
                parsed = []
                for field in value.elts[:2]:
                    if isinstance(field, (ast.List, ast.Tuple)) and len(field.elts) == 2:
                        name_node, type_node = field.elts
                        name = name_node.value if isinstance(name_node, ast.Constant) else None
                        parsed.append((name, _attr_name(type_node)))
                if parsed == [('name', 'ctypes.c_char_p'), ('value', 'ctypes.c_int')] or \
                   parsed == [('name', 'c_char_p'), ('value', 'c_int')]:
                    valid_struct = True
    assert valid_struct, 'ctypes Structure must define name as c_char_p and value as c_int'

    byte_names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and _is_bytes_expression(node.value, byte_names):
            for target in node.targets:
                if isinstance(target, ast.Name):
                    byte_names.add(target.id)
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name) and \
             node.value is not None and _is_bytes_expression(node.value, byte_names):
            byte_names.add(node.target.id)

    struct_calls = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and _attr_name(node.func).split('.')[-1] in struct_names:
            arg = node.args[0] if node.args else next(
                (kw.value for kw in node.keywords if kw.arg == 'name'), None)
            struct_calls.append(arg)
    assert struct_calls, 'The ctypes data structure is never constructed'
    assert all(arg is not None and _is_bytes_expression(arg, byte_names) for arg in struct_calls), \
        'C-string arguments to the ctypes structure must be bytes'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
