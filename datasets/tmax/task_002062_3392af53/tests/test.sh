#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import stat
import subprocess
import tempfile
import pytest

CONFIG_DIR = "/home/user/config_vault"
CONFIG_FILE = "/home/user/config_vault/app_config.json"
CHECK_PERMS_C = "/home/user/check_perms.c"
CHECK_PERMS_EXE = "/home/user/check_perms"
VERIFY_SCRIPT = "/home/user/verify.sh"
STATUS_FILE = "/home/user/security_status.txt"


def run_checker(path):
    result = subprocess.run([path], capture_output=True, text=True, timeout=5)
    return result.stdout


def test_config_file_content():
    assert os.path.exists(CONFIG_FILE), f"File {CONFIG_FILE} does not exist"
    with open(CONFIG_FILE, "r") as f:
        content = f.read()
    assert content == '{"status":"locked"}', f"Incorrect content in {CONFIG_FILE}"


def test_permissions():
    assert os.path.exists(CONFIG_DIR), f"Directory {CONFIG_DIR} does not exist"
    dir_stat = os.stat(CONFIG_DIR)
    assert stat.S_IMODE(dir_stat.st_mode) == 0o700, f"Incorrect permissions for {CONFIG_DIR}"

    assert os.path.exists(CONFIG_FILE), f"File {CONFIG_FILE} does not exist"
    file_stat = os.stat(CONFIG_FILE)
    assert stat.S_IMODE(file_stat.st_mode) == 0o400, f"Incorrect permissions for {CONFIG_FILE}"


def test_security_status_file():
    assert os.path.exists(STATUS_FILE), f"File {STATUS_FILE} does not exist"
    with open(STATUS_FILE, "r") as f:
        content = f.read()
    assert content == "SECURE\n", f"Incorrect content in {STATUS_FILE}"


