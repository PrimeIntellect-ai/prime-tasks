#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import os
import random
import re
import subprocess


def run(cmd, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 120)
    return subprocess.run(cmd, **kwargs)


def read_varint(data, pos):
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


def parse_wire_message(data):
    result = []
    pos = 0
    while pos < len(data):
        key, pos = read_varint(data, pos)
        field_number = key >> 3
        wire_type = key & 7
        if wire_type == 0:
            value, pos = read_varint(data, pos)
        elif wire_type == 1:
            assert pos + 8 <= len(data), "Truncated fixed64 field"
            value = data[pos:pos + 8]
            pos += 8
        elif wire_type == 2:
            length, pos = read_varint(data, pos)
            assert pos + length <= len(data), "Truncated length-delimited field"
            value = data[pos:pos + length]
            pos += length
        elif wire_type == 5:
            assert pos + 4 <= len(data), "Truncated fixed32 field"
            value = data[pos:pos + 4]
            pos += 4
        else:
            raise AssertionError("Unsupported wire type in protobuf descriptor")
        result.append((field_number, wire_type, value))
    return result


def values(message, number, wire_type=None):
    return [value for field, wire, value in message
            if field == number and (wire_type is None or wire == wire_type)]


def one(message, number, wire_type=None):
    found = values(message, number, wire_type)
    assert len(found) == 1, f"Expected exactly one descriptor field {number}, found {len(found)}"
    return found[0]


def test_protobuf_file():
    proto_path = "/home/user/aggregator.proto"
    assert os.path.exists(proto_path), f"{proto_path} does not exist."

    with open(proto_path, "r") as f:
        content = f.read()

    # Preserve the original source-level assertions.
    assert re.search(r'syntax\s*=\s*"proto3"\s*;', content), "Missing or incorrect syntax declaration."
    assert re.search(r'package\s+migration\s*;', content), "Missing or incorrect package declaration."
    assert "service Aggregator" in content, "Aggregator service not defined."
    assert re.search(r'rpc\s+Record\s*\(\s*RecordRequest\s*\)\s*returns\s*\(\s*RecordResponse\s*\)', content), "Record RPC not correctly defined."
    assert re.search(r'rpc\s+GetTop\s*\(\s*TopRequest\s*\)\s*returns\s*\(\s*TopResponse\s*\)', content), "GetTop RPC not correctly defined."
    assert "message RecordRequest" in content, "RecordRequest message not defined."
    assert "message RecordResponse" in content, "RecordResponse message not defined."
    assert "message TopRequest" in content, "TopRequest message not defined."
    assert "message TopResponse" in content, "TopResponse message not defined."

    descriptor_path = "/tmp/aggregator.desc"
    compile_res = run([
        "protoc", "--proto_path=/home/user",
        f"--descriptor_set_out={descriptor_path}",
        "aggregator.proto"
    ])
    assert compile_res.returncode == 0, f"aggregator.proto does not compile:\n{compile_res.stderr}"

    with open(descriptor_path, "rb") as f:
        descriptor_set = parse_wire_message(f.read())
    files = [parse_wire_message(raw) for raw in values(descriptor_set, 1, 2)]
    target = [fd for fd in files if one(fd, 1, 2).decode() == "aggregator.proto"]
    assert len(target) == 1, "Compiled descriptor for aggregator.proto was not found"
    fd = target[0]
    assert one(fd, 2, 2).decode() == "migration", "Compiled package must be migration"
    assert one(fd, 12, 2).decode() == "proto3", "Compiled schema must use proto3"

    messages = {}
    for raw in values(fd, 4, 2):
        msg = parse_wire_message(raw)
        messages[one(msg, 1, 2).decode()] = msg
    assert set(messages) == {"RecordRequest", "RecordResponse", "TopRequest", "TopResponse"}, "Schema must define the four required messages"

    # FieldDescriptorProto: name=1, number=3, label=4, type=5.
    expected_fields = {
        "RecordRequest": ("item", 1, 1, 9),       # optional string
        "RecordResponse": ("success", 1, 1, 8),  # optional bool
        "TopRequest": ("limit", 1, 1, 5),        # optional int32
        "TopResponse": ("items", 1, 3, 9),       # repeated string
    }
    for message_name, expected in expected_fields.items():
        field_blobs = values(messages[message_name], 2, 2)
        assert len(field_blobs) == 1, f"{message_name} must contain exactly one field"
        field = parse_wire_message(field_blobs[0])
        actual = (
            one(field, 1, 2).decode(),
            one(field, 3, 0),
            one(field, 4, 0),
            one(field, 5, 0),
        )
        assert actual == expected, f"Incorrect field declaration in {message_name}: {actual}"

    services = {}
    for raw in values(fd, 6, 2):
        service = parse_wire_message(raw)
        services[one(service, 1, 2).decode()] = service
    assert set(services) == {"Aggregator"}, "Schema must define the Aggregator service"
    methods = {}
    for raw in values(services["Aggregator"], 2, 2):
        method = parse_wire_message(raw)
        methods[one(method, 1, 2).decode()] = (
            one(method, 2, 2).decode(), one(method, 3, 2).decode()
        )
    assert methods == {
        "Record": (".migration.RecordRequest", ".migration.RecordResponse"),
        "GetTop": (".migration.TopRequest", ".migration.TopResponse"),
    }, f"Incorrect compiled RPC definitions: {methods}"


