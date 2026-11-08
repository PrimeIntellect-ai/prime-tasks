#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import secrets
import shutil
import string
import struct
import subprocess
import tempfile


def assert_elf_amd64(path):
    with open(path, "rb") as f:
        header = f.read(64)
    assert header[:4] == b"\x7fELF", f"{path} is not an ELF binary."
    assert header[4] == 2, f"{path} is not a 64-bit ELF binary."
    assert header[5] == 1, f"{path} is not a little-endian ELF binary."
    assert struct.unpack_from("<H", header, 18)[0] == 62, f"{path} is not an amd64 ELF binary."
    assert struct.unpack_from("<H", header, 16)[0] in (2, 3), f"{path} is not an executable ELF type."


def run_and_expect_reverse(path, value):
    result = subprocess.run([path, value], capture_output=True, timeout=10)
    assert result.returncode == 0, f"{path} exited with status {result.returncode}: {result.stderr!r}"
    expected = value[::-1].encode()
    assert result.stdout == expected, f"For {value!r}, expected {expected!r}, got {result.stdout!r}."


def test_c_binary_compiled_correctly():
    path = "/home/user/artifacts/c_linux_amd64"
    assert os.path.isfile(path), f"File {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    assert_elf_amd64(path)

    result = subprocess.run([path, "abcdef"], capture_output=True, text=True)
    assert result.stdout == "fedcba", f"Expected 'fedcba', but got '{result.stdout}'. Was ENABLE_REVERSE=1 passed?"

    alphabet = string.ascii_letters + string.digits + "_-.:@"
    for _ in range(20):
        value = "".join(secrets.choice(alphabet) for _ in range(secrets.randbelow(70) + 1))
        run_and_expect_reverse(path, value)


def test_go_binary_compiled_correctly():
    path = "/home/user/artifacts/go_linux_amd64"
    assert os.path.isfile(path), f"File {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    assert_elf_amd64(path)

    result = subprocess.run([path, "12345"], capture_output=True, text=True)
    assert result.stdout == "54321", f"Expected '54321', but got '{result.stdout}'."

    alphabet = string.ascii_letters + string.digits + "_-.:@"
    for _ in range(20):
        value = "".join(secrets.choice(alphabet) for _ in range(secrets.randbelow(70) + 1))
        run_and_expect_reverse(path, value)

    metadata = subprocess.run(["go", "version", "-m", path], capture_output=True, text=True, timeout=10)
    assert metadata.returncode == 0, f"{path} is not recognized as a Go executable."
    assert "go1" in metadata.stdout, f"{path} lacks Go build metadata."
    assert "GOOS=linux" in metadata.stdout and "GOARCH=amd64" in metadata.stdout, metadata.stdout


def test_native_binaries_match_on_unpredictable_inputs():
    c_path = "/home/user/artifacts/c_linux_amd64"
    go_path = "/home/user/artifacts/go_linux_amd64"
    alphabet = string.ascii_lowercase + string.digits
    for _ in range(30):
        value = "".join(secrets.choice(alphabet) for _ in range(secrets.randbelow(50) + 1))
        c_result = subprocess.run([c_path, value], capture_output=True, timeout=10)
        go_result = subprocess.run([go_path, value], capture_output=True, timeout=10)
        assert c_result.returncode == 0 and go_result.returncode == 0
        assert c_result.stdout == go_result.stdout == value[::-1].encode()


def test_go_windows_cross_compiled():
    path = "/home/user/artifacts/go_windows_amd64.exe"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "rb") as f:
        data = f.read()
    header = data[:2]
    assert header == b"MZ", f"File {path} does not appear to be a valid Windows executable (missing MZ header)."
    assert len(data) >= 0x40, "Truncated DOS header."
    pe_offset = struct.unpack_from("<I", data, 0x3c)[0]
    assert pe_offset + 24 <= len(data), "Invalid PE header offset."
    assert data[pe_offset:pe_offset + 4] == b"PE\0\0", "Missing PE signature."
    machine, sections, _, _, _, optional_size, characteristics = struct.unpack_from("<HHIIIHH", data, pe_offset + 4)
    assert machine == 0x8664, "Windows executable is not amd64."
    assert sections > 0, "Windows executable has no sections."
    assert characteristics & 0x0002, "PE image is not marked executable."
    assert optional_size >= 2 and pe_offset + 24 + optional_size <= len(data), "Invalid PE optional header."
    assert struct.unpack_from("<H", data, pe_offset + 24)[0] == 0x20b, "Windows executable is not PE32+."

    metadata = subprocess.run(["go", "version", "-m", path], capture_output=True, text=True, timeout=10)
    assert metadata.returncode == 0, f"{path} is not recognized as a Go executable."
    assert "go1" in metadata.stdout, f"{path} lacks Go build metadata."
    assert "GOOS=windows" in metadata.stdout and "GOARCH=amd64" in metadata.stdout, metadata.stdout


