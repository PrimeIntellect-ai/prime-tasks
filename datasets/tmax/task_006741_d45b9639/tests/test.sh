#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import secrets
import sqlite3
import subprocess
import tempfile

PIPELINE_DIR = "/home/user/pipeline"
DB_PATH = os.path.join(PIPELINE_DIR, "db.sqlite")
SUCCESS_LOG_PATH = os.path.join(PIPELINE_DIR, "success.log")
AUTH_SOURCE = os.path.join(PIPELINE_DIR, "src", "auth.c")
RUST_SOURCE = os.path.join(PIPELINE_DIR, "src", "main.rs")
BUILD_SCRIPT = os.path.join(PIPELINE_DIR, "build.sh")


def run(cmd, **kwargs):
    return subprocess.run(
        cmd,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
        **kwargs,
    )


def test_pipeline_sources_and_build():
    assert os.path.isfile(AUTH_SOURCE), f"Missing C source: {AUTH_SOURCE}"
    assert os.path.isfile(RUST_SOURCE), f"Missing Rust source: {RUST_SOURCE}"
    assert os.path.isfile(BUILD_SCRIPT), f"Missing build script: {BUILD_SCRIPT}"

    # Remove prior outputs so the verifier cannot accept stale or hand-written results.
    for name in ("libauth.so", "main", "success.log"):
        path = os.path.join(PIPELINE_DIR, name)
        if os.path.lexists(path):
            os.remove(path)

    run(["/bin/bash", BUILD_SCRIPT], cwd=PIPELINE_DIR)

    lib_path = os.path.join(PIPELINE_DIR, "libauth.so")
    main_path = os.path.join(PIPELINE_DIR, "main")
    assert os.path.isfile(lib_path), "build.sh did not produce libauth.so"
    assert os.path.isfile(main_path), "build.sh did not produce the Rust executable"
    with open(lib_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libauth.so is not an ELF shared library"
    with open(main_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "main is not an ELF executable"

    assert os.path.isfile(SUCCESS_LOG_PATH), f"The file {SUCCESS_LOG_PATH} does not exist. Did you run build.sh successfully?"
    with open(SUCCESS_LOG_PATH, "r") as f:
        content = f.read().strip()
    assert content == "Auth Check: 1", f"Expected success.log to contain exactly 'Auth Check: 1', but found: '{content}'"

    with tempfile.TemporaryDirectory() as td:
        # Compile the submitted C source independently and exercise the new ABI
        # over both branches, including values selected by the verifier.
        submitted_lib = os.path.join(td, "libsubmitted_auth.so")
        run(["gcc", "-shared", "-fPIC", "-o", submitted_lib, AUTH_SOURCE])
        auth = ctypes.CDLL(submitted_lib)
        check_auth = auth.check_auth
        check_auth.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int]
        check_auth.restype = ctypes.c_int

        positive = secrets.randbelow(1_000_000) + 1
        negative = -(secrets.randbelow(1_000_000) + 1)
        for expiry, expected in ((positive, 1), (1, 1), (0, 0), (negative, 0)):
            actual = check_auth(b"arbitrary-user", b"arbitrary-token", expiry)
            assert actual == expected, (
                f"check_auth returned {actual} for expiry={expiry}; expected {expected}"
            )

        # Link the submitted Rust source against an instrumented implementation.
        # This proves it keeps valid C strings alive, passes the intended arguments,
        # calls the FFI function, and prints the returned result.
        capture_path = os.path.join(td, "ffi_capture.txt")
        shim_source = os.path.join(td, "shim.c")
        shim_lib = os.path.join(td, "libauth.so")
        rust_binary = os.path.join(td, "rust_main")
        with open(shim_source, "w") as f:
            f.write(r'''
#include <stdio.h>
int check_auth(const char *username, const char *token, int expiry) {
    FILE *out = fopen("''' + capture_path + r'''", "w");
    if (!out || !username || !token) return -91;
    fprintf(out, "%s\n%s\n%d\n", username, token, expiry);
    fclose(out);
    return 73;
}
''')
        run(["gcc", "-shared", "-fPIC", "-o", shim_lib, shim_source])
        run(["rustc", RUST_SOURCE, "-L", td, "-l", "auth", "-o", rust_binary])
        env = os.environ.copy()
        env["LD_LIBRARY_PATH"] = td
        result = run([rust_binary], cwd=PIPELINE_DIR, env=env)
        assert result.stdout.strip() == "Auth Check: 73", (
            "The Rust wrapper did not print the result returned by its FFI call"
        )
        assert os.path.isfile(capture_path), "The Rust wrapper did not call check_auth"
        with open(capture_path, "r") as f:
            captured = f.read().splitlines()
        assert captured == ["admin", "secret123", "3600"], (
            f"Unexpected arguments passed through FFI: {captured}"
        )


def test_sqlite_schema():
    assert os.path.isfile(DB_PATH), f"SQLite database {DB_PATH} is missing."

    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute("PRAGMA table_info(sessions);")
        columns = {row[1]: row[2] for row in cursor.fetchall()}

        assert "expiry" in columns, "The 'expiry' column is missing from the 'sessions' table."
        assert "INTEGER" in columns["expiry"].upper(), f"The 'expiry' column should be of type INTEGER, but found {columns['expiry']}."
    finally:
        conn.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
