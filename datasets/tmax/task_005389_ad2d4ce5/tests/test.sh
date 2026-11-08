#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess

ROOT = "/home/user/rpc_utility"
SRC = os.path.join(ROOT, "src")
INPUT = os.path.join(ROOT, "data/input.bin")
LOG = os.path.join(ROOT, "allowed.log")
PROCESSOR = os.path.join(ROOT, "bin/processor")


def test_request_proto_fixed():
    request_proto_path = os.path.join(ROOT, "schemas/request.proto")
    assert os.path.isfile(request_proto_path), f"File missing: {request_proto_path}"

    with open(request_proto_path, "r") as f:
        content = f.read()

    assert 'import "user.proto";' not in content, "Circular import 'import \"user.proto\";' was not removed from request.proto"
    assert re.search(r'int32\s+owner_id\s*=\s*2\s*;', content), "Field 'int32 owner_id = 2;' not found in request.proto"
    assert "User owner" not in content, "'User owner' field was not removed from request.proto"


def test_generated_c_files_exist():
    expected_files = [
        "user.pb-c.c", "user.pb-c.h",
        "request.pb-c.c", "request.pb-c.h",
        "batch.pb-c.c", "batch.pb-c.h"
    ]
    for filename in expected_files:
        path = os.path.join(SRC, filename)
        assert os.path.isfile(path), f"Generated protobuf-c file missing: {path}"


def test_processor_source_exists():
    processor_c_path = os.path.join(SRC, "processor.c")
    assert os.path.isfile(processor_c_path), f"Processor source file missing: {processor_c_path}"


def test_processor_executable_exists():
    assert os.path.isfile(PROCESSOR), f"Processor executable missing: {PROCESSOR}"
    assert os.access(PROCESSOR, os.X_OK), f"Processor executable is not marked as executable: {PROCESSOR}"
    with open(PROCESSOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", "processor is not a compiled ELF executable"


def test_allowed_log_contents():
    assert os.path.isfile(LOG), f"Log file missing: {LOG}"
    with open(LOG, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_ids = ["101", "102", "103", "105", "106", "109"]
    assert lines == expected_ids, f"allowed.log contents are incorrect. Expected {expected_ids}, got {lines}"


def varint(value):
    value = int(value)
    out = bytearray()
    while value > 0x7f:
        out.append((value & 0x7f) | 0x80)
        value >>= 7
    out.append(value)
    return bytes(out)


def encode_batch(rows):
    result = bytearray()
    for req_id, owner_id in rows:
        request = bytearray()
        request += b"\x08" + varint(req_id)
        request += b"\x10" + varint(owner_id)
        request += b"\x18" + varint(1600000000)
        result += b"\x0a" + varint(len(request)) + request
    return bytes(result)


def expected_allowed(rows):
    counts = {}
    result = []
    for req_id, owner_id in rows:
        counts[owner_id] = counts.get(owner_id, 0) + 1
        if counts[owner_id] <= 2:
            result.append(str(req_id))
    return result


def run_case(executable, rows, require_unpack_marker=False):
    with open(INPUT, "wb") as f:
        f.write(encode_batch(rows))
    if os.path.exists(LOG):
        os.unlink(LOG)
    marker = "/tmp/protobuf_unpack_called"
    if os.path.exists(marker):
        os.unlink(marker)

    completed = subprocess.run([executable], cwd=ROOT, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, timeout=10)
    assert completed.returncode == 0, (
        f"processor exited with {completed.returncode}: "
        f"{completed.stderr.decode(errors='replace')}"
    )
    assert os.path.isfile(LOG), "processor did not create allowed.log"
    with open(LOG, "r") as f:
        actual = [line.strip() for line in f if line.strip()]
    expected = expected_allowed(rows)
    assert actual == expected, f"For generated input expected {expected}, got {actual}"
    if require_unpack_marker:
        assert os.path.isfile(marker), "processor did not call request_batch__unpack"


def test_processor_builds_deserializes_and_rate_limits_generated_inputs():
    assert subprocess.run(["sh", "-c", "command -v protoc-c >/dev/null"]).returncode == 0, \
        "protobuf-c-compiler is not installed"

    wrapper = "/tmp/unpack_wrapper.c"
    rebuilt = "/tmp/verified_processor"
    with open(wrapper, "w") as f:
        f.write(r'''
#include <stdint.h>
#include <stdio.h>
#include "batch.pb-c.h"
RequestBatch *__real_request_batch__unpack(ProtobufCAllocator *, size_t, const uint8_t *);
RequestBatch *__wrap_request_batch__unpack(ProtobufCAllocator *a, size_t n, const uint8_t *d) {
    FILE *marker = fopen("/tmp/protobuf_unpack_called", "w");
    if (marker) { fputs("1", marker); fclose(marker); }
    return __real_request_batch__unpack(a, n, d);
}
''')

    command = [
        "gcc", "-std=c11", "-I", SRC,
        os.path.join(SRC, "processor.c"),
        os.path.join(SRC, "user.pb-c.c"),
        os.path.join(SRC, "request.pb-c.c"),
        os.path.join(SRC, "batch.pb-c.c"),
        wrapper, "-Wl,--wrap=request_batch__unpack", "-lprotobuf-c", "-o", rebuilt
    ]
    built = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert built.returncode == 0, "C sources do not build against protobuf-c:\n" + built.stderr.decode(errors="replace")

    base = 100000 + secrets.randbelow(500000)
    a = 1000 + secrets.randbelow(100000)
    b = a + 100001
    c = b + 100001
    rows1 = [
        (base + 1, a), (base + 2, b), (base + 3, a),
        (base + 4, a), (base + 5, c), (base + 6, b),
        (base + 7, b), (base + 8, c)
    ]
    run_case(PROCESSOR, rows1)

    base += 700000
    rows2 = [
        (base + 1, c), (base + 2, c), (base + 3, a),
        (base + 4, c), (base + 5, a), (base + 6, a),
        (base + 7, b)
    ]
    run_case(rebuilt, rows2, require_unpack_marker=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
