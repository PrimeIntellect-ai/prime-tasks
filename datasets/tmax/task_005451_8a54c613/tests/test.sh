#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import signal
import string
import subprocess
import sys
import tempfile
import time

import grpc
import pytest
from google.protobuf import descriptor_pb2

PROTO_CONTENT = '''
syntax = "proto3";
package telemetry;

service TelemetryProcessor {
  rpc ProcessData (DataPacket) returns (ProcessResponse);
}

message DataPacket {
  bytes payload = 1;
}

message ProcessResponse {
  bool success = 1;
  bytes decoded_data = 2;
}
'''


def listener_pids(port):
    inodes = set()
    wanted = format(port, '04X')
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    cols = line.split()
                    if len(cols) > 9 and cols[3] == '0A' and cols[1].split(':')[-1].upper() == wanted:
                        inodes.add(cols[9])
        except FileNotFoundError:
            pass

    pids = set()
    for procdir in glob.glob('/proc/[0-9]*'):
        try:
            pid = int(procdir.rsplit('/', 1)[1])
            for fd in glob.glob(procdir + '/fd/*'):
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    pids.add(pid)
                    break
        except (OSError, ValueError):
            continue
    return pids


def stop_listeners(port):
    pids = listener_pids(port)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids(port):
        time.sleep(0.05)
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


