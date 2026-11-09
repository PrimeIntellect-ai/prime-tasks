#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import re
import secrets
import sqlite3
import subprocess
import tempfile


def test_files_exist_and_executable():
    scripts = [
        "/home/user/migrate.sh",
        "/home/user/build_and_run.sh"
    ]
    for script in scripts:
        assert os.path.isfile(script), f"Expected script {script} does not exist."
        assert os.access(script, os.X_OK), f"Script {script} is not executable."

    assert os.path.isfile("/home/user/custom.s"), "Assembly file /home/user/custom.s does not exist."
    assert os.path.isfile("/home/user/legacy/libcustom.so"), "Shared library /home/user/legacy/libcustom.so was not created."


def test_database_schema_updated():
    db_path = "/home/user/legacy/db.sqlite"
    assert os.path.isfile(db_path), f"Database {db_path} does not exist."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("PRAGMA table_info(metrics);")
    columns = {row[1] for row in cursor.fetchall()}
    assert "hash_val" in columns, "Column 'hash_val' was not added to the 'metrics' table."
    conn.close()


def test_database_contents_updated():
    db_path = "/home/user/legacy/db.sqlite"
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT id, raw_val, hash_val FROM metrics ORDER BY id;")
    rows = cursor.fetchall()

    expected_rows = []
    for row in [(1, 100), (2, 255), (3, 0)]:
        raw_val = row[1]
        hash_val = (raw_val ^ 0x5A) + 12
        expected_rows.append((row[0], raw_val, hash_val))

    assert rows == expected_rows, f"Database contents do not match expected values. Got {rows}, expected {expected_rows}."
    conn.close()


def test_final_dump_txt_contents():
    dump_path = "/home/user/final_dump.txt"
    assert os.path.isfile(dump_path), f"Dump file {dump_path} does not exist."

    with open(dump_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = []
    for row in [(1, 100), (2, 255), (3, 0)]:
        raw_val = row[1]
        hash_val = (raw_val ^ 0x5A) + 12
        expected_lines.append(f"{row[0]}|{raw_val}|{hash_val}")

    assert lines == expected_lines, f"Contents of {dump_path} do not match expected values. Got {lines}, expected {expected_lines}."


def expected_hash(value):
    return ctypes.c_int32((value ^ 0x5A) + 12).value


def assert_shared_object_and_hashes(lib_path, values):
    header = subprocess.run(
        ["readelf", "-h", lib_path], capture_output=True, text=True, timeout=10
    )
    assert header.returncode == 0, f"{lib_path} is not a readable ELF file: {header.stderr}"
    assert re.search(r"Class:\s+ELF64", header.stdout), "Library is not ELF64."
    assert re.search(r"Machine:\s+Advanced Micro Devices X86-64", header.stdout), "Library is not x86_64."
    assert re.search(r"Type:\s+DYN", header.stdout), "Library is not a shared object."

    symbols = subprocess.run(
        ["nm", "-D", "--defined-only", lib_path], capture_output=True, text=True, timeout=10
    )
    assert symbols.returncode == 0, f"Unable to inspect dynamic symbols: {symbols.stderr}"
    assert re.search(r"\bcompute_hash$", symbols.stdout, re.MULTILINE), "compute_hash is not exported."

    lib = ctypes.CDLL(lib_path)
    func = lib.compute_hash
    func.argtypes = [ctypes.c_int]
    func.restype = ctypes.c_int
    for value in values:
        actual = func(value)
        expected = expected_hash(value)
        assert actual == expected, f"compute_hash({value}) returned {actual}, expected {expected}."


def test_assembly_and_build_script_on_fresh_dynamic_database():
    random_values = [ctypes.c_int32(secrets.randbits(32)).value for _ in range(5)]
    probe_values = [0, 1, -1, 0x7FFFFFFF, -0x80000000] + random_values

    # Compile the submitted assembly independently so a prebuilt or dummy library cannot pass.
    with tempfile.TemporaryDirectory() as temp_dir:
        probe_lib = os.path.join(temp_dir, "libprobe.so")
        compile_result = subprocess.run(
            ["gcc", "-nostdlib", "-fPIC", "-shared", "/home/user/custom.s", "-o", probe_lib],
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert compile_result.returncode == 0, f"custom.s failed to compile as required: {compile_result.stderr}"
        assert_shared_object_and_hashes(probe_lib, probe_values)

    # Restore a fresh pre-migration database with unpredictable inputs, then require
    # build_and_run.sh to build, migrate, process, and dump it.
    db_path = "/home/user/legacy/db.sqlite"
    lib_path = "/home/user/legacy/libcustom.so"
    dump_path = "/home/user/final_dump.txt"
    for path in (db_path, lib_path, dump_path):
        if os.path.lexists(path):
            os.remove(path)

    dynamic_rows = [
        (101, random_values[0]),
        (203, random_values[1]),
        (307, random_values[2]),
        (409, random_values[3]),
        (503, random_values[4]),
    ]
    conn = sqlite3.connect(db_path)
    conn.execute("CREATE TABLE metrics (id INTEGER PRIMARY KEY, raw_val INTEGER)")
    conn.executemany("INSERT INTO metrics (id, raw_val) VALUES (?, ?)", dynamic_rows)
    conn.commit()
    conn.close()

    run_result = subprocess.run(
        ["/home/user/build_and_run.sh"],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert run_result.returncode == 0, (
        "build_and_run.sh failed on a fresh database.\n"
        f"stdout:\n{run_result.stdout}\nstderr:\n{run_result.stderr}"
    )

    assert os.path.isfile(lib_path), "build_and_run.sh did not create libcustom.so."
    assert os.path.isfile(dump_path), "build_and_run.sh did not create final_dump.txt."
    assert_shared_object_and_hashes(lib_path, probe_values)

    conn = sqlite3.connect(db_path)
    columns = {row[1] for row in conn.execute("PRAGMA table_info(metrics)").fetchall()}
    assert "hash_val" in columns, "Migration did not add hash_val on a fresh database."
    actual_rows = conn.execute(
        "SELECT id, raw_val, hash_val FROM metrics ORDER BY id"
    ).fetchall()
    conn.close()

    expected_rows = [(row_id, raw, expected_hash(raw)) for row_id, raw in dynamic_rows]
    assert actual_rows == expected_rows, (
        f"Dynamic database contents are wrong. Got {actual_rows}, expected {expected_rows}."
    )

    with open(dump_path, "r") as f:
        dump_lines = [line.strip() for line in f if line.strip()]
    expected_lines = [f"{row_id}|{raw}|{expected_hash(raw)}" for row_id, raw in dynamic_rows]
    assert dump_lines == expected_lines, (
        f"Dynamic final dump is wrong. Got {dump_lines}, expected {expected_lines}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
