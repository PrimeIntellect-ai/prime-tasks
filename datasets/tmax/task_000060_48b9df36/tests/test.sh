#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import shutil
import sqlite3
import stat
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/ci_test.sh"
BUILD_DIR = "/home/user/build"
LIB_PATH = os.path.join(BUILD_DIR, "libcompute.so")
APP_PATH = os.path.join(BUILD_DIR, "app")
DB_PATH = os.path.join(BUILD_DIR, "app.db")
LOG_PATH = "/home/user/test_result.log"


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."


def test_script_execution():
    # Remove all prior outputs so the submitted script must recreate them.
    shutil.rmtree(BUILD_DIR, ignore_errors=True)
    if os.path.lexists(LOG_PATH):
        os.unlink(LOG_PATH)

    result = subprocess.run(
        ["bash", SCRIPT_PATH],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"Script execution failed with return code {result.returncode}.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"


def test_build_artifacts_exist():
    assert os.path.isfile(LIB_PATH), f"Shared library {LIB_PATH} was not created."
    assert os.path.isfile(APP_PATH), f"Executable {APP_PATH} was not created."
    assert os.path.isfile(DB_PATH), f"Database {DB_PATH} was not created."

    for path in (LIB_PATH, APP_PATH, DB_PATH):
        assert stat.S_ISREG(os.lstat(path).st_mode), f"{path} is not a regular, non-symlink file."

    assert os.access(APP_PATH, os.X_OK), f"Executable {APP_PATH} is not executable."
    with open(LIB_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{LIB_PATH} is not an ELF shared library."
    with open(APP_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{APP_PATH} is not an ELF executable."
    with open(DB_PATH, "rb") as f:
        assert f.read(16) == b"SQLite format 3\x00", f"{DB_PATH} is not a SQLite database."

    lib_header = subprocess.run(
        ["readelf", "-h", LIB_PATH], capture_output=True, text=True, check=True
    ).stdout
    assert "DYN (Shared object file)" in lib_header, f"{LIB_PATH} is not a shared object."

    dynamic = subprocess.run(
        ["readelf", "-d", APP_PATH], capture_output=True, text=True, check=True
    ).stdout
    assert "libcompute.so" in dynamic, "app is not dynamically linked against libcompute.so."
    assert "libsqlite3.so" in dynamic, "app is not dynamically linked against sqlite3."

    symbols = subprocess.run(
        ["nm", "-D", LIB_PATH], capture_output=True, text=True, check=True
    ).stdout
    assert any(line.split()[-1:] == ["compute_hash"] for line in symbols.splitlines()), \
        "libcompute.so does not export compute_hash."


def test_database_schema_and_migration():
    con = sqlite3.connect(DB_PATH)
    try:
        integrity = con.execute("PRAGMA integrity_check").fetchone()[0]
        assert integrity == "ok", f"Database integrity check failed: {integrity}"
        columns = con.execute("PRAGMA table_info(config)").fetchall()
        assert [(row[1], row[2], row[5]) for row in columns] == [
            ("id", "INTEGER", 1),
            ("value", "INTEGER", 0),
        ], f"Unexpected config schema: {columns}"
        rows = con.execute("SELECT id, value FROM config ORDER BY id").fetchall()
        assert rows == [(1, 15)], f"Schema and migration did not produce the expected data: {rows}"
    finally:
        con.close()


def test_compiled_application_uses_library_and_database():
    lib = ctypes.CDLL(LIB_PATH)
    compute_hash = lib.compute_hash
    compute_hash.argtypes = [ctypes.c_int]
    compute_hash.restype = ctypes.c_int
    for value in (0, 1, -7, 23):
        assert compute_hash(value) == value * 42, "Compiled libcompute.so has incorrect behavior."

    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = BUILD_DIR + os.pathsep + env.get("LD_LIBRARY_PATH", "")

    # Exercise the executable independently on database values not present in the
    # submitted script or its original output.
    with tempfile.TemporaryDirectory() as td:
        test_db = os.path.join(td, "variant.db")
        shutil.copy2(DB_PATH, test_db)
        for value in (-7, 23):
            con = sqlite3.connect(test_db)
            try:
                con.execute("UPDATE config SET value = ? WHERE id = 1", (value,))
                con.commit()
                actual_value = con.execute("SELECT value FROM config WHERE id = 1").fetchone()[0]
            finally:
                con.close()

            expected = f"MIGRATED_HASH={compute_hash(actual_value)}"
            result = subprocess.run(
                [APP_PATH, test_db], capture_output=True, text=True, env=env, timeout=15
            )
            assert result.returncode == 0, f"app failed: {result.stderr}"
            assert result.stdout.strip() == expected, \
                f"app did not compute from the supplied database: expected {expected!r}, got {result.stdout.strip()!r}"


def test_test_result_log():
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} was not created."
    with open(LOG_PATH, "r") as f:
        content = f.read().strip()

    expected_output = "MIGRATED_HASH=630"
    assert content == expected_output, f"Expected log content '{expected_output}', but got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
