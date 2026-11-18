#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import ast
import re
import sys
import time
import math
import base64
import signal
import secrets
import subprocess
from pathlib import Path

import grpc
import pytest
from grpc_tools import protoc

PROJECT_DIR = '/home/user/project'
SERVER_FILE = os.path.join(PROJECT_DIR, 'server.py')


def test_protobuf_compiled():
    pb2_file = os.path.join(PROJECT_DIR, 'calc_pb2.py')
    pb2_grpc_file = os.path.join(PROJECT_DIR, 'calc_pb2_grpc.py')

    assert os.path.isfile(pb2_file), f"{pb2_file} is missing. Protobuf was not compiled."
    assert os.path.isfile(pb2_grpc_file), f"{pb2_grpc_file} is missing. Protobuf was not compiled."
    assert os.path.getsize(pb2_file) > 0, f"{pb2_file} is empty."
    assert os.path.getsize(pb2_grpc_file) > 0, f"{pb2_grpc_file} is empty."

    check = subprocess.run(
        [sys.executable, '-c',
         "import calc_pb2, calc_pb2_grpc; "
         "assert calc_pb2.DESCRIPTOR.services_by_name['Calculator']; "
         "assert calc_pb2.CalcRequest and calc_pb2.CalcResponse; "
         "assert calc_pb2_grpc.CalculatorStub; "
         "assert calc_pb2_grpc.CalculatorServicer; "
         "assert calc_pb2_grpc.add_CalculatorServicer_to_server"],
        cwd=PROJECT_DIR,
        env={**os.environ, 'PYTHONPATH': PROJECT_DIR},
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert check.returncode == 0, f"Generated protobuf modules are unusable: {check.stderr}"


def test_server_file_exists():
    assert os.path.isfile(SERVER_FILE), f"{SERVER_FILE} is missing."


def test_rate_limiter_logic():
    with open(SERVER_FILE, 'r', encoding='utf-8') as f:
        content = f.read()

    tree = ast.parse(content)

    rate_limiter_class = None
    for node in tree.body:
        if isinstance(node, ast.ClassDef) and node.name == 'RateLimiter':
            rate_limiter_class = node
            break

    assert rate_limiter_class is not None, "RateLimiter class not found in server.py"

    init_func = None
    allow_func = None
    for node in rate_limiter_class.body:
        if isinstance(node, ast.FunctionDef):
            if node.name == '__init__':
                init_func = node
            elif node.name == 'allow':
                allow_func = node

    assert init_func is not None, "RateLimiter.__init__ missing"
    assert allow_func is not None, "RateLimiter.allow missing"

    has_dict = "dict" in content or "{}" in content or "defaultdict" in content
    assert has_dict, "RateLimiter does not seem to use a dictionary to track per-client state."

    args = [arg.arg for arg in allow_func.args.args]
    assert 'client_id' in args, "RateLimiter.allow must take client_id as an argument."


def test_input_validation_and_safety():
    with open(SERVER_FILE, 'r', encoding='utf-8') as f:
        content = f.read()

    assert "50" in content, "Could not find length limit of 50 in server.py"

    has_char_check = re.search(r'[\+\-\*/\(\)\.\s0-9]', content) is not None
    assert has_char_check, "Could not find character whitelist validation in server.py"

    tree = ast.parse(content)
    eval_in_try = False
    decode_in_try = False

    for node in ast.walk(tree):
        if isinstance(node, ast.Try):
            try_body_code = ast.unparse(node.body)
            if 'eval(' in try_body_code:
                eval_in_try = True
            if 'b64decode' in try_body_code or 'decode' in try_body_code:
                decode_in_try = True

    assert decode_in_try, "Base64 decoding must be wrapped in a try/except block to catch errors."
    assert eval_in_try, "The eval() function must be wrapped in a try/except block to catch evaluation errors."


def test_grpc_status_codes_used():
    with open(SERVER_FILE, 'r', encoding='utf-8') as f:
        content = f.read()

    assert "grpc.StatusCode.RESOURCE_EXHAUSTED" in content, "Must use grpc.StatusCode.RESOURCE_EXHAUSTED for rate limiting."
    assert "grpc.StatusCode.INVALID_ARGUMENT" in content, "Must use grpc.StatusCode.INVALID_ARGUMENT for validation/evaluation errors."


def _stop_existing_project_servers():
    me = os.getpid()
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit() or int(entry.name) == me:
            continue
        try:
            cmdline = (entry / 'cmdline').read_bytes().split(b'\0')
            cwd = os.readlink(entry / 'cwd')
        except (OSError, PermissionError):
            continue
        exact_path = any(arg == SERVER_FILE.encode() for arg in cmdline)
        cwd_server = cwd == PROJECT_DIR and any(arg == b'server.py' for arg in cmdline)
        if exact_path or cwd_server:
            try:
                os.kill(int(entry.name), signal.SIGTERM)
            except ProcessLookupError:
                pass
    time.sleep(0.3)


@pytest.fixture(scope='session')
def live_service(tmp_path_factory):
    client_dir = tmp_path_factory.mktemp('grpc_client')
    proto_file = os.path.join(PROJECT_DIR, 'proto', 'calc.proto')
    rc = protoc.main([
        'grpc_tools.protoc',
        f'-I{os.path.dirname(proto_file)}',
        f'--python_out={client_dir}',
        f'--grpc_python_out={client_dir}',
        proto_file,
    ])
    assert rc == 0, "Could not compile calc.proto for the independent verifier client"

    sys.path.insert(0, str(client_dir))
    import calc_pb2
    import calc_pb2_grpc

    _stop_existing_project_servers()
    log_path = '/tmp/calculator_server.log'
    log = open(log_path, 'w+', encoding='utf-8')
    proc = subprocess.Popen(
        [sys.executable, SERVER_FILE],
        cwd=PROJECT_DIR,
        stdout=log,
        stderr=subprocess.STDOUT,
        env={**os.environ, 'PYTHONPATH': PROJECT_DIR},
    )
    channel = grpc.insecure_channel('localhost:50051')
    try:
        grpc.channel_ready_future(channel).result(timeout=10)
        assert proc.poll() is None, "server.py exited instead of running continuously"
        yield calc_pb2, calc_pb2_grpc.CalculatorStub(channel)
    except Exception:
        log.flush()
        log.seek(0)
        output = log.read()
        pytest.fail(f"Server failed to start or serve gRPC on port 50051. Output:\n{output}")
    finally:
        channel.close()
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=3)
        log.close()


