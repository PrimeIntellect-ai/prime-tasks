#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib
import os
import secrets
import stat
import subprocess
import sys
import tempfile

TELEMETRY_DIR = "/home/user/telemetry"
PROTO_FILE = os.path.join(TELEMETRY_DIR, "telemetry.proto")
MAKEFILE = os.path.join(TELEMETRY_DIR, "Makefile")
C_FILE = os.path.join(TELEMETRY_DIR, "verify_checksum.c")
BIN_FILE = os.path.join(TELEMETRY_DIR, "verify_checksum")
SCRIPT_FILE = os.path.join(TELEMETRY_DIR, "generate_test_data.py")
PB2_FILE = os.path.join(TELEMETRY_DIR, "telemetry_pb2.py")
PB2_GRPC_FILE = os.path.join(TELEMETRY_DIR, "telemetry_pb2_grpc.py")
PAYLOAD_FILE = os.path.join(TELEMETRY_DIR, "test_payload.bin")
RESULT_FILE = os.path.join(TELEMETRY_DIR, "pipeline_result.txt")
EXPECTED_BYTES = b'\x08\x65\x12\x06ONLINE'


def test_telemetry_proto_patched():
    assert os.path.isfile(PROTO_FILE), f"File {PROTO_FILE} is missing."
    with open(PROTO_FILE, "r") as f:
        content = f.read()
    assert "string status = 2;" in content, "telemetry.proto is missing the 'status' field. Was the patch applied?"
    assert "service TelemetryService" in content, "telemetry.proto is missing the 'TelemetryService'. Was the patch applied?"

    with tempfile.TemporaryDirectory() as out_dir:
        proc = subprocess.run(
            [sys.executable, "-m", "grpc_tools.protoc", f"-I{TELEMETRY_DIR}",
             f"--python_out={out_dir}", f"--grpc_python_out={out_dir}", PROTO_FILE],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
        )
        assert proc.returncode == 0, f"Updated telemetry.proto does not compile with grpcio-tools: {proc.stderr}"
        assert os.path.isfile(os.path.join(out_dir, "telemetry_pb2.py"))
        assert os.path.isfile(os.path.join(out_dir, "telemetry_pb2_grpc.py"))


def test_generated_protobuf_modules():
    assert os.path.isfile(PB2_FILE), "telemetry_pb2.py is missing."
    assert os.path.isfile(PB2_GRPC_FILE), "telemetry_pb2_grpc.py is missing."

    sys.path.insert(0, TELEMETRY_DIR)
    try:
        importlib.invalidate_caches()
        sys.modules.pop("telemetry_pb2", None)
        sys.modules.pop("telemetry_pb2_grpc", None)
        pb2 = importlib.import_module("telemetry_pb2")
        importlib.import_module("telemetry_pb2_grpc")
        message = pb2.DESCRIPTOR.message_types_by_name["DeviceStatus"]
        assert message.fields_by_name["device_id"].number == 1
        assert message.fields_by_name["status"].number == 2
        service = pb2.DESCRIPTOR.services_by_name["TelemetryService"]
        method = service.methods_by_name["SendStatus"]
        assert method.input_type.full_name == message.full_name
        assert method.output_type.full_name == message.full_name
    finally:
        sys.path.remove(TELEMETRY_DIR)


