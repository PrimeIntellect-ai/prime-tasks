#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import textwrap
import pytest

BUILD_DIR = "/home/user/build"
CRUNCH_C_PATH = os.path.join(BUILD_DIR, "crunch.c")
MAKEFILE_PATH = os.path.join(BUILD_DIR, "Makefile")
TEST_RUN_PATH = os.path.join(BUILD_DIR, "test_run.py")
RELEASE_INFO_PATH = "/home/user/release_info.txt"
LIBCRUNCH_SO_PATH = os.path.join(BUILD_DIR, "libcrunch.so")


def test_release_info_contents():
    assert os.path.isfile(RELEASE_INFO_PATH), f"File {RELEASE_INFO_PATH} does not exist."
    with open(RELEASE_INFO_PATH, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {RELEASE_INFO_PATH}, got {len(lines)}"
    assert lines[0] == "BUILD: SUCCESS", f"Line 1 should be 'BUILD: SUCCESS', got '{lines[0]}'"
    assert lines[1] == "LEAK: FIXED", f"Line 2 should be 'LEAK: FIXED', got '{lines[1]}'"


def test_makefile_and_build():
    if os.path.exists(LIBCRUNCH_SO_PATH):
        os.remove(LIBCRUNCH_SO_PATH)

    result = subprocess.run(
        ["make", "release"],
        cwd=BUILD_DIR,
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"make release failed:\n{result.stderr}"
    assert os.path.isfile(LIBCRUNCH_SO_PATH), "libcrunch.so was not created by make release."

    # Rebuild through a compiler wrapper so the flags actually passed to gcc are checked,
    # rather than trusting text or comments in the Makefile.
    wrapper_path = "/tmp/recording-gcc"
    args_path = "/tmp/recording-gcc.args"
    with open(wrapper_path, "w") as f:
        f.write("#!/bin/sh\n: > /tmp/recording-gcc.args\nprintf '%s\\n' \"$@\" > /tmp/recording-gcc.args\nexec /usr/bin/gcc \"$@\"\n")
    os.chmod(wrapper_path, 0o755)
    if os.path.exists(args_path):
        os.remove(args_path)
    if os.path.exists(LIBCRUNCH_SO_PATH):
        os.remove(LIBCRUNCH_SO_PATH)

    instrumented = subprocess.run(
        ["make", "-B", "release", f"CC={wrapper_path}"],
        cwd=BUILD_DIR,
        capture_output=True,
        text=True
    )
    assert instrumented.returncode == 0, f"instrumented make release failed:\n{instrumented.stderr}"
    assert os.path.isfile(LIBCRUNCH_SO_PATH), "instrumented release build did not create libcrunch.so."
    assert os.path.isfile(args_path), "release target did not invoke the configured C compiler."
    with open(args_path, "r") as f:
        compiler_args = [line.rstrip("\n") for line in f]
    assert "-O3" in compiler_args, f"release compiler invocation did not use -O3: {compiler_args}"
    assert "-shared" in compiler_args, f"release compiler invocation did not use -shared: {compiler_args}"
    assert "-fPIC" in compiler_args, f"release compiler invocation did not use -fPIC: {compiler_args}"


def test_libcrunch_is_shared_object():
    assert os.path.isfile(LIBCRUNCH_SO_PATH), "libcrunch.so does not exist."
    result = subprocess.run(
        ["file", LIBCRUNCH_SO_PATH],
        capture_output=True,
        text=True
    )
    assert "shared object" in result.stdout.lower(), f"libcrunch.so is not a valid shared object. file output: {result.stdout}"


def test_memory_leak_fixed():
    assert os.path.isfile(CRUNCH_C_PATH), f"File {CRUNCH_C_PATH} does not exist."
    with open(CRUNCH_C_PATH, "r") as f:
        content = f.read()
    assert "free(" in content, "crunch.c does not seem to contain a call to free()."

    # Exercise process_array on independently generated inputs and verify its output.
    driver_path = "/tmp/exercise_crunch.py"
    with open(driver_path, "w") as f:
        f.write(textwrap.dedent(f"""
            import ctypes

            lib = ctypes.CDLL({LIBCRUNCH_SO_PATH!r})
            lib.process_array.argtypes = [ctypes.POINTER(ctypes.c_int), ctypes.c_int]
            lib.process_array.restype = None

            for round_no in range(64):
                size = 4096
                expected = [((i * 7919 + round_no * 104729) % 2000001) - 1000000 for i in range(size)]
                Array = ctypes.c_int * size
                data = Array(*expected)
                lib.process_array(data, size)
                actual = list(data)
                if actual != expected:
                    raise AssertionError(f"process_array changed data on round {{round_no}}")
            print("DONE")
        """))

    valgrind_result = subprocess.run(
        [
            "valgrind",
            "--leak-check=full",
            "--show-leak-kinds=definite",
            "--errors-for-leak-kinds=definite",
            "--error-exitcode=97",
            "python3",
            driver_path,
        ],
        cwd=BUILD_DIR,
        capture_output=True,
        text=True,
        timeout=180
    )

    run_result = subprocess.run(
        ["python3", TEST_RUN_PATH],
        cwd=BUILD_DIR,
        capture_output=True,
        text=True,
        timeout=180
    )
    assert run_result.returncode == 0, f"test_run.py failed to execute:\n{run_result.stderr}"
    assert "DONE" in run_result.stdout, "test_run.py did not print DONE. It might have crashed or been killed."

    valgrind_output = valgrind_result.stdout + valgrind_result.stderr
    assert valgrind_result.returncode == 0, f"Valgrind detected a definite leak or execution failure:\n{valgrind_output}"
    assert "DONE" in valgrind_result.stdout, f"Valgrind exercise did not complete successfully:\n{valgrind_output}"
    assert "definitely lost: 0 bytes in 0 blocks" in valgrind_output, f"Valgrind did not report zero definitely-lost memory:\n{valgrind_output}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