def test_cpp_frequency_store():
    header_path = "/home/user/FrequencyStore.h"
    cpp_path = "/home/user/FrequencyStore.cpp"
    assert os.path.exists(header_path), f"{header_path} does not exist."
    assert os.path.exists(cpp_path), f"{cpp_path} does not exist."

    # Preserve the original fixed behavioral checks.
    fixed_code = r'''
    #include "/home/user/FrequencyStore.h"
    #include <iostream>
    int main() {
        FrequencyStore store;
        store.record("banana"); store.record("apple"); store.record("banana");
        store.record("cherry"); store.record("apple"); store.record("apple");
        auto top = store.get_top(2);
        if (top.size() != 2) return 1;
        if (top[0] != "apple") return 2;
        if (top[1] != "banana") return 3;
        FrequencyStore store2;
        store2.record("zebra"); store2.record("alpha");
        auto top2 = store2.get_top(2);
        if (top2.size() != 2) return 4;
        if (top2[0] != "alpha") return 5;
        if (top2[1] != "zebra") return 6;
        return 0;
    }
    '''
    with open("/tmp/test_runner.cpp", "w") as f:
        f.write(fixed_code)
    compile_res = run(["g++", "-std=c++11", "/tmp/test_runner.cpp", cpp_path, "-o", "/tmp/test_runner"])
    assert compile_res.returncode == 0, f"Failed to compile FrequencyStore.cpp:\n{compile_res.stderr}"
    run_res = run(["/tmp/test_runner"])
    assert run_res.returncode == 0, f"C++ logic test failed with return code {run_res.returncode}. Ensure sorting logic is correct."

    # Generate fresh datasets and derive their answers independently.
    rng = random.SystemRandom()
    cases = []
    for case_index in range(14):
        item_count = rng.randint(3, 10)
        names = [f"item_{case_index}_{rng.randrange(10**9):09d}" for _ in range(item_count)]
        records = []
        for name in names:
            records.extend([name] * rng.randint(1, 8))
        rng.shuffle(records)
        limit = rng.randint(0, item_count + 3)
        counts = collections.Counter(records)
        expected = sorted(counts, key=lambda s: (-counts[s], s))[:limit]
        cases.append((records, limit, expected))

    source = [
        '#include "/home/user/FrequencyStore.h"',
        '#include <string>',
        '#include <vector>',
        'int main() {'
    ]
    for index, (records, limit, expected) in enumerate(cases):
        source.append('  {')
        source.append('    FrequencyStore store;')
        for item in records:
            source.append(f'    store.record({json.dumps(item)});')
        source.append(f'    std::vector<std::string> expected = {{{", ".join(json.dumps(x) for x in expected)}}};')
        source.append(f'    if (store.get_top({limit}) != expected) return {20 + index};')
        source.append('  }')
    source.append('  return 0;')
    source.append('}')
    with open("/tmp/random_runner.cpp", "w") as f:
        f.write("\n".join(source))
    compile_res = run(["g++", "-std=c++11", "/tmp/random_runner.cpp", cpp_path, "-o", "/tmp/random_runner"])
    assert compile_res.returncode == 0, f"Failed to compile randomized FrequencyStore test:\n{compile_res.stderr}"
    run_res = run(["/tmp/random_runner"])
    assert run_res.returncode == 0, f"FrequencyStore failed a generated dataset (code {run_res.returncode})"


def test_rust_client_output():
    project = "/home/user/rust_client"
    source = os.path.join(project, "src/main.rs")
    assert os.path.isfile(source), "Rust client src/main.rs does not exist"
    assert os.path.isfile(os.path.join(project, "Cargo.toml")), "Rust client Cargo.toml does not exist"

    expected_lines = [
        "Recorded: error",
        "Successfully processed log: error",
        "Recorded: warning",
        "Successfully processed log: warning",
        "Recorded: error",
        "Successfully processed log: error",
        "Recorded: info",
        "Successfully processed log: info",
    ]

    # Compile main.rs itself, preventing a Cargo target redirection from hiding a broken source file.
    rustc_res = run(["rustc", "--edition=2021", source, "-o", "/tmp/rust_client_main"])
    assert rustc_res.returncode == 0, f"src/main.rs does not compile:\n{rustc_res.stderr}"
    direct_res = run(["/tmp/rust_client_main"])
    assert direct_res.returncode == 0, f"Compiled Rust client failed:\n{direct_res.stderr}"
    assert direct_res.stdout.splitlines() == expected_lines, "Rust client produced incorrect output"

    # Execute the requested Cargo command afresh and regenerate the required log.
    log_path = "/home/user/rust_output.log"
    if os.path.exists(log_path):
        os.remove(log_path)
    cargo_res = run(["cargo", "run", "--quiet"], cwd=project)
    assert cargo_res.returncode == 0, f"cargo run failed:\n{cargo_res.stderr}"
    with open(log_path, "w") as f:
        f.write(cargo_res.stdout)
    assert os.path.exists(log_path), f"{log_path} does not exist. Did you run the Rust client?"

    with open(log_path, "r") as f:
        content = f.read()
    # Preserve all original substring assertions.
    for line in expected_lines:
        assert line in content, f"Expected log line '{line}' not found in rust_output.log. Ensure the Rust bug is fixed properly."
    assert content.splitlines() == expected_lines, "rust_output.log must be the actual output of the fixed client in the required order"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
