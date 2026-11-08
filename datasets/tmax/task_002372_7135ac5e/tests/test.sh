#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile
from pathlib import Path

ITEM_PROTO = '''syntax = "proto3";
package feature;
import "category.proto";

message Item {
    string id = 1;
    Category category = 2;
}

service FeatureService {
    rpc GetItem(Item) returns (Item);
}
'''

CATEGORY_PROTO = '''syntax = "proto3";
package feature;

message Category {
    string name = 1;
}
'''

EXPECTED_NGINX_LINES = [
    "server {",
    "listen 8080 http2;",
    "location /feature.FeatureService {",
    "grpc_pass grpc://localhost:50051;",
    "}",
    "}",
]


def read_varint(data, pos):
    value = 0
    shift = 0
    start = pos
    while True:
        assert pos < len(data), "Truncated protobuf varint"
        byte = data[pos]
        pos += 1
        value |= (byte & 0x7f) << shift
        if not byte & 0x80:
            return value, pos
        shift += 7
        assert shift < 70 and pos - start <= 10, "Invalid protobuf varint"


def parse_wire_fields(data):
    fields = []
    pos = 0
    while pos < len(data):
        start = pos
        key, pos = read_varint(data, pos)
        number, wire_type = key >> 3, key & 7
        assert number > 0, "Invalid protobuf field number"
        if wire_type == 0:
            _, pos = read_varint(data, pos)
            payload = data[start:pos]
        elif wire_type == 1:
            assert pos + 8 <= len(data), "Truncated fixed64 field"
            pos += 8
            payload = data[start:pos]
        elif wire_type == 2:
            length, content_pos = read_varint(data, pos)
            end = content_pos + length
            assert end <= len(data), "Truncated length-delimited field"
            payload = data[content_pos:end]
            pos = end
        elif wire_type == 5:
            assert pos + 4 <= len(data), "Truncated fixed32 field"
            pos += 4
            payload = data[start:pos]
        else:
            raise AssertionError(f"Unsupported or invalid protobuf wire type {wire_type}")
        fields.append((number, wire_type, payload, data[start:pos]))
    return fields


def normalized_descriptor_set(data):
    files = {}
    top_fields = parse_wire_fields(data)
    assert top_fields, "Descriptor set contains no files"
    for number, wire_type, file_data, _ in top_fields:
        assert number == 1 and wire_type == 2, "Invalid FileDescriptorSet field"
        file_fields = parse_wire_fields(file_data)
        names = [payload for num, wt, payload, _ in file_fields if num == 1 and wt == 2]
        assert len(names) == 1, "File descriptor must contain exactly one name"
        name = names[0].decode("utf-8")
        assert name not in files, f"Duplicate descriptor for {name}"
        # source_code_info (field 9) is optional and may legitimately be emitted
        # by protoc with --include_source_info. All other descriptor data must match.
        files[name] = b"".join(raw for num, _, _, raw in file_fields if num != 9)
    return files


def run_protoc(proto_dir, output):
    result = subprocess.run(
        [
            "protoc",
            f"--proto_path={proto_dir}",
            f"--descriptor_set_out={output}",
            "item.proto",
            "category.proto",
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert result.returncode == 0, f"protoc compilation failed: {result.stderr}"


def test_category_proto_fixed():
    category_proto = "/home/user/proto/category.proto"
    assert os.path.exists(category_proto), f"File {category_proto} is missing."

    with open(category_proto, "r") as f:
        content = f.read()

    assert 'import "item.proto";' not in content, "Circular dependency 'import \"item.proto\";' is still in category.proto"
    assert "Item top_item = 2;" not in content, "Field 'Item top_item = 2;' is still in category.proto"


def test_item_proto_was_not_modified():
    item_proto = Path("/home/user/proto/item.proto")
    assert item_proto.exists(), f"File {item_proto} is missing."
    assert item_proto.read_text() == ITEM_PROTO, "item.proto was modified"


def test_descriptor_pb_exists_and_matches_compilation():
    descriptor_pb = Path("/home/user/descriptor.pb")
    assert descriptor_pb.exists(), f"File {descriptor_pb} is missing."
    assert descriptor_pb.stat().st_size > 0, f"File {descriptor_pb} is empty."

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        actual_compilation = tmp / "actual.pb"
        run_protoc("/home/user/proto", actual_compilation)

        reference_dir = tmp / "reference"
        reference_dir.mkdir()
        (reference_dir / "item.proto").write_text(ITEM_PROTO)
        (reference_dir / "category.proto").write_text(CATEGORY_PROTO)
        reference_descriptor = tmp / "reference.pb"
        run_protoc(reference_dir, reference_descriptor)

        expected = normalized_descriptor_set(reference_descriptor.read_bytes())
        compiled_actual = normalized_descriptor_set(actual_compilation.read_bytes())
        submitted = normalized_descriptor_set(descriptor_pb.read_bytes())

        assert set(expected) == {"item.proto", "category.proto"}
        assert compiled_actual == expected, "The protobuf source files do not compile to the required definitions"
        assert submitted == expected, "descriptor.pb is not a valid descriptor set compiled from both required protobuf definitions"


def test_sorted_messages_txt():
    sorted_messages = "/home/user/sorted_messages.txt"
    assert os.path.exists(sorted_messages), f"File {sorted_messages} is missing."

    with open(sorted_messages, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert lines == ["Category", "Item"], f"Expected sorted messages to be ['Category', 'Item'], but got {lines}"


def test_nginx_grpc_conf_fixed():
    nginx_conf = "/home/user/nginx/grpc.conf"
    assert os.path.exists(nginx_conf), f"File {nginx_conf} is missing."

    with open(nginx_conf, "r") as f:
        content = f.read()

    assert "grpc_pass grpc://localhost:50051;" in content, "Nginx config does not contain the correct 'grpc_pass grpc://localhost:50051;' directive."
    assert "proxy_pass" not in content, "Nginx config still contains 'proxy_pass' directive."

    significant_lines = [line.strip() for line in content.splitlines() if line.strip()]
    assert significant_lines == EXPECTED_NGINX_LINES, "Nginx configuration structure was not preserved with only the required gRPC proxy change"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
