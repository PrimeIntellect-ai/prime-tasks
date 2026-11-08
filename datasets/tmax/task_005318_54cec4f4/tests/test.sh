#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import sqlite3
import subprocess
import tempfile
import uuid

import pytest

TELEMETRY_DIR = "/home/user/telemetry"
LIB_PATH = os.path.join(TELEMETRY_DIR, "libtelemetry.so")
GO_PATH = os.path.join(TELEMETRY_DIR, "process.go")
DB_PATH = "/home/user/metrics.db"


def test_makefile_builds_library_from_scratch():
    if os.path.exists(LIB_PATH):
        os.remove(LIB_PATH)

    result = subprocess.run(
        ["make"],
        cwd=TELEMETRY_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert result.returncode == 0, f"Running make failed:\n{result.stdout}"
    assert os.path.isfile(LIB_PATH), "Running make did not create libtelemetry.so."


def test_libtelemetry_compiled_correctly():
    lib_path = "/home/user/telemetry/libtelemetry.so"
    assert os.path.isfile(lib_path), f"Shared library {lib_path} was not created."

    # Check if it's a shared object
    file_output = subprocess.check_output(["file", lib_path]).decode("utf-8")
    assert "shared object" in file_output, f"{lib_path} is not a valid shared object. Ensure -shared and -fPIC are used."

    # Check for exported symbol
    try:
        nm_output = subprocess.check_output(["nm", "-D", lib_path]).decode("utf-8")
        assert "process_telemetry" in nm_output, f"Symbol 'process_telemetry' not found in {lib_path}"
    except subprocess.CalledProcessError:
        pytest.fail(f"Failed to run nm on {lib_path}. Is it a valid shared library?")


def test_database_schema_migrated():
    db_path = "/home/user/metrics.db"
    assert os.path.isfile(db_path), f"Database {db_path} does not exist."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("PRAGMA table_info(builds);")
    columns = {row[1]: row[2].upper() for row in cursor.fetchall()}
    conn.close()

    assert "memory_used" in columns, "Column 'memory_used' was not added to the builds table."
    assert "battery_drain" in columns, "Column 'battery_drain' was not added to the builds table."

    # Check data types if possible, though SQLite is flexible, the task specifies INTEGER and REAL
    assert "INT" in columns["memory_used"], "Column 'memory_used' should be of type INTEGER."
    assert "REAL" in columns["battery_drain"], "Column 'battery_drain' should be of type REAL."


def test_database_has_new_telemetry_data():
    db_path = "/home/user/metrics.db"
    assert os.path.isfile(db_path), f"Database {db_path} does not exist."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    try:
        cursor.execute("SELECT device, build_time, memory_used, battery_drain FROM builds WHERE device='Pixel 7';")
        row = cursor.fetchone()
    except sqlite3.OperationalError as e:
        pytest.fail(f"Failed to query the builds table: {e}")
    finally:
        conn.close()

    assert row is not None, "No row found for device 'Pixel 7'. Did the Go program execute successfully?"

    device, build_time, memory_used, battery_drain = row
    assert device == "Pixel 7", f"Expected device 'Pixel 7', got {device}"
    assert abs(float(build_time) - 145.2) < 0.01, f"Expected build_time 145.2, got {build_time}"
    assert int(memory_used) == 4096, f"Expected memory_used 4096, got {memory_used}"
    assert abs(float(battery_drain) - 1.5) < 0.01, f"Expected battery_drain 1.5, got {battery_drain}"


def test_go_process_file_exists():
    go_file = "/home/user/telemetry/process.go"
    assert os.path.isfile(go_file), f"Go source file {go_file} does not exist."


def test_go_processor_uses_cgo_and_process_telemetry():
    source = open(GO_PATH, "r", encoding="utf-8").read()
    assert re.search(r'import\s+"C"', source), "process.go must use cgo via import \"C\"."
    assert re.search(r'\bC\.process_telemetry\s*\(', source), "process.go must call C.process_telemetry."

    result = subprocess.run(
        ["go", "list", "-json", "process.go"],
        cwd=TELEMETRY_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        env={**os.environ, "CGO_ENABLED": "1"},
        timeout=60,
    )
    assert result.returncode == 0, f"process.go is not a valid buildable cgo program:\n{result.stdout}"
    metadata = json.loads(result.stdout)
    assert "process.go" in metadata.get("CgoFiles", []), "Go tooling does not recognize process.go as a cgo source file."


def test_go_processor_executes_c_library_parses_json_and_inserts_row():
    token = uuid.uuid4().hex
    device = f"Verifier-{token}"
    seed = int(token[:8], 16)
    build_time = 200.0 + (seed % 10000) / 100.0
    memory_used = 10000 + (seed % 50000)
    battery_drain = 2.0 + (seed % 1000) / 1000.0

    json_payload = json.dumps({
        "device": device,
        "build_time": build_time,
        "memory_used": memory_used,
        "battery_drain": battery_drain,
    }, separators=(",", ":"))
    c_payload = json_payload.replace("\\", "\\\\").replace('"', '\\"')

    c_source = f'''\
#include <string.h>
#include <stdio.h>

int process_telemetry(const char* input_file, char* output_buffer, int max_len) {{
    const char* expected_path = "/home/user/telemetry/raw.dat";
    const char* result = "{c_payload}";
    if (input_file == NULL || strcmp(input_file, expected_path) != 0) return -10;
    if (output_buffer == NULL || max_len <= 0) return -11;
    if ((int)strlen(result) >= max_len) return -12;
    strcpy(output_buffer, result);
    return 0;
}}
'''

    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute("DELETE FROM builds WHERE device = ?", (device,))
        conn.commit()
    finally:
        conn.close()

    with tempfile.TemporaryDirectory() as temp_dir:
        source_path = os.path.join(temp_dir, "dynamic_telemetry.c")
        replacement_lib = os.path.join(temp_dir, "libtelemetry.so")
        backup_lib = os.path.join(temp_dir, "original_libtelemetry.so")
        with open(source_path, "w", encoding="utf-8") as f:
            f.write(c_source)

        compile_result = subprocess.run(
            ["gcc", "-shared", "-fPIC", "-o", replacement_lib, source_path],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=60,
        )
        assert compile_result.returncode == 0, f"Verifier failed to build test library:\n{compile_result.stdout}"

        shutil.copy2(LIB_PATH, backup_lib)
        os.replace(replacement_lib, LIB_PATH)
        try:
            env = os.environ.copy()
            env["CGO_ENABLED"] = "1"
            env["LD_LIBRARY_PATH"] = TELEMETRY_DIR + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
            result = subprocess.run(
                ["go", "run", "process.go"],
                cwd=TELEMETRY_DIR,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=120,
            )
        finally:
            shutil.copy2(backup_lib, LIB_PATH)

    assert result.returncode == 0, f"Executing process.go failed:\n{result.stdout}"

    conn = sqlite3.connect(DB_PATH)
    try:
        row = conn.execute(
            "SELECT device, build_time, memory_used, battery_drain "
            "FROM builds WHERE device = ? ORDER BY id DESC LIMIT 1",
            (device,),
        ).fetchone()
    finally:
        conn.close()

    assert row is not None, "process.go did not insert the dynamically generated telemetry row."
    assert row[0] == device
    assert abs(float(row[1]) - build_time) < 0.0001
    assert int(row[2]) == memory_used
    assert abs(float(row[3]) - battery_drain) < 0.0001
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