def test_c_code_and_makefile_fixed_and_builds():
    assert os.path.isfile(C_FILE), f"File {C_FILE} is missing."
    with open(C_FILE, "r") as f:
        content = f.read()
    assert 'printf("Checksum: %d\\n", sum);' in content, "verify_checksum.c is still missing the semicolon."
    assert os.path.isfile(MAKEFILE), f"File {MAKEFILE} is missing."

    assert os.path.isfile(BIN_FILE), f"Executable {BIN_FILE} is missing. Did you run make?"
    st = os.stat(BIN_FILE)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {BIN_FILE} is not executable."

    os.remove(BIN_FILE)
    proc = subprocess.run(["make"], cwd=TELEMETRY_DIR, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True, timeout=30)
    assert proc.returncode == 0, f"Makefile does not successfully build verify_checksum:\n{proc.stdout}\n{proc.stderr}"
    assert os.path.isfile(BIN_FILE), "make did not recreate verify_checksum."
    assert os.access(BIN_FILE, os.X_OK), "Rebuilt verify_checksum is not executable."
    with open(BIN_FILE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "verify_checksum is not a native ELF executable."


def test_verify_checksum_on_derived_inputs():
    for length in (0, 1, 17, 257, 4096):
        data = secrets.token_bytes(length)
        with tempfile.NamedTemporaryFile(dir=TELEMETRY_DIR, delete=False) as f:
            f.write(data)
            path = f.name
        try:
            proc = subprocess.run([BIN_FILE, path], cwd=TELEMETRY_DIR,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  text=True, timeout=10)
            assert proc.returncode == 0, f"verify_checksum failed on a valid input: {proc.stderr}"
            assert proc.stdout.strip() == f"Checksum: {sum(data)}", \
                f"verify_checksum returned the wrong checksum for a generated input: {proc.stdout!r}"
        finally:
            os.unlink(path)


def test_payload_generated_by_script():
    assert os.path.isfile(SCRIPT_FILE), f"File {SCRIPT_FILE} is missing."
    with open(SCRIPT_FILE, "r") as f:
        source = f.read()
    tree = ast.parse(source, SCRIPT_FILE)

    module_aliases = set()
    ctor_aliases = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "telemetry_pb2":
                    module_aliases.add(alias.asname or alias.name)
        elif isinstance(node, ast.ImportFrom) and node.module == "telemetry_pb2":
            for alias in node.names:
                if alias.name == "DeviceStatus":
                    ctor_aliases.add(alias.asname or alias.name)

    calls_device_status = False
    has_device_id = False
    has_status = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name) and node.func.id in ctor_aliases:
                calls_device_status = True
            if (isinstance(node.func, ast.Attribute) and node.func.attr == "DeviceStatus"
                    and isinstance(node.func.value, ast.Name)
                    and node.func.value.id in module_aliases):
                calls_device_status = True
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Attribute):
            if node.targets[0].attr == "device_id" and isinstance(node.value, ast.Constant) and node.value.value == 101:
                has_device_id = True
            if node.targets[0].attr == "status" and isinstance(node.value, ast.Constant) and node.value.value == "ONLINE":
                has_status = True

    assert module_aliases or ctor_aliases, "generate_test_data.py does not import telemetry_pb2."
    assert calls_device_status, "generate_test_data.py does not construct a generated DeviceStatus message."
    assert has_device_id and has_status, "generate_test_data.py does not assign the required DeviceStatus values."

    assert os.path.isfile(PAYLOAD_FILE), f"File {PAYLOAD_FILE} is missing. Did you run generate_test_data.py?"
    with open(PAYLOAD_FILE, "rb") as f:
        original_content = f.read()
    assert original_content == EXPECTED_BYTES, \
        f"test_payload.bin does not contain the correct serialized data. Expected {EXPECTED_BYTES.hex()}, got {original_content.hex()}."

    os.remove(PAYLOAD_FILE)
    proc = subprocess.run([sys.executable, SCRIPT_FILE], cwd=TELEMETRY_DIR,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30)
    assert proc.returncode == 0, f"generate_test_data.py failed when executed: {proc.stderr}"
    assert os.path.isfile(PAYLOAD_FILE), "generate_test_data.py did not recreate test_payload.bin."
    with open(PAYLOAD_FILE, "rb") as f:
        generated_content = f.read()
    assert generated_content == EXPECTED_BYTES, \
        f"generate_test_data.py serialized incorrect data. Expected {EXPECTED_BYTES.hex()}, got {generated_content.hex()}."


def test_pipeline_result():
    assert os.path.isfile(RESULT_FILE), f"File {RESULT_FILE} is missing. Did you run the verify_checksum utility?"
    with open(RESULT_FILE, "r") as f:
        content = f.read().strip()

    expected_sum = sum(EXPECTED_BYTES)
    expected_output = f"Checksum: {expected_sum}"
    assert expected_output in content, \
        f"pipeline_result.txt does not contain the correct output. Expected '{expected_output}', got '{content}'."

    proc = subprocess.run([BIN_FILE, PAYLOAD_FILE], cwd=TELEMETRY_DIR,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10)
    assert proc.returncode == 0, f"verify_checksum failed on test_payload.bin: {proc.stderr}"
    assert proc.stdout.strip() == expected_output, \
        f"Executing verify_checksum on test_payload.bin produced {proc.stdout!r}, expected '{expected_output}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
