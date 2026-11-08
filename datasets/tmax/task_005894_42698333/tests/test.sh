#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import tempfile


def generate_expected(url, secret):
    value = 5381
    for byte in (url + secret).encode("ascii"):
        value = ((value * 33) + byte) & 0xFFFFFFFF
    return value


def test_incident_report():
    path = "/home/user/incident_report.txt"
    assert os.path.exists(path), f"Missing required file: {path}"
    assert os.path.isfile(path), f"Path is not a file: {path}"

    with open(path, 'r') as f:
        content = f.read().strip()

    expected_content = "CWE: CWE-601\nSecret: Inc1d3nt_R3sp0nse_K3y_8872!"

    # Normalize line endings for comparison
    content_normalized = '\n'.join([line.strip() for line in content.splitlines() if line.strip()])
    expected_normalized = '\n'.join([line.strip() for line in expected_content.splitlines() if line.strip()])

    assert content_normalized == expected_normalized, f"Content of {path} is incorrect. Expected:\n{expected_content}\nGot:\n{content}"


def test_safe_token():
    path = "/home/user/safe_token.txt"
    assert os.path.exists(path), f"Missing required file: {path}"
    assert os.path.isfile(path), f"Path is not a file: {path}"

    with open(path, 'r') as f:
        content = f.read().strip()

    expected_token = "3187217578"
    assert content == expected_token, f"Content of {path} is incorrect. Expected {expected_token}, got {content}"

    # Check permissions
    st = os.stat(path)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o600, f"Permissions of {path} are incorrect. Expected 0600, got {oct(perms)}"


def test_forge_cpp():
    path = "/home/user/forge.cpp"
    assert os.path.exists(path), f"Missing required file: {path}"
    assert os.path.isfile(path), f"Path is not a file: {path}"

    with open(path, 'r') as f:
        content = f.read()

    assert len(content.strip()) > 0, f"File {path} is empty"

    executable = "/tmp/forge_submission"
    compile_result = subprocess.run(
        ["g++", "-std=c++17", path, "-o", executable],
        text=True, capture_output=True, timeout=30
    )
    assert compile_result.returncode == 0, f"forge.cpp did not compile:\n{compile_result.stderr}"

    # Remove the pre-existing token while executing the submitted program so the
    # run must itself produce the required value, either on stdout or in the file.
    token_path = "/home/user/safe_token.txt"
    backup_path = tempfile.mktemp(prefix="safe_token_backup_", dir="/tmp")
    os.replace(token_path, backup_path)
    generated_file_value = None
    try:
        run_result = subprocess.run(
            [executable], cwd="/home/user", text=True,
            capture_output=True, timeout=10
        )
        if os.path.isfile(token_path):
            with open(token_path, "r") as f:
                generated_file_value = f.read().strip()
    finally:
        if os.path.lexists(token_path):
            os.unlink(token_path)
        os.replace(backup_path, token_path)

    required = str(generate_expected(
        "https://secure.internal.com",
        "Inc1d3nt_R3sp0nse_K3y_8872!"
    ))
    assert run_result.returncode == 0, f"Compiled forge program failed:\n{run_result.stderr}"
    assert run_result.stdout.strip() == required or generated_file_value == required, (
        "Executing forge.cpp did not generate the required token"
    )

    # Exercise the submitted generate_token implementation on independently
    # derived inputs, preventing a program that merely prints the one fixed token.
    harness_path = "/tmp/forge_harness.cpp"
    harness_executable = "/tmp/forge_harness"
    with open(harness_path, "w") as f:
        f.write(r'''#include <iostream>
#include <string>
#define main forge_submission_main
#include "/home/user/forge.cpp"
#undef main
int main() {
    std::cout << generate_token("https://example.net/callback", "alpha-42") << "\n";
    std::cout << generate_token("/login?next=/admin", "Responder_Key_9!") << "\n";
    std::cout << generate_token("https://secure.internal.com", "Inc1d3nt_R3sp0nse_K3y_8872!") << "\n";
    return 0;
}
''')

    harness_compile = subprocess.run(
        ["g++", "-std=c++17", harness_path, "-o", harness_executable],
        text=True, capture_output=True, timeout=30
    )
    assert harness_compile.returncode == 0, (
        "Could not exercise generate_token from forge.cpp:\n" + harness_compile.stderr
    )

    harness_run = subprocess.run(
        [harness_executable], text=True, capture_output=True, timeout=10
    )
    assert harness_run.returncode == 0, f"Token-generation harness failed:\n{harness_run.stderr}"

    cases = [
        ("https://example.net/callback", "alpha-42"),
        ("/login?next=/admin", "Responder_Key_9!"),
        ("https://secure.internal.com", "Inc1d3nt_R3sp0nse_K3y_8872!"),
    ]
    expected = [str(generate_expected(url, secret)) for url, secret in cases]
    actual = [line.strip() for line in harness_run.stdout.splitlines() if line.strip()]
    assert actual == expected, f"generate_token logic is incorrect. Expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
