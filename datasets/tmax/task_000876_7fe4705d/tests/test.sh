#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import stat
import subprocess

import pytest

BASE = "/home/user"
SETUP = f"{BASE}/setup_env.sh"
SOURCE = f"{BASE}/src/ip_filter.cpp"
BINARY = f"{BASE}/bin/ip_filter"
ACL = f"{BASE}/config/acl.conf"
LOG = f"{BASE}/logs/filter.log"
COMPILED = "/tmp/ip_filter_from_submitted_source"


def mode(path):
    return stat.S_IMODE(os.stat(path).st_mode)


def run_setup():
    result = subprocess.run(["bash", SETUP], capture_output=True, text=True)
    assert result.returncode == 0, (
        f"setup_env.sh failed with exit code {result.returncode}. "
        f"stderr: {result.stderr}"
    )


def write_acl(lines):
    os.makedirs(os.path.dirname(ACL), exist_ok=True)
    with open(ACL, "w") as f:
        for line in lines:
            f.write(line + "\n")
    os.chmod(ACL, 0o400)


def assert_invocation(executable, address, expected_status, expected_entry):
    marker = b"preexisting-log-entry\n"
    with open(LOG, "wb") as f:
        f.write(marker)
    os.chmod(LOG, 0o644)
    result = subprocess.run([executable, address], capture_output=True)
    assert result.returncode == expected_status, (
        f"{executable} returned {result.returncode} for {address}; "
        f"expected {expected_status}. stderr={result.stderr!r}"
    )
    with open(LOG, "rb") as f:
        contents = f.read()
    assert contents == marker + expected_entry.encode() + b"\n", (
        f"Incorrect log append for {address}: {contents!r}"
    )


def test_directories_exist():
    dirs = [
        "/home/user/src",
        "/home/user/bin",
        "/home/user/config",
        "/home/user/logs",
    ]
    for directory in dirs:
        assert os.path.isdir(directory), f"Directory {directory} does not exist."


