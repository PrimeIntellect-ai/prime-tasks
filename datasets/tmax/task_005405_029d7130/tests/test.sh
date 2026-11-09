#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import re
import shutil
import subprocess
import sys
import tempfile
import textwrap

import pytest
from google.protobuf import descriptor_pb2

BUILD_DIR = "/home/user/build_system"
SCHEMA_FILE = os.path.join(BUILD_DIR, "schema.proto")
BUILD_SCRIPT = os.path.join(BUILD_DIR, "build.sh")
PAYLOAD_FILE = os.path.join(BUILD_DIR, "payload.bin")
BENCH_LOG = os.path.join(BUILD_DIR, "bench.log")
PB2_FILE = os.path.join(BUILD_DIR, "schema_pb2.py")
SERIALIZE_FILE = os.path.join(BUILD_DIR, "serialize.py")
DESERIALIZE_FILE = os.path.join(BUILD_DIR, "deserialize.py")


def run_checked(command, **kwargs):
    try:
        return subprocess.run(command, check=True, timeout=30, **kwargs)
    except subprocess.TimeoutExpired:
        pytest.fail(f"Command timed out: {command}")
    except subprocess.CalledProcessError as exc:
        stdout = getattr(exc, "stdout", "") or ""
        stderr = getattr(exc, "stderr", "") or ""
        pytest.fail(f"Command failed: {command}\nstdout:\n{stdout}\nstderr:\n{stderr}")


def test_schema_proto_exists_and_valid():
    assert os.path.exists(SCHEMA_FILE), f"Schema file not found at {SCHEMA_FILE}"
    with open(SCHEMA_FILE, "r") as f:
        content = f.read()

    # Preserve the original textual assertions.
    assert "syntax" in content and "proto3" in content, "Schema must use proto3 syntax."
    assert "message ConfigRequest" in content, "Schema missing 'message ConfigRequest'."
    assert "message ConfigResponse" in content, "Schema missing 'message ConfigResponse'."
    assert "service Configurator" in content, "Schema missing 'service Configurator'."
    assert "rpc UpdateConfig" in content, "Schema missing 'rpc UpdateConfig'."

    # Compile the schema and inspect protoc's descriptor rather than trusting text.
    with tempfile.TemporaryDirectory() as tmp:
        descriptor_path = os.path.join(tmp, "schema.desc")
        run_checked(
            [
                "protoc",
                f"--descriptor_set_out={descriptor_path}",
                "--include_imports",
                f"--proto_path={BUILD_DIR}",
                SCHEMA_FILE,
            ],
            capture_output=True,
            text=True,
        )
        descriptor_set = descriptor_pb2.FileDescriptorSet()
        with open(descriptor_path, "rb") as f:
            descriptor_set.ParseFromString(f.read())

    schema_desc = next((f for f in descriptor_set.file if f.name == "schema.proto"), None)
    assert schema_desc is not None, "protoc did not produce a descriptor for schema.proto"
    assert schema_desc.syntax == "proto3", "schema.proto must use proto3 syntax"

    messages = {message.name: message for message in schema_desc.message_type}
    assert "ConfigRequest" in messages
    assert "ConfigResponse" in messages

    request_fields = list(messages["ConfigRequest"].field)
    assert [(f.name, f.number, f.type) for f in request_fields] == [
        ("key", 1, descriptor_pb2.FieldDescriptorProto.TYPE_STRING),
        ("value", 2, descriptor_pb2.FieldDescriptorProto.TYPE_INT32),
    ], "ConfigRequest must contain exactly string key=1 and int32 value=2"

    response_fields = list(messages["ConfigResponse"].field)
    assert [(f.name, f.number, f.type) for f in response_fields] == [
        ("success", 1, descriptor_pb2.FieldDescriptorProto.TYPE_BOOL),
    ], "ConfigResponse must contain exactly bool success=1"

    services = [service for service in schema_desc.service if service.name == "Configurator"]
    assert len(services) == 1, "Schema must define one Configurator service"
    assert len(services[0].method) == 1, "Configurator must contain a single RPC"
    method = services[0].method[0]
    prefix = f".{schema_desc.package}." if schema_desc.package else "."
    assert method.name == "UpdateConfig"
    assert method.input_type == prefix + "ConfigRequest"
    assert method.output_type == prefix + "ConfigResponse"
    assert not method.client_streaming and not method.server_streaming


