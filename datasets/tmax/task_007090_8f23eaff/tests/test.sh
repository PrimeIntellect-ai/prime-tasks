#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import os
import re
import shutil
import subprocess
import tempfile
import time

import pytest

HOME = "/home/user"
SO_PATH = f"{HOME}/librle.so"
CPP_PATH = f"{HOME}/rle.cpp"
PATCH_PATH = f"{HOME}/rle.patch"
PY_PATH = f"{HOME}/ffi_test.py"
SH_PATH = f"{HOME}/benchmark.sh"
LOG_PATH = f"{HOME}/benchmark.log"

ORIGINAL = '''void rle_encode(const char* input, char* output, int max_out_len) {
    int i = 0;
    int j = 0;
    while (input[i] != '\\0') {
        int count = 1;
        while (input[i] == input[i+1] && count < 9) { // count < 9 keeps it to a single digit
            count++;
            i++;
        }
        output[j++] = input[i];
        output[j++] = count + '0';
        i++;
    }
    output[j] = '\\0';
}
'''

CHILD_TEST = r'''
import ctypes
import random
import sys

path = sys.argv[1]
seed = int(sys.argv[2])
rng = random.Random(seed)
lib = ctypes.CDLL(path)
fn = lib.rle_encode
fn.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_char), ctypes.c_int]
fn.restype = None

def encoded(data):
    out = bytearray()
    i = 0
    while i < len(data):
        count = 1
        while i + count < len(data) and data[i + count] == data[i] and count < 9:
            count += 1
        out.extend((data[i], ord('0') + count))
        i += count
    return bytes(out)

def invoke(data, maximum):
    guard = 32
    span = max(maximum, 0)
    total = guard + span + guard
    raw = (ctypes.c_ubyte * total)()
    for i in range(total):
        raw[i] = 0xA5
    ptr = ctypes.cast(ctypes.byref(raw, guard), ctypes.POINTER(ctypes.c_char))
    before = bytes(raw)
    fn(data, ptr, maximum)
    after = bytes(raw)
    if maximum <= 0:
        assert after == before, (data, maximum, before, after)
        return b''
    assert after[:guard] == bytes([0xA5]) * guard
    assert after[guard + maximum:] == bytes([0xA5]) * guard
    region = after[guard:guard + maximum]
    assert 0 in region, (data, maximum, region)
    return region.split(b'\0', 1)[0]

cases = [
    b'', b'A', b'ABCD', b'AAAAAAAAAAAA', b'AAABCCCCCCCCCCDD',
    b'WWWWWWWWWWWWBWWWWWWWWWWWW', b'1111222233334444'
]
for _ in range(30):
    value = bytearray()
    for _ in range(rng.randint(1, 18)):
        value.extend(bytes([rng.choice(b'ABCDE0123')]) * rng.randint(1, 15))
    cases.append(bytes(value))

for data in cases:
    want = encoded(data)
    # With enough room, the complete encoding must be exact.
    assert invoke(data, len(want) + 1) == want
    assert invoke(data, len(want) + 7) == want

    # Exercise many truncation boundaries. A truncation may either consume every
    # available byte or stop before an incomplete two-byte RLE token.
    for maximum in range(1, min(len(want) + 2, 18)):
        got = invoke(data, maximum)
        capacity = maximum - 1
        if len(want) <= capacity:
            assert got == want, (data, maximum, got, want)
        else:
            complete = want[:capacity - (capacity % 2)]
            partial = want[:capacity]
            assert got in (complete, partial), (data, maximum, got, complete, partial)

# Non-positive bounds must not cause any write.
invoke(b'AAAA', 0)
invoke(b'AAAA', -3)
'''


def run_library_suite(path):
    seed = int.from_bytes(os.urandom(16), "big")
    child = "/tmp/rle_behavior_test.py"
    with open(child, "w") as f:
        f.write(CHILD_TEST)
    result = subprocess.run(
        ["python3", child, path, str(seed)], capture_output=True, text=True, timeout=20
    )
    assert result.returncode == 0, (
        f"RLE behavior or bounds test failed for {path}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )


def test_librle_so_exists_and_valid():
    assert os.path.isfile(SO_PATH), f"{SO_PATH} does not exist."
    try:
        librle = ctypes.CDLL(SO_PATH)
    except OSError as e:
        pytest.fail(f"Failed to load {SO_PATH}: {e}")
    assert hasattr(librle, "rle_encode"), "Function 'rle_encode' not found in librle.so. Did you add extern \"C\"?"

    # Preserve the original fixed-input assertions.
    rle_encode = librle.rle_encode
    rle_encode.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int]
    rle_encode.restype = None
    input_str = b"WWWWWWWWWWWWBWWWWWWWWWWWW"
    buf = ctypes.create_string_buffer(10)
    rle_encode(input_str, buf, 10)
    result = buf.value.decode("utf-8")
    assert len(result) < 10, "Result exceeds max_out_len."
    assert result.startswith("W9"), "Output encoding is incorrect."

    run_library_suite(SO_PATH)


