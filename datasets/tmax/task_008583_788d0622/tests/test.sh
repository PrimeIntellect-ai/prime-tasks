#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import time
import pytest

WORKSPACE_DIR = "/home/user/workspace"
PROTO_PATH = os.path.join(WORKSPACE_DIR, "workload.proto")
BUILD_PATH = os.path.join(WORKSPACE_DIR, "build.sh")
VALIDATOR_PATH = os.path.join(WORKSPACE_DIR, "validator")
LOG_PATH = os.path.join(WORKSPACE_DIR, "validation.log")


def write_varint(value):
    if value < 0:
        value &= (1 << 64) - 1
    result = bytearray()
    while True:
        byte = value & 0x7f
        value >>= 7
        if value:
            result.append(byte | 0x80)
        else:
            result.append(byte)
            return bytes(result)


def encode_string(field_num, value):
    encoded = value.encode("utf-8")
    return write_varint((field_num << 3) | 2) + write_varint(len(encoded)) + encoded


def encode_int32(field_num, value):
    return write_varint(field_num << 3) + write_varint(value)


def generate_payload(path, workload_id, cpu, memory, dependencies, reverse=False, unknown=False):
    fields = [
        encode_string(1, workload_id),
        encode_int32(2, cpu),
        encode_int32(3, memory),
    ]
    fields.extend(encode_string(4, dependency) for dependency in dependencies)
    if unknown:
        fields.insert(1, encode_string(15, "ignored-" + secrets.token_hex(4)))
    if reverse:
        fields.reverse()
    with open(path, "wb") as payload:
        payload.write(b"".join(fields))


def assert_schema():
    assert os.path.isfile(PROTO_PATH), f"Schema {PROTO_PATH} not found."
    source = open(PROTO_PATH, "r", encoding="utf-8").read()
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    source = re.sub(r"//[^\n]*", "", source)

    matches = re.findall(r"\bmessage\s+Workload\s*\{([^{}]*)\}", source, flags=re.S)
    assert len(matches) == 1, "workload.proto must define exactly one Workload message declaration."

    declarations = []
    for statement in matches[0].split(";"):
        statement = statement.strip()
        if not statement:
            continue
        match = re.fullmatch(
            r"(?:(optional|required|repeated)\s+)?(string|int32)\s+([A-Za-z_]\w*)\s*=\s*(\d+)(?:\s*\[[^\]]*\])?",
            statement,
        )
        assert match, f"Unexpected declaration in Workload message: {statement!r}"
        label, field_type, name, number = match.groups()
        declarations.append((label or "", field_type, name, int(number)))

    by_name = {entry[2]: entry for entry in declarations}
    assert len(declarations) == 4 and len(by_name) == 4, "Workload must contain exactly four fields."
    assert by_name.get("id") in {
        ("", "string", "id", 1),
        ("optional", "string", "id", 1),
        ("required", "string", "id", 1),
    }
    assert by_name.get("cpu_cores") in {
        ("", "int32", "cpu_cores", 2),
        ("optional", "int32", "cpu_cores", 2),
        ("required", "int32", "cpu_cores", 2),
    }
    assert by_name.get("memory_mb") in {
        ("", "int32", "memory_mb", 3),
        ("optional", "int32", "memory_mb", 3),
        ("required", "int32", "memory_mb", 3),
    }
    assert by_name.get("dependencies") == ("repeated", "string", "dependencies", 4)


