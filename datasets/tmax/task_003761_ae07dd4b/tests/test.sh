#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import re
import runpy
import shutil
import stat
import subprocess

import pytest

HOME = "/home/user"
PROJECT = "/home/user/mobile_sensor"
LIB_NAMES = [
    "libmobile_sensor_default.so",
    "libmobile_sensor_android.so",
    "libmobile_sensor_ios.so",
]
EXPECTED_CALLS = [os.path.join(HOME, "libs", name) for name in LIB_NAMES]


@pytest.fixture(scope="session", autouse=True)
def execute_submitted_pipeline():
    script_path = os.path.join(HOME, "run_all_tests.sh")
    verify_path = os.path.join(HOME, "verify.py")
    assert os.path.exists(script_path), f"File {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"File {script_path} is not executable."
    assert os.path.exists(verify_path), f"File {verify_path} does not exist."

    with open(verify_path, "rb") as f:
        original_verify = f.read()
    original_mode = stat.S_IMODE(os.stat(verify_path).st_mode)

    backup_path = "/tmp/submitted_verify.py"
    calls_path = "/tmp/verify_calls.log"
    with open(backup_path, "wb") as f:
        f.write(original_verify)
    os.chmod(backup_path, original_mode)

    wrapper = '''#!/usr/bin/env python3
import os
import runpy
import sys
with open("/tmp/verify_calls.log", "a") as call_log:
    call_log.write(os.path.abspath(sys.argv[1]) + "\\n")
runpy.run_path("/tmp/submitted_verify.py", run_name="__main__")
'''

    if os.path.exists(calls_path):
        os.remove(calls_path)
    shutil.rmtree(os.path.join(HOME, "libs"), ignore_errors=True)
    try:
        os.remove(os.path.join(HOME, "final_output.log"))
    except FileNotFoundError:
        pass

    try:
        with open(verify_path, "w") as f:
            f.write(wrapper)
        os.chmod(verify_path, 0o755)
        result = subprocess.run(
            [script_path],
            cwd=HOME,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=300,
        )
    finally:
        with open(verify_path, "wb") as f:
            f.write(original_verify)
        os.chmod(verify_path, original_mode)

    assert result.returncode == 0, (
        "run_all_tests.sh failed.\nSTDOUT:\n"
        + result.stdout
        + "\nSTDERR:\n"
        + result.stderr
    )
    assert os.path.exists(calls_path), "run_all_tests.sh did not execute verify.py."
    with open(calls_path) as f:
        calls = [line.strip() for line in f if line.strip()]
    assert calls == EXPECTED_CALLS, (
        "run_all_tests.sh must invoke verify.py once for each generated library "
        f"in default/android/ios order; got {calls}"
    )


def test_final_output_log():
    log_path = "/home/user/final_output.log"
    assert os.path.exists(log_path), f"File {log_path} does not exist."

    with open(log_path, "r") as f:
        content = f.read().strip()

    expected_content = "default: -1\nandroid: 15\nios: 22"
    assert content == expected_content, f"Content of {log_path} does not match expected output.\nExpected:\n{expected_content}\nGot:\n{content}"


def test_mobile_sensor_directory():
    dir_path = "/home/user/mobile_sensor"
    assert os.path.isdir(dir_path), f"Directory {dir_path} does not exist."


def test_cargo_toml_configuration():
    cargo_path = "/home/user/mobile_sensor/Cargo.toml"
    assert os.path.exists(cargo_path), f"File {cargo_path} does not exist."

    with open(cargo_path, "r") as f:
        content = f.read()

    assert re.search(r'crate-type\s*=\s*\[\s*"cdylib"\s*\]', content), "Cargo.toml does not contain crate-type = [\"cdylib\"]."
    assert re.search(r'libc\s*=', content) or "[dependencies.libc]" in content or "libc" in content, "Cargo.toml does not contain libc as a dependency."
    assert re.search(r'android\s*=', content) or "[features]" in content and "android" in content, "Cargo.toml does not define the 'android' feature."
    assert re.search(r'ios\s*=', content) or "[features]" in content and "ios" in content, "Cargo.toml does not define the 'ios' feature."


def test_run_all_tests_script():
    script_path = "/home/user/run_all_tests.sh"
    assert os.path.exists(script_path), f"File {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"File {script_path} is not executable."


def test_verify_py_script():
    script_path = "/home/user/verify.py"
    assert os.path.exists(script_path), f"File {script_path} does not exist."


def test_libs_directory_and_files():
    libs_dir = "/home/user/libs"
    assert os.path.isdir(libs_dir), f"Directory {libs_dir} does not exist."

    for name in LIB_NAMES:
        file_path = os.path.join(libs_dir, name)
        assert os.path.exists(file_path), f"Shared library {file_path} does not exist."
        assert os.path.isfile(file_path), f"Shared library {file_path} is not a regular file."
        assert os.path.getsize(file_path) > 0, f"Shared library {file_path} is empty."


def load_function(library_path):
    library = ctypes.CDLL(library_path)
    function = library.process_sensor_data
    function.argtypes = [ctypes.POINTER(ctypes.c_float), ctypes.c_size_t]
    function.restype = ctypes.c_int32
    return library, function


def exercise_library(library_path, multiplier):
    library, function = load_function(library_path)
    assert function(None, 0) == -1, "Null pointers must return -1."

    cases = [
        [1.5, 2.5, 3.5],
        [0.25, 1.75, -0.5],
        [-1.5, -2.0, 0.25],
        [4.0, -1.0, 0.5, 2.0],
    ]
    for values in cases:
        array_type = ctypes.c_float * len(values)
        array = array_type(*values)
        expected = -1 if multiplier is None else int(sum(values) * multiplier)
        actual = function(array, len(values))
        assert actual == expected, (
            f"{library_path} returned {actual} for {values}; expected {expected}"
        )
    del function
    del library


def test_pipeline_libraries_are_loadable_and_correct():
    multipliers = [None, 2.0, 3.0]
    for name, multiplier in zip(LIB_NAMES, multipliers):
        exercise_library(os.path.join(HOME, "libs", name), multiplier)


def test_submitted_verify_py_executes_the_ffi_libraries():
    expected = ["-1", "15", "22"]
    for name, wanted in zip(LIB_NAMES, expected):
        library_path = os.path.join(HOME, "libs", name)
        result = subprocess.run(
            ["python3", os.path.join(HOME, "verify.py"), library_path],
            cwd=HOME,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, f"verify.py failed for {library_path}: {result.stderr}"
        assert result.stdout.strip() == wanted, (
            f"verify.py printed {result.stdout!r} for {library_path}; expected only {wanted!r}"
        )


def test_fresh_cargo_builds_from_submitted_rust_source():
    subprocess.run(
        ["cargo", "clean"],
        cwd=PROJECT,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )

    variants = [([], None), (["--features", "android"], 2.0), (["--features", "ios"], 3.0)]
    output_path = os.path.join(PROJECT, "target", "release", "libmobile_sensor.so")
    for feature_args, multiplier in variants:
        try:
            os.remove(output_path)
        except FileNotFoundError:
            pass
        result = subprocess.run(
            ["cargo", "build", "--release"] + feature_args,
            cwd=PROJECT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=300,
        )
        assert result.returncode == 0, (
            f"Fresh Cargo build failed for arguments {feature_args}.\n"
            f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )
        assert os.path.isfile(output_path), f"Cargo did not produce {output_path}."
        exercise_library(output_path, multiplier)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