def test_source_builds_and_has_same_required_behavior():
    assert os.path.isfile(CPP_PATH), f"{CPP_PATH} does not exist."
    source = open(CPP_PATH).read()
    assert re.search(r'extern\s+"C"', source), "rle_encode is not exposed with C linkage in rle.cpp."

    rebuilt = "/tmp/librle_rebuilt.so"
    result = subprocess.run(
        ["g++", "-shared", "-fPIC", CPP_PATH, "-o", rebuilt],
        capture_output=True, text=True
    )
    assert result.returncode == 0, f"rle.cpp could not be compiled as a PIC shared library: {result.stderr}"
    run_library_suite(rebuilt)


def test_rle_patch_exists_and_valid():
    assert os.path.isfile(PATCH_PATH), f"{PATCH_PATH} does not exist."
    content = open(PATCH_PATH).read()

    # Preserve the original unified-diff marker assertions.
    assert "---" in content and "+++" in content, "Patch does not appear to be a unified diff."
    assert "+" in content and "-" in content, "Patch does not contain added/removed lines."

    with tempfile.TemporaryDirectory() as td:
        reconstructed = os.path.join(td, "rle.cpp")
        with open(reconstructed, "w") as f:
            f.write(ORIGINAL)
        result = subprocess.run(
            ["patch", reconstructed, PATCH_PATH], capture_output=True, text=True
        )
        assert result.returncode == 0, f"rle.patch does not apply to the supplied original file: {result.stderr}"
        assert open(reconstructed, "rb").read() == open(CPP_PATH, "rb").read(), (
            "Applying rle.patch to the supplied original does not reproduce /home/user/rle.cpp."
        )


