#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import struct
import subprocess
import time


def test_regression_script_exists_and_executable():
    script_path = "/home/user/test_regression.sh"
    assert os.path.isfile(script_path), f"Regression script {script_path} is missing."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Regression script {script_path} is not executable."


def test_regression_script_contents():
    script_path = "/home/user/test_regression.sh"
    assert os.path.isfile(script_path), f"Regression script {script_path} is missing."
    with open(script_path, "r") as f:
        content = f.read()

    assert "CONF_PATH=/home/user/conf" in content, "The script does not set the CONF_PATH correctly."
    assert "timeout" in content, "The script does not use the 'timeout' command."
    assert "g++" in content, "The script does not compile the parser with 'g++'."


def test_parser_cpp_fixed():
    parser_path = "/home/user/parser.cpp"
    assert os.path.isfile(parser_path), f"Source file {parser_path} is missing."
    with open(parser_path, "r") as f:
        content = f.read()
    assert "chunk_size" in content, "The chunk_size variable is missing."


def test_regression_script_execution():
    script_path = "/home/user/test_regression.sh"
    source_path = "/home/user/parser.cpp"
    binary_path = "/home/user/parser"
    assert os.path.isfile(script_path), f"Regression script {script_path} is missing."

    with open(source_path, "rb") as f:
        original_source = f.read()

    # Confirm that the script really compiles and runs the source, and reports a timeout.
    try:
        with open(source_path, "w") as f:
            f.write("int main() { for (;;) {} }\n")
        if os.path.lexists(binary_path):
            os.unlink(binary_path)
        failed = subprocess.run([script_path], capture_output=True, text=True, timeout=8)
        assert failed.returncode == 1, (
            f"Regression script did not report failure for a hanging parser. "
            f"Exit: {failed.returncode}; stdout: {failed.stdout}; stderr: {failed.stderr}"
        )
        assert failed.stdout.strip().endswith("FAIL"), (
            f"Regression script did not print FAIL for a hanging parser. Output: {failed.stdout}"
        )
    finally:
        with open(source_path, "wb") as f:
            f.write(original_source)
        if os.path.lexists(binary_path):
            os.unlink(binary_path)

    # Preserve the original successful execution assertion and ensure compilation produced
    # a real native executable rather than a fabricated PASS script.
    result = subprocess.run([script_path], capture_output=True, text=True, timeout=8)
    assert result.returncode == 0, (
        f"Regression script failed with exit code {result.returncode}. Stderr: {result.stderr}"
    )
    stdout = result.stdout.strip()
    assert stdout.endswith("PASS"), f"Regression script did not print PASS. Output: {stdout}"
    assert os.path.isfile(binary_path), "Regression script did not create /home/user/parser."
    assert os.access(binary_path, os.X_OK), "Compiled parser is not executable."
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The generated parser is not a native compiled executable."


def test_parser_behavior_on_zero_length_chunk():
    source_path = "/home/user/parser.cpp"
    test_binary = "/tmp/parser_behavior_test"
    crafted_payload = "/tmp/zero_then_data.dat"

    compiled = subprocess.run(
        ["g++", source_path, "-o", test_binary],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert compiled.returncode == 0, f"parser.cpp does not compile: {compiled.stderr}"

    # A chunk after a zero-length chunk must never be processed: zero terminates the loop.
    with open(crafted_payload, "wb") as f:
        f.write(struct.pack("<I", 0))
        f.write(struct.pack("<I", 7))
        f.write(b"BBBBBBB")

    env = os.environ.copy()
    env["CONF_PATH"] = "/home/user/conf"
    result = subprocess.run(
        [test_binary, crafted_payload],
        capture_output=True,
        text=True,
        env=env,
        timeout=2,
    )
    assert result.returncode == 0, (
        f"Fixed parser did not exit normally: {result.returncode}; stderr: {result.stderr}"
    )
    assert "Processed chunk of size 7" not in result.stdout, (
        "Parser continued processing data after the zero-length chunk."
    )

    original = subprocess.run(
        [test_binary, "/home/user/payload.dat"],
        capture_output=True,
        text=True,
        env=env,
        timeout=2,
    )
    assert original.returncode == 0, (
        f"Parser did not successfully process the supplied payload: {original.stderr}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