def run_validator(payload_path, workload_id, should_pass):
    if os.path.lexists(LOG_PATH):
        os.remove(LOG_PATH)

    subprocess.run(
        [VALIDATOR_PATH, payload_path],
        cwd=WORKSPACE_DIR,
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert os.path.isfile(LOG_PATH), "validation.log was not created."

    with open(LOG_PATH, "rb") as log_file:
        actual = log_file.read()
    verdict = "PASS" if should_pass else "FAIL"
    expected = f"Workload {workload_id} verification: {verdict}\n".encode("utf-8")
    assert actual == expected, f"Expected exact log {expected!r}, got {actual!r}"


@pytest.fixture(scope="session", autouse=True)
def setup_and_build():
    assert_schema()
    assert os.path.isfile(BUILD_PATH), f"Build script {BUILD_PATH} not found."
    assert os.access(BUILD_PATH, os.X_OK), f"Build script {BUILD_PATH} is not executable."

    build_source = open(BUILD_PATH, "r", encoding="utf-8").read()
    active_build_source = re.sub(r"(?m)^\s*#.*$", "", build_source)
    assert re.search(r"\bprotoc-c\b", active_build_source), "build.sh must invoke protoc-c."
    assert re.search(r"(?:^|\s)-lprotobuf-c(?:\s|$)", active_build_source), "build.sh must link with -lprotobuf-c."

    for name in ("validator", "workload.pb-c.c", "workload.pb-c.h"):
        path = os.path.join(WORKSPACE_DIR, name)
        if os.path.lexists(path):
            os.remove(path)

    started = time.time()
    result = subprocess.run(
        ["bash", "build.sh"],
        cwd=WORKSPACE_DIR,
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"build.sh failed with exit code {result.returncode}.\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )

    for name in ("workload.pb-c.c", "workload.pb-c.h"):
        generated = os.path.join(WORKSPACE_DIR, name)
        assert os.path.isfile(generated), f"protoc-c output {name} was not generated."
        text = open(generated, "r", encoding="utf-8", errors="replace").read()
        assert "Generated by protobuf-c" in text, f"{name} does not appear to be protoc-c output."
        assert os.path.getmtime(generated) >= started - 1, f"{name} was not regenerated by build.sh."

    assert os.path.isfile(VALIDATOR_PATH), "Executable 'validator' was not created by the build script."
    assert os.access(VALIDATOR_PATH, os.X_OK), "validator is not executable."
    with open(VALIDATOR_PATH, "rb") as executable:
        assert executable.read(4) == b"\x7fELF", "validator must be a compiled executable."

    ldd = subprocess.run(["ldd", VALIDATOR_PATH], capture_output=True, text=True)
    assert ldd.returncode == 0, f"Unable to inspect validator linkage: {ldd.stderr}"
    assert "libprotobuf-c" in ldd.stdout, "validator is not dynamically linked against protobuf-c."

    symbols = subprocess.run(["nm", "-D", VALIDATOR_PATH], capture_output=True, text=True)
    assert symbols.returncode == 0, f"Unable to inspect validator symbols: {symbols.stderr}"
    assert "protobuf_c_message_unpack" in symbols.stdout, "validator does not include protobuf-c deserialization support."


def test_original_cases():
    cases = [
        ("test_pass.bin", "job-123", 4, 1024, ["nginx", "mysql", "redis"], True),
        ("test_fail_cpu.bin", "job-124", 16, 1024, ["mysql", "redis"], False),
        ("test_fail_deps.bin", "job-125", 2, 512, ["mysql", "postgres"], False),
        ("test_fail_mem.bin", "job-126", 4, 4096, ["mysql", "redis"], False),
    ]
    for filename, workload_id, cpu, memory, dependencies, expected in cases:
        path = os.path.join(WORKSPACE_DIR, filename)
        generate_payload(path, workload_id, cpu, memory, dependencies)
        run_validator(path, workload_id, expected)


def test_randomized_general_constraints_and_deserialization():
    randomized_cases = [
        (1, 1, ["mysql", "redis"], True),
        (8, 2048, ["redis", "extra", "mysql", "redis"], True),
        (4, 512, ["nginx", "mysql", "redis", "postgres"], True),
        (0, 1024, ["mysql", "redis"], False),
        (-1, 1024, ["mysql", "redis"], False),
        (9, 1024, ["mysql", "redis"], False),
        (4, 0, ["mysql", "redis"], False),
        (4, -3, ["mysql", "redis"], False),
        (4, 2049, ["mysql", "redis"], False),
        (4, 1024, ["mysql"], False),
        (4, 1024, ["redis"], False),
        (4, 1024, ["MYSQL", "redis"], False),
        (4, 1024, ["mysql", "Redis"], False),
        (4, 1024, [], False),
        (9, 4096, ["mysql"], False),
    ]

    for index, (cpu, memory, dependencies, expected) in enumerate(randomized_cases):
        workload_id = f"wl-{secrets.token_hex(12)}-{index}"
        path = os.path.join(WORKSPACE_DIR, f"payload-{secrets.token_hex(10)}.bin")
        generate_payload(
            path,
            workload_id,
            cpu,
            memory,
            dependencies,
            reverse=(index % 2 == 1),
            unknown=(index % 3 == 0),
        )
        try:
            run_validator(path, workload_id, expected)
        finally:
            if os.path.exists(path):
                os.remove(path)
PYTEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