def test_build_script_exists_and_executable():
    assert os.path.exists(BUILD_SCRIPT), f"Build script not found at {BUILD_SCRIPT}"
    assert os.access(BUILD_SCRIPT, os.X_OK), f"Build script at {BUILD_SCRIPT} is not executable."

    with open(BUILD_SCRIPT, "r") as f:
        content = f.read()

    assert content.startswith("#!") and "bash" in content.splitlines()[0], "build.sh must be a Bash script"
    assert re.search(r"\bprotoc\b[^\n]*schema\.proto", content), "build.sh must invoke protoc on schema.proto"
    assert re.search(r"\bprotoc\b[^\n]*--python_out(?:=|\s)", content), "protoc must generate Python bindings"
    assert re.search(r"cat[^\n]*<<[^\n]*serialize\.py", content), "serialize.py must be generated with a Here-Doc"
    assert re.search(r"cat[^\n]*<<[^\n]*deserialize\.py", content), "deserialize.py must be generated with a Here-Doc"
    assert re.search(r"python3[^\n]*serialize\.py", content), "build.sh must execute serialize.py"
    assert re.search(r"\btime\b[^\n]*python3[^\n]*deserialize\.py", content), "build.sh must benchmark deserialize.py with time"
    assert re.search(r"2\s*>[^\n]*bench\.log", content), "time standard error must be redirected to bench.log"


def test_execute_build_pipeline_from_clean_outputs():
    # Existing fabricated outputs cannot satisfy this test: the submitted build
    # script must regenerate every requested artifact itself.
    for path in (PB2_FILE, SERIALIZE_FILE, DESERIALIZE_FILE, PAYLOAD_FILE, BENCH_LOG):
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.remove(path)
    shutil.rmtree(os.path.join(BUILD_DIR, "__pycache__"), ignore_errors=True)

    run_checked(
        [BUILD_SCRIPT],
        cwd=BUILD_DIR,
        capture_output=True,
        text=True,
    )

    for path in (PB2_FILE, SERIALIZE_FILE, DESERIALIZE_FILE, PAYLOAD_FILE, BENCH_LOG):
        assert os.path.isfile(path), f"build.sh did not generate {path}"


