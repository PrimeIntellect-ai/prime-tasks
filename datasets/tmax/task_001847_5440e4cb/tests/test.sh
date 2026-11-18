#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import shutil
import stat
import subprocess
import tempfile
import uuid

import pytest

LIB_PATH = "/home/user/ffi/libseccheck.so"
AUDIT_PATH = "/home/user/audit.sh"
LOCK_PATH = "/home/user/project/secure-lock.txt"
LOG_PATH = "/home/user/vuln.log"
RESOLVED_PATH = "/home/user/project/resolved_package.json"


def run_audit():
    result = subprocess.run(
        [AUDIT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"audit.sh exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_libseccheck_exists():
    assert os.path.isfile(LIB_PATH), (
        f"Shared library {LIB_PATH} is missing. Did you compile sec_check.c?"
    )

    try:
        lib = ctypes.CDLL(LIB_PATH)
        check = lib.check_vulnerability
    except (OSError, AttributeError) as exc:
        pytest.fail(f"{LIB_PATH} is not a loadable shared library with check_vulnerability: {exc}")

    check.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    check.restype = ctypes.c_int
    assert check(b"auth-utils", b"1.2.0") == 1
    assert check(b"form-parser", b"0.9.4") == 1
    assert check(b"dev-server", b"1.0.0") == 1
    assert check(b"ui-buttons", b"3.0.0") == 0


def test_audit_sh_exists_and_executable():
    assert os.path.isfile(AUDIT_PATH), f"Bash script {AUDIT_PATH} is missing."
    st = os.stat(AUDIT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), (
        f"Bash script {AUDIT_PATH} is not executable. Run chmod +x on it."
    )


def test_vuln_log_contents_are_generated_by_audit():
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)

    run_audit()
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} is missing. Did your script generate it?"

    lines = read_nonempty_lines(LOG_PATH)
    expected = ["auth-utils@1.2.0", "form-parser@0.9.4"]
    assert lines == expected, (
        f"Contents of {LOG_PATH} do not match the expected output. "
        f"Expected {expected}, but got {lines}. Ensure you only process [Web-Components] "
        "and sort the results alphabetically."
    )


def test_audit_uses_shared_library_and_parses_arbitrary_blocks():
    token = uuid.uuid4().hex
    web_a = f"alpha-{token}"
    web_z = f"zeta-{token}"
    safe = f"safe-{token}"
    dev_vuln = f"dev-{token}"
    system_vuln = f"system-{token}"
    ver_a = f"7.{int(token[:2], 16)}.1"
    ver_z = f"8.{int(token[2:4], 16)}.2"
    excluded_ver = f"9.{int(token[4:6], 16)}.3"

    challenge_source = f'''#include <string.h>
int check_vulnerability(const char *pkg, const char *version) {{
    if (strcmp(pkg, "{web_a}") == 0 && strcmp(version, "{ver_a}") == 0) return 1;
    if (strcmp(pkg, "{web_z}") == 0 && strcmp(version, "{ver_z}") == 0) return 1;
    if (strcmp(pkg, "{dev_vuln}") == 0 && strcmp(version, "{excluded_ver}") == 0) return 1;
    if (strcmp(pkg, "{system_vuln}") == 0 && strcmp(version, "{excluded_ver}") == 0) return 1;
    return 0;
}}
'''

    challenge_lock = f'''BEGIN [System]
  {system_vuln} {excluded_ver}
END [System]
BEGIN [Web-Components]
  {web_z} {ver_z}
  {safe} 1.0.0
END [Web-Components]
BEGIN [Dev-Tools]
  {dev_vuln} {excluded_ver}
END [Dev-Tools]
BEGIN [Web-Components]
  {web_a} {ver_a}
END [Web-Components]
'''

    with tempfile.TemporaryDirectory() as td:
        source_path = os.path.join(td, "challenge.c")
        challenge_lib = os.path.join(td, "libseccheck.so")
        backup_lib = os.path.join(td, "original-libseccheck.so")
        backup_lock = os.path.join(td, "original-secure-lock.txt")

        with open(source_path, "w") as f:
            f.write(challenge_source)
        subprocess.run(
            ["gcc", "-shared", "-fPIC", source_path, "-o", challenge_lib],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        shutil.copy2(LIB_PATH, backup_lib)
        shutil.copy2(LOCK_PATH, backup_lock)
        try:
            shutil.copy2(challenge_lib, LIB_PATH)
            with open(LOCK_PATH, "w") as f:
                f.write(challenge_lock)
            if os.path.exists(LOG_PATH):
                os.remove(LOG_PATH)

            run_audit()
            assert os.path.isfile(LOG_PATH), "audit.sh did not generate vuln.log for the challenge lockfile."
            actual = read_nonempty_lines(LOG_PATH)
            expected = sorted([f"{web_a}@{ver_a}", f"{web_z}@{ver_z}"])
            assert actual == expected, (
                "audit.sh must parse all and only Web-Components blocks, call the current "
                f"libseccheck.so for every candidate, and sort its output. Expected {expected}, got {actual}."
            )
        finally:
            shutil.copy2(backup_lib, LIB_PATH)
            shutil.copy2(backup_lock, LOCK_PATH)


def test_resolved_package_json():
    assert os.path.isfile(RESOLVED_PATH), f"Resolved package file {RESOLVED_PATH} is missing."

    with open(RESOLVED_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESOLVED_PATH} is not a valid JSON file.")

    deps = data.get("dependencies", {})
    assert deps.get("express-router") == "4.5.0", (
        "The 'express-router' dependency in resolved_package.json was not updated to '4.5.0'."
    )

    expected = {
        "name": "legacy-web",
        "version": "1.0.0",
        "dependencies": {
            "auth-utils": "^1.2.0",
            "express-router": "4.5.0",
        },
        "peerDependencies": {
            "form-parser": "0.9.4",
        },
    }
    assert data == expected, (
        "resolved_package.json must preserve the original package manifest while updating "
        "express-router to 4.5.0."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
