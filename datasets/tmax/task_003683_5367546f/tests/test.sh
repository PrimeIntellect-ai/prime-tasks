#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess

POLYBUILD_DIR = "/home/user/polybuild"
EXPECTED_HEADER = b"Content-Type: application/x-protobuf\r\n\r\n"
EXPECTED_BODY = b"\x08\x65\x12\x13mechanical-keyboard\x18\x01"
EXPECTED_RESPONSE = EXPECTED_HEADER + EXPECTED_BODY


def test_polybuild_directory_exists():
    assert os.path.isdir(POLYBUILD_DIR), f"Directory {POLYBUILD_DIR} does not exist"


def test_source_files_exist():
    proto_file = os.path.join(POLYBUILD_DIR, "catalog.proto")
    c_file = os.path.join(POLYBUILD_DIR, "api_endpoint.c")
    makefile = os.path.join(POLYBUILD_DIR, "Makefile")

    assert os.path.isfile(proto_file), f"{proto_file} does not exist"
    assert os.path.isfile(c_file), f"{c_file} does not exist"
    assert os.path.isfile(makefile), f"{makefile} does not exist"


def test_generated_and_compiled_files_exist():
    pb_c = os.path.join(POLYBUILD_DIR, "catalog.pb-c.c")
    pb_h = os.path.join(POLYBUILD_DIR, "catalog.pb-c.h")
    executable = os.path.join(POLYBUILD_DIR, "api_endpoint")

    assert os.path.isfile(pb_c), f"Generated file {pb_c} does not exist"
    assert os.path.isfile(pb_h), f"Generated file {pb_h} does not exist"
    assert os.path.isfile(executable), f"Executable {executable} does not exist"
    assert os.access(executable, os.X_OK), f"{executable} is not executable"


def _read_varint(data, pos):
    value = 0
    shift = 0
    while True:
        assert pos < len(data), "Truncated protobuf descriptor"
        byte = data[pos]
        pos += 1
        value |= (byte & 0x7f) << shift
        if not byte & 0x80:
            return value, pos
        shift += 7
        assert shift < 70, "Invalid protobuf varint"


def _wire_fields(data):
    fields = []
    pos = 0
    while pos < len(data):
        key, pos = _read_varint(data, pos)
        number, wire_type = key >> 3, key & 7
        if wire_type == 0:
            value, pos = _read_varint(data, pos)
        elif wire_type == 1:
            assert pos + 8 <= len(data), "Truncated fixed64 descriptor field"
            value = data[pos:pos + 8]
            pos += 8
        elif wire_type == 2:
            length, pos = _read_varint(data, pos)
            assert pos + length <= len(data), "Truncated length-delimited descriptor field"
            value = data[pos:pos + length]
            pos += length
        elif wire_type == 5:
            assert pos + 4 <= len(data), "Truncated fixed32 descriptor field"
            value = data[pos:pos + 4]
            pos += 4
        else:
            raise AssertionError(f"Unsupported wire type {wire_type} in descriptor")
        fields.append((number, wire_type, value))
    return fields


def _first(fields, number, wire_type):
    values = [value for n, w, value in fields if n == number and w == wire_type]
    return values[0] if values else None


def test_proto_schema_and_c_include():
    descriptor = "/tmp/catalog-verifier.desc"
    subprocess.run(
        ["protoc", f"--descriptor_set_out={descriptor}", "catalog.proto"],
        cwd=POLYBUILD_DIR,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    with open(descriptor, "rb") as f:
        descriptor_data = f.read()

    products = []
    for number, wire_type, file_data in _wire_fields(descriptor_data):
        if number != 1 or wire_type != 2:
            continue
        file_fields = _wire_fields(file_data)
        for n, w, message_data in file_fields:
            if n != 4 or w != 2:
                continue
            message_fields = _wire_fields(message_data)
            name = _first(message_fields, 1, 2)
            if name == b"Product":
                products.append(message_fields)

    assert len(products) == 1, "catalog.proto must define exactly one Product message"
    actual_fields = []
    for n, w, field_data in products[0]:
        if n != 2 or w != 2:
            continue
        field_fields = _wire_fields(field_data)
        name = _first(field_fields, 1, 2)
        number = _first(field_fields, 3, 0)
        field_type = _first(field_fields, 5, 0)
        actual_fields.append((name, number, field_type))

    # FieldDescriptorProto type enum: int32=5, bool=8, string=9.
    assert sorted(actual_fields, key=lambda item: item[1]) == [
        (b"id", 1, 5),
        (b"slug", 2, 9),
        (b"in_stock", 3, 8),
    ], f"Incorrect Product fields: {actual_fields!r}"

    with open(os.path.join(POLYBUILD_DIR, "api_endpoint.c"), encoding="utf-8") as f:
        c_source = f.read()
    assert re.search(r"#\s*include\s*[<\"]catalog\.pb-c\.h[>\"]", c_source), \
        "api_endpoint.c must include catalog.pb-c.h"


def test_make_rebuilds_required_artifacts():
    for name in ("catalog.pb-c.c", "catalog.pb-c.h", "api_endpoint"):
        path = os.path.join(POLYBUILD_DIR, name)
        if os.path.lexists(path):
            os.remove(path)
    for name in os.listdir(POLYBUILD_DIR):
        if name.endswith(".o"):
            os.remove(os.path.join(POLYBUILD_DIR, name))

    result = subprocess.run(
        ["make"],
        cwd=POLYBUILD_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert result.returncode == 0, "Default make target failed:\n" + result.stdout.decode(errors="replace")

    subprocess.run(
        ["make", "-n", "all"],
        cwd=POLYBUILD_DIR,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )

    for name in ("catalog.pb-c.c", "catalog.pb-c.h", "api_endpoint"):
        assert os.path.isfile(os.path.join(POLYBUILD_DIR, name)), f"make did not create {name}"

    executable = os.path.join(POLYBUILD_DIR, "api_endpoint")
    assert os.access(executable, os.X_OK), f"{executable} is not executable"
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", "api_endpoint must be a compiled ELF executable"


def test_executable_output_and_response_bin_contents():
    executable = os.path.join(POLYBUILD_DIR, "api_endpoint")
    run = subprocess.run(
        [executable],
        cwd=POLYBUILD_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert run.returncode == 0, f"api_endpoint exited with status {run.returncode}: {run.stderr!r}"
    assert run.stdout == EXPECTED_RESPONSE, \
        f"api_endpoint emitted an invalid HTTP/Protobuf response: {run.stdout!r}"

    response_file = os.path.join(POLYBUILD_DIR, "response.bin")
    assert os.path.isfile(response_file), f"Output file {response_file} does not exist"

    with open(response_file, "rb") as f:
        data = f.read()

    # Preserve the original header/body and payload assertions.
    parts = data.split(b"\r\n\r\n", 1)
    if len(parts) != 2:
        parts = data.split(b"\n\n", 1)

    assert len(parts) == 2, "Could not find HTTP header/body separator (CRLF CRLF or LF LF)"
    headers, body = parts
    assert b"Content-Type: application/x-protobuf" in headers, \
        "Missing or incorrect Content-Type header in response.bin"
    assert body == EXPECTED_BODY, \
        f"Protobuf payload mismatch. Expected {EXPECTED_BODY.hex()}, got {body.hex()}"

    assert data == run.stdout, "response.bin was not produced from the current api_endpoint output"
    assert data == EXPECTED_RESPONSE, "response.bin must contain exactly one header, CRLF separator, and payload"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
