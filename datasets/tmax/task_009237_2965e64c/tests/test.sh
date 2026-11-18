#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_math_perf.py
import importlib
import json
import math
import os
import re
import signal
import subprocess
import sys
import threading
import time
from concurrent import futures
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = '/home/user/math_perf'
VENV = '/home/user/venv'
PYTHON = os.path.join(VENV, 'bin', 'python')
REPORT = os.path.join(ROOT, 'report.json')


def divisor_sum(n):
    if n <= 0:
        return 0
    total = 0
    i = 1
    while i * i <= n:
        if n % i == 0:
            total += i
            if i != n // i:
                total += n // i
        i += 1
    return total


def stop_existing_servers():
    me = os.getpid()
    victims = []
    for entry in os.listdir('/proc'):
        if not entry.isdigit() or int(entry) == me:
            continue
        try:
            with open(f'/proc/{entry}/cmdline', 'rb') as f:
                cmd = f.read().replace(b'\0', b' ').decode(errors='ignore')
        except (OSError, PermissionError):
            continue
        if ('/home/user/math_perf/rest_server.py' in cmd or
                '/home/user/math_perf/grpc_server.py' in cmd):
            victims.append(int(entry))
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.5)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def terminate(proc):
    if proc is None or proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=5)


# Preserve the original virtual-environment assertions.
assert os.path.isdir(VENV), f'The virtual environment directory {VENV} is missing.'
assert os.path.isfile(PYTHON), f'Python executable missing in virtual environment at {PYTHON}.'

# The verifier itself runs under the submitted environment so all requested
# runtime and compilation dependencies must really be importable there.
for module in ('flask', 'grpc', 'grpc_tools', 'requests'):
    importlib.import_module(module)
import grpc
import requests

# Preserve the original file and proto text assertions.
pb2_path = os.path.join(ROOT, 'math_service_pb2.py')
pb2_grpc_path = os.path.join(ROOT, 'math_service_pb2_grpc.py')
proto_path = os.path.join(ROOT, 'math_service.proto')
benchmark_path = os.path.join(ROOT, 'benchmark.py')
assert os.path.isfile(pb2_path), f'The compiled protobuf file {pb2_path} is missing.'
assert os.path.isfile(pb2_grpc_path), f'The compiled protobuf file {pb2_grpc_path} is missing.'
assert os.path.isfile(proto_path), f'The file {proto_path} is missing.'
assert os.path.isfile(benchmark_path), f'The file {benchmark_path} is missing.'
with open(proto_path) as f:
    proto_content = f.read()
assert 'service MathService' in proto_content, 'MathService is not defined in math_service.proto.'
assert 'message DivisorRequest' in proto_content, 'DivisorRequest is not defined in math_service.proto.'
assert 'message DivisorResponse' in proto_content, 'DivisorResponse is not defined in math_service.proto.'

# Import and inspect the generated protobuf artifacts rather than accepting
# arbitrary files with the expected names.
sys.path.insert(0, ROOT)
pb2 = importlib.import_module('math_service_pb2')
pb2_grpc = importlib.import_module('math_service_pb2_grpc')
request_desc = pb2.DivisorRequest.DESCRIPTOR
response_desc = pb2.DivisorResponse.DESCRIPTOR
assert set(request_desc.fields_by_name) == {'number'}
assert request_desc.fields_by_name['number'].type == request_desc.fields_by_name['number'].TYPE_INT64
assert set(response_desc.fields_by_name) == {'result'}
assert response_desc.fields_by_name['result'].type == response_desc.fields_by_name['result'].TYPE_INT64
service_desc = request_desc.file.services_by_name.get('MathService')
assert service_desc is not None, 'Generated protobuf has no MathService service.'
assert set(service_desc.methods_by_name) == {'SumOfDivisors'}
method_desc = service_desc.methods_by_name['SumOfDivisors']
assert method_desc.input_type.full_name == request_desc.full_name
assert method_desc.output_type.full_name == response_desc.full_name
assert hasattr(pb2_grpc, 'MathServiceStub')

