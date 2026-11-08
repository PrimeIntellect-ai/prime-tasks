#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import random
import re
import shutil
import string
import subprocess
import urllib.parse

C_FILE = "/home/user/libmath_encode.c"
SO_FILE = "/home/user/libmath_encode.so"
SCRIPT_FILE = "/home/user/process_request"
REQUEST_FILE = "/home/user/request.txt"
RESULT_FILE = "/home/user/result.txt"


class MathBuffer(ctypes.Structure):
    _fields_ = [("data", ctypes.POINTER(ctypes.c_ubyte)), ("length", ctypes.c_int)]


def expected_encoding(data, key):
    return bytes((ord(char) * key + i) % 256 for i, char in enumerate(data)).hex()


def run_script(data, key):
    url = "http://api.local/v1/math_encode?" + urllib.parse.urlencode({"data": data, "key": str(key)})
    with open(REQUEST_FILE, "w") as f:
        f.write(url + "\n")
    if os.path.exists(RESULT_FILE):
        os.unlink(RESULT_FILE)
    completed = subprocess.run(
        [SCRIPT_FILE],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert completed.returncode == 0, (
        f"process_request failed with status {completed.returncode}.\n"
        f"stdout: {completed.stdout}\nstderr: {completed.stderr}"
    )
    assert os.path.isfile(RESULT_FILE), "process_request did not create /home/user/result.txt"
    with open(RESULT_FILE, "r") as f:
        return f.read()


def check_library(path, cases):
    lib = ctypes.CDLL(path)
    encode = lib.encode_data
    encode.argtypes = [ctypes.c_char_p, ctypes.c_int]
    encode.restype = ctypes.POINTER(MathBuffer)
    for data, key in cases:
        encoded = encode(data.encode("ascii"), key)
        assert bool(encoded), f"encode_data in {path} returned NULL"
        result = encoded.contents
        assert result.length == len(data), (
            f"encode_data in {path} returned length {result.length}, expected {len(data)}"
        )
        actual = bytes(result.data[i] for i in range(result.length))
        expected = bytes((ord(char) * key + i) % 256 for i, char in enumerate(data))
        assert actual == expected, f"encode_data in {path} produced incorrect bytes"


def test_files_exist_and_permissions():
    c_file = "/home/user/libmath_encode.c"
    so_file = "/home/user/libmath_encode.so"
    script_file = "/home/user/process_request"

    assert os.path.isfile(c_file), f"C source file {c_file} is missing."
    assert os.path.isfile(so_file), f"Shared library {so_file} is missing."
    assert os.path.isfile(script_file), f"Script file {script_file} is missing."
    assert os.access(script_file, os.X_OK), f"Script file {script_file} is not executable."


def test_result_file_content():
    request_file_path = "/home/user/request.txt"
    result_file_path = "/home/user/result.txt"

    assert os.path.isfile(request_file_path), f"File {request_file_path} is missing."
    assert os.path.isfile(result_file_path), f"File {result_file_path} is missing."

    with open(request_file_path, "r") as f:
        url = f.read().strip()

    parsed_url = urllib.parse.urlparse(url)
    query_params = urllib.parse.parse_qs(parsed_url.query)

    assert "data" in query_params, "URL in request.txt is missing the 'data' parameter."
    assert "key" in query_params, "URL in request.txt is missing the 'key' parameter."

    data = query_params["data"][0]
    key = int(query_params["key"][0])

    expected_hex = ""
    for i, char in enumerate(data):
        encoded_byte = (ord(char) * key + i) % 256
        expected_hex += f"{encoded_byte:02x}"

    with open(result_file_path, "r") as f:
        actual_hex = f.read().strip()

    assert actual_hex == expected_hex, (
        f"Content of {result_file_path} is incorrect.\n"
        f"Expected: '{expected_hex}'\n"
        f"Got:      '{actual_hex}'"
    )


def test_source_library_and_ffi_execution():
    with open(SCRIPT_FILE, "rb") as f:
        assert f.readline().startswith(b"#!"), "process_request must have a shebang"

    with open(SO_FILE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libmath_encode.so is not an ELF shared library"

    with open(C_FILE, "r", errors="replace") as f:
        source = f.read()
    cleaned = re.sub(r"/\*.*?\*/|//[^\n]*", "", source, flags=re.S)
    matches = re.findall(r"\bstruct\s+MathBuffer\s*\{([^}]*)\}\s*(?:MathBuffer\s*)?;", cleaned, re.S)
    matches += re.findall(r"\btypedef\s+struct\s*\{([^}]*)\}\s*MathBuffer\s*;", cleaned, re.S)
    assert matches, "C source does not define a MathBuffer struct"
    valid_struct = False
    for body in matches:
        fields = [field.strip() for field in body.split(";") if field.strip()]
        if len(fields) == 2 and re.fullmatch(r"unsigned\s+char\s*\*\s*data", fields[0]) and re.fullmatch(r"int\s+length", fields[1]):
            valid_struct = True
            break
    assert valid_struct, "MathBuffer must contain exactly unsigned char* data followed by int length"
    assert re.search(
        r"\bMathBuffer\s*\*\s*encode_data\s*\(\s*const\s+char\s*\*\s*\w+\s*,\s*int\s+\w+\s*\)",
        cleaned,
    ), "C source is missing the required encode_data signature"

    rebuilt = "/tmp/rebuilt_libmath_encode.so"
    subprocess.run(
        ["gcc", "-shared", "-fPIC", C_FILE, "-o", rebuilt],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )

    rng = random.SystemRandom()
    cases = []
    for _ in range(4):
        data = "".join(rng.choice(string.ascii_letters + string.digits) for _ in range(rng.randint(5, 28)))
        cases.append((data, rng.randint(2, 97)))
    check_library(rebuilt, cases)
    check_library(SO_FILE, cases)

    with open(REQUEST_FILE, "rb") as f:
        original_request = f.read()
    backup_so = "/tmp/original_libmath_encode.so"
    shutil.copy2(SO_FILE, backup_so)

    try:
        for data, key in cases[:3]:
            actual = run_script(data, key)
            assert actual == expected_encoding(data, key), (
                "process_request produced incorrect output when executed against the submitted library"
            )

        spy_source = "/tmp/ffi_spy.c"
        spy_so = "/tmp/ffi_spy.so"
        with open(spy_source, "w") as f:
            f.write(r'''#include <stdlib.h>
#include <string.h>
typedef struct MathBuffer {
    unsigned char *data;
    int length;
} MathBuffer;
MathBuffer* encode_data(const char* input, int key) {
    int n = (int)strlen(input);
    MathBuffer *out = (MathBuffer*)malloc(sizeof(MathBuffer));
    out->length = n;
    out->data = (unsigned char*)malloc(n ? (size_t)n : 1);
    for (int i = 0; i < n; i++)
        out->data[i] = (unsigned char)(((unsigned char)input[i]) ^ ((key + i * 29) & 255));
    return out;
}
''')
        subprocess.run(
            ["gcc", "-shared", "-fPIC", spy_source, "-o", spy_so],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        os.replace(spy_so, SO_FILE)
        data = "".join(rng.choice(string.ascii_letters + string.digits) for _ in range(23))
        key = rng.randint(3, 101)
        expected_spy = bytes(ord(char) ^ ((key + i * 29) & 255) for i, char in enumerate(data)).hex()
        actual = run_script(data, key)
        assert actual == expected_spy, (
            "process_request did not use encode_data from /home/user/libmath_encode.so or did not read MathBuffer through FFI"
        )
    finally:
        shutil.copy2(backup_so, SO_FILE)
        with open(REQUEST_FILE, "wb") as f:
            f.write(original_request)

    with open(REQUEST_FILE, "r") as f:
        parsed = urllib.parse.urlparse(f.read().strip())
    params = urllib.parse.parse_qs(parsed.query)
    final_data = params["data"][0]
    final_key = int(params["key"][0])
    final_result = run_script(final_data, final_key)
    assert final_result == expected_encoding(final_data, final_key)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
