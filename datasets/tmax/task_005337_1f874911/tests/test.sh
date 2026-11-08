#!/bin/bash
set -e
mkdir -p /logs/verifier

# Remove generated artifacts so the verifier checks a fresh pipeline execution.
rm -rf /home/user/waf_pipeline/rust_sanitizer/target
rm -f /home/user/waf_pipeline/python_scanner/librust_sanitizer.so
rm -f /home/user/waf_pipeline/scan_result.log

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import ctypes
import importlib.util
import os
import random
import stat
import subprocess

ROOT = "/home/user/waf_pipeline"
SCRIPT = os.path.join(ROOT, "build_and_run.sh")
RUST_LIB = os.path.join(ROOT, "rust_sanitizer", "target", "release", "librust_sanitizer.so")
COPIED_LIB = os.path.join(ROOT, "python_scanner", "librust_sanitizer.so")
LOG = os.path.join(ROOT, "scan_result.log")


def test_00_build_and_run_script_executable_and_runs_pipeline():
    assert os.path.exists(SCRIPT), f"The script {SCRIPT} does not exist."
    st = os.stat(SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"The script {SCRIPT} is not executable."

    completed = subprocess.run(
        [SCRIPT], cwd=ROOT, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=180
    )
    assert completed.returncode == 0, completed.stdout

    assert os.path.isfile(RUST_LIB), "The release-mode Rust shared library was not built."
    assert os.path.isfile(COPIED_LIB), "The Rust shared library was not copied to python_scanner."
    with open(RUST_LIB, "rb") as built, open(COPIED_LIB, "rb") as copied:
        assert built.read() == copied.read(), "The copied library differs from the release build."


def test_01_rust_sanitizer_behavior():
    lib = ctypes.CDLL(COPIED_LIB)
    sanitize = lib.sanitize_payload
    sanitize.argtypes = [ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t]
    sanitize.restype = ctypes.c_size_t

    rng = random.Random(73129)
    for length in (1, 2, 7, 31):
        original = bytes([rng.randrange(1, 256)] + [rng.randrange(256) for _ in range(length - 1)])
        buffer = (ctypes.c_uint8 * length)(*original)
        returned = sanitize(buffer, length)
        assert returned == length
        expected = bytes((value - 1) & 0xFF for value in original)
        assert bytes(buffer) == expected


def load_vm_class():
    path = os.path.join(ROOT, "python_scanner", "vm.py")
    spec = importlib.util.spec_from_file_location("submitted_waf_vm", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.WAFEmulator


def test_02_python_vm_xor_behavior():
    WAFEmulator = load_vm_class()
    rng = random.Random(90210)
    cases = [(0, 0), (42, 17), (255, 170)]
    cases.extend((rng.randrange(256), rng.randrange(256)) for _ in range(20))

    for a, b in cases:
        bytecode = bytes([0x01, a, 0x01, b, 0x03, 0x00])
        assert WAFEmulator(bytecode).run() == [a ^ b]

    mixed = bytes([0x01, 10, 0x01, 20, 0x02, 0x01, 7, 0x03, 0x00])
    assert WAFEmulator(mixed).run() == [((10 + 20) & 0xFF) ^ 7]


def independently_execute(bytecode):
    stack = []
    pc = 0
    while pc < len(bytecode):
        opcode = bytecode[pc]
        pc += 1
        if opcode == 0x00:
            break
        if opcode == 0x01:
            stack.append(bytecode[pc])
            pc += 1
        elif opcode == 0x02:
            b = stack.pop()
            a = stack.pop()
            stack.append((a + b) & 0xFF)
        elif opcode == 0x03:
            b = stack.pop()
            a = stack.pop()
            stack.append(a ^ b)
    return stack


def test_03_scan_result_log():
    assert os.path.exists(LOG), f"The log file {LOG} does not exist. Did the pipeline run successfully?"
    with open(LOG, "r") as f:
        content = f.read().strip()

    payload_path = os.path.join(ROOT, "python_scanner", "payload.b64")
    with open(payload_path, "r") as f:
        encoded = f.read().strip()
    raw = base64.b64decode(encoded)
    sanitized = bytes((value - 1) & 0xFF for value in raw)
    expected_stack = independently_execute(sanitized)
    expected_str = f"RESULT: {expected_stack}"

    assert expected_stack == [59]
    assert content == expected_str, f"Expected log file to contain '{expected_str}', but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