def test_check_perms_source():
    assert os.path.exists(CHECK_PERMS_C), f"Source {CHECK_PERMS_C} does not exist"
    assert stat.S_ISREG(os.lstat(CHECK_PERMS_C).st_mode), f"{CHECK_PERMS_C} is not a regular file"
    with open(CHECK_PERMS_C, "r") as f:
        source = f.read()
    assert re.search(r"\bstat\s*\(", source), "C source does not call stat"
    assert CONFIG_DIR in source, f"{CONFIG_DIR} not found in C source"
    assert CONFIG_FILE in source, f"{CONFIG_FILE} not found in C source"

    fd, compiled = tempfile.mkstemp(prefix="compiled_check_perms_", dir="/tmp")
    os.close(fd)
    os.unlink(compiled)
    try:
        build = subprocess.run(
            ["gcc", CHECK_PERMS_C, "-o", compiled],
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert build.returncode == 0, f"C source does not compile: {build.stderr}"
        exercise_checker(compiled)
    finally:
        if os.path.exists(compiled):
            os.unlink(compiled)


def exercise_checker(checker):
    rng = secrets.SystemRandom()
    scenarios = [
        (0o700, 0o400),
        (0o700, 0o600),
        (0o755, 0o400),
        (0o000, 0o000),
        (0o777, 0o777),
    ]
    for _ in range(15):
        scenarios.append((rng.randrange(0o1000), rng.randrange(0o1000)))
    rng.shuffle(scenarios)

    try:
        for dir_mode, file_mode in scenarios:
            os.chmod(CONFIG_DIR, dir_mode)
            os.chmod(CONFIG_FILE, file_mode)
            expected = "SECURE\n" if (dir_mode, file_mode) == (0o700, 0o400) else "INSECURE\n"
            actual = run_checker(checker)
            assert actual == expected, (
                f"For modes {dir_mode:04o}/{file_mode:04o}, expected {expected!r}, got {actual!r}"
            )

        os.chmod(CONFIG_DIR, 0o700)
        os.chmod(CONFIG_FILE, 0o400)
        missing_file = CONFIG_FILE + ".missing_" + secrets.token_hex(8)
        os.rename(CONFIG_FILE, missing_file)
        try:
            assert run_checker(checker) == "INSECURE\n", "Checker did not reject a missing config file"
        finally:
            os.rename(missing_file, CONFIG_FILE)

        missing_dir = CONFIG_DIR + ".missing_" + secrets.token_hex(8)
        os.rename(CONFIG_DIR, missing_dir)
        try:
            assert run_checker(checker) == "INSECURE\n", "Checker did not reject a missing directory"
        finally:
            os.rename(missing_dir, CONFIG_DIR)
    finally:
        os.chmod(CONFIG_DIR, 0o700)
        os.chmod(CONFIG_FILE, 0o400)


def test_check_perms_executable():
    assert os.path.exists(CHECK_PERMS_EXE), f"Executable {CHECK_PERMS_EXE} does not exist"
    assert stat.S_ISREG(os.lstat(CHECK_PERMS_EXE).st_mode), f"{CHECK_PERMS_EXE} is not a regular file"
    assert os.access(CHECK_PERMS_EXE, os.X_OK), f"{CHECK_PERMS_EXE} is not executable"

    # Retain the original fixed-state assertions.
    os.chmod(CONFIG_DIR, 0o700)
    os.chmod(CONFIG_FILE, 0o400)
    result = subprocess.run([CHECK_PERMS_EXE], capture_output=True, text=True)
    assert result.stdout == "SECURE\n", f"Expected SECURE\\n, got {result.stdout!r}"

    os.chmod(CONFIG_FILE, 0o600)
    result = subprocess.run([CHECK_PERMS_EXE], capture_output=True, text=True)
    assert result.stdout == "INSECURE\n", f"Expected INSECURE\\n, got {result.stdout!r}"

    os.chmod(CONFIG_FILE, 0o400)
    os.chmod(CONFIG_DIR, 0o755)
    result = subprocess.run([CHECK_PERMS_EXE], capture_output=True, text=True)
    assert result.stdout == "INSECURE\n", f"Expected INSECURE\\n, got {result.stdout!r}"

    os.chmod(CONFIG_DIR, 0o700)
    exercise_checker(CHECK_PERMS_EXE)


def test_verify_script():
    assert os.path.exists(VERIFY_SCRIPT), f"Script {VERIFY_SCRIPT} does not exist"
    assert stat.S_ISREG(os.lstat(VERIFY_SCRIPT).st_mode), f"{VERIFY_SCRIPT} is not a regular file"
    assert os.access(VERIFY_SCRIPT, os.X_OK), f"{VERIFY_SCRIPT} is not executable"
    with open(VERIFY_SCRIPT, "r") as f:
        content = f.read()
    assert "TZ=UTC" in content, f"TZ=UTC not found in {VERIFY_SCRIPT}"
    assert "LC_ALL=C" in content, f"LC_ALL=C not found in {VERIFY_SCRIPT}"

    token = secrets.token_hex(24)
    marker = "/tmp/verify_marker_" + secrets.token_hex(16)
    backup = CHECK_PERMS_EXE + ".verifier_backup_" + secrets.token_hex(16)
    probe = (
        "#!/bin/sh\n"
        + "printf '%s' '" + token + "' > '" + marker + "'\n"
        + "printf '%s|%s|%s\\n' '" + token + "' \"$TZ\" \"$LC_ALL\"\n"
    )

    os.replace(CHECK_PERMS_EXE, backup)
    try:
        with open(CHECK_PERMS_EXE, "w") as f:
            f.write(probe)
        os.chmod(CHECK_PERMS_EXE, 0o700)
        if os.path.exists(STATUS_FILE):
            os.unlink(STATUS_FILE)
        result = subprocess.run([VERIFY_SCRIPT], capture_output=True, text=True, timeout=10)
        marker_ok = os.path.exists(marker) and open(marker, "r").read() == token
        status_exists = os.path.exists(STATUS_FILE)
        status_content = open(STATUS_FILE, "r").read() if status_exists else None
        captured_stdout = result.stdout
        returncode = result.returncode
    finally:
        if os.path.exists(CHECK_PERMS_EXE):
            os.unlink(CHECK_PERMS_EXE)
        os.replace(backup, CHECK_PERMS_EXE)
        if os.path.exists(marker):
            os.unlink(marker)

    # Restore the required final status using the real checker.
    restore = subprocess.run([VERIFY_SCRIPT], capture_output=True, text=True, timeout=10)

    assert returncode == 0, "verify.sh failed while executing the checker"
    assert marker_ok, "verify.sh did not execute /home/user/check_perms"
    assert captured_stdout == "", "verify.sh did not redirect checker standard output"
    assert status_exists, "verify.sh did not create security_status.txt"
    assert status_content == f"{token}|UTC|C\n", "verify.sh did not export TZ=UTC and LC_ALL=C to the checker"
    assert restore.returncode == 0, "verify.sh failed with the real checker"
    with open(STATUS_FILE, "r") as f:
        assert f.read() == "SECURE\n", "verify.sh did not restore the required security status"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
