#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import sys
import time
import uuid
import signal
import socket
import random
import pathlib
import subprocess

import pytest


def find_artifact(name):
    preferred = [pathlib.Path('/home/user') / name, pathlib.Path('/app') / name]
    for path in preferred:
        if path.is_file():
            return path
    found = []
    for root in (pathlib.Path('/home/user'), pathlib.Path('/app')):
        if root.exists():
            found.extend(p for p in root.rglob(name) if p.is_file())
    assert found, f"Required artifact {name} was not found under /home/user or /app"
    return sorted(found, key=lambda p: (len(p.parts), str(p)))[0]


def setup_client_proto():
    proto_content = '''
syntax = "proto3";
package ci_video;
service CIAnalyzer {
  rpc RunEmulator (RunRequest) returns (RunResponse);
}
message RunRequest { string video_path = 1; }
message RunResponse { repeated int32 output = 1; }
'''
    proto_path = '/tmp/ci_analyzer_test.proto'
    with open(proto_path, 'w') as f:
        f.write(proto_content)
    subprocess.check_call([
        sys.executable, '-m', 'grpc_tools.protoc', '-I/tmp',
        '--python_out=/tmp', '--grpc_python_out=/tmp', proto_path
    ])
    if '/tmp' not in sys.path:
        sys.path.insert(0, '/tmp')


def kill_port_50051():
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    parts = line.split()
                    if parts[1].split(':')[-1].upper() == 'C383' and parts[3] == '0A':
                        inodes.add(parts[9])
        except FileNotFoundError:
            pass
    victims = set()
    for procdir in pathlib.Path('/proc').iterdir():
        if not procdir.name.isdigit():
            continue
        fd_dir = procdir / 'fd'
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    victims.add(int(procdir.name))
                    break
        except (OSError, PermissionError):
            continue
    for pid in victims:
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    deadline = time.time() + 3
    while time.time() < deadline:
        try:
            with socket.create_connection(('127.0.0.1', 50051), timeout=0.15):
                time.sleep(0.1)
        except OSError:
            return
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


@pytest.fixture(scope='module', autouse=True)
def prepare_and_run_submission():
    setup_client_proto()
    server = find_artifact('server.py')
    subprocess.check_call([sys.executable, '-m', 'py_compile', str(server)])

    log_path = pathlib.Path('/home/user/server.log')
    try:
        log_path.unlink()
    except FileNotFoundError:
        pass

    kill_port_50051()
    output = open('/tmp/verifier_server_stdout.log', 'w+')
    proc = subprocess.Popen(
        [sys.executable, str(server)], cwd=str(server.parent),
        stdout=output, stderr=subprocess.STDOUT,
        env={**os.environ, 'PYTHONUNBUFFERED': '1'}
    )

    import grpc
    channel = grpc.insecure_channel('127.0.0.1:50051')
    try:
        grpc.channel_ready_future(channel).result(timeout=12)
    except Exception:
        output.flush()
        output.seek(0)
        details = output.read()
        proc.terminate()
        pytest.fail(f'Submitted server.py did not start on port 50051. Output:\n{details}')

    yield

    channel.close()
    proc.terminate()
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
    output.close()
    kill_port_50051()


def test_required_proto_definition():
    from google.protobuf import descriptor_pb2

    proto = find_artifact('ci_analyzer.proto')
    descriptor_path = f'/tmp/submission_{uuid.uuid4().hex}.desc'
    subprocess.check_call([
        sys.executable, '-m', 'grpc_tools.protoc',
        f'-I{proto.parent}', f'--descriptor_set_out={descriptor_path}', proto.name
    ], cwd=str(proto.parent))
    descriptor_set = descriptor_pb2.FileDescriptorSet()
    descriptor_set.ParseFromString(pathlib.Path(descriptor_path).read_bytes())
    assert len(descriptor_set.file) == 1
    fd = descriptor_set.file[0]
    assert fd.package == 'ci_video'

    messages = {m.name: m for m in fd.message_type}
    assert 'RunRequest' in messages and 'RunResponse' in messages
    request_fields = list(messages['RunRequest'].field)
    response_fields = list(messages['RunResponse'].field)
    assert len(request_fields) == 1
    assert (request_fields[0].name, request_fields[0].number, request_fields[0].type) == ('video_path', 1, 9)
    assert len(response_fields) == 1
    assert (response_fields[0].name, response_fields[0].number, response_fields[0].type, response_fields[0].label) == ('output', 1, 5, 3)

    services = {s.name: s for s in fd.service}
    assert 'CIAnalyzer' in services
    methods = {m.name: m for m in services['CIAnalyzer'].method}
    assert 'RunEmulator' in methods
    method = methods['RunEmulator']
    assert method.input_type == '.ci_video.RunRequest'
    assert method.output_type == '.ci_video.RunResponse'


