#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile
import uuid

EXPECTED_SOURCE = b'''#include <stdio.h>
#include <string.h>

int main() {
    char input[256];

    printf("Welcome to the Legacy Migration Daemon\\n");
    printf("Enter Auth Key: ");
    fflush(stdout);
    if (fgets(input, sizeof(input), stdin) == NULL) return 1;
    input[strcspn(input, "\\n")] = 0;

    if (strcmp(input, "cloud_admin_99") != 0) {
        printf("Auth failed.\\n");
        return 1;
    }

    printf("Command: ");
    fflush(stdout);
    if (fgets(input, sizeof(input), stdin) == NULL) return 1;

    printf("Target IP: ");
    fflush(stdout);
    if (fgets(input, sizeof(input), stdin) == NULL) return 1;
    input[strcspn(input, "\\n")] = 0;

    printf("\\nSUCCESS: Migration started to %s\\n", input);
    return 0;
}
'''


def run_program(path, input_data):
    return subprocess.run(
        [path], input=input_data, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=5, check=False
    )


def test_legacy_daemon_compiled():
    """Test that the supplied C source was compiled to the expected executable."""
    source = "/home/user/legacy_daemon.c"
    executable = "/home/user/legacy_daemon"
    assert os.path.isfile(executable), f"Executable {executable} is missing."
    assert os.access(executable, os.X_OK), f"{executable} is not executable."

    with open(source, "rb") as f:
        assert f.read() == EXPECTED_SOURCE, "The supplied legacy daemon source was modified."
    with open(executable, "rb") as f:
        assert f.read(4) == b"\\x7fELF", f"{executable} is not a compiled ELF executable."

    with tempfile.TemporaryDirectory() as td:
        reference_source = os.path.join(td, "legacy_daemon.c")
        reference_exe = os.path.join(td, "legacy_daemon")
        with open(reference_source, "wb") as f:
            f.write(EXPECTED_SOURCE)
        subprocess.run(
            ["gcc", reference_source, "-o", reference_exe],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
        )

        nonce = uuid.uuid4().hex
        cases = [
            b"wrong_" + nonce.encode() + b"\\n",
            b"cloud_admin_99\\nSTART_MIGRATE\\n10.0.0.50\\n",
            b"cloud_admin_99\\ncommand_" + nonce.encode() + b"\\n192.0.2.77\\n",
            b"cloud_admin_99\\n",
        ]
        for case in cases:
            expected = run_program(reference_exe, case)
            actual = run_program(executable, case)
            assert actual.returncode == expected.returncode, "Daemon exit status differs from the compiled source."
            assert actual.stdout == expected.stdout, "Daemon output differs from the compiled source."
            assert actual.stderr == expected.stderr, "Daemon error output differs from the compiled source."


def test_expect_script_exists():
    """Test that the expect script was created."""
    script_file = "/home/user/trigger_migration.exp"
    assert os.path.isfile(script_file), f"Expect script {script_file} is missing."

    with open(script_file, "r") as f:
        content = f.read()

    # Preserve the original static assertions.
    assert "spawn" in content, f"Expect script {script_file} does not contain 'spawn'."
    assert "cloud_admin_99" in content, f"Expect script {script_file} does not contain 'cloud_admin_99'."
    assert "START_MIGRATE" in content, f"Expect script {script_file} does not contain 'START_MIGRATE'."
    assert "10.0.0.50" in content, f"Expect script {script_file} does not contain '10.0.0.50'."

    # Execute the script against a verifier-controlled interactive daemon at the
    # required path. This proves that it spawns the daemon and answers each prompt.
    daemon = "/home/user/legacy_daemon"
    backup = f"/tmp/legacy_daemon.real.{uuid.uuid4().hex}"
    marker = f"/tmp/legacy_daemon.marker.{uuid.uuid4().hex}"
    challenge = f'''#!/usr/bin/python3
import pathlib
import sys
pathlib.Path({marker!r}).write_text("spawned")
def prompt(value):
    sys.stdout.write(value)
    sys.stdout.flush()
def read():
    value = sys.stdin.readline()
    if value == "":
        sys.exit(20)
    return value.rstrip("\\r\\n")
prompt("Enter Auth Key: ")
if read() != "cloud_admin_99":
    sys.exit(21)
prompt("Command: ")
if read() != "START_MIGRATE":
    sys.exit(22)
prompt("Target IP: ")
if read() != "10.0.0.50":
    sys.exit(23)
print("SUCCESS: Migration started to 10.0.0.50")
'''

    os.rename(daemon, backup)
    try:
        with open(daemon, "w") as f:
            f.write(challenge)
        os.chmod(daemon, 0o755)
        result = subprocess.run(
            ["/usr/bin/expect", script_file],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=15, check=False
        )
        assert result.returncode == 0, f"Expect script failed when executed: {result.stderr}"
        assert os.path.isfile(marker), "Expect script did not spawn /home/user/legacy_daemon."
        assert "SUCCESS: Migration started to 10.0.0.50" in result.stdout, \
            "Expect script did not complete the required interaction."
    finally:
        try:
            os.unlink(daemon)
        except FileNotFoundError:
            pass
        os.rename(backup, daemon)
        try:
            os.unlink(marker)
        except FileNotFoundError:
            pass


def test_migration_run_log():
    """Test that the expect script was run and output redirected to the log file."""
    log_file = "/home/user/migration_run.log"
    assert os.path.isfile(log_file), f"Log file {log_file} is missing."

    with open(log_file, "r") as f:
        content = f.read()

    expected_success = "SUCCESS: Migration started to 10.0.0.50"
    assert expected_success in content, f"Log file {log_file} does not contain the expected success message: '{expected_success}'."


def test_migration_cron_file():
    """Test that the cron file was created with the correct schedule and command."""
    cron_file = "/home/user/migration.cron"
    assert os.path.isfile(cron_file), f"Cron file {cron_file} is missing."

    with open(cron_file, "r") as f:
        lines = f.readlines()

    valid_cron_found = False
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if re.match(r'^0\s+\*\s+\*\s+\*\s+\*\s+/usr/bin/expect\s+/home/user/trigger_migration\.exp\s*>\s*/home/user/migration_run\.log$', line):
            valid_cron_found = True
            break

    assert valid_cron_found, f"Cron file {cron_file} does not contain the correct cron schedule and command."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