def test_python_script_modified_and_actually_tests_binaries():
    script = "/home/user/src/test_props.py"
    report = "/home/user/artifacts/test_report.txt"
    c_path = "/home/user/artifacts/c_linux_amd64"
    go_path = "/home/user/artifacts/go_linux_amd64"
    assert os.path.isfile(script), f"File {script} does not exist."

    with open(script, "r") as f:
        content = f.read()
    assert "TODO: Implement subprocess calls" not in content, "The Python script still contains the TODO comment, indicating it was not fully modified."
    assert "subprocess" in content, "The Python script does not seem to use 'subprocess'."

    tree = ast.parse(content)
    functions = [node for node in tree.body if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == "test_processors_match"]
    assert functions, "test_processors_match(input_str) is missing."
    function = functions[0]
    assert any(arg.arg == "input_str" for arg in function.args.args), "test_processors_match must accept input_str."
    assert any(isinstance(node, ast.Assert) and isinstance(node.test, ast.Compare) and any(isinstance(op, ast.Eq) for op in node.test.ops) for node in ast.walk(function)), "test_processors_match must assert strict equality."

    tempdir = tempfile.mkdtemp(prefix="verify-props-")
    saved_c = os.path.join(tempdir, "c_linux_amd64")
    saved_go = os.path.join(tempdir, "go_linux_amd64")
    c_log = os.path.join(tempdir, "c_args.json")
    go_log = os.path.join(tempdir, "go_args.json")
    left = secrets.token_hex(24)
    right = secrets.token_hex(24)

    os.replace(c_path, saved_c)
    os.replace(go_path, saved_go)
    try:
        wrappers = ((c_path, c_log, left), (go_path, go_log, right))
        for path, log, output in wrappers:
            wrapper = "#!/usr/bin/python3\nimport json,sys\njson.dump(sys.argv[1:], open(%r, 'w'))\nsys.stdout.write(%r)\n" % (log, output)
            with open(path, "w") as f:
                f.write(wrapper)
            os.chmod(path, 0o755)

        if os.path.exists(report):
            os.unlink(report)
        mismatch = subprocess.run(["python3", script], capture_output=True, text=True, timeout=90)
        assert mismatch.returncode != 0, "The property test did not fail when the two processors produced different stdout."
        assert os.path.isfile(c_log) and os.path.isfile(go_log), "The property test did not execute both required native binaries."
        with open(c_log) as f:
            c_args = json.load(f)
        with open(go_log) as f:
            go_args = json.load(f)
        assert len(c_args) == 1 and len(go_args) == 1, "Each processor must receive input_str as its only argument."
        assert c_args == go_args, "The property test did not pass the same input_str to both processors."
    finally:
        for path in (c_path, go_path):
            if os.path.lexists(path):
                os.unlink(path)
        os.replace(saved_c, c_path)
        os.replace(saved_go, go_path)
        shutil.rmtree(tempdir, ignore_errors=True)

    if os.path.exists(report):
        os.unlink(report)
    completed = subprocess.run(["python3", script], capture_output=True, text=True, timeout=120)
    assert completed.returncode == 0, f"Property test script failed:\n{completed.stdout}\n{completed.stderr}"


def test_test_report_generated():
    path = "/home/user/artifacts/test_report.txt"
    assert os.path.isfile(path), f"File {path} does not exist. Did you run the tests?"
    with open(path, "r") as f:
        content = f.read().strip()
    assert "PROPERTY TESTS PASSED" in content, f"Report file {path} does not contain the expected success message."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