def test_setup_env_script_and_acl_file():
    assert os.path.isfile(SETUP), f"{SETUP} does not exist."
    assert os.access(SETUP, os.X_OK), f"{SETUP} is not executable."

    run_setup()

    assert os.path.isfile(ACL), f"{ACL} does not exist."
    with open(ACL, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    assert lines == ["10.0.0.5", "192.168.1.100"], (
        f"acl.conf contents are incorrect: {lines}"
    )
    with open(ACL, "rb") as f:
        assert f.read() == b"10.0.0.5\n192.168.1.100\n"
    assert mode(ACL) == 0o400, (
        f"acl.conf has incorrect permissions: {oct(mode(ACL))}, expected 0o400."
    )
    assert os.path.isfile(LOG), f"{LOG} does not exist."
    assert mode(LOG) == 0o644

    # Damage managed state and ensure repeated setup repairs it without
    # truncating an already-existing log.
    os.chmod(ACL, 0o600)
    with open(ACL, "w") as f:
        f.write("203.0.113.9\nJUNK\n")
    sentinel = b"preserve-existing-log\n"
    with open(LOG, "wb") as f:
        f.write(sentinel)
    os.chmod(LOG, 0o600)

    run_setup()
    run_setup()

    with open(ACL, "rb") as f:
        assert f.read() == b"10.0.0.5\n192.168.1.100\n"
    assert mode(ACL) == 0o400
    with open(LOG, "rb") as f:
        assert f.read() == sentinel, "Idempotent setup truncated an existing log."
    assert mode(LOG) == 0o644


@pytest.fixture(scope="session")
def compiled_source():
    assert os.path.isfile(SOURCE), f"{SOURCE} does not exist."
    assert stat.S_ISREG(os.stat(SOURCE).st_mode), f"{SOURCE} is not a regular file."
    result = subprocess.run(
        ["g++", "-std=c++17", SOURCE, "-o", COMPILED],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, (
        f"ip_filter.cpp did not compile. stdout: {result.stdout} stderr: {result.stderr}"
    )
    assert os.path.isfile(COMPILED) and os.access(COMPILED, os.X_OK)
    return COMPILED


def test_cpp_source_compiles(compiled_source):
    assert compiled_source == COMPILED


def test_ip_filter_binary_original_cases():
    assert os.path.isfile(BINARY), f"{BINARY} does not exist."
    assert stat.S_ISREG(os.stat(BINARY).st_mode), f"{BINARY} is not a regular file."
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "ip_filter must be a compiled executable."

    write_acl(["10.0.0.5", "192.168.1.100"])
    assert_invocation(BINARY, "192.168.1.100", 0, "[ALLOW] 192.168.1.100")
    assert_invocation(BINARY, "1.1.1.1", 1, "[DENY] 1.1.1.1")


def test_ip_filter_acl_dependent_behavior_and_arguments(compiled_source):
    executables = [BINARY, compiled_source]
    octets = [secrets.randbelow(200) + 1 for _ in range(6)]
    allowed = f"10.{octets[0]}.{octets[1]}.{octets[2]}"
    other_allowed = f"172.{16 + octets[3] % 16}.{octets[4]}.{octets[5]}"
    denied = f"192.0.2.{secrets.randbelow(253) + 1}"
    while denied in (allowed, other_allowed):
        denied = f"198.51.100.{secrets.randbelow(253) + 1}"

    try:
        for executable in executables:
            write_acl([allowed, other_allowed])
            assert_invocation(executable, allowed, 0, f"[ALLOW] {allowed}")
            assert_invocation(executable, denied, 1, f"[DENY] {denied}")

            write_acl([])
            assert_invocation(executable, allowed, 1, f"[DENY] {allowed}")

            os.unlink(ACL)
            assert_invocation(executable, other_allowed, 1, f"[DENY] {other_allowed}")

            # Exactly one command-line argument is required. Invalid arity must
            # be rejected and must not fabricate an IP log entry.
            with open(LOG, "wb") as f:
                f.write(b"arity-marker\n")
            no_arg = subprocess.run([executable], capture_output=True)
            assert no_arg.returncode != 0, "ip_filter accepted zero arguments."
            with open(LOG, "rb") as f:
                assert f.read() == b"arity-marker\n"

            extra_arg = subprocess.run(
                [executable, allowed, denied], capture_output=True
            )
            assert extra_arg.returncode != 0, "ip_filter accepted multiple arguments."
            with open(LOG, "rb") as f:
                assert f.read() == b"arity-marker\n"
    finally:
        run_setup()


def test_rotate_script():
    rotate_script = "/home/user/rotate.sh"
    assert os.path.isfile(rotate_script), f"{rotate_script} does not exist."
    assert os.access(rotate_script, os.X_OK), f"{rotate_script} is not executable."

    log_dir = "/home/user/logs"
    with open(f"{log_dir}/filter.log", "w") as f:
        f.write("test0\n")
    with open(f"{log_dir}/filter.log.1", "w") as f:
        f.write("test1\n")
    with open(f"{log_dir}/filter.log.2", "w") as f:
        f.write("test2\n")

    result = subprocess.run(["bash", rotate_script], capture_output=True, text=True)
    assert result.returncode == 0, f"rotate.sh failed with exit code {result.returncode}."

    assert os.path.isfile(f"{log_dir}/filter.log"), "New filter.log was not created."
    with open(f"{log_dir}/filter.log", "r") as f:
        assert f.read() == "", "New filter.log is not empty."
    assert mode(f"{log_dir}/filter.log") == 0o644

    with open(f"{log_dir}/filter.log.1", "r") as f:
        assert f.read().strip() == "test0"
    with open(f"{log_dir}/filter.log.2", "r") as f:
        assert f.read().strip() == "test1"
    with open(f"{log_dir}/filter.log.3", "r") as f:
        assert f.read().strip() == "test2"


def test_rotate_script_repeated_randomized_state():
    rotate_script = "/home/user/rotate.sh"
    log_dir = "/home/user/logs"
    values = [secrets.token_hex(12) for _ in range(5)]
    for suffix, value in zip(["", ".1", ".2", ".3"], values[:4]):
        with open(f"{log_dir}/filter.log{suffix}", "w") as f:
            f.write(value + "\n")

    result = subprocess.run(["bash", rotate_script], capture_output=True, text=True)
    assert result.returncode == 0
    with open(f"{log_dir}/filter.log", "rb") as f:
        assert f.read() == b""
    with open(f"{log_dir}/filter.log.1") as f:
        assert f.read() == values[0] + "\n"
    with open(f"{log_dir}/filter.log.2") as f:
        assert f.read() == values[1] + "\n"
    with open(f"{log_dir}/filter.log.3") as f:
        assert f.read() == values[2] + "\n"

    with open(f"{log_dir}/filter.log", "w") as f:
        f.write(values[4] + "\n")
    result = subprocess.run(["bash", rotate_script], capture_output=True, text=True)
    assert result.returncode == 0
    with open(f"{log_dir}/filter.log", "rb") as f:
        assert f.read() == b""
    assert mode(f"{log_dir}/filter.log") == 0o644
    with open(f"{log_dir}/filter.log.1") as f:
        assert f.read() == values[4] + "\n"
    with open(f"{log_dir}/filter.log.2") as f:
        assert f.read() == values[0] + "\n"
    with open(f"{log_dir}/filter.log.3") as f:
        assert f.read() == values[1] + "\n"


def test_diagnostics():
    test_script = "/home/user/test_filter.sh"
    diag_file = "/home/user/logs/diagnostics.txt"
    assert os.path.isfile(test_script), f"{test_script} does not exist."
    assert os.access(test_script, os.X_OK), f"{test_script} is not executable."

    # Preserve the original assertion that diagnostics were run before grading.
    assert os.path.isfile(diag_file), f"{diag_file} does not exist."
    with open(diag_file, "r") as f:
        content = f.read()
    assert "DIAGNOSTICS_PASSED" in content, (
        "diagnostics.txt does not contain 'DIAGNOSTICS_PASSED'. "
        f"Content: {content}"
    )

    backup = "/tmp/original_ip_filter_for_diagnostics"
    calls = "/tmp/diagnostic_filter_calls"
    control = "/tmp/diagnostic_filter_mode"
    if os.path.exists(backup):
        os.unlink(backup)
    os.replace(BINARY, backup)
    stub = '''#!/bin/bash
printf '%s:%s\\n' "$#" "$*" >> /tmp/diagnostic_filter_calls
mode=$(cat /tmp/diagnostic_filter_mode)
if [ "$#" -ne 1 ]; then exit 9; fi
case "$mode:$1" in
  ok:10.0.0.5) exit 0 ;;
  ok:10.0.0.99) exit 1 ;;
  first_fail:10.0.0.5) exit 1 ;;
  first_fail:10.0.0.99) exit 1 ;;
  second_success:10.0.0.5) exit 0 ;;
  second_success:10.0.0.99) exit 0 ;;
  *) exit 8 ;;
esac
'''
    try:
        with open(BINARY, "w") as f:
            f.write(stub)
        os.chmod(BINARY, 0o755)

        def exercise(diag_mode, should_append):
            with open(control, "w") as f:
                f.write(diag_mode)
            with open(calls, "w"):
                pass
            with open(diag_file, "w"):
                pass
            subprocess.run(["bash", test_script], capture_output=True, text=True)
            with open(diag_file, "r") as f:
                diagnostic_lines = [line.strip() for line in f if line.strip()]
            if should_append:
                assert diagnostic_lines == ["DIAGNOSTICS_PASSED"]
            else:
                assert "DIAGNOSTICS_PASSED" not in diagnostic_lines
            with open(calls, "r") as f:
                return [line.strip() for line in f if line.strip()]

        valid_calls = exercise("ok", True)
        assert valid_calls == ["1:10.0.0.5", "1:10.0.0.99"], (
            f"test_filter.sh made incorrect calls: {valid_calls}"
        )

        success_on_denied_calls = exercise("second_success", False)
        assert success_on_denied_calls == ["1:10.0.0.5", "1:10.0.0.99"]

        exercise("first_fail", False)
    finally:
        if os.path.lexists(BINARY):
            os.unlink(BINARY)
        os.replace(backup, BINARY)
        for path in (calls, control):
            if os.path.exists(path):
                os.unlink(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
