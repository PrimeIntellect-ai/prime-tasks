#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import operator
import os
import stat
import struct
import subprocess
import tempfile
import pytest

EXPECTED_SOURCE = '''#include <stdio.h>
#include <stdlib.h>

#ifndef VERSION
#define VERSION "0.0"
#endif

int main() {
    int *arr = malloc(5 * sizeof(int));
    arr[0] = 1;
    free(arr);
    printf("App Version: %s\\n", VERSION);
    return 0;
}
'''

BIN_OPS = {
    ast.Add: operator.add,
    ast.Sub: operator.sub,
    ast.Mult: operator.mul,
    ast.Div: operator.truediv,
    ast.FloorDiv: operator.floordiv,
    ast.Mod: operator.mod,
    ast.Pow: operator.pow,
}
UNARY_OPS = {ast.UAdd: operator.pos, ast.USub: operator.neg}

def eval_arithmetic(expression):
    def visit(node):
        if isinstance(node, ast.Expression):
            return visit(node.body)
        if isinstance(node, ast.Constant) and type(node.value) is int:
            return node.value
        if isinstance(node, ast.BinOp) and type(node.op) in BIN_OPS:
            return BIN_OPS[type(node.op)](visit(node.left), visit(node.right))
        if isinstance(node, ast.UnaryOp) and type(node.op) in UNARY_OPS:
            return UNARY_OPS[type(node.op)](visit(node.operand))
        raise AssertionError(f"Unsupported expression element: {ast.dump(node)}")
    value = visit(ast.parse(expression, mode="eval"))
    assert isinstance(value, (int, float)) and int(value) == value
    return int(value)

def evaluated_version():
    values = {}
    with open('/home/user/versions.expr', 'r') as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line:
                continue
            name, expression = line.split('=', 1)
            name = name.strip()
            assert name in {'MAJOR', 'MINOR'}
            assert name not in values
            values[name] = eval_arithmetic(expression.strip())
    assert set(values) == {'MAJOR', 'MINOR'}
    return f"{values['MAJOR']}.{values['MINOR']}"

def test_ci_vars_env_created():
    path = "/home/user/ci_vars.env"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == 'VERSION="8.7"', f"File {path} does not contain the expected VERSION string. Found: {content}"
    assert content == f'VERSION="{evaluated_version()}"'

def test_app_c_patched():
    path = "/home/user/src/app.c"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, "r") as f:
        content = f.read()
    assert "free(arr);" in content, f"File {path} does not appear to be patched. Missing 'free(arr);'."
    assert content == EXPECTED_SOURCE, "app.c is not the source produced by applying the supplied memory-leak patch."

def test_app_compiled_and_executable():
    path = "/home/user/bin/app"
    assert os.path.isfile(path), f"Executable {path} is missing."
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    assert stat.S_ISREG(os.stat(path, follow_symlinks=False).st_mode), f"File {path} must be a regular file."
    with open(path, 'rb') as f:
        header = f.read(20)
    assert header[:4] == b'\x7fELF', f"File {path} is not a compiled ELF binary."
    assert len(header) >= 20 and header[4] == 2, "Release binary is not a 64-bit ELF file."
    endian = '<' if header[5] == 1 else '>' if header[5] == 2 else None
    assert endian is not None, "Release binary has an invalid ELF byte order."
    elf_type, machine = struct.unpack(endian + 'HH', header[16:20])
    assert elf_type in (2, 3), "Release artifact is not an ELF executable or PIE executable."
    assert machine == 62, "Release artifact is not an x86-64 binary produced for this environment."

def test_patched_source_compiles_with_evaluated_version():
    version = evaluated_version()
    assert version == '8.7'
    with tempfile.TemporaryDirectory() as directory:
        rebuilt = os.path.join(directory, 'app')
        result = subprocess.run(
            ['gcc', f'-DVERSION="{version}"', '/home/user/src/app.c', '-o', rebuilt],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, f"Patched app.c does not compile with gcc: {result.stderr}"
        run = subprocess.run([rebuilt], capture_output=True, text=True, timeout=5)
        assert run.returncode == 0
        assert run.stdout.strip() == f'App Version: {version}'

def test_app_execution_output():
    path = "/home/user/bin/app"
    assert os.path.isfile(path), f"Executable {path} is missing."
    try:
        result = subprocess.run([path], capture_output=True, text=True, check=True, timeout=5)
        output = result.stdout.strip()
        expected = "App Version: 8.7"
        assert output == expected, f"Expected output '{expected}', but got '{output}'"
        assert output == f"App Version: {evaluated_version()}"
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Execution of {path} failed with return code {e.returncode}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