def test_generated_scripts_are_real_and_executable():
    with open(SERIALIZE_FILE, "r") as f:
        serialize_source = f.read()
    with open(DESERIALIZE_FILE, "r") as f:
        deserialize_source = f.read()

    try:
        serialize_tree = ast.parse(serialize_source)
        deserialize_tree = ast.parse(deserialize_source)
    except SyntaxError as exc:
        pytest.fail(f"Generated Python script is invalid: {exc}")

    serialize_calls = [n for n in ast.walk(serialize_tree) if isinstance(n, ast.Call)]
    assert any(isinstance(n.func, ast.Attribute) and n.func.attr == "ConfigRequest" for n in serialize_calls), \
        "serialize.py must instantiate schema_pb2.ConfigRequest"
    assert any(isinstance(n.func, ast.Attribute) and n.func.attr == "SerializeToString" for n in serialize_calls), \
        "serialize.py must serialize the request"
    serialize_constants = {n.value for n in ast.walk(serialize_tree) if isinstance(n, ast.Constant)}
    assert "max_workers" in serialize_constants and 42 in serialize_constants
    assert PAYLOAD_FILE in serialize_constants, "serialize.py must write the requested absolute payload path"

    matching_loops = []
    for node in ast.walk(deserialize_tree):
        if not isinstance(node, ast.For) or not isinstance(node.iter, ast.Call):
            continue
        call = node.iter
        if isinstance(call.func, ast.Name) and call.func.id == "range" and len(call.args) == 1:
            if isinstance(call.args[0], ast.Constant) and call.args[0].value == 1000:
                has_parse = any(
                    isinstance(child, ast.Call)
                    and isinstance(child.func, ast.Attribute)
                    and child.func.attr == "ParseFromString"
                    for child in ast.walk(node)
                )
                has_break = any(isinstance(child, ast.Break) for child in ast.walk(node))
                if has_parse and not has_break:
                    matching_loops.append(node)
    assert matching_loops, "deserialize.py must parse a ConfigRequest in a range(1000) loop"
    deserialize_constants = {n.value for n in ast.walk(deserialize_tree) if isinstance(n, ast.Constant)}
    assert PAYLOAD_FILE in deserialize_constants, "deserialize.py must read the requested absolute payload path"

    # Execute serialize.py independently, proving that it—not build.sh fabrication—creates the payload.
    os.remove(PAYLOAD_FILE)
    run_checked(["python3", SERIALIZE_FILE], cwd=BUILD_DIR, capture_output=True, text=True)
    assert os.path.isfile(PAYLOAD_FILE), "serialize.py did not create payload.bin"

    # Execute deserialize.py against an instrumented schema module. This derives
    # the expected input from the generated payload and verifies exactly 1000 parses.
    with open(PAYLOAD_FILE, "rb") as f:
        expected_payload = f.read()
    count_file = os.path.join(BUILD_DIR, ".deserialize_count")
    backup_pb2 = PB2_FILE + ".verifier_backup"
    if os.path.exists(count_file):
        os.remove(count_file)
    shutil.rmtree(os.path.join(BUILD_DIR, "__pycache__"), ignore_errors=True)
    os.replace(PB2_FILE, backup_pb2)
    stub = textwrap.dedent(f"""
        import atexit
        count = 0
        expected = {expected_payload!r}
        output = {count_file!r}

        class ConfigRequest:
            def __init__(self, *args, **kwargs):
                pass
            def ParseFromString(self, data):
                global count
                if data != expected:
                    raise AssertionError("deserialize.py parsed data other than payload.bin")
                count += 1

        @atexit.register
        def save_count():
            with open(output, "w") as f:
                f.write(str(count))
    """)
    try:
        with open(PB2_FILE, "w") as f:
            f.write(stub)
        run_checked(["python3", DESERIALIZE_FILE], cwd=BUILD_DIR, capture_output=True, text=True)
    finally:
        if os.path.exists(PB2_FILE):
            os.remove(PB2_FILE)
        os.replace(backup_pb2, PB2_FILE)
        shutil.rmtree(os.path.join(BUILD_DIR, "__pycache__"), ignore_errors=True)

    assert os.path.isfile(count_file), "deserialize.py did not instantiate the generated request type"
    with open(count_file, "r") as f:
        parse_count = int(f.read())
    os.remove(count_file)
    assert parse_count == 1000, f"deserialize.py parsed the payload {parse_count} times instead of 1000"


def test_payload_exists():
    assert os.path.exists(PAYLOAD_FILE), f"Payload file not found at {PAYLOAD_FILE}"


def test_bench_log_exists_and_contains_timing():
    assert os.path.exists(BENCH_LOG), f"Benchmark log not found at {BENCH_LOG}"
    with open(BENCH_LOG, "r") as f:
        content = f.read().lower()

    # Preserve the original assertion and additionally require a recognizable
    # shell-time or GNU-time output format.
    has_timing = "real" in content or "user" in content or "sys" in content
    assert has_timing, f"Benchmark log {BENCH_LOG} does not appear to contain 'time' command output."
    posix_time = re.search(r"(?m)^\s*(real|user|sys)\s+\d", content)
    gnu_time = re.search(r"\d+(?:\.\d+)?user\s+\d+(?:\.\d+)?system", content)
    assert posix_time or gnu_time, "bench.log does not contain recognizable output from time"


def test_payload_content():
    assert os.path.exists(PAYLOAD_FILE), "Payload file missing, cannot verify content."
    assert os.path.exists(PB2_FILE), f"Generated python bindings not found at {PB2_FILE}"

    sys.path.insert(0, BUILD_DIR)
    try:
        sys.modules.pop("schema_pb2", None)
        import schema_pb2

        with open(PAYLOAD_FILE, "rb") as f:
            data = f.read()

        req = schema_pb2.ConfigRequest()
        consumed = req.ParseFromString(data)
        assert consumed == len(data), "payload.bin contains trailing or invalid protobuf data"
        assert getattr(req, "key", None) == "max_workers", f"Expected key 'max_workers', got {getattr(req, 'key', None)}"
        assert getattr(req, "value", None) == 42, f"Expected value 42, got {getattr(req, 'value', None)}"
    except ImportError:
        pytest.fail("Failed to import schema_pb2. Make sure it was generated correctly.")
    except Exception as e:
        pytest.fail(f"Failed to parse payload.bin or verify contents: {e}")
    finally:
        sys.modules.pop("schema_pb2", None)
        sys.path.pop(0)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
