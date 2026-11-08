#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import json
import os
import random
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import pytest

PROJECT = Path('/home/user/deploy_bridge')
LOG_FILE = PROJECT / 'test_result.log'
PROCS = []
LOG_HANDLES = []


def stop_processes():
    for proc in reversed(PROCS):
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=3)
    PROCS.clear()
    for handle in LOG_HANDLES:
        try:
            handle.close()
        except Exception:
            pass
    LOG_HANDLES.clear()
    subprocess.run(['pkill', '-f', '/home/user/deploy_bridge/grpc_server.py'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(['pkill', '-f', '/home/user/deploy_bridge/gateway.js'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if shutil.which('fuser'):
        subprocess.run(['fuser', '-k', '3000/tcp'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(['fuser', '-k', '50051/tcp'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.3)


def start_process(command, name, env=None):
    handle = open('/tmp/' + name + '.log', 'w')
    LOG_HANDLES.append(handle)
    proc = subprocess.Popen(command, cwd=PROJECT, env=env, stdout=handle, stderr=subprocess.STDOUT)
    PROCS.append(proc)
    return proc


def wait_port(port, proc=None, timeout=12):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc is not None and proc.poll() is not None:
            pytest.fail(f'Process exited before port {port} opened; see /tmp verifier logs')
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=0.3):
                return
        except OSError:
            time.sleep(0.15)
    pytest.fail(f'Timed out waiting for port {port}')


def compile_proto(out_dir):
    result = subprocess.run(
        [sys.executable, '-m', 'grpc_tools.protoc', f'-I{PROJECT}', f'--python_out={out_dir}', str(PROJECT / 'deployment.proto')],
        text=True, capture_output=True, timeout=30
    )
    assert result.returncode == 0, f'deployment.proto did not compile: {result.stdout}{result.stderr}'


def load_proto_module(out_dir):
    import importlib.util
    path = Path(out_dir) / 'deployment_pb2.py'
    spec = importlib.util.spec_from_file_location('verifier_deployment_pb2', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def validate_proto(pb):
    from google.protobuf.descriptor import FieldDescriptor
    services = [s for s in pb.DESCRIPTOR.services_by_name.values() if s.name == 'ReadinessService']
    assert len(services) == 1, 'deployment.proto must define ReadinessService'
    service = services[0]
    methods = [m for m in service.methods if m.name == 'Check']
    assert len(methods) == 1, 'ReadinessService must define Check'
    method = methods[0]
    request_fields = method.input_type.fields_by_name
    response_fields = method.output_type.fields_by_name
    assert 'service_name' in request_fields and request_fields['service_name'].type == FieldDescriptor.TYPE_STRING
    assert 'version' in request_fields and request_fields['version'].type == FieldDescriptor.TYPE_INT32
    assert 'score' in response_fields and response_fields['score'].type == FieldDescriptor.TYPE_INT32
    return service, method


def grpc_check(pb, service, method, service_name, version, timeout=12):
    import grpc
    from google.protobuf import message_factory
    request_cls = message_factory.GetMessageClass(method.input_type)
    response_cls = message_factory.GetMessageClass(method.output_type)
    request = request_cls()
    request.service_name = service_name
    request.version = version
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        channel = grpc.insecure_channel('localhost:50051')
        call = channel.unary_unary(
            f'/{service.full_name}/{method.name}',
            request_serializer=lambda value: value.SerializeToString(),
            response_deserializer=response_cls.FromString,
        )
        try:
            response = call(request, timeout=1)
            channel.close()
            return response.score
        except Exception as exc:
            last_error = exc
            channel.close()
            time.sleep(0.15)
    pytest.fail(f'gRPC Check request failed: {last_error}')


def assert_server_uses_ctypes():
    source = (PROJECT / 'grpc_server.py').read_text()
    tree = ast.parse(source)
    imports_ctypes = any(
        (isinstance(node, ast.Import) and any(alias.name == 'ctypes' for alias in node.names)) or
        (isinstance(node, ast.ImportFrom) and node.module == 'ctypes')
        for node in ast.walk(tree)
    )
    loads_library = any(
        isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr in ('CDLL', 'LoadLibrary')
        for node in ast.walk(tree)
    )
    assert imports_ctypes and loads_library, 'grpc_server.py must load libreadiness.so using ctypes'


def verify_run_test_captures_websocket(challenge):
    stop_processes()
    raw_message = json.dumps({
        'event': 'deployment_checked',
        'service': 'billing-service',
        'version': 4,
        'score': challenge,
    }, separators=(',', ':'))
    fake_server = r'''const http = require('http');
const WebSocket = require('ws');
const fs = require('fs');
const raw = process.env.RAW_MESSAGE;
let connected = false;
const server = http.createServer((req, res) => {
  fs.writeFileSync('/tmp/run_test_request_path', req.url);
  res.writeHead(200, {'Content-Type':'application/json'});
  res.end(JSON.stringify({score: -999999}));
  if (connected) {
    for (const client of wss.clients) {
      if (client.readyState === WebSocket.OPEN) client.send(raw);
    }
    setTimeout(() => {
      for (const client of wss.clients) client.close();
      server.close();
    }, 250);
  }
});
const wss = new WebSocket.Server({server, path:'/ws'});
wss.on('connection', () => { connected = true; });
server.listen(3000, '127.0.0.1');
setTimeout(() => process.exit(2), 12000);
'''
    fake_path = Path('/tmp/verifier_fake_gateway.js')
    fake_path.write_text(fake_server)
    env = os.environ.copy()
    env['NODE_PATH'] = str(PROJECT / 'node_modules')
    env['RAW_MESSAGE'] = raw_message
    proc = start_process(['node', str(fake_path)], 'fake_gateway', env)
    wait_port(3000, proc)
    LOG_FILE.unlink(missing_ok=True)
    result = subprocess.run(['node', 'run_test.js'], cwd=PROJECT, env=env, text=True, capture_output=True, timeout=15)
    assert result.returncode == 0, f'run_test.js did not exit cleanly: {result.stdout}{result.stderr}'
    assert LOG_FILE.is_file(), 'run_test.js did not create test_result.log'
    assert LOG_FILE.read_text() == raw_message, 'run_test.js must write the exact WebSocket message it receives'
    assert Path('/tmp/run_test_request_path').read_text() == '/check/billing-service/4', 'run_test.js requested the wrong HTTP endpoint'
    stop_processes()


def exercise_gateway(service_name, version, expected_score):
    script = r'''const http = require('http');
const WebSocket = require('ws');
const service = process.env.TEST_SERVICE;
const version = Number(process.env.TEST_VERSION);
const expected = Number(process.env.TEST_SCORE);
const expectedEvent = {event:'deployment_checked', service, version, score:expected};
let gotHttp = false;
let gotWs = false;
const timer = setTimeout(() => { console.error('timeout'); process.exit(2); }, 10000);
function done() { if (gotHttp && gotWs) { clearTimeout(timer); ws.close(); process.exit(0); } }
const ws = new WebSocket('ws://localhost:3000/ws');
ws.on('error', e => { console.error(e); process.exit(3); });
ws.on('message', data => {
  let value;
  try { value = JSON.parse(data.toString()); } catch (e) { console.error(e); process.exit(4); }
  if (JSON.stringify(value) !== JSON.stringify(expectedEvent)) {
    console.error('bad websocket payload', value); process.exit(5);
  }
  gotWs = true; done();
});
ws.on('open', () => {
  http.get('http://localhost:3000/check/' + encodeURIComponent(service) + '/' + version, res => {
    let body = '';
    res.on('data', chunk => body += chunk);
    res.on('end', () => {
      if (res.statusCode !== 200) { console.error('status', res.statusCode); process.exit(6); }
      let value;
      try { value = JSON.parse(body); } catch (e) { console.error(e); process.exit(7); }
      if (JSON.stringify(value) !== JSON.stringify({score:expected})) {
        console.error('bad http payload', value); process.exit(8);
      }
      gotHttp = true; done();
    });
  }).on('error', e => { console.error(e); process.exit(9); });
});
'''
    path = Path('/tmp/verifier_gateway_client.js')
    path.write_text(script)
    env = os.environ.copy()
    env['NODE_PATH'] = str(PROJECT / 'node_modules')
    env['TEST_SERVICE'] = service_name
    env['TEST_VERSION'] = str(version)
    env['TEST_SCORE'] = str(expected_score)
    result = subprocess.run(['node', str(path)], cwd=PROJECT, env=env, text=True, capture_output=True, timeout=15)
    assert result.returncode == 0, f'Gateway HTTP/WebSocket behavior failed: {result.stdout}{result.stderr}'


def test_complete_architecture_and_integration_script():
    required = ['readiness.c', 'libreadiness.so', 'deployment.proto', 'grpc_server.py', 'gateway.js', 'run_test.js']
    for name in required:
        path = PROJECT / name
        assert path.exists(), f'Missing required artifact: {path}'
        assert path.is_file(), f'Expected a regular file: {path}'

    readelf = subprocess.run(['readelf', '-Ws', str(PROJECT / 'libreadiness.so')], text=True, capture_output=True)
    assert readelf.returncode == 0, 'libreadiness.so is not a readable ELF shared library'
    exported_functions = []
    for line in readelf.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 8 and parts[3] == 'FUNC' and parts[4] == 'GLOBAL' and parts[6] != 'UND':
            exported_functions.append(parts[7].split('@')[0])
    assert sorted(set(exported_functions)) == ['calculate_score'], f'Expected only calculate_score to be exported, got {exported_functions}'

    library = ctypes.CDLL(str(PROJECT / 'libreadiness.so'))
    calculate = library.calculate_score
    calculate.argtypes = [ctypes.c_char_p, ctypes.c_int]
    calculate.restype = ctypes.c_int
    for name, version in [('auth', 3), ('release-canary', 7), ('x' * 23, 11)]:
        assert calculate(name.encode(), version) == len(name) * version

    assert_server_uses_ctypes()
    proto_dir = tempfile.mkdtemp(prefix='deploy_proto_')
    compile_proto(proto_dir)
    pb = load_proto_module(proto_dir)
    grpc_service, grpc_method = validate_proto(pb)

    challenge = random.SystemRandom().randint(7000, 50000)
    verify_run_test_captures_websocket(challenge)

    original_lib = PROJECT / 'libreadiness.so'
    backup_lib = PROJECT / '.libreadiness.so.verifier-backup'
    sentinel_src = Path('/tmp/verifier_readiness.c')
    sentinel_so = Path('/tmp/verifier_libreadiness.so')
    sentinel_src.write_text(f'''#include <string.h>\nint calculate_score(const char *s, int v) {{ return (int)strlen(s) * v + {challenge}; }}\n''')
    built = subprocess.run(['gcc', '-shared', '-fPIC', '-o', str(sentinel_so), str(sentinel_src)], text=True, capture_output=True)
    assert built.returncode == 0, f'Could not build verifier library: {built.stderr}'

    stop_processes()
    os.replace(original_lib, backup_lib)
    shutil.copy2(sentinel_so, original_lib)
    try:
        grpc_proc = start_process([sys.executable, 'grpc_server.py'], 'grpc_sentinel')
        wait_port(50051, grpc_proc)
        for name, version in [('dynamic-a', 5), ('longer-dynamic-service', 9)]:
            assert grpc_check(pb, grpc_service, grpc_method, name, version) == len(name) * version + challenge, 'gRPC server did not return the value from the loaded C library'

        gateway_proc = start_process(['node', 'gateway.js'], 'gateway_sentinel')
        wait_port(3000, gateway_proc)
        service_name = 'release-check-' + str(random.SystemRandom().randint(10000, 99999))
        version = random.SystemRandom().randint(6, 19)
        exercise_gateway(service_name, version, len(service_name) * version + challenge)
    finally:
        stop_processes()
        original_lib.unlink(missing_ok=True)
        if backup_lib.exists():
            os.replace(backup_lib, original_lib)

    grpc_proc = start_process([sys.executable, 'grpc_server.py'], 'grpc_normal')
    wait_port(50051, grpc_proc)
    assert grpc_check(pb, grpc_service, grpc_method, 'billing-service', 4) == 60
    gateway_proc = start_process(['node', 'gateway.js'], 'gateway_normal')
    wait_port(3000, gateway_proc)
    LOG_FILE.unlink(missing_ok=True)
    env = os.environ.copy()
    env['NODE_PATH'] = str(PROJECT / 'node_modules')
    result = subprocess.run(['node', 'run_test.js'], cwd=PROJECT, env=env, text=True, capture_output=True, timeout=20)
    assert result.returncode == 0, f'run_test.js did not exit cleanly: {result.stdout}{result.stderr}'
    stop_processes()


def test_test_result_log_exists():
    log_file = "/home/user/deploy_bridge/test_result.log"
    assert os.path.exists(log_file), f"Expected log file {log_file} does not exist."
    assert os.path.isfile(log_file), f"Expected {log_file} to be a file."


def test_test_result_log_content():
    log_file = "/home/user/deploy_bridge/test_result.log"

    try:
        with open(log_file, "r") as f:
            content = f.read().strip()
    except Exception as e:
        pytest.fail(f"Could not read {log_file}: {e}")

    assert content, f"The file {log_file} is empty."

    try:
        data = json.loads(content)
    except json.JSONDecodeError as e:
        pytest.fail(f"The content of {log_file} is not valid JSON. Content: {content}. Error: {e}")

    assert isinstance(data, dict), f"The JSON in {log_file} is not a dictionary."

    expected_event = "deployment_checked"
    expected_service = "billing-service"
    expected_version = 4
    expected_score = len(expected_service) * expected_version

    assert data.get("event") == expected_event, f"Expected event '{expected_event}', got '{data.get('event')}'"
    assert data.get("service") == expected_service, f"Expected service '{expected_service}', got '{data.get('service')}'"
    assert data.get("version") == expected_version, f"Expected version {expected_version}, got {data.get('version')}"
    assert data.get("score") == expected_score, f"Expected score {expected_score}, got {data.get('score')}"
PYTEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
