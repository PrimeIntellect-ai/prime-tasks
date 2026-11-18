#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import re
import secrets
import shlex
import shutil
import subprocess
import tempfile


def test_compute_sig_exists_and_executable():
    path = "/home/user/compute_sig.sh"
    assert os.path.isfile(path), f"{path} does not exist"
    assert os.access(path, os.X_OK), f"{path} is not executable"


def run_signature(path, data):
    with tempfile.NamedTemporaryFile(delete=False) as f:
        f.write(data)
        name = f.name
    try:
        result = subprocess.run([path, name], capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, f"{path} failed on execution: {result.stderr}"
        expected = sum(data) % 256
        assert result.stdout in (str(expected), str(expected) + "\n"), (
            f"Expected only signature {expected}, got {result.stdout!r}"
        )
        return result.stdout.strip()
    finally:
        os.remove(name)


def test_compute_sig_logic():
    path = "/home/user/compute_sig.sh"

    # Test case 1: "hello"
    with tempfile.NamedTemporaryFile(delete=False) as f1:
        f1.write(b"hello")
        f1_name = f1.name

    try:
        result = subprocess.run([path, f1_name], capture_output=True, text=True)
        assert result.returncode == 0, f"{path} failed on execution"
        assert result.stdout.strip() == "20", f"Expected signature 20 for 'hello', got {result.stdout.strip()}"
    finally:
        os.remove(f1_name)

    # Test case 2: "\x01\x02\xFF"
    with tempfile.NamedTemporaryFile(delete=False) as f2:
        f2.write(b"\x01\x02\xFF")
        f2_name = f2.name

    try:
        result = subprocess.run([path, f2_name], capture_output=True, text=True)
        assert result.returncode == 0, f"{path} failed on execution"
        assert result.stdout.strip() == "2", f"Expected signature 2 for '\\x01\\x02\\xFF', got {result.stdout.strip()}"
    finally:
        os.remove(f2_name)


def test_compute_sig_randomized_and_edge_cases():
    path = "/home/user/compute_sig.sh"
    cases = [b"", bytes(range(256)), b"\x00" * 513, b"\xff" * 257]
    for _ in range(24):
        cases.append(os.urandom(secrets.randbelow(4096) + 1))
    for data in cases:
        run_signature(path, data)


def read_varint(data, pos):
    value = 0
    shift = 0
    while True:
        assert pos < len(data), "Truncated protobuf descriptor"
        byte = data[pos]
        pos += 1
        value |= (byte & 0x7f) << shift
        if not (byte & 0x80):
            return value, pos
        shift += 7
        assert shift < 70, "Invalid protobuf varint"


def parse_wire(data):
    fields = {}
    pos = 0
    while pos < len(data):
        key, pos = read_varint(data, pos)
        number, wire = key >> 3, key & 7
        if wire == 0:
            value, pos = read_varint(data, pos)
        elif wire == 1:
            assert pos + 8 <= len(data)
            value, pos = data[pos:pos + 8], pos + 8
        elif wire == 2:
            length, pos = read_varint(data, pos)
            assert pos + length <= len(data)
            value, pos = data[pos:pos + length], pos + length
        elif wire == 5:
            assert pos + 4 <= len(data)
            value, pos = data[pos:pos + 4], pos + 4
        else:
            raise AssertionError(f"Unsupported wire type {wire}")
        fields.setdefault(number, []).append(value)
    return fields


def text_field(message, number):
    values = message.get(number, [])
    assert len(values) == 1
    return values[0].decode("utf-8")


def test_file_service_proto():
    path = "/home/user/file_service.proto"
    assert os.path.isfile(path), f"{path} does not exist"

    with open(path, "r") as f:
        content = f.read()

    # Check syntax
    assert re.search(r'syntax\s*=\s*"proto3"\s*;', content), "Missing or incorrect syntax declaration"

    # Check package
    assert re.search(r'package\s+fileorg\s*;', content), "Missing or incorrect package declaration"

    # Check service
    assert re.search(r'service\s+FileOrganizer\s*\{', content), "Missing FileOrganizer service"
    assert re.search(r'rpc\s+ComputeSignature\s*\(\s*FileRequest\s*\)\s*returns\s*\(\s*SignatureResponse\s*\)', content), "Missing or incorrect ComputeSignature rpc"

    # Check messages
    assert re.search(r'message\s+FileRequest\s*\{', content), "Missing FileRequest message"
    assert re.search(r'string\s+filepath\s*=\s*1\s*;', content), "Missing or incorrect filepath field in FileRequest"

    assert re.search(r'message\s+SignatureResponse\s*\{', content), "Missing SignatureResponse message"
    assert re.search(r'uint32\s+signature\s*=\s*1\s*;', content), "Missing or incorrect signature field in SignatureResponse"

    # Compile the file and inspect protoc's descriptor, so comments or malformed
    # text cannot satisfy the source regex checks.
    with tempfile.TemporaryDirectory() as td:
        descriptor_path = os.path.join(td, "service.desc")
        result = subprocess.run(
            ["protoc", "-I/home/user", f"--descriptor_set_out={descriptor_path}", "file_service.proto"],
            cwd="/home/user", capture_output=True, text=True, timeout=15
        )
        assert result.returncode == 0, f"Invalid protobuf: {result.stderr}"
        with open(descriptor_path, "rb") as f:
            descriptor_set = parse_wire(f.read())

    files = descriptor_set.get(1, [])
    assert len(files) == 1, "Expected one compiled proto file"
    file_desc = parse_wire(files[0])
    assert text_field(file_desc, 2) == "fileorg"
    assert text_field(file_desc, 12) == "proto3"

    messages = {}
    for raw in file_desc.get(4, []):
        message = parse_wire(raw)
        messages[text_field(message, 1)] = message
    assert "FileRequest" in messages
    assert "SignatureResponse" in messages

    request_fields = messages["FileRequest"].get(2, [])
    assert len(request_fields) == 1, "FileRequest must have a single field"
    request_field = parse_wire(request_fields[0])
    assert text_field(request_field, 1) == "filepath"
    assert request_field.get(3) == [1]
    assert request_field.get(5) == [9], "filepath must be a string"

    response_fields = messages["SignatureResponse"].get(2, [])
    assert len(response_fields) == 1, "SignatureResponse must have a single field"
    response_field = parse_wire(response_fields[0])
    assert text_field(response_field, 1) == "signature"
    assert response_field.get(3) == [1]
    assert response_field.get(5) == [13], "signature must be a uint32"

    services = [parse_wire(raw) for raw in file_desc.get(6, [])]
    organizer = next((s for s in services if text_field(s, 1) == "FileOrganizer"), None)
    assert organizer is not None, "Missing FileOrganizer service"
    methods = [parse_wire(raw) for raw in organizer.get(2, [])]
    method = next((m for m in methods if text_field(m, 1) == "ComputeSignature"), None)
    assert method is not None, "Missing ComputeSignature method"
    assert text_field(method, 2) == ".fileorg.FileRequest"
    assert text_field(method, 3) == ".fileorg.SignatureResponse"


def test_prop_test_exists_and_executable():
    path = "/home/user/prop_test.sh"
    assert os.path.isfile(path), f"{path} does not exist"
    assert os.access(path, os.X_OK), f"{path} is not executable"


def test_prop_test_execution():
    path = "/home/user/prop_test.sh"
    compute = "/home/user/compute_sig.sh"
    token = secrets.token_hex(12)
    backup = f"/home/user/.compute_sig.verifier.{token}"
    log = f"/tmp/prop_calls.{token}.jsonl"

    os.replace(compute, backup)
    wrapper = f'''#!/bin/bash
python3 - "$1" <<'PY'
import hashlib, json, os, sys
p = sys.argv[1]
with open(p, "rb") as f:
    data = f.read()
record = {{"path": os.path.realpath(p), "size": len(data), "sha256": hashlib.sha256(data).hexdigest(), "unique": len(set(data))}}
with open({log!r}, "a") as out:
    out.write(json.dumps(record) + "\\n")
PY
exec {shlex.quote(backup)} "$@"
'''
    try:
        with open(compute, "w") as f:
            f.write(wrapper)
        os.chmod(compute, 0o755)
        result = subprocess.run([path], capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, f"{path} exited with code {result.returncode}: {result.stderr}"
        assert "PASS" in result.stdout, f"Expected 'PASS' in output, got {result.stdout}"

        assert os.path.isfile(log), "Property test did not invoke compute_sig.sh"
        with open(log) as f:
            calls = [json.loads(line) for line in f if line.strip()]
        assert len(calls) == 10, f"Expected 10 signature computations (5 pairs), observed {len(calls)}"

        originals = []
        for iteration in range(5):
            first, second = calls[2 * iteration:2 * iteration + 2]
            assert first["path"] != second["path"], f"Iteration {iteration + 1} did not use a separate copy"
            assert 10 <= first["size"] <= 100, f"Iteration {iteration + 1} length is outside 10..100"
            assert second["size"] == first["size"]
            assert second["sha256"] == first["sha256"], f"Iteration {iteration + 1} inputs were not exact copies"
            assert first["unique"] >= 2, f"Iteration {iteration + 1} did not contain plausibly random bytes"
            originals.append(first["sha256"])
        assert len(set(originals)) == 5, "The five generated test files were not independently varied"
    finally:
        try:
            if os.path.exists(compute):
                os.remove(compute)
        finally:
            if os.path.exists(backup):
                os.replace(backup, compute)
            if os.path.exists(log):
                os.remove(log)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
