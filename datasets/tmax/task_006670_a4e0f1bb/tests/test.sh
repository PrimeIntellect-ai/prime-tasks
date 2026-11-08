#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import shutil
import stat
import subprocess
import tempfile
import pytest

RELEASE_DIR = "/home/user/release"
SCRIPT_PATH = os.path.join(RELEASE_DIR, "prepare_release.sh")
REPORT_PATH = os.path.join(RELEASE_DIR, "report.json")
HANDLER_PATH = os.path.join(RELEASE_DIR, "handler.o")
LIBAUTH_PATH = os.path.join(RELEASE_DIR, "libauth.so")
THRESHOLDS_PATH = os.path.join(RELEASE_DIR, "thresholds.conf")


def run_script():
    result = subprocess.run(
        [SCRIPT_PATH],
        cwd=RELEASE_DIR,
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"prepare_release.sh failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def load_report():
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."
    with open(REPORT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} does not contain valid JSON.")


def objdump_offset(path):
    result = subprocess.run(["objdump", "-t", path], capture_output=True, text=True)
    assert result.returncode == 0, "objdump command failed."
    for line in result.stdout.splitlines():
        parts = line.split()
        if parts and parts[-1] == "check_auth":
            value = parts[0].lstrip("0")
            return value if value else "0"
    pytest.fail("Could not find 'check_auth' in objdump output.")


def snapshot(path):
    return (open(path, "rb").read(), stat.S_IMODE(os.stat(path).st_mode))


def restore(path, saved):
    data, mode = saved
    temp_path = path + ".verifier_restore"
    with open(temp_path, "wb") as f:
        f.write(data)
    os.chmod(temp_path, mode)
    os.replace(temp_path, path)


def test_prepare_release_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_report_json_exists_and_valid():
    # Require the submitted automation to create a fresh report.
    if os.path.lexists(REPORT_PATH):
        os.unlink(REPORT_PATH)
    run_script()
    data = load_report()

    assert isinstance(data, dict), "JSON root must be an object/dictionary."
    assert "abi_secure" in data, "Missing 'abi_secure' key in report.json."
    assert "max_retries_value" in data, "Missing 'max_retries_value' key in report.json."
    assert "check_auth_offset" in data, "Missing 'check_auth_offset' key in report.json."


def test_report_json_values():
    data = load_report()

    # Check abi_secure
    assert data["abi_secure"] is False, "abi_secure should be false (boolean)."

    # Check max_retries_value
    assert data["max_retries_value"] == 13, "max_retries_value should be 13 (integer)."

    # Dynamically determine check_auth_offset
    assert os.path.isfile(HANDLER_PATH), f"File {HANDLER_PATH} missing, cannot verify offset."
    result = subprocess.run(["objdump", "-t", HANDLER_PATH], capture_output=True, text=True)
    assert result.returncode == 0, "objdump command failed."

    offset_val = None
    for line in result.stdout.splitlines():
        if "check_auth" in line:
            parts = line.split()
            if len(parts) > 0:
                offset_val = parts[0].lstrip("0")
                if offset_val == "":
                    offset_val = "0"
                break

    assert offset_val is not None, "Could not find 'check_auth' in objdump output."
    assert data["check_auth_offset"] == offset_val, \
        f"check_auth_offset should be '{offset_val}'."


def test_script_reanalyzes_changed_inputs():
    saved_inputs = {
        LIBAUTH_PATH: snapshot(LIBAUTH_PATH),
        HANDLER_PATH: snapshot(HANDLER_PATH),
        THRESHOLDS_PATH: snapshot(THRESHOLDS_PATH),
    }
    saved_report = snapshot(REPORT_PATH) if os.path.isfile(REPORT_PATH) else None

    rng = random.SystemRandom()
    filler_size = rng.randrange(37, 240)
    left = rng.randrange(7, 30)
    right = rng.randrange(4, 18)
    subtract = rng.randrange(1, 20)
    expected_retries = left * right - subtract

    try:
        with tempfile.TemporaryDirectory() as td:
            source = os.path.join(td, "auth.c")
            library = os.path.join(td, "libauth.so")
            with open(source, "w") as f:
                f.write("int do_auth(void) { return 1; }\n")
            compile_result = subprocess.run(
                ["gcc", "-shared", "-fPIC", "-o", library, source],
                capture_output=True,
                text=True,
            )
            assert compile_result.returncode == 0, compile_result.stderr
            shutil.copyfile(library, LIBAUTH_PATH)

            assembly = os.path.join(td, "handler.s")
            objfile = os.path.join(td, "handler.o")
            with open(assembly, "w") as f:
                f.write(
                    ".text\n"
                    ".global padding_start\n"
                    "padding_start:\n"
                    f"    .space {filler_size}, 0x90\n"
                    ".global check_auth\n"
                    ".type check_auth, @function\n"
                    "check_auth:\n"
                    "    mov $1, %eax\n"
                    "    ret\n"
                )
            assemble_result = subprocess.run(
                ["as", "-o", objfile, assembly], capture_output=True, text=True
            )
            assert assemble_result.returncode == 0, assemble_result.stderr
            shutil.copyfile(objfile, HANDLER_PATH)

        with open(THRESHOLDS_PATH, "w") as f:
            f.write("timeout = 9 + 1\n")
            f.write(f"max_retries = ({left} * {right}) - {subtract}\n")
            f.write("rate_limit = 777\n")

        expected_offset = objdump_offset(HANDLER_PATH)
        nm_result = subprocess.run(
            ["nm", "-D", LIBAUTH_PATH], capture_output=True, text=True
        )
        assert nm_result.returncode == 0, "nm command failed on generated library."
        has_undefined_md5 = any(
            len(parts := line.split()) >= 2
            and parts[-1] == "MD5_Init"
            and parts[-2] == "U"
            for line in nm_result.stdout.splitlines()
        )
        expected_secure = not has_undefined_md5

        if os.path.lexists(REPORT_PATH):
            os.unlink(REPORT_PATH)
        run_script()
        data = load_report()

        assert isinstance(data, dict), "JSON root must be an object/dictionary."
        assert "abi_secure" in data, "Missing 'abi_secure' key in report.json."
        assert "max_retries_value" in data, "Missing 'max_retries_value' key in report.json."
        assert "check_auth_offset" in data, "Missing 'check_auth_offset' key in report.json."
        assert data["abi_secure"] is expected_secure, \
            "abi_secure was not recomputed from the replacement shared library."
        assert data["max_retries_value"] == expected_retries, \
            "max_retries_value was not recomputed from thresholds.conf."
        assert data["check_auth_offset"] == expected_offset, \
            "check_auth_offset was not recomputed from the replacement object file."
    finally:
        for path, saved in saved_inputs.items():
            restore(path, saved)
        if saved_report is not None:
            restore(REPORT_PATH, saved_report)
        elif os.path.lexists(REPORT_PATH):
            os.unlink(REPORT_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
