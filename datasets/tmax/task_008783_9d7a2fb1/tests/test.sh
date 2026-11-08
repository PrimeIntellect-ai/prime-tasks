#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import binascii
import json
import os
import re
import stat
import subprocess

import pytest

BASE_DIR = "/home/user/pr_review"
LIB_PATH = os.path.join(BASE_DIR, "libchecksum.so")
VERIFIER_PATH = os.path.join(BASE_DIR, "verifier")
SCRIPT_PATH = os.path.join(BASE_DIR, "test_fixture.py")
MOCK_PATH = os.path.join(BASE_DIR, "mock_data.bin")
LOG_PATH = os.path.join(BASE_DIR, "test_result.log")
EXPECTED_DATA = b"VERIFY_CHECKSUM_TEST_STRING"
EXPECTED_CRC = f"{binascii.crc32(EXPECTED_DATA) & 0xFFFFFFFF:08x}"


def clean_env():
    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    return env


def run_checked(args, **kwargs):
    result = subprocess.run(args, capture_output=True, text=True, **kwargs)
    assert result.returncode == 0, (
        f"Command {args!r} failed with code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def test_01_makefile_build_artifacts():
    assert os.path.isfile(os.path.join(BASE_DIR, "Makefile")), "Makefile is missing."

    subprocess.run(["make", "clean"], cwd=BASE_DIR, capture_output=True, text=True)
    for path in (LIB_PATH, VERIFIER_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    run_checked(["make"], cwd=BASE_DIR, env=clean_env(), timeout=30)

    assert os.path.isfile(LIB_PATH), "libchecksum.so was not built."
    assert os.path.isfile(VERIFIER_PATH), "verifier executable was not built."
    assert os.stat(VERIFIER_PATH).st_mode & stat.S_IXUSR, "verifier is not executable."

    lib_header = run_checked(["readelf", "-h", LIB_PATH]).stdout
    verifier_header = run_checked(["readelf", "-h", VERIFIER_PATH]).stdout
    assert "ELF Header:" in lib_header and re.search(r"Type:\s+DYN", lib_header), \
        "libchecksum.so is not an ELF shared object."
    assert "ELF Header:" in verifier_header, "verifier is not an ELF executable."

    symbols = run_checked(["nm", "-D", LIB_PATH]).stdout
    assert re.search(r"\bcalculate_crc32$", symbols, re.MULTILINE), \
        "libchecksum.so does not export calculate_crc32."


def test_02_verifier_linkage_rpath_and_startup():
    dynamic = run_checked(["readelf", "-d", VERIFIER_PATH]).stdout
    assert re.search(r"\(NEEDED\).*\[libchecksum\.so\]", dynamic), \
        "verifier is not dynamically linked against libchecksum.so."

    rpath_values = re.findall(r"\((?:RPATH|RUNPATH)\).*?\[(.*?)\]", dynamic)
    components = [part for value in rpath_values for part in value.split(":")]
    assert any(part in ("$ORIGIN", "${ORIGIN}", "$ORIGIN/.", "${ORIGIN}/.") for part in components), \
        "verifier does not have an RPATH/RUNPATH for its origin directory."

    ldd_result = run_checked(["ldd", VERIFIER_PATH], env=clean_env())
    ldd_output = ldd_result.stdout + ldd_result.stderr
    assert "not found" not in ldd_output, "ldd reports a missing library."
    match = re.search(r"libchecksum\.so\s+=>\s+(\S+)", ldd_output)
    assert match, "ldd does not show verifier loading libchecksum.so."
    assert os.path.realpath(match.group(1)) == os.path.realpath(LIB_PATH), \
        "verifier does not load the libchecksum.so from the project directory."

    result = subprocess.run(
        [VERIFIER_PATH], cwd=BASE_DIR, env=clean_env(), capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 1, "verifier without arguments should return the usage error code."
    assert "Usage:" in result.stdout, "verifier did not print its usage message."


def test_03_crc_functionality_on_derived_inputs():
    for index in range(5):
        data = os.urandom(31 + index * 47) + bytes([0, index, 255])
        path = os.path.join(BASE_DIR, f".verifier_test_{os.getpid()}_{index}.bin")
        try:
            with open(path, "wb") as f:
                f.write(data)
            expected_value = binascii.crc32(data) & 0xFFFFFFFF
            expected = f"{expected_value:08x}"

            good = subprocess.run(
                [VERIFIER_PATH, path, expected], cwd=BASE_DIR, env=clean_env(),
                capture_output=True, text=True, timeout=10
            )
            assert good.returncode == 0, (
                f"verifier rejected the derived CRC {expected} for test input {index}: "
                f"{good.stdout}{good.stderr}"
            )

            wrong = f"{expected_value ^ 0xA5A5A5A5:08x}"
            bad = subprocess.run(
                [VERIFIER_PATH, path, wrong], cwd=BASE_DIR, env=clean_env(),
                capture_output=True, text=True, timeout=10
            )
            assert bad.returncode != 0, "verifier accepted an incorrect CRC32 value."
        finally:
            try:
                os.remove(path)
            except FileNotFoundError:
                pass


def test_04_execute_test_fixture_and_check_outputs():
    assert os.path.isfile(SCRIPT_PATH), "test_fixture.py is missing."

    real_verifier = VERIFIER_PATH + ".real"
    trace_path = os.path.join(BASE_DIR, ".fixture_verifier_trace.jsonl")
    wrapper = f'''#!/usr/bin/python3
import json
import os
import sys
with open({trace_path!r}, "a") as trace:
    trace.write(json.dumps(sys.argv[1:]) + "\\n")
if os.environ.get("FIXTURE_FORCE_VERIFIER_FAILURE") == "1":
    sys.exit(9)
os.execv({real_verifier!r}, [{real_verifier!r}] + sys.argv[1:])
'''

    for path in (MOCK_PATH, LOG_PATH, trace_path):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    os.replace(VERIFIER_PATH, real_verifier)
    try:
        with open(VERIFIER_PATH, "w") as f:
            f.write(wrapper)
        os.chmod(VERIFIER_PATH, 0o755)

        failure_env = clean_env()
        failure_env["FIXTURE_FORCE_VERIFIER_FAILURE"] = "1"
        failed_run = subprocess.run(
            ["python3", SCRIPT_PATH], cwd=BASE_DIR, env=failure_env,
            capture_output=True, text=True, timeout=20
        )
        assert failed_run.returncode == 0, (
            f"test_fixture.py crashed when verifier failed:\n{failed_run.stdout}\n{failed_run.stderr}"
        )
        assert os.path.isfile(LOG_PATH), "test_fixture.py did not create test_result.log on failure."
        with open(LOG_PATH, "r") as f:
            assert f.read().strip() == "FAILED", \
                "test_fixture.py must write FAILED when verifier exits unsuccessfully."

        for path in (MOCK_PATH, LOG_PATH):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        success_run = subprocess.run(
            ["python3", SCRIPT_PATH], cwd=BASE_DIR, env=clean_env(),
            capture_output=True, text=True, timeout=20
        )
        assert success_run.returncode == 0, (
            f"test_fixture.py failed:\n{success_run.stdout}\n{success_run.stderr}"
        )

        assert os.path.isfile(MOCK_PATH), "mock_data.bin is missing."
        with open(MOCK_PATH, "rb") as f:
            assert f.read() == EXPECTED_DATA, "mock_data.bin content is incorrect."

        assert os.path.isfile(LOG_PATH), "test_result.log is missing."
        with open(LOG_PATH, "r") as f:
            assert f.read().strip() == EXPECTED_CRC, \
                f"test_result.log must contain the derived CRC32 {EXPECTED_CRC}."

        assert os.path.isfile(trace_path), "test_fixture.py did not execute ./verifier."
        with open(trace_path, "r") as f:
            calls = [json.loads(line) for line in f if line.strip()]
        matching_calls = []
        for call in calls:
            if len(call) != 2:
                continue
            supplied_file = call[0] if os.path.isabs(call[0]) else os.path.join(BASE_DIR, call[0])
            if os.path.realpath(supplied_file) == os.path.realpath(MOCK_PATH) and call[1] == EXPECTED_CRC:
                matching_calls.append(call)
        assert matching_calls, \
            "test_fixture.py did not invoke verifier with mock_data.bin and its computed CRC32."
    finally:
        try:
            os.remove(VERIFIER_PATH)
        except FileNotFoundError:
            pass
        if os.path.exists(real_verifier):
            os.replace(real_verifier, VERIFIER_PATH)
        try:
            os.remove(trace_path)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
