#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile


def expected_obfuscation(data: bytes) -> bytes:
    output = bytearray()
    position = 0

    while position < len(data):
        newline = data.find(b"\n", position)
        if newline == -1:
            content = data[position:]
            has_newline = False
            position = len(data)
        else:
            content = data[position:newline]
            has_newline = True
            position = newline + 1

        if content.startswith(b"+") and not content.startswith(b"+++"):
            output.extend(b"+" + content[1:].hex().encode("ascii"))
        elif content.startswith(b"-") and not content.startswith(b"---"):
            output.extend(b"-" + content[1:].hex().encode("ascii"))
        else:
            output.extend(content)

        if has_newline:
            output.extend(b"\n")

    return bytes(output)


def assert_utility_behavior(executable: str):
    random_text = secrets.token_hex(48).encode("ascii")
    payloads = [
        (
            b"--- a/file.txt\n"
            b"+++ b/file.txt\n"
            b"@@ -1,4 +1,4 @@\n"
            b" unchanged context\n"
            b"-old value with spaces and !@#$%^&*()\n"
            b"+new value with spaces and tabs\t\n"
            b"+\n"
            b"-\n"
            b"+++not-a-change\n"
            b"---not-a-change\n"
        ),
        "--- a/unicode\n+++ b/unicode\n-café 東京\n+naïve 🚀\n context\n".encode("utf-8"),
        b"@@ -0,0 +1,2 @@\n+" + random_text + b"\n-" + random_text[::-1] + b"\n",
        b"header without changes\n+final line has no newline",
    ]

    for payload in payloads:
        result = subprocess.run(
            [executable],
            input=payload,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"{executable} exited with {result.returncode}: "
            f"{result.stderr.decode('utf-8', errors='replace')}"
        )
        assert result.stdout == expected_obfuscation(payload), (
            f"{executable} produced incorrect output for an additional test input."
        )


def test_00_build_script_executes_successfully():
    script_path = "/home/user/build_and_test.sh"
    assert os.path.isfile(script_path), f"Bash script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Bash script {script_path} is not executable."

    for generated_path in ("/home/user/obfuscate_patch", "/home/user/artifact.patch"):
        if os.path.lexists(generated_path):
            os.unlink(generated_path)

    result = subprocess.run(
        [script_path],
        cwd="/home/user",
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Bash script exited with {result.returncode}: "
        f"{result.stderr.decode('utf-8', errors='replace')}"
    )


def test_bash_script_exists_and_executable():
    script_path = "/home/user/build_and_test.sh"
    assert os.path.isfile(script_path), f"Bash script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Bash script {script_path} is not executable."


def test_rust_source_exists():
    rust_path = "/home/user/obfuscate_patch.rs"
    assert os.path.isfile(rust_path), f"Rust source code {rust_path} does not exist."


def test_executable_exists():
    exe_path = "/home/user/obfuscate_patch"
    assert os.path.isfile(exe_path), f"Compiled executable {exe_path} does not exist."
    assert os.access(exe_path, os.X_OK), f"Compiled executable {exe_path} is not executable."
    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Compiled executable {exe_path} is not an ELF binary."


def test_artifact_content():
    input_path = "/home/user/test.patch"
    artifact_path = "/home/user/artifact.patch"

    assert os.path.isfile(input_path), f"Input file {input_path} is missing."
    assert os.path.isfile(artifact_path), f"Output artifact {artifact_path} is missing."

    with open(input_path, "r", encoding="utf-8") as f:
        input_lines = f.readlines()

    expected_lines = []
    for line in input_lines:
        stripped_newline = line.endswith("\n")
        content = line.rstrip("\n")

        if content.startswith("+") and not content.startswith("+++"):
            hex_encoded = content[1:].encode('utf-8').hex()
            expected_line = "+" + hex_encoded
        elif content.startswith("-") and not content.startswith("---"):
            hex_encoded = content[1:].encode('utf-8').hex()
            expected_line = "-" + hex_encoded
        else:
            expected_line = content

        if stripped_newline:
            expected_line += "\n"

        expected_lines.append(expected_line)

    expected_output = "".join(expected_lines)

    with open(artifact_path, "r", encoding="utf-8") as f:
        actual_output = f.read()

    assert actual_output == expected_output, "The contents of artifact.patch do not match the expected hex-encoded output."


def test_rust_source_compiles_and_both_executables_handle_additional_inputs():
    assert_utility_behavior("/home/user/obfuscate_patch")

    with tempfile.TemporaryDirectory() as temp_dir:
        independently_compiled = os.path.join(temp_dir, "obfuscate_patch")
        result = subprocess.run(
            ["rustc", "/home/user/obfuscate_patch.rs", "-o", independently_compiled],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, (
            "The submitted Rust source does not compile with rustc: "
            + result.stderr.decode("utf-8", errors="replace")
        )
        assert_utility_behavior(independently_compiled)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
