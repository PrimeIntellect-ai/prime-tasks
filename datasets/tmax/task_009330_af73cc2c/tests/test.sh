#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile
import uuid
import pytest

MIGRATOR_SOURCE = "/home/user/migrator.cpp"
MIGRATOR_BINARY = "/home/user/migrator"
STATUS_PATH = "/home/user/migration_status.txt"
REQUIRED_ENV = {
    "TZ": "Europe/Berlin",
    "LC_ALL": "de_DE.UTF-8",
    "DATA_MOUNT": "/tmp/migration_data",
}


def clean_env(**updates):
    env = os.environ.copy()
    for name in REQUIRED_ENV:
        env.pop(name, None)
    env.update(updates)
    return env


def run_migrator(binary, env, input_text=""):
    return subprocess.run(
        [binary],
        input=input_text,
        capture_output=True,
        text=True,
        env=env,
        cwd="/home/user",
        timeout=10,
    )


def remove_status():
    if os.path.exists(STATUS_PATH):
        os.remove(STATUS_PATH)


def assert_migrator_behavior(binary):
    wrong = "invalid-" + uuid.uuid4().hex

    invalid_cases = [
        (clean_env(TZ=wrong, LC_ALL=REQUIRED_ENV["LC_ALL"], DATA_MOUNT=REQUIRED_ENV["DATA_MOUNT"]), 1),
        (clean_env(TZ=REQUIRED_ENV["TZ"], LC_ALL=wrong, DATA_MOUNT=REQUIRED_ENV["DATA_MOUNT"]), 2),
        (clean_env(TZ=REQUIRED_ENV["TZ"], LC_ALL=REQUIRED_ENV["LC_ALL"], DATA_MOUNT=wrong), 3),
        (clean_env(LC_ALL=REQUIRED_ENV["LC_ALL"], DATA_MOUNT=REQUIRED_ENV["DATA_MOUNT"]), 1),
        (clean_env(TZ=REQUIRED_ENV["TZ"], DATA_MOUNT=REQUIRED_ENV["DATA_MOUNT"]), 2),
        (clean_env(TZ=REQUIRED_ENV["TZ"], LC_ALL=REQUIRED_ENV["LC_ALL"]), 3),
    ]
    for env, expected_code in invalid_cases:
        remove_status()
        result = run_migrator(binary, env, "y\n")
        assert result.returncode == expected_code, (
            f"{binary} returned {result.returncode}, expected {expected_code} for invalid environment. "
            f"STDOUT: {result.stdout!r} STDERR: {result.stderr!r}"
        )
        assert not os.path.exists(STATUS_PATH), "Invalid environment unexpectedly created the status file."

    valid_env = clean_env(**REQUIRED_ENV)

    remove_status()
    result = run_migrator(binary, valid_env, "n\n")
    assert result.returncode == 4, (
        f"{binary} returned {result.returncode}, expected 4 for input 'n'. "
        f"STDOUT: {result.stdout!r} STDERR: {result.stderr!r}"
    )
    assert result.stdout == "Begin migration? [y/N]: ", f"Incorrect prompt/output: {result.stdout!r}"
    assert not os.path.exists(STATUS_PATH), "Rejected input unexpectedly created the status file."

    remove_status()
    result = run_migrator(binary, valid_env, "y\n")
    assert result.returncode == 0, (
        f"{binary} returned {result.returncode}, expected 0 for input 'y'. "
        f"STDOUT: {result.stdout!r} STDERR: {result.stderr!r}"
    )
    assert result.stdout == "Begin migration? [y/N]: ", f"Incorrect prompt/output: {result.stdout!r}"
    assert os.path.isfile(STATUS_PATH), "Successful migration did not create the status file."
    with open(STATUS_PATH, "rb") as f:
        assert f.read() == b"MIGRATION_READY", "Status file does not contain exactly MIGRATION_READY."


def test_migrator_cpp_exists():
    """Verify that the C++ source file exists."""
    assert os.path.isfile(MIGRATOR_SOURCE), f"File {MIGRATOR_SOURCE} does not exist."


def test_migrator_binary_exists_and_executable():
    """Verify that the compiled binary exists, is executable, and is an ELF binary."""
    assert os.path.isfile(MIGRATOR_BINARY), f"Binary {MIGRATOR_BINARY} does not exist."
    assert os.access(MIGRATOR_BINARY, os.X_OK), f"Binary {MIGRATOR_BINARY} is not executable."
    with open(MIGRATOR_BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{MIGRATOR_BINARY} is not a compiled ELF binary."


def test_migrator_source_compiles_and_both_binaries_behave_correctly():
    """Compile the submitted source and directly exercise it and the installed binary."""
    with tempfile.TemporaryDirectory() as directory:
        rebuilt = os.path.join(directory, "migrator")
        result = subprocess.run(
            ["/usr/bin/g++", MIGRATOR_SOURCE, "-o", rebuilt],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"migrator.cpp failed to compile. STDOUT: {result.stdout}\nSTDERR: {result.stderr}"
        )
        assert_migrator_behavior(rebuilt)
    assert_migrator_behavior(MIGRATOR_BINARY)


def test_automate_exp_exists_and_executable():
    """Verify that the Expect script exists, is executable, and has the correct shebang."""
    path = "/home/user/automate.exp"
    assert os.path.isfile(path), f"Expect script {path} does not exist."
    assert os.access(path, os.X_OK), f"Expect script {path} is not executable."

    with open(path, 'r') as f:
        first_line = f.readline().strip()
    assert first_line == "#!/usr/bin/expect", f"Expect script {path} does not start with #!/usr/bin/expect."


def test_fstab_entry_correct():
    """Verify that the fstab entry file exists and contains the correct configuration."""
    path = "/home/user/fstab_entry.txt"
    assert os.path.isfile(path), f"fstab entry file {path} does not exist."

    with open(path, 'r') as f:
        content = f.read().strip()

    pattern = r"^/dev/xvdf\s+/tmp/migration_data\s+ext4\s+defaults,noatime\s+0\s+2$"
    assert re.match(pattern, content), f"Content of {path} does not match the required fstab entry format. Found: {content}"


def test_automate_exp_execution_and_status_file():
    """Verify that running the Expect script successfully creates the status file with correct content."""
    script_path = "/home/user/automate.exp"

    if os.path.exists(STATUS_PATH):
        os.remove(STATUS_PATH)

    result = subprocess.run([script_path], cwd="/home/user", capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, f"Expect script failed to execute. STDOUT: {result.stdout}\nSTDERR: {result.stderr}"

    assert os.path.isfile(STATUS_PATH), f"Status file {STATUS_PATH} was not created after running the expect script."

    with open(STATUS_PATH, 'r') as f:
        content = f.read().strip()
    assert content == "MIGRATION_READY", f"Status file {STATUS_PATH} contains incorrect text: {content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
