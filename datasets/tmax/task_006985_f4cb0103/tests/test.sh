#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import string
import subprocess
import tempfile


def test_attacker_ip_file():
    """Test that the attacker IP was correctly identified and written to the file."""
    filepath = "/home/user/attacker_ip.txt"
    assert os.path.isfile(filepath), f"File {filepath} is missing"

    with open(filepath, "r") as f:
        raw_content = f.read()
        content = raw_content.strip()

    assert content == "10.13.37.100", f"Incorrect IP address found in {filepath}. Expected '10.13.37.100', got '{content}'"
    assert raw_content == "10.13.37.100\n", f"{filepath} must contain only the IPv4 address and one newline"


def test_auth_checker_code_fixed():
    """Test that the strcpy vulnerability was removed from auth_checker.c."""
    filepath = "/home/user/evidence/auth_checker.c"
    assert os.path.isfile(filepath), f"File {filepath} is missing"

    with open(filepath, "r") as f:
        content = f.read()

    # Preserve the original source-level assertion.
    assert "strcpy(user_buf, username);" not in content, "The vulnerable strcpy(user_buf, username); is still present in the code."


def test_auth_checker_compilation_and_execution():
    """Preserve the original compilation and fixed behavioral checks."""
    source_file = "/home/user/evidence/auth_checker.c"
    assert os.path.isfile(source_file), f"File {source_file} is missing"

    with tempfile.TemporaryDirectory() as tmpdir:
        binary_path = os.path.join(tmpdir, "auth_checker")

        compile_process = subprocess.run(
            ["gcc", "-Wall", "-Werror", source_file, "-o", binary_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        assert compile_process.returncode == 0, f"Compilation failed or had warnings:\n{compile_process.stderr}"

        admin_process = subprocess.run(
            [binary_path, "admin", "supersecret"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        assert admin_process.returncode == 0, "Valid admin login failed."
        assert "Admin access granted." in admin_process.stdout, "Valid admin login output is incorrect."

        invalid_process = subprocess.run(
            [binary_path, "guest", "password"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        assert invalid_process.returncode == 1, "Invalid login should return 1."
        assert "Access denied." in invalid_process.stdout, "Invalid login output is incorrect."

        exploit_process = subprocess.run(
            [binary_path, "AAAAAAAAAAAAAAAAB", "dummy"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        assert exploit_process.returncode == 1, "Exploit payload bypassed authentication (returned 0)."
        assert "Access denied." in exploit_process.stdout, "Exploit payload did not result in 'Access denied.'"


def test_check_auth_general_behavior_and_memory_safety():
    """Call check_auth directly on unpredictable normal and boundary inputs under ASan."""
    source_file = "/home/user/evidence/auth_checker.c"
    assert os.path.isfile(source_file), f"File {source_file} is missing"

    wrapper_source = r'''
#include <stdio.h>
#include <stdlib.h>
#define main submitted_auth_checker_main
#include "/home/user/evidence/auth_checker.c"
#undef main

int main(int argc, char **argv) {
    int (*auth_fn)(const char *, const char *) = check_auth;
    if (argc < 4 || ((argc - 1) % 3) != 0) {
        return 90;
    }
    for (int i = 1; i < argc; i += 3) {
        int expected = atoi(argv[i + 2]);
        int actual = auth_fn(argv[i], argv[i + 1]);
        if (actual != expected) {
            fprintf(stderr, "check_auth mismatch for case %d: expected %d, got %d\n",
                    (i - 1) / 3, expected, actual);
            return 91;
        }
    }
    return 0;
}
'''

    alphabet = string.ascii_letters + string.digits

    def random_text(length):
        return ''.join(secrets.choice(alphabet) for _ in range(length))

    cases = [
        ("admin", "supersecret", 1),
        ("admin", "", 0),
        ("admin", "Supersecret", 0),
        ("admin", "supersecretX", 0),
        ("guest", "password", 0),
        ("AAAAAAAAAAAAAAAAB", "dummy", 0),
    ]

    # Exercise both sides of the original 16-byte boundary, plus substantially
    # longer values. The values are generated only when verification runs.
    for length in (1, 2, 7, 14, 15, 16, 17, 18, 31, 32, 63, 64, 127, 255, 1024, 4096):
        username = random_text(length)
        if username == "admin":
            username += "X"
        cases.append((username, random_text(23), 0))
        cases.append((username, "supersecret", 0))

    for _ in range(30):
        username = random_text(secrets.randbelow(300) + 1)
        password = random_text(secrets.randbelow(80) + 1)
        if username == "admin":
            username += "X"
        cases.append((username, password, 0))

    # Random wrong passwords ensure the implementation preserves the password
    # check rather than merely recognizing the admin username.
    for _ in range(10):
        password = random_text(secrets.randbelow(50) + 1)
        if password == "supersecret":
            password += "X"
        cases.append(("admin", password, 0))

    with tempfile.TemporaryDirectory() as tmpdir:
        wrapper_path = os.path.join(tmpdir, "wrapper.c")
        binary_path = os.path.join(tmpdir, "check_auth_harness")
        with open(wrapper_path, "w") as f:
            f.write(wrapper_source)

        compile_process = subprocess.run(
            [
                "gcc", "-Wall", "-Werror", "-fsanitize=address",
                "-fno-omit-frame-pointer", wrapper_path, "-o", binary_path
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        assert compile_process.returncode == 0, (
            "Direct check_auth harness failed to compile, had warnings, or the function signature changed:\n"
            + compile_process.stderr
        )

        args = [binary_path]
        for username, password, expected in cases:
            args.extend([username, password, str(expected)])

        env = os.environ.copy()
        env["ASAN_OPTIONS"] = "detect_leaks=0:halt_on_error=1"
        run_process = subprocess.run(
            args,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
            timeout=15
        )
        assert run_process.returncode == 0, (
            "check_auth failed randomized functional or memory-safety testing.\n"
            f"stdout:\n{run_process.stdout}\nstderr:\n{run_process.stderr}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