def _call(live_service, client_id, expression=None, raw_b64=None, expected=grpc.StatusCode.OK):
    calc_pb2, stub = live_service
    if raw_b64 is None:
        raw_b64 = base64.b64encode(expression.encode('utf-8')).decode('ascii')
    request = calc_pb2.CalcRequest(client_id=client_id, b64_expression=raw_b64)
    try:
        response = stub.Evaluate(request, timeout=3)
    except grpc.RpcError as exc:
        assert exc.code() == expected, f"Expected {expected}, got {exc.code()}: {exc.details()}"
        return None
    assert expected == grpc.StatusCode.OK, f"Expected {expected}, but request succeeded"
    return response.result


def test_live_evaluation_and_validation(live_service):
    nonce = secrets.token_hex(8)
    a = secrets.randbelow(50) + 2
    b = secrets.randbelow(30) + 2
    c = secrets.randbelow(20) + 2
    expression = f"({a} + {b}) * {c} / 2"
    expected = (a + b) * c / 2
    result = _call(live_service, 'math-' + nonce, expression=expression)
    assert math.isclose(result, expected, rel_tol=1e-12, abs_tol=1e-12)

    exactly_fifty = '1' + (' ' * 49)
    assert _call(live_service, 'len50-' + nonce, expression=exactly_fifty) == 1.0
    _call(live_service, 'len51-' + nonce, expression='1' + (' ' * 50),
          expected=grpc.StatusCode.INVALID_ARGUMENT)

    _call(live_service, 'bad64-' + nonce, raw_b64='%%%not-valid-base64%%%',
          expected=grpc.StatusCode.INVALID_ARGUMENT)
    invalid_utf8 = base64.b64encode(b'\xff\xfe\x80').decode('ascii')
    _call(live_service, 'utf8-' + nonce, raw_b64=invalid_utf8,
          expected=grpc.StatusCode.INVALID_ARGUMENT)

    marker = f'/tmp/grpc_rce_{nonce}'
    try:
        os.unlink(marker)
    except FileNotFoundError:
        pass
    attack = f"__import__('pathlib').Path('{marker}').write_text('owned')"
    _call(live_service, 'rce-' + nonce, expression=attack,
          expected=grpc.StatusCode.INVALID_ARGUMENT)
    assert not os.path.exists(marker), "Disallowed expression was executed"

    _call(live_service, 'zero-' + nonce, expression='10 / (3 - 3)',
          expected=grpc.StatusCode.INVALID_ARGUMENT)
    _call(live_service, 'syntax-' + nonce, expression='1 + (2 *',
          expected=grpc.StatusCode.INVALID_ARGUMENT)


def test_live_per_client_rate_limit(live_service):
    nonce = secrets.token_hex(8)
    client_a = 'rate-a-' + nonce
    client_b = 'rate-b-' + nonce

    for i in range(5):
        assert _call(live_service, client_a, expression=f'{i} + 1') == float(i + 1)

    assert _call(live_service, client_b, expression='7 + 8') == 15.0
    _call(live_service, client_a, expression='1 + 1',
          expected=grpc.StatusCode.RESOURCE_EXHAUSTED)

    time.sleep(1.1)
    assert _call(live_service, client_a, expression='9 - 2') == 7.0


def test_live_rate_limit_is_rolling(live_service):
    client = 'rolling-' + secrets.token_hex(8)

    for _ in range(3):
        assert _call(live_service, client, expression='1 + 1') == 2.0
    time.sleep(0.65)
    for _ in range(2):
        assert _call(live_service, client, expression='2 + 2') == 4.0

    time.sleep(0.55)
    for _ in range(3):
        assert _call(live_service, client, expression='3 + 3') == 6.0
    _call(live_service, client, expression='4 + 4',
          expected=grpc.StatusCode.RESOURCE_EXHAUSTED)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
