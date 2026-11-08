#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import itertools
import os
import pwd
import subprocess

COOKIE_PATH = "/home/user/admin_cookie.txt"
SOURCE_PATH = "/home/user/bruteforce.c"
BINARY_PATH = "/tmp/bruteforce_submission"


def custom_hash(value):
    h = 5381
    for byte in value.encode("ascii"):
        h = ((h << 5) + h + byte) & 0xffffffff
    return h


def derive_expected_cookie():
    captured_signature = 594879208
    secret = None
    for chars in itertools.product("abcdefghijklmnopqrstuvwxyz", repeat=4):
        candidate = "".join(chars)
        if custom_hash("guest" + candidate) == captured_signature:
            secret = candidate
            break
    assert secret is not None, "No secret matched the captured guest signature."
    return f"Cookie: user=admin;sig={custom_hash('admin' + secret)}"


def test_admin_cookie_file_exists():
    """Test that the admin_cookie.txt file exists."""
    assert os.path.isfile(COOKIE_PATH), "The file /home/user/admin_cookie.txt does not exist."


def test_bruteforce_c_file_exists():
    """Test that the bruteforce.c file exists."""
    assert os.path.isfile(SOURCE_PATH), "The file /home/user/bruteforce.c does not exist."


def test_compile_and_run_bruteforce_program():
    """Compile the submitted C source and require it to regenerate the forged cookie."""
    assert os.path.getsize(SOURCE_PATH) > 0, "The submitted C source is empty."
    subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE_PATH, "-o", BINARY_PATH],
        check=True,
        timeout=30,
    )

    os.unlink(COOKIE_PATH)
    user = pwd.getpwnam("user")

    def drop_privileges():
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    with open(COOKIE_PATH, "wb") as output:
        subprocess.run(
            [BINARY_PATH],
            cwd="/home/user",
            stdout=output,
            stderr=subprocess.PIPE,
            check=True,
            timeout=30,
            preexec_fn=drop_privileges,
        )

    expected = derive_expected_cookie().encode("ascii")
    with open(COOKIE_PATH, "rb") as f:
        generated = f.read()
    assert generated == expected, (
        "Running the compiled bruteforce.c did not generate the exact forged cookie."
    )


def test_admin_cookie_content():
    """Test that the admin_cookie.txt contains the correct forged cookie."""
    with open(COOKIE_PATH, "r") as f:
        content = f.read().strip()

    expected_cookie = "Cookie: user=admin;sig=415309657"
    assert content == expected_cookie, f"Expected cookie '{expected_cookie}', but found '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
