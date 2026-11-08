#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import json
import os
import runpy
import subprocess

ROOT = "/home/user/pr-review"


def run(cmd, **kwargs):
    return subprocess.run(
        cmd,
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        **kwargs,
    )


def execute(lib, bytecode, input_data):
    bytecode = bytes(bytecode)
    input_data = bytes(input_data)
    output_data = bytearray(len(input_data))
    b_arr = (ctypes.c_uint8 * len(bytecode)).from_buffer_copy(bytecode)
    i_arr = (ctypes.c_uint8 * len(input_data)).from_buffer_copy(input_data)
    o_arr = (ctypes.c_uint8 * len(output_data)).from_buffer(output_data)
    lib.execute_vm(b_arr, len(bytecode), i_arr, len(input_data), o_arr)
    return list(output_data)


def test_complete_submission():
    os.chdir(ROOT)

    makefile = os.path.join(ROOT, "Makefile")
    vm_c_path = os.path.join(ROOT, "vm.c")
    test_path = os.path.join(ROOT, "test_vm.py")
    process_path = os.path.join(ROOT, "process.py")
    so_path = os.path.join(ROOT, "libvm.so")
    input_path = os.path.join(ROOT, "input.bin")
    output_path = os.path.join(ROOT, "output.json")

    for path in (makefile, vm_c_path, test_path, process_path, input_path):
        assert os.path.isfile(path), f"Expected {path} to exist."

    # Rebuild from the submitted Makefile so a pre-existing or fabricated ELF file
    # cannot satisfy the build check.
    if os.path.exists(so_path):
        os.remove(so_path)
    result = run(["make"])
    assert result.returncode == 0, f"make failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(so_path), f"Expected {so_path} to be built."
    with open(so_path, "rb") as f:
        magic = f.read(4)
    assert magic == b"\x7fELF", f"{so_path} is not a valid ELF binary."

    elf = run(["readelf", "-h", so_path])
    assert elf.returncode == 0, f"readelf failed:\n{elf.stdout}\n{elf.stderr}"
    assert "DYN (Shared object file)" in elf.stdout, "libvm.so is not a shared object."

    # Load and exercise the rebuilt VM independently across its arithmetic ISA.
    lib = ctypes.CDLL(so_path)
    lib.execute_vm.argtypes = [
        ctypes.POINTER(ctypes.c_uint8), ctypes.c_int,
        ctypes.POINTER(ctypes.c_uint8), ctypes.c_int,
        ctypes.POINTER(ctypes.c_uint8),
    ]
    lib.execute_vm.restype = None

    samples = [0, 1, 3, 17, 127, 200, 255]
    assert execute(lib, [0x05, 0x01, 0x05, 0x02, 0x06, 0x07], samples) == [
        (x + 5) & 0xff for x in samples
    ]
    assert execute(lib, [0x05, 0x01, 0x03, 0x03, 0x06, 0x07], samples) == [
        (x - 3) & 0xff for x in samples
    ]
    assert execute(lib, [0x05, 0x01, 0x07, 0x04, 0x06, 0x07], samples) == [
        (x * 7) & 0xff for x in samples
    ]

    # Retain the original source assertion for the ADD fix.
    with open(vm_c_path, "r") as f:
        vm_content = f.read()
    assert "b + a" in vm_content, f"Expected to find 'b + a' in {vm_c_path} for the ADD instruction fix."

    # Verify the submitted ctypes binding at runtime and require the original
    # meaningful test to remain present, then run pytest as requested.
    test_globals = runpy.run_path(test_path)
    assert "lib" in test_globals, "test_vm.py must load the VM library."
    bound = test_globals["lib"].execute_vm.argtypes
    expected_types = [
        ctypes.POINTER(ctypes.c_uint8), ctypes.c_int,
        ctypes.POINTER(ctypes.c_uint8), ctypes.c_int,
        ctypes.POINTER(ctypes.c_uint8),
    ]
    assert bound == expected_types, f"execute_vm argtypes are incorrect: {bound!r}"
    assert callable(test_globals.get("test_add")), "test_vm.py must retain the VM addition test."
    test_globals["test_add"]()

    result = run(["python3", "-m", "pytest", "test_vm.py", "-q"])
    assert result.returncode == 0, f"pytest on {test_path} failed:\n{result.stdout}\n{result.stderr}"

    # Inspect and execute the submitted BYTECODE independently, so output.json
    # cannot be passed with a hardcoded fixed result.
    with open(process_path, "r") as f:
        process_source = f.read()
    process_tree = ast.parse(process_source, process_path)
    assert any(
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr == "execute_vm"
        for node in ast.walk(process_tree)
    ), "process.py must invoke execute_vm."

    process_globals = runpy.run_path(process_path)
    bytecode = process_globals.get("BYTECODE")
    assert isinstance(bytecode, bytes) and bytecode, "BYTECODE must be a non-empty bytes value."

    dynamic_input = bytes([0, 1, 2, 6, 31, 63, 124, 125, 127, 128, 200, 249, 255]) + os.urandom(41)
    dynamic_expected = [((2 * x) + 7) & 0xff for x in dynamic_input]
    assert execute(lib, bytecode, dynamic_input) == dynamic_expected, "BYTECODE does not implement y = 2*x + 7."

    original_input = open(input_path, "rb").read()
    try:
        with open(input_path, "wb") as f:
            f.write(dynamic_input)
        if os.path.exists(output_path):
            os.remove(output_path)
        result = run(["python3", "process.py"])
        assert result.returncode == 0, f"process.py failed:\n{result.stdout}\n{result.stderr}"
        assert os.path.isfile(output_path), f"Expected {output_path} to exist."
        with open(output_path, "r") as f:
            try:
                dynamic_output = json.load(f)
            except json.JSONDecodeError:
                assert False, f"{output_path} is not valid JSON."
        assert dynamic_output == dynamic_expected, "process.py produced incorrect output for verifier-generated input."
    finally:
        with open(input_path, "wb") as f:
            f.write(original_input)

    # Re-run on the task's original data and retain the original exact assertion.
    result = run(["python3", "process.py"])
    assert result.returncode == 0, f"process.py failed on original input:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(output_path), f"Expected {output_path} to exist."
    with open(output_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{output_path} is not valid JSON."
    expected = [9, 17, 27, 47, 107, 207]
    assert data == expected, f"Expected output.json to contain {expected}, but got {data}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
