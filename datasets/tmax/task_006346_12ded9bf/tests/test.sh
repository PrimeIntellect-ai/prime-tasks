#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import stat
import subprocess
import tempfile

C_FILE = "/home/user/verify_restore.c"
BINARY = "/home/user/verify_restore"
SCRIPT = "/home/user/run_validation.sh"
RESTORE_DIR = "/home/user/restore_test"
LOG_FILE = "/home/user/restore_log.txt"
EXPECTED_FILES = {"mail_config.conf", "vm_settings.json", "postfix_main.cf", "aliases"}
EXPECTED_OUTPUT = "RESTORE_CHECK: SUCCESS, FILES: 4, PORT: 2525"


def test_c_file_exists_and_no_hardcoding():
    assert os.path.exists(C_FILE), f"C source file {C_FILE} is missing."
    with open(C_FILE, "r") as f:
        content = f.read()
    assert "2525" not in content, "The SMTP port (2525) appears to be hardcoded in the C source."
    assert "FILES: 4" not in content, "The file count (4) appears to be hardcoded in the C source."


def test_c_binary_exists_and_executable():
    assert os.path.exists(BINARY), f"Compiled binary {BINARY} is missing."
    assert os.access(BINARY, os.X_OK), f"Binary {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "verify_restore is not a compiled executable."


def test_bash_script_exists_and_executable():
    assert os.path.exists(SCRIPT), f"Bash script {SCRIPT} is missing."
    assert os.access(SCRIPT, os.X_OK), f"Bash script {SCRIPT} is not executable."
    with open(SCRIPT, "r") as f:
        first_line = f.readline().strip()
    assert "bash" in first_line, "run_validation.sh is not a Bash script."
    syntax = subprocess.run(["bash", "-n", SCRIPT], capture_output=True, text=True)
    assert syntax.returncode == 0, f"run_validation.sh has invalid Bash syntax: {syntax.stderr}"


def exercise_tool(executable):
    rng = secrets.SystemRandom()
    for _ in range(3):
        with tempfile.TemporaryDirectory(prefix="restore_dynamic_") as directory:
            port = rng.randrange(1025, 65000)
            extra_count = rng.randrange(1, 7)
            with open(os.path.join(directory, "mail_config.conf"), "w") as f:
                f.write("LISTEN_IP=127.0.0.1\n")
                f.write(f"UNRELATED_PORT={rng.randrange(1, 1000)}\n")
                f.write(f"SMTP_PORT={port}\n")
                f.write("ENABLE_TLS=yes\n")

            for i in range(extra_count):
                name = f"data_{secrets.token_hex(5)}_{i}.cfg"
                with open(os.path.join(directory, name), "w") as f:
                    f.write(secrets.token_hex(12))

            nested = os.path.join(directory, "nested")
            os.mkdir(nested)
            for i in range(3):
                with open(os.path.join(nested, f"ignored_{i}"), "w") as f:
                    f.write("must not be counted")

            expected = f"RESTORE_CHECK: SUCCESS, FILES: {extra_count + 1}, PORT: {port}\n"
            result = subprocess.run([executable, directory], capture_output=True, text=True)
            assert result.returncode == 0, f"Tool failed on a dynamic fixture: {result.stderr}"
            assert result.stdout == expected, f"Dynamic output incorrect. Expected {expected!r}, got {result.stdout!r}"

    no_arg = subprocess.run([executable], capture_output=True, text=True)
    assert no_arg.returncode != 0, "Tool must reject invocation without a directory argument."
    two_args = subprocess.run([executable, "/tmp", "/tmp"], capture_output=True, text=True)
    assert two_args.returncode != 0, "Tool must reject invocation with more than one argument."


def test_c_source_compiles_and_is_dynamic():
    with tempfile.TemporaryDirectory(prefix="compiled_source_") as td:
        compiled = os.path.join(td, "verify_restore_from_source")
        build = subprocess.run(["gcc", C_FILE, "-o", compiled], capture_output=True, text=True)
        assert build.returncode == 0, f"verify_restore.c does not compile: {build.stderr}"
        exercise_tool(compiled)


