#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import struct
import string
import subprocess
import tempfile

PROJECT = "/home/user/sec-eval"
LINUX_BIN = "/home/user/dist/sec-linux"
WINDOWS_BIN = "/home/user/dist/sec-win.exe"


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def assert_go_metadata(path, goos):
    result = run(["go", "version", "-m", path])
    assert result.returncode == 0, result.stderr
    metadata = result.stdout + result.stderr
    assert "sec-eval" in metadata, f"{path} is not a Go sec-eval binary: {metadata}"
    assert f"GOOS={goos}" in metadata, f"Wrong target OS in {path}: {metadata}"
    assert "GOARCH=amd64" in metadata, f"Wrong architecture in {path}: {metadata}"


def test_linux_binary_exists_and_elf():
    path = LINUX_BIN
    assert os.path.isfile(path), f"Linux binary {path} is missing."

    with open(path, "rb") as f:
        header = f.read(20)
    assert header[:4] == b"\x7fELF", f"File {path} is not a valid ELF executable."
    assert header[4] == 2, f"File {path} is not a 64-bit ELF executable."
    assert struct.unpack("<H", header[18:20])[0] == 62, f"File {path} is not amd64 ELF."
    assert_go_metadata(path, "linux")


def test_windows_binary_exists_and_pe():
    path = WINDOWS_BIN
    assert os.path.isfile(path), f"Windows binary {path} is missing."

    with open(path, "rb") as f:
        data = f.read()
    assert data[:2] == b"MZ", f"File {path} is not a valid Windows PE executable."
    assert len(data) >= 0x40, f"File {path} has a truncated DOS header."
    pe_offset = struct.unpack_from("<I", data, 0x3c)[0]
    assert pe_offset + 26 <= len(data), f"File {path} has a truncated PE header."
    assert data[pe_offset:pe_offset + 4] == b"PE\0\0", f"File {path} lacks a PE signature."
    assert struct.unpack_from("<H", data, pe_offset + 4)[0] == 0x8664, f"File {path} is not amd64 PE."
    assert struct.unpack_from("<H", data, pe_offset + 24)[0] == 0x20b, f"File {path} is not PE32+."
    assert_go_metadata(path, "windows")


def check_evaluator(path):
    result = run([path, "ALLOW"], timeout=10)
    assert result.returncode == 0, f"Expected return code 0 for 'ALLOW', got {result.returncode}."
    assert "ALLOW" in result.stdout, f"Expected output to contain 'ALLOW', got {result.stdout}."

    result_empty = run([path], timeout=10)
    assert result_empty.returncode == 1, f"Expected return code 1 for missing args, got {result_empty.returncode}."

    empty_argument = run([path, ""], timeout=10)
    assert empty_argument.returncode == 1, f"Expected return code 1 for an empty expression, got {empty_argument.returncode}."

    rng = random.SystemRandom()
    alphabet = string.ascii_letters + string.digits + " !&|():_-"
    cases = ["REPARSE", "EVAL:ALLOW", "EVAL:REPARSE"]
    for _ in range(30):
        value = "".join(rng.choice(alphabet) for _ in range(rng.randint(1, 80)))
        if value == "ALLOW" or "PANIC" in value:
            value += "_DENY"
        cases.append(value)

    for value in cases:
        result = run([path, value], timeout=10)
        assert result.returncode == 0, f"Expression {value!r} returned {result.returncode}: {result.stderr}"
        assert result.stdout.strip() == "DENY", f"Expression {value!r} should print DENY, got {result.stdout!r}"

    panic_token = "PANIC_" + "".join(rng.choice(string.ascii_letters) for _ in range(20))
    panic_result = run([path, panic_token], timeout=10)
    assert panic_result.returncode == 2, f"Panic path must retain exit code 2, got {panic_result.returncode}."


def test_linux_binary_execution():
    assert os.path.isfile(LINUX_BIN), f"Linux binary {LINUX_BIN} is missing."
    check_evaluator(LINUX_BIN)


def test_source_builds_without_circular_import_and_matches_behavior():
    assert os.path.isfile(os.path.join(PROJECT, "go.mod")), "Go module is missing."

    listed = run(["go", "list", "./..."], cwd=PROJECT, timeout=60)
    assert listed.returncode == 0, f"Go packages cannot be loaded (possible import cycle):\n{listed.stderr}"

    tested = run(["go", "test", "./..."], cwd=PROJECT, timeout=120)
    assert tested.returncode == 0, f"Go source tests/build failed:\n{tested.stdout}\n{tested.stderr}"

    with tempfile.TemporaryDirectory() as td:
        rebuilt_linux = os.path.join(td, "sec-linux")
        rebuilt_windows = os.path.join(td, "sec-win.exe")

        env = os.environ.copy()
        env.update({"GOOS": "linux", "GOARCH": "amd64", "CGO_ENABLED": "0"})
        built = run(["go", "build", "-o", rebuilt_linux, "."], cwd=PROJECT, env=env, timeout=120)
        assert built.returncode == 0, f"Linux source build failed:\n{built.stderr}"
        check_evaluator(rebuilt_linux)

        env.update({"GOOS": "windows", "GOARCH": "amd64"})
        built = run(["go", "build", "-o", rebuilt_windows, "."], cwd=PROJECT, env=env, timeout=120)
        assert built.returncode == 0, f"Windows cross-build failed:\n{built.stderr}"
        assert_go_metadata(rebuilt_windows, "windows")


def test_test_props_py_exists_and_valid_and_executes_property():
    path = "/home/user/test_props.py"
    assert os.path.isfile(path), f"Python test script {path} is missing."

    with open(path, "r") as f:
        content = f.read()
    assert "hypothesis" in content, f"Script {path} does not import hypothesis."
    assert "@given" in content, f"Script {path} does not use the @given decorator."

    real_run = run(["python3", path], cwd="/home/user", timeout=180)
    assert real_run.returncode == 0, f"Property test did not pass when executed:\n{real_run.stdout}\n{real_run.stderr}"

    backup = LINUX_BIN + ".verifier-backup"
    probe_log = "/tmp/sec_eval_property_probe.log"
    shutil.copy2(LINUX_BIN, backup)
    if os.path.exists(probe_log):
        os.unlink(probe_log)
    try:
        with open(LINUX_BIN, "w") as f:
            f.write("#!/usr/bin/python3\n")
            f.write("import sys\n")
            f.write(f"open({probe_log!r}, 'a').write(repr(sys.argv) + '\\n')\n")
            f.write("sys.exit(2 if len(sys.argv) == 2 else 0)\n")
        os.chmod(LINUX_BIN, 0o755)

        probe_run = run(["python3", path], cwd="/home/user", timeout=180)
        assert probe_run.returncode != 0, "Property test did not fail when the binary returned panic code 2."
        assert os.path.isfile(probe_log), "Property test never executed /home/user/dist/sec-linux."
        with open(probe_log) as f:
            calls = [line for line in f if line.strip()]
        assert calls, "Property test made no subprocess calls to the target binary."
    finally:
        if os.path.exists(LINUX_BIN):
            os.unlink(LINUX_BIN)
        os.replace(backup, LINUX_BIN)


def test_test_result_log():
    path = "/home/user/test_result.log"
    assert os.path.isfile(path), f"Result log {path} is missing."

    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "TESTS_PASSED", f"Expected log to contain exactly 'TESTS_PASSED', got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
