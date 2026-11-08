#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import importlib.util
import os
import re
import secrets
import shutil
import subprocess
import sys
import tempfile

from google.protobuf import descriptor_pb2

BASE = "/home/user/artifacts"
PROTO = os.path.join(BASE, "build_artifact.proto")
MIGRATE = os.path.join(BASE, "migrate.py")
LEGACY = os.path.join(BASE, "legacy_build.log")
OUT = os.path.join(BASE, "out")
COMPLETION = os.path.join(BASE, "completion.log")


def test_01_proto_file_exists_and_valid():
    assert os.path.isfile(PROTO), f"Missing proto file at {PROTO}"
    with open(PROTO, "r") as f:
        content = f.read()
    assert "proto3" in content, "Proto file must use proto3 syntax."
    assert "buildsystem" in content, "Proto file must use package 'buildsystem'."
    assert "enum BuildState" in content, "Proto file must define enum 'BuildState'."
    assert "message Artifact" in content, "Proto file must define message 'Artifact'."


def test_02_out_directory_and_bins():
    assert os.path.isdir(OUT), f"Directory {OUT} does not exist."
    for name in ["core_lib.bin", "ui_module.bin", "data_parser.bin"]:
        path = os.path.join(OUT, name)
        assert os.path.isfile(path), f"Missing binary file: {path}"


def check_completion_log():
    assert os.path.isfile(COMPLETION), f"Missing completion log at {COMPLETION}"
    with open(COMPLETION, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == 3, f"completion.log should have exactly 3 lines, found {len(lines)}"
    assert lines == sorted(lines), "completion.log lines are not sorted alphabetically by filename."
    for line in lines:
        match = re.match(r"^([\w_]+\.bin):\s*([a-fA-F0-9]{64})$", line)
        assert match, f"Line in completion.log does not match expected format '<name>.bin: <sha256>': {line}"
        filename, log_hash = match.groups()
        bin_path = os.path.join(OUT, filename)
        assert os.path.isfile(bin_path), f"File {filename} referenced in completion.log does not exist."
        with open(bin_path, "rb") as bf:
            actual_hash = hashlib.sha256(bf.read()).hexdigest()
        assert log_hash.lower() == actual_hash.lower(), \
            f"Hash mismatch for {filename}. Expected {actual_hash}, got {log_hash}"


def test_03_completion_log():
    check_completion_log()


def test_04_test_migrate_exists():
    test_file = os.path.join(BASE, "test_migrate.py")
    assert os.path.isfile(test_file), f"Missing test suite at {test_file}"
    assert os.path.isfile(MIGRATE), f"Missing migration script at {MIGRATE}"


def compile_and_load_submission_proto():
    generated = tempfile.mkdtemp(prefix="verifier_proto_")
    subprocess.run(
        ["protoc", f"--proto_path={BASE}", f"--python_out={generated}", PROTO],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    module_path = os.path.join(generated, "build_artifact_pb2.py")
    assert os.path.isfile(module_path), "The submitted schema did not compile to Python."
    spec = importlib.util.spec_from_file_location("verifier_build_artifact_pb2", module_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_05_compiled_schema_is_exact():
    pb2 = compile_and_load_submission_proto()
    file_proto = descriptor_pb2.FileDescriptorProto()
    file_proto.ParseFromString(pb2.DESCRIPTOR.serialized_pb)
    assert file_proto.syntax == "proto3"
    assert file_proto.package == "buildsystem"

    enums = {enum.name: enum for enum in file_proto.enum_type}
    assert "BuildState" in enums
    values = [(value.name, value.number) for value in enums["BuildState"].value]
    assert values == [
        ("UNKNOWN_STATE", 0), ("INIT", 1), ("COMPILED", 2),
        ("PACKAGED", 3), ("FAILED", 4),
    ]

    messages = {message.name: message for message in file_proto.message_type}
    assert "Artifact" in messages
    fields = messages["Artifact"].field
    actual = [(f.name, f.number, f.label, f.type, f.type_name) for f in fields]
    expected = [
        ("name", 1, f.LABEL_OPTIONAL, f.TYPE_STRING, ""),
        ("dependencies", 2, f.LABEL_REPEATED, f.TYPE_STRING, ""),
        ("artifact_hash", 3, f.LABEL_OPTIONAL, f.TYPE_STRING, ""),
        ("final_state", 4, f.LABEL_OPTIONAL, f.TYPE_ENUM, ".buildsystem.BuildState"),
    ]
    assert actual == expected


def run_migrate():
    subprocess.run(
        [sys.executable, MIGRATE], cwd=BASE, check=True, timeout=20,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )


def clean_out():
    if os.path.exists(OUT):
        shutil.rmtree(OUT)
    os.makedirs(OUT)


def read_artifacts(pb2, expected):
    actual_files = sorted(name for name in os.listdir(OUT) if name.endswith(".bin"))
    assert actual_files == sorted(name + ".bin" for name in expected)
    for name, wanted in expected.items():
        message = pb2.Artifact()
        path = os.path.join(OUT, name + ".bin")
        with open(path, "rb") as f:
            message.ParseFromString(f.read())
        assert message.name == name
        assert list(message.dependencies) == wanted["dependencies"]
        assert message.artifact_hash == wanted["artifact_hash"]
        assert message.final_state == wanted["final_state"]


def test_06_migrate_executes_and_serializes_correctly():
    pb2 = compile_and_load_submission_proto()
    with open(LEGACY, "rb") as f:
        original_log = f.read()

    token = secrets.token_hex(6)
    first = "dynamic_" + token
    second = "secondary_" + token
    custom_log = f"""BEGIN_ARTIFACT {first}
STATE INIT
DEPENDS dep_{token}_a
DEPENDS dep_{token}_b
HASH hash_{token}_one
STATE COMPILED
STATE PACKAGED
END_ARTIFACT

BEGIN_ARTIFACT {second}
STATE INIT
HASH hash_{token}_two
STATE FAILED
END_ARTIFACT
"""
    dynamic_expected = {
        first: {
            "dependencies": [f"dep_{token}_a", f"dep_{token}_b"],
            "artifact_hash": f"hash_{token}_one",
            "final_state": pb2.PACKAGED,
        },
        second: {
            "dependencies": [],
            "artifact_hash": f"hash_{token}_two",
            "final_state": pb2.FAILED,
        },
    }

    try:
        with open(LEGACY, "w") as f:
            f.write(custom_log)
        clean_out()
        run_migrate()
        read_artifacts(pb2, dynamic_expected)
    finally:
        with open(LEGACY, "wb") as f:
            f.write(original_log)
        clean_out()
        run_migrate()

    canonical_expected = {
        "core_lib": {
            "dependencies": ["glibc"],
            "artifact_hash": "7a8b9c0d",
            "final_state": pb2.PACKAGED,
        },
        "ui_module": {
            "dependencies": ["core_lib", "libpng"],
            "artifact_hash": "none",
            "final_state": pb2.FAILED,
        },
        "data_parser": {
            "dependencies": [],
            "artifact_hash": "ffff1111",
            "final_state": pb2.COMPILED,
        },
    }
    read_artifacts(pb2, canonical_expected)
    check_completion_log()
TEST_EOF

if (cd /home/user/artifacts && python3 -m pytest test_migrate.py -x --tb=short) \
   && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
