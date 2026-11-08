#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import shutil
import stat
import subprocess

BASE_DIR = "/home/user/system_check"
SCRIPT_PATH = "/home/user/build_and_test.sh"
LOG_PATH = "/home/user/test_results.log"
LIB_PATH = os.path.join(BASE_DIR, "libcore.so")
RUST_BINARY = os.path.join(BASE_DIR, "rust_app", "target", "debug", "rust_app")


def run_checked(command, *, cwd, env=None, timeout=180):
    result = subprocess.run(
        command,
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Command failed with status {result.returncode}: {command}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def test_00_execute_build_and_test_script_from_clean_state():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."

    for path in (LOG_PATH, LIB_PATH, os.path.join(BASE_DIR, "stress_test")):
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.remove(path)
    shutil.rmtree(os.path.join(BASE_DIR, "rust_app", "target"), ignore_errors=True)

    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    run_checked([SCRIPT_PATH], cwd=BASE_DIR, env=env)


def test_patch_applied_libcore():
    filepath = os.path.join(BASE_DIR, "libcore.c")
    assert os.path.isfile(filepath), f"File {filepath} does not exist"
    with open(filepath, "r") as f:
        content = f.read()
    assert "free(ptr);" in content, "The memory leak in libcore.c was not fixed (patch not applied properly)."


def test_patch_applied_rust():
    filepath = os.path.join(BASE_DIR, "rust_app", "src", "main.rs")
    assert os.path.isfile(filepath), f"File {filepath} does not exist"
    with open(filepath, "r") as f:
        content = f.read()
    assert "fn process_data(input: i64) -> i64;" in content, "The ABI signature in main.rs was not updated (patch not applied properly)."
    assert "process_data(21i64)" in content, "The function call in main.rs was not updated (patch not applied properly)."


def test_stress_test_go_fixed():
    filepath = os.path.join(BASE_DIR, "stress_test.go")
    assert os.path.isfile(filepath), f"File {filepath} does not exist"
    with open(filepath, "r") as f:
        content = f.read()
    assert "close(results)" in content, "stress_test.go does not contain 'close(results)'. The deadlock was not fixed."


def test_build_and_test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()
    assert "LD_LIBRARY_PATH" in content, "The script does not configure LD_LIBRARY_PATH."


def test_fresh_native_and_rust_artifacts_are_real_and_work():
    assert os.path.isfile(LIB_PATH), "The build script did not create libcore.so."
    with open(LIB_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libcore.so is not an ELF binary."

    lib = ctypes.CDLL(LIB_PATH)
    process_data = lib.process_data
    process_data.argtypes = [ctypes.c_long]
    process_data.restype = ctypes.c_long
    for value in (-17, 0, 9, 123456):
        assert process_data(value) == value * 2

    assert os.path.isfile(RUST_BINARY), "The Rust debug binary was not built."
    assert os.access(RUST_BINARY, os.X_OK), "The Rust binary is not executable."
    with open(RUST_BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The Rust application is not an ELF binary."

    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = BASE_DIR
    result = run_checked([RUST_BINARY], cwd=BASE_DIR, env=env, timeout=30)
    assert result.stdout.strip() == "Result: 42", f"Unexpected Rust output: {result.stdout!r}"


def test_go_stress_test_really_runs_without_deadlock():
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = BASE_DIR
    result = run_checked(["go", "run", "stress_test.go"], cwd=BASE_DIR, env=env, timeout=90)
    assert result.stdout.strip() == "All workers completed successfully", (
        f"Unexpected Go stress-test output: {result.stdout!r}"
    )


def test_test_results_log():
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} does not exist. Did the script run successfully and redirect output?"
    with open(LOG_PATH, "r") as f:
        content = f.read().strip()
    assert content == "All workers completed successfully", f"Log file content is incorrect. Expected 'All workers completed successfully', got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
