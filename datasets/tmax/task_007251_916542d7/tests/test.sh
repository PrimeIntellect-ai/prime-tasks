#!/bin/bash
mkdir -p /logs/verifier

BASE_DIR="/home/user/rust-api"
script_ok=1
tests_ok=1

# Remove all generated artifacts so they must be recreated by the submitted script.
rm -rf "$BASE_DIR/bin"
rm -f "$BASE_DIR/src/rate_limit.rs" "$BASE_DIR/build.log"

# Execute the artifact the task required the agent to fix.
if ! timeout 60s runuser -u user -- bash -c 'cd /home/user/rust-api && ./build_and_run.sh' >/tmp/build_and_run.stdout 2>/tmp/build_and_run.stderr; then
    script_ok=0
    cat /tmp/build_and_run.stdout 2>/dev/null || true
    cat /tmp/build_and_run.stderr 2>/dev/null || true
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess

BASE_DIR = "/home/user/rust-api"
SRC_DIR = os.path.join(BASE_DIR, "src")
BIN_DIR = os.path.join(BASE_DIR, "bin")
MAIN_RS = os.path.join(SRC_DIR, "main.rs")
RATE_LIMIT_RS = os.path.join(SRC_DIR, "rate_limit.rs")
BUILD_SH = os.path.join(BASE_DIR, "build_and_run.sh")
BIN_MAIN = os.path.join(BIN_DIR, "main")
BUILD_LOG = os.path.join(BASE_DIR, "build.log")


def test_build_script_exists_and_executable():
    assert os.path.isfile(BUILD_SH), f"File {BUILD_SH} does not exist."
    st = os.stat(BUILD_SH)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {BUILD_SH} is not executable."


def test_rate_limit_rs_content():
    assert os.path.isfile(RATE_LIMIT_RS), f"File {RATE_LIMIT_RS} was not generated."
    with open(RATE_LIMIT_RS, "r") as f:
        content = f.read().strip()

    # Check that it contains the correct Rust syntax and the decoded limit (100)
    assert "pub const LIMIT: u32 = 100;" in content, f"{RATE_LIMIT_RS} does not contain the expected Rust constant definition."


def test_compiled_binary_exists_and_executable():
    assert os.path.isdir(BIN_DIR), f"Directory {BIN_DIR} was not created."
    assert os.path.isfile(BIN_MAIN), f"Compiled binary {BIN_MAIN} does not exist."
    st = os.stat(BIN_MAIN)
    assert bool(st.st_mode & stat.S_IXUSR), f"Compiled binary {BIN_MAIN} is not executable."


def test_compiled_binary_is_native_executable():
    with open(BIN_MAIN, "rb") as f:
        magic = f.read(4)
    assert magic == b"\x7fELF", f"{BIN_MAIN} is not an ELF executable produced for this Linux environment."


def test_build_log_content():
    assert os.path.isfile(BUILD_LOG), f"File {BUILD_LOG} was not generated."
    with open(BUILD_LOG, "r") as f:
        content = f.read().strip()

    expected_output = "API configured with rate limit: 100"
    assert content == expected_output, f"Expected {BUILD_LOG} to contain '{expected_output}', but got '{content}'"


def test_compiled_binary_behavior_matches_log():
    result = subprocess.run(
        [BIN_MAIN],
        cwd=BASE_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, f"{BIN_MAIN} exited with {result.returncode}: {result.stderr}"
    expected_output = "API configured with rate limit: 100"
    assert result.stdout.strip() == expected_output, (
        f"Expected the compiled binary to output '{expected_output}', but got '{result.stdout.strip()}'"
    )
    with open(BUILD_LOG, "r") as f:
        logged_output = f.read().strip()
    assert result.stdout.strip() == logged_output, "build.log does not match the compiled binary's output."
TEST_EOF

if ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    tests_ok=0
fi

if [ "$script_ok" -eq 1 ] && [ "$tests_ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
