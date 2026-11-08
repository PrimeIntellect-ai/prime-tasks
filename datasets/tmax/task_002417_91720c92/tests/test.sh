#!/bin/bash
set -e
mkdir -p /logs/verifier

# Remove prior build products so placeholders or stale artifacts cannot satisfy the checks.
rm -f /home/user/waf_project/c_src/libparser.so
rm -f /home/user/waf_project/rust_app/target/debug/waf_app
rm -f /home/user/waf_project/rust_app/target/release/waf_app

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import sqlite3
import subprocess

PROJECT = "/home/user/waf_project"
SO_PATH = f"{PROJECT}/c_src/libparser.so"
DEBUG_BIN = f"{PROJECT}/rust_app/target/debug/waf_app"
RELEASE_BIN = f"{PROJECT}/rust_app/target/release/waf_app"


def rust_binary():
    if os.path.isfile(DEBUG_BIN):
        return DEBUG_BIN
    if os.path.isfile(RELEASE_BIN):
        return RELEASE_BIN
    raise AssertionError("Rust binary 'waf_app' not found in target/debug/ or target/release/. Did the build succeed?")


def expected_decode(value):
    result = []
    i = 0
    while i < len(value):
        if value[i] == "%" and i + 2 < len(value):
            result.append(chr(int(value[i + 1:i + 3], 16)))
            i += 3
        elif value[i] == "+":
            result.append(" ")
            i += 1
        else:
            result.append(value[i])
            i += 1
    return "".join(result)


def test_build_project():
    build_script = f"{PROJECT}/build.sh"
    assert os.path.isfile(build_script), f"Build script {build_script} is missing."
    completed = subprocess.run(
        ["bash", build_script],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
    )
    assert completed.returncode == 0, f"build.sh failed:\n{completed.stdout}"


def test_result_log():
    log_path = "/home/user/waf_project/result.log"
    assert os.path.isfile(log_path), f"Log file {log_path} is missing. The application may not have been run or output was not redirected."

    with open(log_path, "r") as f:
        content = f.read().strip()

    expected = "Decoded: SELECT * FROM users"
    assert expected in content, f"Expected '{expected}' in {log_path}, but got: {content}"

    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = f"{PROJECT}/c_src" + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
    actual = subprocess.run(
        [rust_binary(), "SELECT%20*%20FROM%20users"],
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
        check=True,
    ).stdout.strip()
    assert actual == expected, f"Rust application produced {actual!r} for the required payload"
    assert content == actual, "result.log does not exactly match the Rust application's output for the required payload."


def test_database_schema():
    db_path = "/home/user/waf_project/rules.db"
    assert os.path.isfile(db_path), f"Database file {db_path} is missing."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("PRAGMA table_info(rules);")
    columns = cursor.fetchall()

    col_names = [col[1] for col in columns]
    assert "action" in col_names, "The 'action' column is missing from the 'rules' table schema."

    action_col = next((col for col in columns if col[1] == "action"), None)
    assert action_col is not None
    dflt_value = action_col[4]
    assert dflt_value in ("'block'", '\"block\"', "block"), f"Expected default value 'block' for action column, got {dflt_value}"

    conn.close()


def test_rust_binary_exists():
    assert os.path.isfile(DEBUG_BIN) or os.path.isfile(RELEASE_BIN), "Rust binary 'waf_app' not found in target/debug/ or target/release/. Did the build succeed?"
    binary = rust_binary()
    assert os.access(binary, os.X_OK), f"Rust binary {binary} is not executable."
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Rust binary {binary} is not an ELF executable."


def test_c_shared_library_exists():
    assert os.path.isfile(SO_PATH), f"Shared library {SO_PATH} is missing. Did the C code compile successfully?"
    with open(SO_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Shared library {SO_PATH} is not an ELF shared object."


def test_c_decoder_behavior():
    library = ctypes.CDLL(SO_PATH)
    decoder = library.url_decode
    decoder.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    decoder.restype = None

    cases = [
        "plain+words",
        "%41%42%43",
        "path%2fitem%3Fid%3d7",
        "mix%20UPPER%2blower+case%21",
        "%53%45%4c%45%43%54%20%2a",
    ]
    for value in cases:
        destination = ctypes.create_string_buffer(len(value) + 1)
        decoder(value.encode("ascii"), destination)
        actual = destination.value.decode("ascii")
        assert actual == expected_decode(value), f"C decoder returned {actual!r} for {value!r}"


def test_rust_uses_library_and_decodes_dynamic_inputs():
    binary = rust_binary()
    dynamic_info = subprocess.run(
        ["readelf", "-d", binary],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=15,
        check=True,
    ).stdout
    assert "libparser.so" in dynamic_info, "Rust binary is not dynamically linked to libparser.so."

    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = f"{PROJECT}/c_src" + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
    cases = [
        "hello+ffi",
        "%52%75%73%74%20and%20C",
        "admin%2Fpanel%3Fmode%3Dtest",
        "%31%2b%32%3d%33",
    ]
    for value in cases:
        completed = subprocess.run(
            [binary, value],
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert completed.returncode == 0, f"Rust application failed for {value!r}: {completed.stderr}"
        expected = f"Decoded: {expected_decode(value)}"
        assert completed.stdout.strip() == expected, f"Expected {expected!r}, got {completed.stdout.strip()!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