@pytest.fixture(scope='module')
def server_process():
    server_path = '/home/user/server.py'
    assert os.path.isfile(server_path), 'The server implementation /home/user/server.py does not exist.'
    assert os.path.getsize(server_path) > 0, 'The server implementation is empty.'

    stop_listeners(50051)
    proc = subprocess.Popen(
        [sys.executable, server_path],
        cwd='/home/user',
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    channel = grpc.insecure_channel('127.0.0.1:50051')
    try:
        grpc.channel_ready_future(channel).result(timeout=10)
    except grpc.FutureTimeoutError:
        proc.poll()
        pytest.fail(f'/home/user/server.py did not start a gRPC server on 127.0.0.1:50051 (exit={proc.returncode})')
    finally:
        channel.close()

    yield proc

    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
    stop_listeners(50051)


@pytest.fixture(scope='module')
def grpc_stub(server_process):
    with tempfile.TemporaryDirectory() as tmpdir:
        proto_path = os.path.join(tmpdir, 'telemetry.proto')
        with open(proto_path, 'w') as f:
            f.write(PROTO_CONTENT)

        from grpc_tools import protoc
        rc = protoc.main((
            '',
            f'-I{tmpdir}',
            f'--python_out={tmpdir}',
            f'--grpc_python_out={tmpdir}',
            proto_path,
        ))
        assert rc == 0

        sys.path.insert(0, tmpdir)
        import telemetry_pb2
        import telemetry_pb2_grpc

        channel = grpc.insecure_channel('127.0.0.1:50051')
        stub = telemetry_pb2_grpc.TelemetryProcessorStub(channel)
        yield stub, telemetry_pb2
        channel.close()
        sys.path.pop(0)


def get_encoded_payload(text: str) -> bytes:
    out = subprocess.check_output(['/app/legacy_encoder', text]).decode().strip()
    return bytes.fromhex(out)


def call(stub, pb2, payload):
    try:
        return stub.ProcessData(pb2.DataPacket(payload=payload), timeout=5)
    except grpc.RpcError as e:
        pytest.fail(f'gRPC call failed: {e}')


def random_text():
    alphabet = string.ascii_letters + string.digits + '_-'
    length = 1 + secrets.randbelow(48)
    return ''.join(secrets.choice(alphabet) for _ in range(length))


def test_proto_file_exists_and_schema():
    path = '/home/user/telemetry.proto'
    assert os.path.exists(path), 'The protobuf file /home/user/telemetry.proto does not exist.'
    assert os.path.isfile(path)

    with tempfile.TemporaryDirectory() as tmpdir:
        descriptor_path = os.path.join(tmpdir, 'schema.pb')
        from grpc_tools import protoc
        rc = protoc.main(('', '-I/home/user', f'--descriptor_set_out={descriptor_path}', path))
        assert rc == 0, 'telemetry.proto does not compile'
        descriptor_set = descriptor_pb2.FileDescriptorSet()
        with open(descriptor_path, 'rb') as f:
            descriptor_set.ParseFromString(f.read())

    assert len(descriptor_set.file) == 1
    fd = descriptor_set.file[0]
    assert fd.syntax == 'proto3'
    assert fd.package == 'telemetry'

    messages = {m.name: m for m in fd.message_type}
    assert 'DataPacket' in messages and 'ProcessResponse' in messages
    data_fields = [(f.name, f.number, f.type) for f in messages['DataPacket'].field]
    response_fields = [(f.name, f.number, f.type) for f in messages['ProcessResponse'].field]
    assert data_fields == [('payload', 1, descriptor_pb2.FieldDescriptorProto.TYPE_BYTES)]
    assert response_fields == [
        ('success', 1, descriptor_pb2.FieldDescriptorProto.TYPE_BOOL),
        ('decoded_data', 2, descriptor_pb2.FieldDescriptorProto.TYPE_BYTES),
    ]

    services = {s.name: s for s in fd.service}
    assert 'TelemetryProcessor' in services
    methods = services['TelemetryProcessor'].method
    assert len(methods) == 1
    assert methods[0].name == 'ProcessData'
    assert methods[0].input_type == '.telemetry.DataPacket'
    assert methods[0].output_type == '.telemetry.ProcessResponse'
    assert not methods[0].client_streaming and not methods[0].server_streaming


def test_server_valid_packet(grpc_stub):
    stub, pb2 = grpc_stub
    text = 'hello_world'
    resp = call(stub, pb2, get_encoded_payload(text))
    assert resp.success is True, 'Expected success=True for valid packet'
    assert resp.decoded_data == text.encode(), 'Decoded data does not match original text'


def test_server_single_bit_error(grpc_stub):
    stub, pb2 = grpc_stub
    text = 'single_bit_test'
    payload = bytearray(get_encoded_payload(text))
    payload[0] ^= 0x01
    resp = call(stub, pb2, bytes(payload))
    assert resp.success is True, 'Expected success=True for packet with 1-bit error (should be corrected)'
    assert resp.decoded_data == text.encode(), 'Decoded data does not match original text after 1-bit correction'


def test_server_two_bit_error(grpc_stub):
    stub, pb2 = grpc_stub
    text = 'two_bit_test'
    payload = bytearray(get_encoded_payload(text))
    payload[0] ^= 0x03
    resp = call(stub, pb2, bytes(payload))
    assert resp.success is False, 'Expected success=False for packet with 2-bit error (uncorrectable)'


def test_random_valid_packets(grpc_stub):
    stub, pb2 = grpc_stub
    for _ in range(10):
        text = random_text()
        resp = call(stub, pb2, get_encoded_payload(text))
        assert resp.success is True
        assert resp.decoded_data == text.encode()


def test_random_single_bit_errors_across_code_bits(grpc_stub):
    stub, pb2 = grpc_stub
    for bit in range(7):
        text = random_text()
        payload = bytearray(get_encoded_payload(text))
        position = secrets.randbelow(len(payload))
        payload[position] ^= 1 << bit
        resp = call(stub, pb2, bytes(payload))
        assert resp.success is True
        assert resp.decoded_data == text.encode()


def test_random_uncorrectable_errors(grpc_stub):
    stub, pb2 = grpc_stub
    for _ in range(8):
        text = random_text()
        payload = bytearray(get_encoded_payload(text))
        position = secrets.randbelow(len(payload))
        first = secrets.randbelow(7)
        second = secrets.randbelow(6)
        if second >= first:
            second += 1
        payload[position] ^= (1 << first) | (1 << second)
        resp = call(stub, pb2, bytes(payload))
        assert resp.success is False
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
