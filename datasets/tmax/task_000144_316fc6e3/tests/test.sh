#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import socket
import sqlite3
import subprocess
import tempfile
import uuid

import pytest

CJSON_DIR = "/app/cJSON-1.7.15"
SOURCE = "/home/user/etl_server.c"


def run_checked(args):
    return subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True)


def test_cjson_fixed_and_built():
    """Verify that the cJSON Makefile was fixed and a real shared library was built."""
    makefile_path = os.path.join(CJSON_DIR, "Makefile")
    assert os.path.exists(makefile_path), f"Makefile {makefile_path} is missing."

    with open(makefile_path, "r") as f:
        makefile_content = f.read()

    assert "CC = gcc\n" in makefile_content or "CC=gcc\n" in makefile_content or "CC = gcc" in makefile_content, "The Makefile was not fixed to use 'gcc'."
    assert "gccc" not in makefile_content, "The 'gccc' typo is still present in the Makefile."

    # Preserve the original library assertion.
    lib_exists = os.path.exists(os.path.join(CJSON_DIR, "libcjson.so")) or \
                 os.path.exists(os.path.join(CJSON_DIR, "libcjson.so.1.7.15")) or \
                 os.path.exists(os.path.join(CJSON_DIR, "libcjson.a"))
    assert lib_exists, "The cJSON library (libcjson.so or libcjson.a) was not built in /app/cJSON-1.7.15."

    shared_candidates = [
        os.path.join(CJSON_DIR, "libcjson.so"),
        os.path.join(CJSON_DIR, "libcjson.so.1"),
        os.path.join(CJSON_DIR, "libcjson.so.1.7.15"),
    ]
    shared = next((p for p in shared_candidates if os.path.isfile(p)), None)
    assert shared is not None, "The required cJSON shared library was not built."

    header = run_checked(["readelf", "-h", shared]).stdout
    assert re.search(r"Type:\s+DYN", header), f"{shared} is not an ELF shared object."
    symbols = run_checked(["nm", "-D", shared]).stdout
    assert "cJSON_CreateArray" in symbols and "cJSON_Print" in symbols, "The shared object does not export expected cJSON functions."


def listening_server_pid():
    socket_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        if not os.path.exists(table):
            continue
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                local_address, state, inode = fields[1], fields[3], fields[9]
                if int(local_address.rsplit(":", 1)[1], 16) == 8000 and state == "0A":
                    socket_inodes.add(inode)

    assert socket_inodes, "No process is listening on TCP port 8000."
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in socket_inodes:
                    return int(pid)
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    pytest.fail("Could not identify the process listening on TCP port 8000.")


