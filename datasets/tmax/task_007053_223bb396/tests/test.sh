#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib
import json
import os
import re
import subprocess
import sys
import tempfile

from google.protobuf import descriptor_pb2
from grpc_tools import protoc

PROTO_DIR = '/home/user/protos'
GEN_DIR = '/home/user/generated'

EXPECTED_SOURCES = {
    'base.proto': '''syntax = "proto3";
package myproject.base;

enum Status {
    UNKNOWN = 0;
    OK = 1;
    ERROR = 2;
}
''',
    'user.proto': '''syntax = "proto3";
package myproject.user;

import "base.proto";

message User {
    int32 id = 1;
    string name = 2;
    myproject.base.Status status = 3;
}
''',
    'service.proto': '''syntax = "proto3";
package myproject.service;

import "user.proto";

message UserResponse {
    myproject.user.User user = 1;
    string message = 2;
}
'''
}


def test_original_proto_files_unchanged():
    assert set(os.listdir(PROTO_DIR)) == set(EXPECTED_SOURCES)
    for name, expected in EXPECTED_SOURCES.items():
        with open(os.path.join(PROTO_DIR, name), encoding='utf-8') as f:
            assert f.read() == expected, f'{name} was modified'


def test_proto_graph_json():
    graph_path = '/home/user/proto_graph.json'
    assert os.path.isfile(graph_path), f"File not found: {graph_path}"

    with open(graph_path, 'r') as f:
        try:
            graph = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{graph_path} is not valid JSON"

    expected_graph = {
        "base.proto": [],
        "user.proto": ["base.proto"],
        "service.proto": ["user.proto"]
    }
    assert graph == expected_graph, f"Graph content mismatch. Expected {expected_graph}, got {graph}"

    derived_graph = {}
    for name in sorted(EXPECTED_SOURCES):
        with open(os.path.join(PROTO_DIR, name), encoding='utf-8') as f:
            derived_graph[name] = re.findall(r'^\s*import\s+"([^"]+)"\s*;', f.read(), re.MULTILINE)
    assert graph == derived_graph, f"Graph does not match imports parsed from the proto files: {derived_graph}"


def test_test_serde_script_runs_and_creates_payload():
    script_path = '/home/user/test_serde.py'
    assert os.path.isfile(script_path), f"Script not found: {script_path}"

    payload_path = '/home/user/payload.bin'
    if os.path.lexists(payload_path):
        os.unlink(payload_path)

    result = subprocess.run(
        ['python3', script_path],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"python3 {script_path} failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(payload_path), 'test_serde.py did not create /home/user/payload.bin'


def test_generated_directory():
    assert os.path.isdir(GEN_DIR), f"Directory not found: {GEN_DIR}"

    expected_files = ['__init__.py', 'base_pb2.py', 'user_pb2.py', 'service_pb2.py']
    for f in expected_files:
        file_path = os.path.join(GEN_DIR, f)
        assert os.path.isfile(file_path), f"Expected generated file not found: {file_path}"
    assert os.path.getsize(os.path.join(GEN_DIR, '__init__.py')) == 0, '__init__.py must be empty'

    with tempfile.TemporaryDirectory() as tmp:
        descriptor_path = os.path.join(tmp, 'reference.pb')
        args = [
            'grpc_tools.protoc',
            f'-I{PROTO_DIR}',
            f'--descriptor_set_out={descriptor_path}',
            '--include_imports',
        ] + [os.path.join(PROTO_DIR, name) for name in sorted(EXPECTED_SOURCES)]
        assert protoc.main(args) == 0, 'Failed to compile the original proto files for validation'

        reference_set = descriptor_pb2.FileDescriptorSet()
        with open(descriptor_path, 'rb') as f:
            reference_set.ParseFromString(f.read())
        references = {item.name: item for item in reference_set.file}

    if GEN_DIR not in sys.path:
        sys.path.insert(0, GEN_DIR)
    for proto_name in sorted(EXPECTED_SOURCES):
        module_name = proto_name[:-6] + '_pb2'
        try:
            module = importlib.import_module(module_name)
        except Exception as e:
            assert False, f"Failed to import generated protobuf module {module_name}: {e}"
        actual = descriptor_pb2.FileDescriptorProto()
        actual.ParseFromString(module.DESCRIPTOR.serialized_pb)
        assert actual == references[proto_name], f'{module_name} does not match {proto_name}'


def test_payload_bin_content():
    payload_path = '/home/user/payload.bin'
    assert os.path.isfile(payload_path), f"Payload file not found: {payload_path}"

    if GEN_DIR not in sys.path:
        sys.path.insert(0, GEN_DIR)

    try:
        import service_pb2
        import base_pb2
    except ImportError as e:
        assert False, f"Failed to import generated protobuf modules: {e}"

    with open(payload_path, 'rb') as f:
        data = f.read()

    msg = service_pb2.UserResponse()
    try:
        msg.ParseFromString(data)
    except Exception as e:
        assert False, f"Failed to parse payload.bin: {e}"

    assert msg.message == "Success", f"Expected message='Success', got {msg.message}"
    assert msg.user.id == 42, f"Expected user.id=42, got {msg.user.id}"
    assert msg.user.name == "Bob", f"Expected user.name='Bob', got {msg.user.name}"
    assert msg.user.status == base_pb2.OK, f"Expected user.status=OK, got {msg.user.status}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
