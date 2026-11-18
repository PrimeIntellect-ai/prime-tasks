#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import string
import subprocess
import tempfile

ORACLE_PATH = "/app/firewall_validator_oracle"
STUDENT_BINARY = "/home/user/validator"
STUDENT_SOURCE = "/home/user/validator.c"
SERVICE_FILE = "/home/user/validator.service"


def test_student_files_exist():
    assert os.path.isfile(STUDENT_SOURCE), f"Source file {STUDENT_SOURCE} does not exist."
    assert os.path.isfile(STUDENT_BINARY), f"Compiled binary {STUDENT_BINARY} does not exist."
    assert os.access(STUDENT_BINARY, os.X_OK), f"Compiled binary {STUDENT_BINARY} is not executable."
    assert os.path.isfile(SERVICE_FILE), f"Service file {SERVICE_FILE} does not exist."


def test_service_file_content():
    with open(SERVICE_FILE, "r") as f:
        content = f.read()

    assert "ExecStart=/home/user/validator" in content and "\"test_string\"" in content, \
        "Service file missing correct ExecStart directive."
    assert "Restart=always" in content, "Service file missing Restart=always directive."
    assert "RestartSec=5" in content, "Service file missing RestartSec=5 directive."


def test_fuzz_equivalence():
    # Rebuild the submitted C source so an unrelated wrapper binary cannot pass.
    rebuilt = "/tmp/validator_rebuilt"
    compile_proc = subprocess.run(
        ["gcc", "-O2", "-static", STUDENT_SOURCE, "-o", rebuilt],
        capture_output=True,
        text=True,
    )
    assert compile_proc.returncode == 0, (
        "Submitted validator.c could not be compiled:\n"
        + compile_proc.stdout + compile_proc.stderr
    )
    assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)

    random.seed(42)
    printable_chars = string.printable
    test_inputs = [
        "".join(random.choice(printable_chars) for _ in range(random.randint(0, 255)))
        for _ in range(10000)
    ]

    # Obtain the oracle answers before executing either submitted artifact.
    expected = []
    for test_string in test_inputs:
        oracle_proc = subprocess.run(
            [ORACLE_PATH, test_string],
            capture_output=True,
            text=True,
        )
        assert oracle_proc.returncode == 0
        expected.append(oracle_proc.stdout.strip())

    # The oracle must not be available for delegation while student code runs.
    os.unlink(ORACLE_PATH)

    # Run the rebuilt source in an otherwise empty chroot, preventing it from
    # reaching alternate helper executables or files from the agent filesystem.
    sandbox = tempfile.mkdtemp(prefix="validator-root-")
    os.chmod(sandbox, 0o755)
    sandbox_binary = os.path.join(sandbox, "validator")
    shutil.copy2(rebuilt, sandbox_binary)
    os.chmod(sandbox_binary, 0o755)

    for test_string, oracle_out in zip(test_inputs, expected):
        # Preserve the original assertion against the requested compiled binary.
        student_proc = subprocess.run(
            [STUDENT_BINARY, test_string],
            capture_output=True,
            text=True,
        )
        student_out = student_proc.stdout.strip()
        assert oracle_out == student_out, (
            f"Mismatch on input {repr(test_string)}.\n"
            f"Oracle output: {repr(oracle_out)}\n"
            f"Student output: {repr(student_out)}"
        )

        # Also verify the executable freshly built from validator.c in isolation.
        rebuilt_proc = subprocess.run(
            ["chroot", "--userspec=65534:65534", sandbox, "/validator", test_string],
            capture_output=True,
            text=True,
        )
        rebuilt_out = rebuilt_proc.stdout.strip()
        assert rebuilt_proc.returncode == 0 and oracle_out == rebuilt_out, (
            f"Rebuilt validator.c mismatch on input {repr(test_string)}.\n"
            f"Oracle output: {repr(oracle_out)}\n"
            f"Rebuilt output: {repr(rebuilt_out)}\n"
            f"Rebuilt stderr: {repr(rebuilt_proc.stderr)}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
