#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shlex
import shutil
import subprocess
from pathlib import Path

import pytest


def test_migration_log():
    log_path = "/home/user/migration.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."
    with open(log_path, "r") as f:
        content = f.read().strip()

    expected_content = "Migrated device 104 to status enum 2"
    assert content == expected_content, f"Log file content is incorrect. Expected: '{expected_content}', but got: '{content}'"


def test_output_binary_exists():
    out_path = "/home/user/data/output_v2.bin"
    assert os.path.isfile(out_path), f"Output binary {out_path} does not exist."
    assert os.path.getsize(out_path) > 0, f"Output binary {out_path} is empty."


def test_output_binary_content():
    out_path = "/home/user/data/output_v2.bin"
    schema_dir = "/home/user/schemas"
    v2_proto = "/home/user/schemas/v2.proto"

    cmd = [
        "protoc",
        "--decode=TelemetryV2",
        f"-I{schema_dir}",
        v2_proto
    ]

    try:
        with open(out_path, "rb") as f:
            result = subprocess.run(cmd, stdin=f, capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to decode output binary using protoc. Error: {e.stderr}")
    except FileNotFoundError:
        pytest.fail("protoc command not found. Cannot verify binary content.")

    output = result.stdout
    assert "device_id: 104" in output, "device_id is incorrect or missing in output_v2.bin."
    assert "temperature: 42.5" in output, "temperature is incorrect or missing in output_v2.bin."
    assert "status: ERROR" in output, "status is incorrect or missing in output_v2.bin."
    assert "timestamp: 1710000000" in output, "timestamp is incorrect or missing in output_v2.bin."


def test_source_uses_protobuf_c_and_handles_fresh_inputs():
    source_path = Path("/home/user/migrate.c")
    assert source_path.is_file(), "/home/user/migrate.c does not exist."
    source = source_path.read_text(errors="replace")
    assert re.search(r"(?:telemetry_v1__unpack|protobuf_c_message_unpack)\s*\(", source), \
        "migrate.c does not deserialize the v1 message using protobuf-c."
    assert re.search(r"(?:telemetry_v2__pack|protobuf_c_message_pack)\s*\(", source), \
        "migrate.c does not serialize the v2 message using protobuf-c."

    assert shutil.which("protoc-c"), "protoc-c is not installed."
    assert shutil.which("gcc"), "gcc is not installed."

    build_dir = Path("/tmp/migration-verifier-build")
    shutil.rmtree(build_dir, ignore_errors=True)
    build_dir.mkdir()
    subprocess.run([
        "protoc-c", "--c_out", str(build_dir),
        "-I/home/user/schemas",
        "/home/user/schemas/v1.proto", "/home/user/schemas/v2.proto"
    ], check=True, capture_output=True, text=True)

    try:
        flags = shlex.split(subprocess.run(
            ["pkg-config", "--cflags", "--libs", "libprotobuf-c"],
            check=True, capture_output=True, text=True
        ).stdout)
    except (FileNotFoundError, subprocess.CalledProcessError):
        flags = ["-lprotobuf-c"]

    generated_sources = []
    if not re.search(r'#\s*include\s*["<][^">]*v1\.pb-c\.c[">]', source):
        generated_sources.append(str(build_dir / "v1.pb-c.c"))
    if not re.search(r'#\s*include\s*["<][^">]*v2\.pb-c\.c[">]', source):
        generated_sources.append(str(build_dir / "v2.pb-c.c"))

    executable = build_dir / "migrate"
    compile_cmd = [
        "gcc", "-std=c11", "-O2",
        "-I" + str(build_dir), "-I/home/user", "-I/home/user/schemas",
        str(source_path), *generated_sources, "-o", str(executable), *flags
    ]
    compiled = subprocess.run(compile_cmd, capture_output=True, text=True)
    assert compiled.returncode == 0, f"Failed to compile migrate.c:\n{compiled.stderr}"

    input_path = Path("/home/user/data/input_v1.bin")
    output_path = Path("/home/user/data/output_v2.bin")
    log_path = Path("/home/user/migration.log")
    originals = {
        p: p.read_bytes() if p.exists() else None
        for p in (input_path, output_path, log_path)
    }

    rng = secrets.SystemRandom()
    cases = [
        (rng.randrange(1000, 900000), rng.choice([11.25, 19.5, 37.75, -8.25]), "OK", 1, "OK"),
        (rng.randrange(1000, 900000), rng.choice([3.5, 22.25, 61.75, -14.5]), "ERR", 2, "ERROR"),
        (rng.randrange(1000, 900000), rng.choice([7.25, 28.5, 45.75, -2.5]), "OTHER_" + secrets.token_hex(6), 0, None),
    ]

    try:
        for device_id, temperature, status_code, expected_status, status_name in cases:
            text_input = (
                f'device_id: {device_id}\n'
                f'temperature: {temperature}\n'
                f'status_code: "{status_code}"\n'
            ).encode()
            encoded = subprocess.run([
                "protoc", "--encode=TelemetryV1", "-I/home/user/schemas",
                "/home/user/schemas/v1.proto"
            ], input=text_input, capture_output=True)
            assert encoded.returncode == 0, encoded.stderr.decode(errors="replace")
            input_path.write_bytes(encoded.stdout)
            output_path.unlink(missing_ok=True)
            log_path.unlink(missing_ok=True)

            run = subprocess.run([str(executable)], cwd="/home/user", capture_output=True, text=True, timeout=10)
            assert run.returncode == 0, f"Compiled migration program failed: {run.stderr}"
            assert output_path.is_file() and output_path.stat().st_size > 0, "Program did not produce output_v2.bin."
            assert log_path.is_file(), "Program did not produce migration.log."
            assert log_path.read_text().strip() == f"Migrated device {device_id} to status enum {expected_status}"

            with output_path.open("rb") as output_file:
                decoded = subprocess.run([
                    "protoc", "--decode=TelemetryV2", "-I/home/user/schemas",
                    "/home/user/schemas/v2.proto"
                ], stdin=output_file, capture_output=True, text=True)
            assert decoded.returncode == 0, f"Fresh output could not be decoded: {decoded.stderr}"
            fields = decoded.stdout

            id_match = re.search(r"^device_id:\s*(-?\d+)\s*$", fields, re.MULTILINE)
            temp_match = re.search(r"^temperature:\s*([-+0-9.eE]+)\s*$", fields, re.MULTILINE)
            timestamp_match = re.search(r"^timestamp:\s*(-?\d+)\s*$", fields, re.MULTILINE)
            status_match = re.search(r"^status:\s*(\w+)\s*$", fields, re.MULTILINE)
            assert id_match and int(id_match.group(1)) == device_id
            assert temp_match and float(temp_match.group(1)) == pytest.approx(temperature, abs=1e-6)
            assert timestamp_match and int(timestamp_match.group(1)) == 1710000000
            if status_name is None:
                assert status_match is None, f"Unknown status should map to enum value 0, got: {fields}"
            else:
                assert status_match and status_match.group(1) == status_name
    finally:
        for path, content in originals.items():
            if content is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