def grpc_stub():
    import grpc
    import ci_analyzer_test_pb2_grpc
    channel = grpc.insecure_channel('127.0.0.1:50051')
    return channel, ci_analyzer_test_pb2_grpc.CIAnalyzerStub(channel)


def test_grpc_unauthenticated():
    import grpc
    import ci_analyzer_test_pb2
    channel, stub = grpc_stub()
    try:
        request = ci_analyzer_test_pb2.RunRequest(video_path='/app/ci_test_run.mp4')
        with pytest.raises(grpc.RpcError) as excinfo:
            stub.RunEmulator(request, timeout=10)
        assert excinfo.value.code() == grpc.StatusCode.UNAUTHENTICATED
    finally:
        channel.close()


def test_grpc_incorrect_token():
    import grpc
    import ci_analyzer_test_pb2
    channel, stub = grpc_stub()
    try:
        request = ci_analyzer_test_pb2.RunRequest(video_path='/app/ci_test_run.mp4')
        with pytest.raises(grpc.RpcError) as excinfo:
            stub.RunEmulator(request, metadata=(('authorization', 'Bearer wrong-token'),), timeout=10)
        assert excinfo.value.code() == grpc.StatusCode.UNAUTHENTICATED
    finally:
        channel.close()


def authenticated_run(path):
    import ci_analyzer_test_pb2
    channel, stub = grpc_stub()
    try:
        response = stub.RunEmulator(
            ci_analyzer_test_pb2.RunRequest(video_path=path),
            metadata=(('authorization', 'Bearer secret-token-123'),), timeout=15
        )
        return list(response.output)
    finally:
        channel.close()


def test_grpc_authenticated_original_video():
    assert authenticated_run('/app/ci_test_run.mp4') == [3, 4]


def write_video(instructions):
    import cv2
    import numpy as np

    rng = random.SystemRandom()
    rgb_flags = {
        'PUSH1': (1, 0, 0),
        'PUSH2': (0, 1, 0),
        'ADD': (0, 0, 1),
        'MUL': (1, 1, 0),
        'OUT': (0, 1, 1),
        'HALT': (0, 0, 0),
    }
    path = f'/tmp/ci_dynamic_{uuid.uuid4().hex}.mp4'
    writer = cv2.VideoWriter(path, cv2.VideoWriter_fourcc(*'mp4v'), 30, (96, 96))
    assert writer.isOpened(), 'Could not create verifier test video'
    for instruction in instructions:
        flags = rgb_flags[instruction]
        rgb = tuple(rng.randint(220, 250) if high else rng.randint(0, 25) for high in flags)
        frame = np.full((96, 96, 3), (rgb[2], rgb[1], rgb[0]), dtype=np.uint8)
        for _ in range(30):
            writer.write(frame)
    writer.release()
    return path


def emulate(instructions):
    stack = []
    output = []
    for op in instructions:
        if op == 'PUSH1':
            stack.append(1)
        elif op == 'PUSH2':
            stack.append(2)
        elif op == 'ADD':
            b, a = stack.pop(), stack.pop()
            stack.append(a + b)
        elif op == 'MUL':
            b, a = stack.pop(), stack.pop()
            stack.append(a * b)
        elif op == 'OUT':
            output.append(stack.pop())
        elif op == 'HALT':
            break
    return output


def test_server_analyzes_request_path_and_executes_vm():
    programs = [
        ['PUSH1', 'OUT', 'HALT', 'PUSH2', 'OUT'],
        ['PUSH2', 'PUSH2', 'MUL', 'OUT', 'HALT'],
        ['PUSH1', 'PUSH2', 'ADD', 'PUSH2', 'MUL', 'OUT', 'HALT'],
        ['PUSH2', 'OUT', 'PUSH1', 'OUT', 'HALT'],
    ]
    random.SystemRandom().shuffle(programs)
    for program in programs:
        path = write_video(program)
        assert authenticated_run(path) == emulate(program)


def test_startup_log_created_by_launched_server():
    path = pathlib.Path('/home/user/server.log')
    deadline = time.time() + 5
    while time.time() < deadline and (not path.is_file() or not path.read_text(errors='replace').strip()):
        time.sleep(0.1)
    assert path.is_file(), '/home/user/server.log was not created by server.py'
    text = path.read_text(errors='replace').strip()
    assert text, '/home/user/server.log is empty'
    lowered = text.lower()
    assert any(word in lowered for word in ('start', 'listen', 'ready', '50051')), \
        'server.log does not confirm server startup'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
