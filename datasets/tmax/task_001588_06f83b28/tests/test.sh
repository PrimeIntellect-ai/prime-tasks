#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import base64
import csv
import io
import json
import operator
import os
import secrets
import shutil
import stat
import subprocess
import tempfile

import pytest


def test_builder_script_exists():
    path = "/home/user/builder.py"
    assert os.path.isfile(path), f"The script {path} does not exist."


def test_release_dir_exists():
    path = "/home/user/release"
    assert os.path.isdir(path), f"The directory {path} does not exist."


def test_auth_svc_executable():
    path = "/home/user/release/auth_svc_23"
    assert os.path.isfile(path), f"The compiled executable {path} does not exist."

    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"The file {path} is not executable."

    with open(path, "rb") as f:
        magic = f.read(4)
    assert magic == b"\x7fELF", f"The file {path} is not a valid ELF binary."


def test_data_svc_executable():
    path = "/home/user/release/data_svc_20"
    assert os.path.isfile(path), f"The compiled executable {path} does not exist."

    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"The file {path} is not executable."

    with open(path, "rb") as f:
        magic = f.read(4)
    assert magic == b"\x7fELF", f"The file {path} is not a valid ELF binary."


def test_release_log_json():
    path = "/home/user/release_log.json"
    assert os.path.isfile(path), f"The log file {path} does not exist."

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {path} does not contain valid JSON.")

    expected = {"auth_svc": 23, "data_svc": 20}
    assert data == expected, f"The contents of {path} do not match the expected output. Got: {data}"


_BINOPS = {
    ast.Add: operator.add,
    ast.Sub: operator.sub,
    ast.Mult: operator.mul,
    ast.Div: operator.truediv,
    ast.FloorDiv: operator.floordiv,
}
_UNARYOPS = {ast.UAdd: operator.pos, ast.USub: operator.neg}


def evaluate_expression(expression):
    def visit(node):
        if isinstance(node, ast.Expression):
            return visit(node.body)
        if isinstance(node, ast.Constant) and type(node.value) is int:
            return node.value
        if isinstance(node, ast.BinOp) and type(node.op) in _BINOPS:
            return _BINOPS[type(node.op)](visit(node.left), visit(node.right))
        if isinstance(node, ast.UnaryOp) and type(node.op) in _UNARYOPS:
            return _UNARYOPS[type(node.op)](visit(node.operand))
        raise AssertionError(f"Unexpected expression node: {ast.dump(node)}")

    result = visit(ast.parse(expression, mode="eval"))
    assert int(result) == result
    return int(result)


def assert_built_service(service, version, expected_output):
    path = f"/home/user/release/{service}_{version}"
    assert os.path.isfile(path), f"Expected executable was not built: {path}"
    assert os.access(path, os.X_OK), f"Built file is not executable: {path}"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Built file is not ELF: {path}"
    result = subprocess.run(
        [path], capture_output=True, text=True, timeout=20, check=False
    )
    assert result.returncode == 0, f"{path} failed: {result.stderr}"
    assert result.stdout.strip() == expected_output


def run_builder():
    result = subprocess.run(
        ["python3", "/home/user/builder.py"],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=120,
        check=False,
    )
    assert result.returncode == 0, (
        f"builder.py failed with status {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_builder_executes_manifest_and_builds_sources():
    home = "/home/user"
    manifest_path = os.path.join(home, "manifest.b32")
    release_path = os.path.join(home, "release")
    log_path = os.path.join(home, "release_log.json")

    with open(manifest_path, "rb") as f:
        saved_manifest = f.read()
    saved_log = None
    if os.path.isfile(log_path):
        with open(log_path, "rb") as f:
            saved_log = f.read()

    backup_root = tempfile.mkdtemp(prefix="builder-verifier-")
    backup_release = os.path.join(backup_root, "release")
    if os.path.isdir(release_path):
        shutil.copytree(release_path, backup_release)

    suffix = secrets.token_hex(6)
    c_service = f"calc_c_{suffix}"
    go_service = f"calc_go_{suffix}"
    c_source_name = f"source_{suffix}.c"
    go_source_name = f"source_{suffix}.go"
    c_source_path = os.path.join(home, c_source_name)
    go_source_path = os.path.join(home, go_source_name)
    c_marker = f"C_SOURCE_{secrets.token_hex(12)}"
    go_marker = f"GO_SOURCE_{secrets.token_hex(12)}"

    try:
        # First prove the submitted script can recreate the required original outputs.
        shutil.rmtree(release_path, ignore_errors=True)
        if os.path.exists(log_path):
            os.remove(log_path)
        run_builder()
        with open(log_path, "r") as f:
            original_log = json.load(f)
        assert original_log == {"auth_svc": 23, "data_svc": 20}
        assert all(type(value) is int for value in original_log.values())
        assert_built_service("auth_svc", 23, "Auth Service")
        assert_built_service("data_svc", 20, "Data Service")

        # Replace the manifest and sources with unpredictable cases so fixed outputs
        # cannot pass. Expected versions are independently evaluated here.
        a = secrets.randbelow(15) + 3
        b = secrets.randbelow(15) + 2
        multiplier = secrets.randbelow(5) + 2
        subtract = secrets.randbelow(5) + 1
        divisor = secrets.randbelow(7) + 2
        quotient = secrets.randbelow(40) + 10
        c_expr = f"({a}+{b})*{multiplier}-{subtract}"
        go_expr = f"({quotient}*({divisor}+1)-{quotient})/{divisor}"
        c_version = evaluate_expression(c_expr)
        go_version = evaluate_expression(go_expr)

        with open(c_source_path, "w") as f:
            f.write('#include <stdio.h>\nint main(void) { puts("' + c_marker + '"); return 0; }\n')
        with open(go_source_path, "w") as f:
            f.write('package main\nimport "fmt"\nfunc main() { fmt.Println("' + go_marker + '") }\n')

        csv_buffer = io.StringIO(newline="")
        writer = csv.writer(csv_buffer)
        writer.writerow(["service_name", "language", "source_file", "version_expr"])
        writer.writerow([c_service, "c", c_source_name, c_expr])
        writer.writerow([go_service, "go", go_source_name, go_expr])
        encoded = base64.b32encode(csv_buffer.getvalue().encode("utf-8"))
        with open(manifest_path, "wb") as f:
            f.write(encoded)

        shutil.rmtree(release_path, ignore_errors=True)
        if os.path.exists(log_path):
            os.remove(log_path)
        run_builder()

        assert os.path.isdir(release_path)
        with open(log_path, "r") as f:
            generated_log = json.load(f)
        expected_log = {c_service: c_version, go_service: go_version}
        assert generated_log == expected_log
        assert all(type(value) is int for value in generated_log.values())
        assert_built_service(c_service, c_version, c_marker)
        assert_built_service(go_service, go_version, go_marker)
    finally:
        with open(manifest_path, "wb") as f:
            f.write(saved_manifest)
        for path in (c_source_path, go_source_path):
            if os.path.exists(path):
                os.remove(path)
        shutil.rmtree(release_path, ignore_errors=True)
        if os.path.isdir(backup_release):
            shutil.copytree(backup_release, release_path)
        if saved_log is None:
            if os.path.exists(log_path):
                os.remove(log_path)
        else:
            with open(log_path, "wb") as f:
                f.write(saved_log)
        shutil.rmtree(backup_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
