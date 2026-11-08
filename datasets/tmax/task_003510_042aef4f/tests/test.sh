#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import shutil
import subprocess
import uuid

import pytest

RUST_FILE = "/home/user/src/parser.rs"
PYTHON_FILE = "/home/user/app.py"
LIB_FILE = "/home/user/libparser.so"
DATA_FILE = "/home/user/data.bin"
OUTPUT_FILE = "/home/user/output.json"
CANONICAL_DATA = b'\x01\x04Rust\x02\x04\xe8\x07\x00\x00'
CANONICAL_JSON = '[{"type":1,"value":"Rust"},{"type":2,"value":2024}]'


def run_app(data):
    with open(DATA_FILE, "wb") as f:
        f.write(data)
    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)
    subprocess.run(["python3", PYTHON_FILE], check=True, timeout=15)
    assert os.path.isfile(OUTPUT_FILE), "app.py did not produce output.json"
    with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
        return f.read().strip()


def load_parser(path):
    lib = ctypes.CDLL(path)
    fn = lib.parse_protocol
    fn.argtypes = [
        ctypes.POINTER(ctypes.c_uint8),
        ctypes.c_size_t,
        ctypes.POINTER(ctypes.c_char),
        ctypes.c_size_t,
    ]
    fn.restype = ctypes.c_int32
    return fn


def call_parser(fn, data):
    in_array = (ctypes.c_uint8 * max(1, len(data)))()
    if data:
        ctypes.memmove(in_array, data, len(data))
    out = ctypes.create_string_buffer(4096)
    rc = fn(in_array, len(data), out, len(out))
    return rc, out.value.decode("utf-8")


def encode_records(records):
    wire = bytearray()
    objects = []
    for typ, value in records:
        if typ == 1:
            encoded = value.encode("ascii")
            wire.extend((1, len(encoded)))
            wire.extend(encoded)
        else:
            wire.extend((2, 4))
            wire.extend(int(value).to_bytes(4, "little", signed=True))
        objects.append({"type": typ, "value": value})
    expected = json.dumps(objects, ensure_ascii=False, separators=(",", ":"))
    return bytes(wire), expected


def test_rust_file_exists():
    """Verify that the Rust source file exists."""
    assert os.path.isfile(RUST_FILE), f"Rust source file {RUST_FILE} is missing."


def test_python_script_exists():
    """Verify that the Python script exists."""
    assert os.path.isfile(PYTHON_FILE), f"Python script {PYTHON_FILE} is missing."


def test_shared_library_exists_and_is_elf():
    """Verify that the compiled shared library exists and is an ELF file."""
    assert os.path.isfile(LIB_FILE), f"Shared library {LIB_FILE} is missing."
    with open(LIB_FILE, "rb") as f:
        magic = f.read(4)
    assert magic == b"\x7fELF", f"File {LIB_FILE} is not a valid ELF shared object."


def test_output_json_exists_and_content():
    """Execute app.py and verify the required final output exactly."""
    content = run_app(CANONICAL_DATA)
    assert content == CANONICAL_JSON, (
        f"Content of {OUTPUT_FILE} is incorrect.\n"
        f"Expected: {CANONICAL_JSON}\nGot: {content}"
    )
    parsed = json.loads(content)
    assert isinstance(parsed, list), "Parsed JSON is not a list."
    assert len(parsed) == 2, "Parsed JSON does not have exactly 2 elements."


@pytest.fixture(scope="session")
def parser_libraries(tmp_path_factory):
    rebuilt = tmp_path_factory.mktemp("rebuilt") / "libparser_rebuilt.so"
    subprocess.run(
        ["rustc", "--crate-type=cdylib", RUST_FILE, "-o", str(rebuilt)],
        check=True,
        timeout=60,
    )
    return [LIB_FILE, str(rebuilt)]


