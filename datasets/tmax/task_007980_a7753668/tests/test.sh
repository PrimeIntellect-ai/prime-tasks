#!/bin/bash
set -e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import sqlite3
import stat
import subprocess

import pytest

PROJECT_DIR = "/home/user/project"
BUILD_DIR = os.path.join(PROJECT_DIR, "build")
OUTPUT_LOG = os.path.join(PROJECT_DIR, "output.log")
DB_PATH = os.path.join(PROJECT_DIR, "db.sqlite")
APP_PATH = os.path.join(BUILD_DIR, "myapp")
RUST_ARCHIVE = os.path.join(PROJECT_DIR, "rust_lib/target/debug/librust_lib.a")

EXPECTED_MAIN = '''#include <iostream>
#include <fstream>
#include <sqlite3.h>
#include "wrapper.h"

int main() {
    sqlite3* db;
    if (sqlite3_open("../db.sqlite", &db) != SQLITE_OK) {
        return 1;
    }

    sqlite3_stmt* stmt;
    const char* query = "SELECT version FROM config LIMIT 1;";
    if (sqlite3_prepare_v2(db, query, -1, &stmt, nullptr) != SQLITE_OK) {
        // Migration not applied!
        return 2;
    }

    int version = 0;
    if (sqlite3_step(stmt) == SQLITE_ROW) {
        version = sqlite3_column_int(stmt, 0);
    }
    sqlite3_finalize(stmt);
    sqlite3_close(db);

    if (version != 2) return 3;

    const char* sys_name = get_system_name();

    std::ofstream out("../output.log");
    out << "System OK. Name: " << sys_name << ", Version: " << version << std::endl;
    out.close();

    free_system_name(const_cast<char*>(sys_name));
    return 0;
}
'''

EXPECTED_WRAPPER = '''#include "wrapper.h"
// Wrapper implementations or additional logic could go here.
'''


def run_checked(command, cwd, timeout=180):
    result = subprocess.run(
        command,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Command failed with exit code {result.returncode}: {' '.join(command)}\n"
        f"{result.stdout}"
    )
    return result


@pytest.fixture(scope="session", autouse=True)
def build_and_run_submission():
    main_path = os.path.join(PROJECT_DIR, "src/main.cpp")
    wrapper_path = os.path.join(PROJECT_DIR, "src/wrapper.cpp")
    with open(main_path, "r") as f:
        assert f.read() == EXPECTED_MAIN, "src/main.cpp was modified, contrary to the instruction."
    with open(wrapper_path, "r") as f:
        assert f.read() == EXPECTED_WRAPPER, "src/wrapper.cpp was modified, contrary to the instruction."

    conn = sqlite3.connect(DB_PATH)
    try:
        row = conn.execute("SELECT version FROM config LIMIT 1").fetchone()
        assert row is not None and row[0] == 2, "The required migration was not applied before building."
    finally:
        conn.close()

    shutil.rmtree(BUILD_DIR, ignore_errors=True)
    os.makedirs(BUILD_DIR)
    if os.path.lexists(OUTPUT_LOG):
        os.remove(OUTPUT_LOG)

    run_checked(["cmake", ".."], BUILD_DIR)
    run_checked(["make", "-j2"], BUILD_DIR)

    assert os.path.isfile(APP_PATH) and not os.path.islink(APP_PATH), "The build did not create a regular myapp executable."
    mode = os.stat(APP_PATH).st_mode
    assert stat.S_ISREG(mode) and mode & 0o111, "myapp is not an executable regular file."
    with open(APP_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "myapp is not a compiled ELF executable."

    assert os.path.isfile(RUST_ARCHIVE), "The Rust static library was not built."
    with open(RUST_ARCHIVE, "rb") as f:
        assert f.read(8) == b"!<arch>\n", "librust_lib.a is not a static archive."

    symbols = run_checked(["nm", "-C", APP_PATH], PROJECT_DIR).stdout
    for symbol in ("get_system_name", "free_system_name", "sqlite3_open"):
        assert symbol in symbols, f"The built myapp does not contain/reference required symbol {symbol}."

    # Exercise the built program against a value it must reject, proving that it
    # actually reads the migrated database rather than merely producing the log.
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute("UPDATE config SET version = 3")
        conn.commit()
    finally:
        conn.close()

    rejected = subprocess.run(
        [APP_PATH], cwd=BUILD_DIR, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, timeout=30
    )
    assert rejected.returncode == 3, (
        "myapp did not reject an unexpected database version as the supplied C++ application does.\n"
        + rejected.stdout
    )
    assert not os.path.exists(OUTPUT_LOG), "myapp wrote a success log for an invalid database version."

    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute("UPDATE config SET version = 2")
        conn.commit()
    finally:
        conn.close()

    # Run more than once to exercise ownership transfer and the C++ free call.
    for _ in range(3):
        if os.path.lexists(OUTPUT_LOG):
            os.remove(OUTPUT_LOG)
        run_checked([APP_PATH], BUILD_DIR, timeout=30)
        assert os.path.isfile(OUTPUT_LOG), "The compiled application did not generate output.log."
        with open(OUTPUT_LOG, "r") as f:
            assert f.read().strip() == "System OK. Name: PolyglotGraphSystem, Version: 2"

    # CMake must not have rewritten the protected sources during configuration.
    with open(main_path, "r") as f:
        assert f.read() == EXPECTED_MAIN, "The build modified src/main.cpp."
    with open(wrapper_path, "r") as f:
        assert f.read() == EXPECTED_WRAPPER, "The build modified src/wrapper.cpp."


def test_output_log_exists_and_correct():
    assert os.path.isfile(OUTPUT_LOG), f"Expected output log at {OUTPUT_LOG} was not found. Did the application run successfully?"

    with open(OUTPUT_LOG, "r") as f:
        content = f.read().strip()

    expected_content = "System OK. Name: PolyglotGraphSystem, Version: 2"
    assert content == expected_content, f"Output log content is incorrect.\nExpected: '{expected_content}'\nFound: '{content}'"


def test_database_migration_applied():
    assert os.path.isfile(DB_PATH), f"Database at {DB_PATH} is missing."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT version FROM config LIMIT 1;")
        row = cursor.fetchone()
        assert row is not None, "No data found in the 'config' table."
        assert row[0] == 2, f"Expected version 2 in 'config' table, but found {row[0]}."
    except sqlite3.OperationalError as e:
        if "no such column: version" in str(e):
            assert False, "Migration was not applied: 'version' column is missing from 'config' table."
        else:
            raise
    finally:
        conn.close()


def test_rust_lib_fixed():
    lib_rs_path = os.path.join(PROJECT_DIR, "rust_lib/src/lib.rs")
    with open(lib_rs_path, "r") as f:
        content = f.read()
    assert "into_raw()" in content or "into_raw" in content, "The rust_lib does not appear to use `into_raw()` to fix the memory leak/borrow checker issue."


def test_cmake_fixed():
    cmake_path = os.path.join(PROJECT_DIR, "CMakeLists.txt")
    with open(cmake_path, "r") as f:
        content = f.read()
    assert "librust_lib.a" in content, "CMakeLists.txt does not link the compiled Rust library."
    assert "dl" in content and "pthread" in content and "m" in content, "CMakeLists.txt does not link the required system libraries (dl, pthread, m)."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
