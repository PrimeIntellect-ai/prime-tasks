#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import importlib.util
import json
import os
import secrets
import subprocess

VM_PATH = "/home/user/pr_review/src/vm.py"
PAYLOAD_PATH = "/home/user/pr_review/tests/test_payload.json"
OUTPUT_PATH = "/home/user/pr_review/output.log"
LIB_PATH = "/home/user/pr_review/lib/libprocessor.so"


def run_vm(payload_path):
    return subprocess.run(
        ["python3", VM_PATH, str(payload_path)],
        text=True,
        capture_output=True,
        timeout=10,
    )


def load_vm():
    spec = importlib.util.spec_from_file_location("submitted_vm", VM_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_output_log_exists_and_correct_after_execution():
    if os.path.lexists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    result = run_vm(PAYLOAD_PATH)
    assert result.returncode == 0, result.stderr
    assert os.path.exists(OUTPUT_PATH), f"Output file is missing: {OUTPUT_PATH}. Did you run the emulator script?"
    assert os.path.isfile(OUTPUT_PATH), f"Output path is not a file: {OUTPUT_PATH}"

    with open(OUTPUT_PATH, "r") as f:
        content = f.read().strip()

    assert content == "SUCCESS: 28", f"Output log contains incorrect state. Expected 'SUCCESS: 28', got '{content}'"


def test_vm_py_modifications_and_real_abi():
    assert os.path.exists(VM_PATH), f"File missing: {VM_PATH}"
    assert os.path.isfile(VM_PATH), f"VM path is not a file: {VM_PATH}"

    with open(VM_PATH, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "argtypes" in content and "restype" in content, "The ctypes ABI definitions (argtypes and restype) are still missing in vm.py."
    assert "c_double" in content, "The ctypes ABI definitions should use ctypes.c_double."

    vm = load_vm()
    fn = vm.lib.execute_magic
    assert isinstance(fn, ctypes._CFuncPtr), "execute_magic must be loaded from the C shared library"
    assert fn.argtypes == [ctypes.c_double], "execute_magic.argtypes must be [ctypes.c_double]"
    assert fn.restype is ctypes.c_double, "execute_magic.restype must be ctypes.c_double"


def test_constraints_and_generated_execution(tmp_path):
    vm = load_vm()

    even_value = 2 * secrets.randbelow(5000) + 2
    odd_value = 2 * secrets.randbelow(5000) + 1

    assert vm.verify_constraints([{"op": "magic", "args": [even_value]}]) is True
    for invalid in (0, -2, odd_value):
        assert vm.verify_constraints([{"op": "magic", "args": [invalid]}]) is False

    # Keep the pre-existing no-consecutive-add constraint intact.
    assert vm.verify_constraints([
        {"op": "add", "args": [1]},
        {"op": "add", "args": [2]},
    ]) is False

    generated = tmp_path / "generated_payload.json"
    add_before = secrets.randbelow(100) + 1
    add_after = secrets.randbelow(100) + 1
    generated.write_text(json.dumps({"instructions": [
        {"op": "add", "args": [add_before]},
        {"op": "magic", "args": [even_value]},
        {"op": "add", "args": [add_after]},
    ]}))

    oracle = ctypes.CDLL(LIB_PATH)
    oracle.execute_magic.argtypes = [ctypes.c_double]
    oracle.execute_magic.restype = ctypes.c_double
    expected = int(add_before + oracle.execute_magic(even_value) + add_after)

    if os.path.lexists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = run_vm(generated)
    assert result.returncode == 0, result.stderr
    assert os.path.isfile(OUTPUT_PATH), "The executed VM did not create output.log"
    with open(OUTPUT_PATH, "r") as f:
        assert f.read().strip() == f"SUCCESS: {expected}"

    for index, invalid in enumerate((0, -2, odd_value)):
        invalid_payload = tmp_path / f"invalid_{index}.json"
        invalid_payload.write_text(json.dumps({"instructions": [
            {"op": "magic", "args": [invalid]}
        ]}))
        if os.path.lexists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
        result = run_vm(invalid_payload)
        assert result.returncode == 0, result.stderr
        assert "CONSTRAINT_VIOLATION" in result.stdout
        assert not os.path.exists(OUTPUT_PATH), "Invalid magic input must not be executed"

    # Restore and revalidate the requested final artifact.
    result = run_vm(PAYLOAD_PATH)
    assert result.returncode == 0, result.stderr
    assert os.path.isfile(OUTPUT_PATH)
    with open(OUTPUT_PATH, "r") as f:
        assert f.read().strip() == "SUCCESS: 28"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
