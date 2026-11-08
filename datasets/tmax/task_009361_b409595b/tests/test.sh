#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import string
import subprocess

REPO = "/home/user/repo"
BINARY = os.path.join(REPO, "ws_vm")


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, capture_output=True, timeout=15, **kwargs)


def test_final_result_file():
    """Keep the original check that the requested test log was produced."""
    result_file = "/home/user/final_result.txt"
    assert os.path.isfile(result_file), (
        f"The file {result_file} does not exist. "
        "Did you run the test script after fixing the code?"
    )
    with open(result_file, "r") as f:
        content = f.read().strip()
    assert content == "ALL_PASSED", (
        f"The content of {result_file} is '{content}', but expected 'ALL_PASSED'. "
        "The test script did not complete successfully."
    )


def test_binary_compiled():
    """Keep the original binary existence and executable checks."""
    assert os.path.isfile(BINARY), (
        f"The binary {BINARY} does not exist. Did you fix the Makefile and run 'make'?"
    )
    assert os.access(BINARY, os.X_OK), f"The binary {BINARY} is not executable."


def test_clean_build_produces_real_binary():
    clean = run(["make", "clean"], cwd=REPO)
    assert clean.returncode == 0, clean.stdout + clean.stderr
    build = run(["make"], cwd=REPO)
    assert build.returncode == 0, build.stdout + build.stderr
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "make did not produce a compiled ELF ws_vm binary"


def test_route_is_safely_truncated():
    # The expected answer is derived here from an unpredictable input rather than
    # trusting the submission's self-reported test result.
    route = "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(200))
    proc = run([BINARY, "route", route])
    assert proc.returncode == 0, proc.stdout + proc.stderr
    assert proc.stdout.splitlines() == [f"Routed to: {route[:15]}"]

    # Recompile the submitted sources with AddressSanitizer so an implementation
    # that merely appears to work while overflowing route[16] is rejected.
    asan_binary = "/tmp/ws_vm_asan"
    compile_proc = run([
        "gcc", "-Wall", "-Wextra", "-fsanitize=address", "-fno-omit-frame-pointer",
        "-g", "-o", asan_binary, "main.c", "http_parser.c", "vm.c"
    ], cwd=REPO)
    assert compile_proc.returncode == 0, compile_proc.stdout + compile_proc.stderr
    env = os.environ.copy()
    env["ASAN_OPTIONS"] = "detect_leaks=0:halt_on_error=1"
    asan_proc = run([asan_binary, "route", route], env=env)
    assert asan_proc.returncode == 0, asan_proc.stdout + asan_proc.stderr
    assert asan_proc.stdout.splitlines() == [f"Routed to: {route[:15]}"]


def vm(hex_code):
    proc = run([BINARY, "vm", hex_code])
    assert proc.returncode == 0, proc.stdout + proc.stderr
    prefix = "VM Result: "
    lines = [line for line in proc.stdout.splitlines() if line.startswith(prefix)]
    assert len(lines) == 1, proc.stdout
    return int(lines[0][len(prefix):])


def test_vm_normal_and_jump_behavior():
    assert vm("010100") == 2
    # This valid jump is accepted under either plausible relative-base convention
    # exposed by the supplied patch/test materials, but must not be rejected as an
    # out-of-bounds jump in either case.
    assert vm("02010000") in (0, 1)


def test_vm_rejects_out_of_bounds_jumps():
    assert vm("027f") == -1
    assert vm("0280") == -1
    assert vm("0102fc") == -1
    # A jump without its required offset byte must also be rejected safely.
    assert vm("02") == -1
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