# Exercise both submitted servers over their real network protocols.
stop_existing_servers()
rest_proc = grpc_proc = None
try:
    rest_proc = subprocess.Popen(
        [PYTHON, os.path.join(ROOT, 'rest_server.py')], cwd=ROOT,
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    grpc_proc = subprocess.Popen(
        [PYTHON, os.path.join(ROOT, 'grpc_server.py')], cwd=ROOT,
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)

    rest_ready = False
    for _ in range(60):
        if rest_proc.poll() is not None:
            raise AssertionError('rest_server.py exited during startup: ' + rest_proc.stderr.read())
        try:
            r = requests.get('http://127.0.0.1:5000/sum_divisors/36', timeout=0.5)
            if r.status_code == 200:
                rest_ready = True
                break
        except requests.RequestException:
            pass
        time.sleep(0.1)
    assert rest_ready, 'REST server did not become ready on port 5000.'

    channel = grpc.insecure_channel('127.0.0.1:50051')
    try:
        grpc.channel_ready_future(channel).result(timeout=8)
        stub = pb2_grpc.MathServiceStub(channel)
        for n in (1, 36, 12345, 49999):
            assert requests.get(
                f'http://127.0.0.1:5000/sum_divisors/{n}', timeout=2
            ).json()['result'] == divisor_sum(n)
            response = stub.SumOfDivisors(pb2.DivisorRequest(number=n), timeout=2)
            assert response.result == divisor_sum(n), f'Incorrect gRPC result for {n}.'
    finally:
        channel.close()
finally:
    terminate(rest_proc)
    terminate(grpc_proc)
    stop_existing_servers()

# Run benchmark.py against verifier-owned counting endpoints. This proves that
# it reads every number and performs both the REST and gRPC request sets.
with open(os.path.join(ROOT, 'numbers.txt')) as f:
    numbers = [int(line.strip()) for line in f if line.strip()]
assert len(numbers) == 100, 'numbers.txt must contain 100 integers.'
expected_total = sum(divisor_sum(n) for n in numbers)
rest_calls = []
grpc_calls = []
call_lock = threading.Lock()

class CountingHTTPServer(ThreadingHTTPServer):
    allow_reuse_address = True

class RestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        match = re.fullmatch(r'/sum_divisors/(-?\d+)', self.path.split('?', 1)[0])
        if not match:
            self.send_response(404)
            self.end_headers()
            return
        n = int(match.group(1))
        with call_lock:
            rest_calls.append(n)
        payload = json.dumps({'result': divisor_sum(n)}).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *args):
        pass

httpd = CountingHTTPServer(('127.0.0.1', 5000), RestHandler)
http_thread = threading.Thread(target=httpd.serve_forever, daemon=True)
http_thread.start()

def grpc_sum(request, context):
    n = request.number
    with call_lock:
        grpc_calls.append(n)
    return pb2.DivisorResponse(result=divisor_sum(n))

grpc_test_server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
handler = grpc.method_handlers_generic_handler(
    service_desc.full_name,
    {'SumOfDivisors': grpc.unary_unary_rpc_method_handler(
        grpc_sum,
        request_deserializer=pb2.DivisorRequest.FromString,
        response_serializer=pb2.DivisorResponse.SerializeToString,
    )}
)
grpc_test_server.add_generic_rpc_handlers((handler,))
assert grpc_test_server.add_insecure_port('127.0.0.1:50051') != 0
grpc_test_server.start()

try:
    if os.path.exists(REPORT):
        os.remove(REPORT)
    completed = subprocess.run(
        [PYTHON, benchmark_path], cwd=ROOT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
    assert completed.returncode == 0, (
        'benchmark.py failed. stdout:\n' + completed.stdout +
        '\nstderr:\n' + completed.stderr)
finally:
    httpd.shutdown()
    httpd.server_close()
    grpc_test_server.stop(0).wait(timeout=5)

assert rest_calls == numbers, 'benchmark.py did not make one ordered REST request for every number.'
assert grpc_calls == numbers, 'benchmark.py did not make one ordered gRPC request for every number.'

# Preserve all original report assertions, now applied to a freshly generated
# report produced by the executed benchmark.
assert os.path.isfile(REPORT), f'The file {REPORT} is missing.'
try:
    with open(REPORT) as f:
        data = json.load(f)
except json.JSONDecodeError as exc:
    raise AssertionError(f'The file {REPORT} is not valid JSON.') from exc
required_keys = ['rest_mean_latency_ms', 'grpc_mean_latency_ms', 'total_divisors_sum']
for key in required_keys:
    assert key in data, f"Key '{key}' is missing from {REPORT}."
assert set(data) == set(required_keys), 'report.json must contain the exact required keys.'
assert isinstance(data['rest_mean_latency_ms'], (float, int)), 'rest_mean_latency_ms must be a number.'
assert not isinstance(data['rest_mean_latency_ms'], bool)
assert math.isfinite(data['rest_mean_latency_ms']) and data['rest_mean_latency_ms'] > 0, 'rest_mean_latency_ms must be greater than 0.'
assert isinstance(data['grpc_mean_latency_ms'], (float, int)), 'grpc_mean_latency_ms must be a number.'
assert not isinstance(data['grpc_mean_latency_ms'], bool)
assert math.isfinite(data['grpc_mean_latency_ms']) and data['grpc_mean_latency_ms'] > 0, 'grpc_mean_latency_ms must be greater than 0.'
assert isinstance(data['total_divisors_sum'], int), 'total_divisors_sum must be an integer.'
assert data['total_divisors_sum'] == 4531853, f"total_divisors_sum is incorrect. Expected 4531853, got {data['total_divisors_sum']}."
assert data['total_divisors_sum'] == expected_total, 'total_divisors_sum does not match numbers.txt.'
PY_EOF

if /home/user/venv/bin/python /tmp/verify_math_perf.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
