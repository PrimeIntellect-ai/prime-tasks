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

import pytest

PROJECT_DIR = "/home/user/project"
BIN_DIR = os.path.join(PROJECT_DIR, "bin")
BUILD_SCRIPT = os.path.join(PROJECT_DIR, "build.sh")


@pytest.fixture(scope="session", autouse=True)
def rebuild_from_scratch():
    assert os.path.isfile(BUILD_SCRIPT), f"{BUILD_SCRIPT} does not exist."
    assert os.access(BUILD_SCRIPT, os.X_OK), f"{BUILD_SCRIPT} is not executable."

    shutil.rmtree(BIN_DIR, ignore_errors=True)
    os.makedirs(BIN_DIR)
    result = subprocess.run(
        [BUILD_SCRIPT],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"build.sh failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_build_script_exists_and_executable():
    build_script = os.path.join(PROJECT_DIR, "build.sh")
    assert os.path.isfile(build_script), f"{build_script} does not exist."
    st = os.stat(build_script)
    assert bool(st.st_mode & stat.S_IXUSR), f"{build_script} is not executable."


@pytest.mark.parametrize("lib_name", [
    "libC.so",
    "libB.so",
    "libA.so",
])
def test_shared_libraries_exist(lib_name):
    lib_path = os.path.join(BIN_DIR, lib_name)
    assert os.path.isfile(lib_path), f"Shared library {lib_path} was not built or is missing."


@pytest.mark.parametrize("lib_name,func_name,expected", [
    ("libC.so", "funcC", 10),
    ("libB.so", "funcB", 30),
    ("libA.so", "funcA", 60),
])
def test_shared_libraries_are_loadable_and_functional(lib_name, func_name, expected):
    lib_path = os.path.join(BIN_DIR, lib_name)
    with open(lib_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{lib_path} is not an ELF shared library."

    code = (
        "import ctypes, sys; "
        "lib = ctypes.CDLL(sys.argv[1]); "
        "fn = getattr(lib, sys.argv[2]); "
        "fn.restype = ctypes.c_int; "
        "print(fn())"
    )
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = BIN_DIR + os.pathsep + env.get("LD_LIBRARY_PATH", "")
    result = subprocess.run(
        ["python3", "-c", code, lib_path, func_name],
        cwd=PROJECT_DIR,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Could not load/call {func_name} from {lib_path}: {result.stderr}"
    )
    assert result.stdout.strip() == str(expected), (
        f"{func_name} from {lib_path} returned {result.stdout.strip()!r}, expected {expected}."
    )


def test_mock_config_json():
    config_path = os.path.join(PROJECT_DIR, "mock_config.json")
    assert os.path.isfile(config_path), f"{config_path} does not exist."

    with open(config_path, "r") as f:
        try:
            config = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{config_path} does not contain valid JSON.")

    expected_config = {"environment": "CI", "strict_mode": True}
    assert config == expected_config, f"{config_path} content {config} does not match expected {expected_config}."


def test_runner_output_and_saved_diff():
    runner_path = os.path.join(PROJECT_DIR, "test_runner.py")
    expected_path = os.path.join(PROJECT_DIR, "expected.txt")
    patch_path = os.path.join(PROJECT_DIR, "test_diff.patch")
    assert os.path.isfile(runner_path), f"{runner_path} does not exist."
    assert os.path.isfile(expected_path), f"{expected_path} does not exist."
    assert os.path.isfile(patch_path), f"{patch_path} does not exist."

    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = BIN_DIR + os.pathsep + env.get("LD_LIBRARY_PATH", "")
    result = subprocess.run(
        ["python3", runner_path],
        cwd=PROJECT_DIR,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"test_runner.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    expected_lines = ["Platform: CI", "Result_A: 60", "Status: SUCCESS"]
    assert sorted(result.stdout.splitlines()) == expected_lines, (
        f"Unexpected test runner output: {result.stdout!r}"
    )

    with tempfile.TemporaryDirectory() as tmpdir:
        actual_sorted = os.path.join(tmpdir, "actual.sorted")
        expected_sorted = os.path.join(tmpdir, "expected.sorted")
        with open(actual_sorted, "w") as f:
            for line in sorted(result.stdout.splitlines()):
                f.write(line + "\n")
        with open(expected_sorted, "wb") as f:
            sort_result = subprocess.run(
                ["sort", expected_path],
                cwd=PROJECT_DIR,
                stdout=f,
                stderr=subprocess.PIPE,
                timeout=20,
            )
        assert sort_result.returncode == 0, "Could not sort expected.txt."

        diff_result = subprocess.run(
            ["diff", "-u", expected_sorted, actual_sorted],
            cwd=PROJECT_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert diff_result.returncode in (0, 1), (
            f"diff failed: {diff_result.stderr.decode(errors='replace')}"
        )
        with open(patch_path, "rb") as f:
            saved_patch = f.read()
        assert saved_patch == diff_result.stdout, (
            "test_diff.patch is not the exact output of diff -u over the sorted expected and actual output."
        )
        assert diff_result.returncode == 0, "The actual test output does not match expected.txt."


def test_test_diff_patch_empty():
    patch_path = os.path.join(PROJECT_DIR, "test_diff.patch")
    assert os.path.isfile(patch_path), f"{patch_path} does not exist."

    file_size = os.path.getsize(patch_path)
    assert file_size == 0, f"{patch_path} is not empty (size is {file_size} bytes). This indicates the diff found differences."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