def test_installed_c_binary_is_dynamic():
    exercise_tool(BINARY)


def test_validation_script_behavior():
    token = "VALIDATION_PROBE_" + secrets.token_hex(16)
    marker = "/tmp/validation_probe_" + secrets.token_hex(10)
    backup_binary = "/tmp/verify_restore_backup_" + secrets.token_hex(10)
    shutil.copy2(BINARY, backup_binary)

    os.makedirs(RESTORE_DIR, exist_ok=True)
    for entry in os.listdir(RESTORE_DIR):
        path = os.path.join(RESTORE_DIR, entry)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)
    with open(os.path.join(RESTORE_DIR, "stale_file_must_be_removed"), "w") as f:
        f.write("stale")

    probe = f'''#!/usr/bin/python3
import os
import sys
expected = {sorted(EXPECTED_FILES)!r}
restore = {RESTORE_DIR!r}
marker = {marker!r}
token = {token!r}
if len(sys.argv) != 2 or os.path.realpath(sys.argv[1]) != os.path.realpath(restore):
    sys.exit(21)
if sorted(os.listdir(restore)) != expected:
    sys.exit(22)
with open(os.path.join(restore, "mail_config.conf"), "r") as f:
    if "SMTP_PORT=2525" not in f.read():
        sys.exit(23)
with open(marker, "w") as f:
    f.write(sys.argv[1])
print(token)
'''

    try:
        with open(BINARY, "w") as f:
            f.write(probe)
        os.chmod(BINARY, 0o755)
        result = subprocess.run([SCRIPT], capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, f"Validation script failed: {result.stderr}"
        assert os.path.exists(marker), "Validation script did not execute /home/user/verify_restore."
        with open(marker, "r") as f:
            assert os.path.realpath(f.read()) == os.path.realpath(RESTORE_DIR), "Validation script passed the wrong directory to the tool."
        with open(LOG_FILE, "r") as f:
            assert f.read() == token + "\n", "Validation script did not redirect the tool's stdout to restore_log.txt."
        assert set(os.listdir(RESTORE_DIR)) == EXPECTED_FILES, "Validation script did not safely empty and freshly extract restore_test."
    finally:
        shutil.copy2(backup_binary, BINARY)
        os.unlink(backup_binary)
        if os.path.exists(marker):
            os.unlink(marker)
        final_run = subprocess.run([SCRIPT], capture_output=True, text=True, timeout=30)
        assert final_run.returncode == 0, f"Validation script failed with the compiled tool: {final_run.stderr}"


def test_restore_test_directory_contents():
    assert os.path.isdir(RESTORE_DIR), f"Directory {RESTORE_DIR} is missing or not a directory."
    actual_files = set(os.listdir(RESTORE_DIR))
    for filename in EXPECTED_FILES:
        assert filename in actual_files, f"Expected file {filename} is missing from {RESTORE_DIR}."
    with open(os.path.join(RESTORE_DIR, "mail_config.conf"), "r") as f:
        content = f.read()
        assert "SMTP_PORT=2525" in content, "mail_config.conf does not contain the expected SMTP_PORT."


def test_restore_log_output():
    assert os.path.exists(LOG_FILE), f"Log file {LOG_FILE} is missing. Did you run the bash script?"
    with open(LOG_FILE, "r") as f:
        content = f.read().strip()
    assert EXPECTED_OUTPUT in content, f"Log file does not contain the expected output. Found: {content}"


def test_c_binary_behavior():
    result = subprocess.run([BINARY, RESTORE_DIR], capture_output=True, text=True)
    assert result.returncode == 0, "C binary did not exit with return code 0."
    assert EXPECTED_OUTPUT in result.stdout.strip(), f"C binary output incorrect. Got: {result.stdout}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