def test_deployed_and_source_built_parsers_on_varied_inputs(parser_libraries):
    rng = random.SystemRandom()
    random_text = "".join(rng.choice("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789") for _ in range(19))
    random_int = rng.randint(-(2**31), 2**31 - 1)
    cases = [
        [],
        [(1, "")],
        [(2, -2147483648), (2, 2147483647)],
        [(1, 'quote"and\\slash'), (2, random_int), (1, random_text)],
    ]

    for library_path in parser_libraries:
        fn = load_parser(library_path)
        for records in cases:
            wire, expected = encode_records(records)
            rc, actual = call_parser(fn, wire)
            assert rc == 0, f"{library_path} rejected valid TLV input {wire!r}"
            assert actual == expected, f"{library_path} returned incorrectly formatted JSON"


def test_malformed_inputs_are_rejected_without_touching_output(parser_libraries):
    malformed = [
        b"\x01",                         # incomplete header
        b"\x01\x05abc",                 # truncated string
        b"\x02\x04\x01\x02\x03",      # truncated int32
        b"\x02\x01\x00",               # invalid int32 length
        b"\x03\x00",                    # unknown type
        b"\x01\x01A\x02",              # valid record plus partial header
        b"\x01\x01\xff",               # not an ASCII string
    ]

    for library_path in parser_libraries:
        fn = load_parser(library_path)
        for data in malformed:
            in_array = (ctypes.c_uint8 * len(data)).from_buffer_copy(data)
            out = ctypes.create_string_buffer(128)
            out.value = b"UNCHANGED-SENTINEL"
            before = out.raw
            rc = fn(in_array, len(data), out, len(out))
            assert rc == -1, f"{library_path} accepted malformed TLV input {data!r}"
            assert out.raw == before, f"{library_path} modified out_json after an error"


def test_app_handles_runtime_varied_input_with_real_library():
    rng = random.SystemRandom()
    text = "runtime-" + "".join(rng.choice("abcdef0123456789") for _ in range(24))
    number = rng.randint(-(2**31), 2**31 - 1)
    wire, expected = encode_records([(2, number), (1, text), (1, 'x"\\y')])
    try:
        assert run_app(wire) == expected
    finally:
        run_app(CANONICAL_DATA)


def test_app_really_calls_library_via_ffi(tmp_path):
    nonce = uuid.uuid4().hex
    marker = f'[{ {"type": 1, "value": "ffi-" + nonce} }]'
    marker = json.dumps([{"type": 1, "value": "ffi-" + nonce}], separators=(",", ":"))
    probe_data = os.urandom(31)
    expected_bytes = ",".join(str(b) for b in probe_data)
    payload_bytes = ",".join(str(b) for b in marker.encode("utf-8"))
    shim_source = tmp_path / "ffi_probe.rs"
    shim_library = tmp_path / "ffi_probe.so"
    shim_source.write_text(f'''use std::slice;
#[no_mangle]
pub unsafe extern "C" fn parse_protocol(input: *const u8, input_len: usize, out_json: *mut i8, out_max_len: usize) -> i32 {{
    let expected: &[u8] = &[{expected_bytes}];
    let payload: &[u8] = &[{payload_bytes}];
    if input.is_null() || out_json.is_null() || input_len != expected.len() || out_max_len != 1024 {{ return -1; }}
    if slice::from_raw_parts(input, input_len) != expected || payload.len() + 1 > out_max_len {{ return -1; }}
    std::ptr::copy_nonoverlapping(payload.as_ptr(), out_json as *mut u8, payload.len());
    *(out_json as *mut u8).add(payload.len()) = 0;
    0
}}
''', encoding="utf-8")
    subprocess.run(
        ["rustc", "--crate-type=cdylib", str(shim_source), "-o", str(shim_library)],
        check=True,
        timeout=60,
    )

    backup = tmp_path / "submitted_libparser.so"
    original_data = open(DATA_FILE, "rb").read()
    os.replace(LIB_FILE, backup)
    shutil.copy2(shim_library, LIB_FILE)
    try:
        assert run_app(probe_data) == marker, (
            "app.py did not load /home/user/libparser.so, call parse_protocol with "
            "the file bytes and a 1024-byte output size, and use the returned JSON"
        )
    finally:
        os.replace(backup, LIB_FILE)
        with open(DATA_FILE, "wb") as f:
            f.write(original_data)
        run_app(CANONICAL_DATA)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
