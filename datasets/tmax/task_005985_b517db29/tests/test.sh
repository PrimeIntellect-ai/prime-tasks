#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import pathlib
import struct
import subprocess
import tempfile

from google.protobuf import descriptor_pb2

SERVICE = pathlib.Path("/home/user/analytics_service")
PROTO = SERVICE / "schema.proto"
EXE = SERVICE / "analytics_engine"
RESULT = pathlib.Path("/home/user/result.txt")
GENERATED_SAMPLES = [10.5, 12.0, 15.5, 14.0, 18.5, 13.5]


def expected_lines(samples):
    mean = sum(samples) / len(samples)
    variance = sum((x - mean) ** 2 for x in samples) / (len(samples) - 1) if len(samples) > 1 else 0.0
    return [f"Mean: {mean:.6f}", f"Variance: {variance:.6f}"]


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def varint(value):
    out = bytearray()
    while value >= 0x80:
        out.append((value & 0x7f) | 0x80)
        value >>= 7
    out.append(value)
    return bytes(out)


def serialize_batch(samples):
    if not samples:
        return b""
    payload = b"".join(struct.pack("<d", value) for value in samples)
    return b"\x0a" + varint(len(payload)) + payload


def run_engine(samples, memory_check=True):
    with tempfile.NamedTemporaryFile() as batch:
        batch.write(serialize_batch(samples))
        batch.flush()
        command = [str(EXE), batch.name]
        if memory_check:
            command = [
                "valgrind",
                "--quiet",
                "--leak-check=full",
                "--show-leak-kinds=definite,indirect,possible",
                "--errors-for-leak-kinds=definite,indirect,possible",
                "--error-exitcode=99",
            ] + command
        return subprocess.run(command, cwd=SERVICE, text=True, capture_output=True, timeout=20)


def test_schema_proto_exists():
    proto_path = "/home/user/analytics_service/schema.proto"
    assert os.path.exists(proto_path), f"File {proto_path} is missing."

    with open(proto_path, "r") as f:
        content = f.read()
    assert "proto3" in content, "schema.proto must use proto3 syntax."
    assert "message DataBatch" in content, "schema.proto must define a DataBatch message."
    assert "repeated double" in content, "schema.proto must contain a repeated double field."

    with tempfile.NamedTemporaryFile() as descriptor_file:
        subprocess.run(
            ["protoc", f"--descriptor_set_out={descriptor_file.name}", "schema.proto"],
            cwd=SERVICE,
            check=True,
            text=True,
            capture_output=True,
            timeout=20,
        )
        descriptor_file.seek(0)
        descriptor_set = descriptor_pb2.FileDescriptorSet.FromString(descriptor_file.read())

    schema = next((f for f in descriptor_set.file if f.name == "schema.proto"), None)
    assert schema is not None
    assert schema.syntax == "proto3", "schema.proto must use proto3 syntax."
    batch = next((m for m in schema.message_type if m.name == "DataBatch"), None)
    assert batch is not None, "schema.proto must define a DataBatch message."
    assert len(batch.field) == 1, "DataBatch must contain a single field."
    field = batch.field[0]
    assert field.name == "samples"
    assert field.number == 1
    assert field.label == field.LABEL_REPEATED
    assert field.type == field.TYPE_DOUBLE


def test_result_txt_content():
    result_path = "/home/user/result.txt"
    assert os.path.exists(result_path), f"File {result_path} is missing. Did you run the analytics_engine and redirect output?"

    lines = read_nonempty_lines(result_path)
    assert len(lines) == 2, f"Expected exactly 2 lines of output in {result_path}, but found {len(lines)}."

    expected_mean, expected_variance = expected_lines(GENERATED_SAMPLES)
    assert lines[0] == expected_mean, f"First line of {result_path} was '{lines[0]}', expected '{expected_mean}'."
    assert lines[1] == expected_variance, f"Second line of {result_path} was '{lines[1]}', expected '{expected_variance}'."


def test_makefile_builds_executable():
    for artifact in SERVICE.glob("*.o"):
        artifact.unlink()
    for name in ("analytics_engine", "schema.pb-c.c", "schema.pb-c.h"):
        path = SERVICE / name
        if path.exists() or path.is_symlink():
            path.unlink()

    completed = subprocess.run(
        ["make"], cwd=SERVICE, text=True, capture_output=True, timeout=30
    )
    assert completed.returncode == 0, completed.stdout + completed.stderr
    assert (SERVICE / "schema.pb-c.c").is_file(), "make did not generate schema.pb-c.c with protoc-c."
    assert (SERVICE / "schema.pb-c.h").is_file(), "make did not generate schema.pb-c.h with protoc-c."


def test_executable_exists():
    exe_path = "/home/user/analytics_service/analytics_engine"
    assert os.path.exists(exe_path), f"Executable {exe_path} is missing. Did the Makefile run successfully?"
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable."
    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "analytics_engine must be a compiled executable."


def test_generated_pipeline_data():
    subprocess.run(
        ["protoc", "--python_out=.", "schema.proto"],
        cwd=SERVICE,
        check=True,
        text=True,
        capture_output=True,
        timeout=20,
    )
    subprocess.run(
        ["python3", "generate_test_data.py"],
        cwd=SERVICE,
        check=True,
        text=True,
        capture_output=True,
        timeout=20,
    )
    completed = subprocess.run(
        [str(EXE), "test_batch.bin"],
        cwd=SERVICE,
        text=True,
        capture_output=True,
        timeout=20,
    )
    assert completed.returncode == 0, completed.stderr
    assert completed.stdout.splitlines() == expected_lines(GENERATED_SAMPLES)


def test_engine_computation_and_memory_safety():
    cases = [
        [1.0, 2.0, 3.0, 4.0],
        [-7.25, 0.5, 3.75, 11.0, 19.5],
        [42.125],
    ]
    for samples in cases:
        completed = run_engine(samples)
        assert completed.returncode == 0, completed.stderr
        assert completed.stdout.splitlines() == expected_lines(samples)


def test_empty_batch_is_safe_and_has_zero_variance():
    completed = run_engine([])
    assert completed.returncode == 0, completed.stderr
    lines = completed.stdout.splitlines()
    assert len(lines) == 2
    assert lines[0].startswith("Mean: ")
    mean = float(lines[0].split(":", 1)[1].strip())
    assert math.isfinite(mean)
    assert lines[1] == "Variance: 0.000000"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