def test_c_source_compilation_and_running_artifact():
    """Require submitted C source, compile it, and verify the listener is a linked native executable."""
    assert os.path.isfile(SOURCE), f"Required C source {SOURCE} is missing."
    with open(SOURCE, "rb") as f:
        source_data = f.read()
    assert source_data, "etl_server.c is empty."

    output = os.path.join(tempfile.mkdtemp(prefix="etl-build-"), "etl_server")
    compile_result = subprocess.run(
        [
            "gcc", SOURCE, "-o", output,
            "-I" + CJSON_DIR,
            "-L" + CJSON_DIR,
            "-Wl,-rpath," + CJSON_DIR,
            "-lcjson", "-lsqlite3",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert compile_result.returncode == 0, f"etl_server.c did not compile and link with SQLite and cJSON:\n{compile_result.stderr}"
    with open(output, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled server is not a native ELF executable."

    pid = listening_server_pid()
    exe_path = f"/proc/{pid}/exe"
    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The process listening on port 8000 is not a native executable."

    dynamic = run_checked(["readelf", "-d", exe_path]).stdout
    try:
        symbols = run_checked(["nm", "-a", exe_path]).stdout
    except subprocess.CalledProcessError:
        symbols = ""

    assert re.search(r"libcjson[^\]]*", dynamic, re.IGNORECASE) or "cJSON_" in symbols, \
        "The running executable is not linked with cJSON."
    assert re.search(r"libsqlite3[^\]]*", dynamic, re.IGNORECASE) or "sqlite3_" in symbols, \
        "The running executable is not linked with SQLite."


def send_tcp_request(host, port, message, timeout=5.0):
    """Helper to send a TCP request and return the response."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(timeout)
        try:
            s.connect((host, port))
            s.sendall(message.encode("utf-8"))
            response = b""
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                response += chunk
            return response.decode("utf-8")
        except ConnectionRefusedError:
            pytest.fail(f"Connection refused on {host}:{port}. Is the service running?")
        except socket.timeout:
            pytest.fail(f"Connection timed out on {host}:{port}.")


def test_service_invalid_command():
    """Verify that the service returns ERROR for invalid commands."""
    response = send_tcp_request("127.0.0.1", 8000, "BAD_COMMAND\n")
    assert response == "ERROR\n", f"Expected 'ERROR\\n' for invalid command, got {repr(response)}"


def mask_email(email):
    local, domain = email.split("@", 1)
    return local[0] + "***@" + domain


def mask_card(card):
    return "X" * (len(card) - 4) + card[-4:]


def test_service_valid_command_and_masking():
    """Insert unpredictable records, then verify live extraction and exact masking."""
    marker = uuid.uuid4().hex
    dynamic_rows = [
        (f"Quoted \\\"Customer\\\" {marker}", f"q{marker}@dynamic-{marker[:8]}.example", "3141592653589793"),
        (f"Backslash \\\\ Name {marker}", f"z{marker}@test-{marker[-8:]}.invalid", "2718281828459045"),
    ]

    with sqlite3.connect("/home/user/data.db", timeout=10) as db:
        db.executemany("INSERT INTO customers(name, email, credit_card) VALUES (?, ?, ?)", dynamic_rows)
        db.commit()
        rows = db.execute("SELECT id, name, email, credit_card FROM customers").fetchall()

    response = send_tcp_request("127.0.0.1", 8000, "RUN_ETL SECRET_TOKEN_42\n")
    assert response.endswith("\nEND\n"), f"Response must end with '\\nEND\\n', got {repr(response[-10:])}"
    json_str = response[:-5]

    try:
        data = json.loads(json_str)
    except json.JSONDecodeError as e:
        pytest.fail(f"Failed to parse JSON payload: {e}. Payload was: {repr(json_str)}")

    assert isinstance(data, list), "Expected a JSON array of objects."
    assert len(data) == len(rows), f"Expected {len(rows)} records from the current database, got {len(data)}."

    expected_data = {
        row_id: {
            "name": name,
            "email": mask_email(email),
            "credit_card": mask_card(credit_card),
        }
        for row_id, name, email, credit_card in rows
    }

    # Preserve the original fixed-record expectations as well as checking new data.
    original_expected = {
        1: {"name": "Alice Smith", "email": "a***@example.com", "credit_card": "XXXXXXXXXXXX5678"},
        2: {"name": "Bob Jones", "email": "b***@test.org", "credit_card": "XXXXXXXXXXXX5432"},
    }

    seen = set()
    for record in data:
        assert isinstance(record, dict), "Each array element must be a JSON object."
        assert "id" in record, "Record missing 'id' field."
        assert "name" in record, "Record missing 'name' field."
        assert "email" in record, "Record missing 'email' field."
        assert "credit_card" in record, "Record missing 'credit_card' field."

        record_id = record["id"]
        assert record_id in expected_data, f"Unexpected record ID {record_id}."
        assert record_id not in seen, f"Duplicate record ID {record_id}."
        seen.add(record_id)

        expected = expected_data[record_id]
        assert record["name"] == expected["name"], f"Name mismatch for ID {record_id}."
        assert re.match(r"^.\*\*\*@[^@]+$", record["email"]), f"Email masking failed for ID {record_id}: {record['email']}"
        assert record["email"] == expected["email"], f"Email mismatch for ID {record_id}."
        assert re.match(r"^X{12}\d{4}$", record["credit_card"]), f"Credit card masking failed for ID {record_id}: {record['credit_card']}"
        assert record["credit_card"] == expected["credit_card"], f"Credit card mismatch for ID {record_id}."

        if record_id in original_expected:
            assert {k: record[k] for k in ("name", "email", "credit_card")} == original_expected[record_id], \
                f"Original setup record {record_id} does not match its required value."

    assert seen == set(expected_data), "The response did not contain exactly all current database rows."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