def test_ffi_test_py_exists_and_runs_and_calls_ffi():
    assert os.path.isfile(PY_PATH), f"{PY_PATH} does not exist."

    # Preserve the original execution and output assertions against the real library.
    result = subprocess.run(["python3", PY_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"{PY_PATH} failed to run. Stderr: {result.stderr}"
    output = result.stdout.strip()
    assert output.startswith("W9"), "Output from ffi_test.py is incorrect."
    assert len(output) < 10, "Output length from ffi_test.py exceeds buffer size."

    source = open(PY_PATH).read()
    tree = ast.parse(source, filename=PY_PATH)
    assert any(
        isinstance(node, (ast.Import, ast.ImportFrom)) and
        ((isinstance(node, ast.ImportFrom) and node.module == "ctypes") or
         (isinstance(node, ast.Import) and any(alias.name == "ctypes" for alias in node.names)))
        for node in ast.walk(tree)
    ), "ffi_test.py must use ctypes."

    ten_byte_buffers = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and isinstance(node.value, ast.Call):
            func = node.value.func
            is_create = ((isinstance(func, ast.Attribute) and func.attr == "create_string_buffer") or
                         (isinstance(func, ast.Name) and func.id == "create_string_buffer"))
            if is_create and node.value.args and isinstance(node.value.args[-1], ast.Constant) and node.value.args[-1].value == 10:
                for target in node.targets:
                    if isinstance(target, ast.Name):
                        ten_byte_buffers.add(target.id)
    assert ten_byte_buffers, "ffi_test.py must create a string buffer of size exactly 10."

    ffi_calls = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            func = node.func
            is_rle = ((isinstance(func, ast.Attribute) and func.attr == "rle_encode") or
                      (isinstance(func, ast.Name) and func.id == "rle_encode"))
            if is_rle and len(node.args) >= 3:
                if isinstance(node.args[1], ast.Name) and node.args[1].id in ten_byte_buffers:
                    if isinstance(node.args[2], ast.Constant) and node.args[2].value == 10:
                        ffi_calls.append(node)
    assert ffi_calls, "ffi_test.py does not pass its 10-byte ctypes buffer and max length 10 to rle_encode."

    # Replace the library briefly with an instrumented ABI-compatible library to
    # prove the Python script actually loads and invokes rle_encode with the required input.
    spy_cpp = "/tmp/rle_spy.cpp"
    spy_so = "/tmp/librle_spy.so"
    spy_log = "/tmp/rle_spy.log"
    with open(spy_cpp, "w") as f:
        f.write(r'''#include <cstdio>
#include <cstdlib>
extern "C" void rle_encode(const char* input, char* output, int max_out_len) {
    const char* path = std::getenv("RLE_SPY_LOG");
    if (path) {
        FILE* fp = std::fopen(path, "a");
        if (fp) { std::fprintf(fp, "%s|%d\n", input ? input : "(null)", max_out_len); std::fclose(fp); }
    }
    if (output && max_out_len > 0) {
        if (max_out_len >= 3) { output[0] = 'W'; output[1] = '9'; output[2] = '\0'; }
        else output[0] = '\0';
    }
}
''')
    subprocess.run(["g++", "-shared", "-fPIC", spy_cpp, "-o", spy_so], check=True)
    backup = "/tmp/librle_submission_backup.so"
    shutil.copy2(SO_PATH, backup)
    try:
        shutil.copy2(spy_so, SO_PATH)
        if os.path.exists(spy_log):
            os.unlink(spy_log)
        env = os.environ.copy()
        env["RLE_SPY_LOG"] = spy_log
        result = subprocess.run(["python3", PY_PATH], capture_output=True, text=True, env=env)
        assert result.returncode == 0, f"ffi_test.py failed with an ABI-compatible library: {result.stderr}"
        assert os.path.isfile(spy_log), "ffi_test.py did not invoke the library's rle_encode function."
        calls = open(spy_log).read().splitlines()
        required = "WWWWWWWWWWWWBWWWWWWWWWWWW|10"
        assert required in calls, "ffi_test.py did not call rle_encode with the required input and max length 10."
    finally:
        shutil.copy2(backup, SO_PATH)


def parse_logged_durations(text):
    values = []
    for minutes, seconds in re.findall(r'(\d+)m([0-9]+(?:\.[0-9]+)?)s', text):
        values.append(int(minutes) * 60 + float(seconds))
    for minutes, seconds in re.findall(r'(\d+):([0-9]+(?:\.[0-9]+)?)(?:elapsed)?', text):
        values.append(int(minutes) * 60 + float(seconds))
    for seconds in re.findall(r'(?i)\breal\s+([0-9]+(?:\.[0-9]+)?)\b', text):
        values.append(float(seconds))
    for seconds in re.findall(r'(?i)([0-9]+(?:\.[0-9]+)?)\s*(?:seconds?|secs?)\b', text):
        values.append(float(seconds))
    for line in text.splitlines():
        if re.fullmatch(r'\s*[0-9]+(?:\.[0-9]+)?\s*', line):
            values.append(float(line.strip()))
    return values


def test_benchmark_sh_exists_and_runs_50_times_and_logs_total_time():
    assert os.path.isfile(SH_PATH), f"{SH_PATH} does not exist."
    assert os.access(SH_PATH, os.X_OK), f"{SH_PATH} is not executable."

    initial_size = os.path.getsize(LOG_PATH) if os.path.exists(LOG_PATH) else 0

    # Substitute a probe script that records exactly one line per Python process.
    original_py = open(PY_PATH, "rb").read()
    original_mode = os.stat(PY_PATH).st_mode
    probe_log = os.path.join("/tmp", "ffi_probe_" + os.urandom(12).hex())
    probe = '''#!/usr/bin/env python3
import os
import time
with open(os.environ["FFI_PROBE_LOG"], "a") as f:
    f.write(str(os.getpid()) + "\\n")
time.sleep(0.02)
print("W9")
'''
    try:
        with open(PY_PATH, "w") as f:
            f.write(probe)
        os.chmod(PY_PATH, 0o755)
        env = os.environ.copy()
        env["FFI_PROBE_LOG"] = probe_log
        started = time.monotonic()
        result = subprocess.run(["bash", SH_PATH], capture_output=True, text=True, env=env, timeout=30)
        elapsed = time.monotonic() - started
    finally:
        with open(PY_PATH, "wb") as f:
            f.write(original_py)
        os.chmod(PY_PATH, original_mode)

    assert result.returncode == 0, f"{SH_PATH} failed to run. Stderr: {result.stderr}"
    assert os.path.isfile(LOG_PATH), f"{LOG_PATH} was not created."
    new_size = os.path.getsize(LOG_PATH)
    assert new_size > initial_size, f"{LOG_PATH} was not appended to."

    assert os.path.isfile(probe_log), "benchmark.sh did not execute ffi_test.py."
    invocations = open(probe_log).read().splitlines()
    assert len(invocations) == 50, f"benchmark.sh executed ffi_test.py {len(invocations)} times instead of 50."
    assert len(set(invocations)) == 50, "The 50 benchmark iterations were not separate Python executions."

    with open(LOG_PATH, "rb") as f:
        f.seek(initial_size)
        appended = f.read().decode("utf-8", errors="replace")
    assert appended.strip(), "benchmark.log did not receive a timing record."
    assert len([line for line in appended.splitlines() if line.strip()]) <= 10, (
        "benchmark.log appears to contain per-iteration records rather than one total timing."
    )
    assert len(re.findall(r'(?i)\breal\b', appended)) <= 1, (
        "benchmark.sh recorded multiple real times instead of the total loop time."
    )
    durations = parse_logged_durations(appended)
    assert durations, f"The appended benchmark log does not contain a recognizable real duration: {appended!r}"
    assert any(0.5 <= value <= elapsed + 2.0 for value in durations), (
        f"The logged value does not plausibly measure the total execution time ({elapsed:.3f}s): {appended!r}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
