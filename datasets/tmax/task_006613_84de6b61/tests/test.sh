#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile

BASE = "/home/user/telemetry_lib"
ANDROID = os.path.join(BASE, "libtelemetry_android.so")
IOS = os.path.join(BASE, "libtelemetry_ios.so")
EXPECTED = ["telemetry_init", "telemetry_process"]


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=20, **kwargs)


def dynamic_defined_functions(path):
    result = run(["readelf", "-W", "--dyn-syms", path])
    assert result.returncode == 0, f"Failed to inspect dynamic symbols in {path}: {result.stderr}"
    names = []
    for line in result.stdout.splitlines():
        fields = line.split()
        if len(fields) < 8 or not fields[0].rstrip(":").isdigit():
            continue
        if fields[3] != "FUNC" or fields[4] not in ("GLOBAL", "WEAK") or fields[6] == "UND":
            continue
        names.append(fields[7].split("@", 1)[0])
    return sorted(set(names))


def telemetry_exports(path):
    return sorted(name for name in dynamic_defined_functions(path) if name.startswith("telemetry_"))


def assert_shared_elf(path):
    result = run(["readelf", "-h", path])
    assert result.returncode == 0, f"{path} is not a readable ELF file: {result.stderr}"
    assert re.search(r"Type:\s+DYN\b", result.stdout), f"{path} is not an ELF shared object"


def call_library(path):
    code = r'''
import ctypes
import sys
lib = ctypes.CDLL(sys.argv[1])
lib.telemetry_init.argtypes = []
lib.telemetry_init.restype = None
lib.telemetry_process.argtypes = []
lib.telemetry_process.restype = None
lib.telemetry_init()
lib.telemetry_process()
ctypes.CDLL(None).fflush(None)
'''
    return run(["python3", "-c", code, path])


def assert_library(path, expected_output):
    assert_shared_elf(path)

    result = run(["nm", "-D", "--defined-only", path])
    assert result.returncode == 0, f"Failed to run nm on {path}"
    assert "internal_parse" not in result.stdout, f"internal_parse is exported in {path}, ABI is polluted."
    assert "internal_format" not in result.stdout, f"internal_format is exported in {path}, ABI is polluted."
    assert "telemetry_init" in result.stdout, f"telemetry_init is missing from exports in {path}."
    assert "telemetry_process" in result.stdout, f"telemetry_process is missing from exports in {path}."

    assert telemetry_exports(path) == EXPECTED, \
        f"Incorrect telemetry ABI in {path}: {telemetry_exports(path)}"

    executed = call_library(path)
    assert executed.returncode == 0, f"Failed to load and execute {path}: {executed.stderr}"
    assert executed.stdout == expected_output + "\n", \
        f"Wrong target behavior from {path}: {executed.stdout!r}"


def test_version_map_exists():
    assert os.path.isfile(os.path.join(BASE, "version.map")), \
        "version.map does not exist in /home/user/telemetry_lib"


def test_patch_was_applied_to_processor_source():
    source = os.path.join(BASE, "processor.c")
    patch_file = os.path.join(BASE, "update.patch")
    assert os.path.isfile(source), "processor.c does not exist"
    assert os.path.isfile(patch_file), "update.patch does not exist"
    result = subprocess.run(
        ["bash", "-c", "patch --dry-run -R -p0 processor.c < update.patch"],
        cwd=BASE, capture_output=True, text=True, timeout=20
    )
    assert result.returncode == 0, \
        f"processor.c is not the result of applying update.patch: {result.stdout}{result.stderr}"


def test_shared_libraries_exist():
    assert os.path.isfile(ANDROID), f"{ANDROID} does not exist."
    assert os.path.isfile(IOS), f"{IOS} does not exist."


def test_submitted_shared_libraries():
    assert_library(ANDROID, "Android")
    assert_library(IOS, "iOS")


def test_version_script_and_source_rebuild_correctly():
    source = os.path.join(BASE, "processor.c")
    version_map = os.path.join(BASE, "version.map")
    with tempfile.TemporaryDirectory() as tmp:
        for macro, expected_output, name in (
            ("TARGET_ANDROID", "Android", "android.so"),
            ("TARGET_IOS", "iOS", "ios.so"),
        ):
            output = os.path.join(tmp, name)
            result = run([
                "gcc", "-shared", "-fPIC", f"-D{macro}", source,
                f"-Wl,--version-script={version_map}", "-o", output
            ])
            assert result.returncode == 0, \
                f"Failed to rebuild processor.c with {macro} and version.map: {result.stderr}"
            assert_library(output, expected_output)


def test_android_exports_log():
    log_path = "/home/user/android_exports.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist."
    with open(log_path, "r") as f:
        content = f.read().strip().splitlines()
    assert content == EXPECTED, f"Incorrect content in {log_path}: {content}"
    assert content == telemetry_exports(ANDROID), \
        f"{log_path} does not match the symbols actually exported by {ANDROID}"


def test_ios_exports_log():
    log_path = "/home/user/ios_exports.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist."
    with open(log_path, "r") as f:
        content = f.read().strip().splitlines()
    assert content == EXPECTED, f"Incorrect content in {log_path}: {content}"
    assert content == telemetry_exports(IOS), \
        f"{log_path} does not match the symbols actually exported by {IOS}"


def test_shared_libraries_preprocessor_flags():
    result_android = run(["strings", ANDROID])
    assert result_android.returncode == 0
    assert "Android" in result_android.stdout, \
        "The string 'Android' was not found in libtelemetry_android.so. Was -DTARGET_ANDROID used?"

    result_ios = run(["strings", IOS])
    assert result_ios.returncode == 0
    assert "iOS" in result_ios.stdout, \
        "The string 'iOS' was not found in libtelemetry_ios.so. Was -DTARGET_IOS used?"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
