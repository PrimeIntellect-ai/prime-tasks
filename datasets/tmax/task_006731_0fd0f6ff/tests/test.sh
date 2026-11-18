#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import stat
import subprocess
from pathlib import Path

SOLUTION_PATH = Path("/home/user/solution.txt")
AUTH_PATH = Path("/home/user/auth_server")
PROJECT_PATH = Path("/home/user/cracker")


def test_solution_file_exists():
    solution_path = "/home/user/solution.txt"
    assert os.path.exists(solution_path), f"The solution file {solution_path} does not exist."
    assert os.path.isfile(solution_path), f"{solution_path} is not a regular file."


def test_solution_content():
    solution_path = "/home/user/solution.txt"
    with open(solution_path, "r", encoding="utf-8") as f:
        content = f.read()

    # The password is known to be "melon" from the setup
    expected_password = "melon"
    actual_password = content.strip()

    assert actual_password == expected_password, f"Expected password '{expected_password}', but got '{actual_password}'."


def test_rust_project_exists():
    assert PROJECT_PATH.is_dir(), "/home/user/cracker is not a directory."
    assert (PROJECT_PATH / "Cargo.toml").is_file(), "Cargo.toml is missing."
    rust_sources = list(PROJECT_PATH.rglob("*.rs"))
    assert rust_sources, "The project contains no Rust source files."


def test_cracker_runs_and_handles_dynamically_generated_binary():
    original_auth = AUTH_PATH.read_bytes()
    original_mode = stat.S_IMODE(AUTH_PATH.stat().st_mode)
    original_solution = SOLUTION_PATH.read_bytes() if SOLUTION_PATH.exists() else None

    # Generate an answer during verification and expose only its salted hash to
    # the submitted program. Vary the marker offsets as well as the salt/hash.
    while True:
        password = "".join(chr(ord("a") + secrets.randbelow(26)) for _ in range(5))
        if password != "melon":
            break
    salt = secrets.token_bytes(8)
    target_hash = hashlib.sha256(password.encode("ascii") + salt).digest()
    prefix_len = 37 + secrets.randbelow(83)
    middle_len = 53 + secrets.randbelow(149)
    suffix_len = 19 + secrets.randbelow(71)
    generated_binary = (
        b"\x7fELF\x02\x01\x01\x00"
        + b"A" * prefix_len
        + b"SALT_HDR"
        + salt
        + b"B" * middle_len
        + b"HASH_HDR"
        + target_hash
        + b"C" * suffix_len
    )

    try:
        AUTH_PATH.write_bytes(generated_binary)
        AUTH_PATH.chmod(0o755)
        if SOLUTION_PATH.exists():
            SOLUTION_PATH.unlink()

        result = subprocess.run(
            ["cargo", "run", "--release", "--quiet"],
            cwd=str(PROJECT_PATH),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=300,
            env={**os.environ, "CARGO_TERM_COLOR": "never"},
        )
        assert result.returncode == 0, "The Rust cracker did not run successfully."
        assert SOLUTION_PATH.is_file(), "The running cracker did not create solution.txt."
        assert SOLUTION_PATH.read_bytes() == password.encode("ascii"), (
            "The running cracker did not extract and crack the dynamically generated salt/hash."
        )
    finally:
        AUTH_PATH.write_bytes(original_auth)
        AUTH_PATH.chmod(original_mode)
        if original_solution is None:
            if SOLUTION_PATH.exists():
                SOLUTION_PATH.unlink()
        else:
            SOLUTION_PATH.write_bytes(original_solution)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
