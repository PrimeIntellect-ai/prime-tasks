#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import random
import runpy
import subprocess

HOME = "/home/user"
RUST = os.path.join(HOME, "framing.rs")
FUZZER = os.path.join(HOME, "fuzzer.py")
LIB = os.path.join(HOME, "libframing.so")
OUTPUT = os.path.join(HOME, "frame_output.hex")
EXPECTED = "820454455354"


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, timeout=30, **kwargs)


def test_required_files_exist():
    assert os.path.isfile(LIB), f"File {LIB} is missing. Did you compile the Rust code?"
    assert os.path.isfile(FUZZER), f"File {FUZZER} is missing."
    assert os.path.isfile(RUST), f"File {RUST} is missing."
    assert os.path.isfile(OUTPUT), f"File {OUTPUT} is missing. Did you run the Python script?"


def test_submitted_library_is_real_and_source_compiles():
    with open(LIB, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{LIB} is not an ELF shared library"

    rebuilt = "/tmp/libframing_rebuilt.so"
    if os.path.exists(rebuilt):
        os.unlink(rebuilt)
    run(["rustc", "--crate-type", "cdylib", RUST, "-o", rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert os.path.isfile(rebuilt)


def exercise_library(path):
    class WsFrame(ctypes.Structure):
        _fields_ = [
            ("fin", ctypes.c_uint8),
            ("opcode", ctypes.c_uint8),
            ("payload_len", ctypes.c_size_t),
            ("payload", ctypes.POINTER(ctypes.c_uint8)),
        ]

    lib = ctypes.CDLL(path)
    fn = lib.generate_frame_bytes
    fn.argtypes = [ctypes.POINTER(WsFrame), ctypes.POINTER(ctypes.c_size_t)]
    fn.restype = ctypes.POINTER(ctypes.c_uint8)

    rng = random.SystemRandom()
    cases = [(1, 2, b"TEST"), (0, 1, b""), (1, 9, os.urandom(rng.randrange(7, 24)))]
    for fin, opcode, payload in cases:
        storage = (ctypes.c_uint8 * max(1, len(payload)))()
        if payload:
            ctypes.memmove(storage, payload, len(payload))
        frame = WsFrame(fin, opcode, len(payload), ctypes.cast(storage, ctypes.POINTER(ctypes.c_uint8)))
        out_len = ctypes.c_size_t()
        ptr = fn(ctypes.byref(frame), ctypes.byref(out_len))
        assert bool(ptr), "generate_frame_bytes returned NULL"
        actual = ctypes.string_at(ptr, out_len.value)
        expected = bytes([((fin << 7) | opcode) & 0xff, len(payload) & 0xff]) + payload
        assert out_len.value == len(expected)
        assert actual == expected


def test_submitted_and_rebuilt_libraries_behave_correctly():
    exercise_library(LIB)
    exercise_library("/tmp/libframing_rebuilt.so")


def test_python_wrapper_defines_and_uses_the_ffi_correctly():
    produced = os.urandom(11)
    calls = []

    class FakeFunction:
        def __init__(self):
            self.argtypes = None
            self.restype = None
            self.buffer = (ctypes.c_uint8 * len(produced)).from_buffer_copy(produced)

        def __call__(self, frame_arg, out_len_arg):
            calls.append((frame_arg, out_len_arg))
            assert isinstance(self.argtypes, (list, tuple)) and len(self.argtypes) == 2
            frame_type = self.argtypes[0]._type_
            assert issubclass(frame_type, ctypes.Structure)
            assert self.argtypes[1]._type_ is ctypes.c_size_t
            assert self.restype._type_ is ctypes.c_uint8

            frame = ctypes.cast(frame_arg, ctypes.POINTER(frame_type)).contents
            assert frame.fin == 1
            assert frame.opcode == 2
            assert frame.payload_len == 4
            assert ctypes.string_at(frame.payload, frame.payload_len) == b"TEST"
            ctypes.cast(out_len_arg, ctypes.POINTER(ctypes.c_size_t)).contents.value = len(produced)
            return ctypes.cast(self.buffer, ctypes.POINTER(ctypes.c_uint8))

    class FakeLibrary:
        def __init__(self):
            self.generate_frame_bytes = FakeFunction()

    fake_library = FakeLibrary()
    original_cdll = ctypes.CDLL
    try:
        ctypes.CDLL = lambda *args, **kwargs: fake_library
        namespace = runpy.run_path(FUZZER, run_name="fuzzer_under_test")

        assert "WsFrame" in namespace, "fuzzer.py must define WsFrame"
        wsframe = namespace["WsFrame"]
        assert issubclass(wsframe, ctypes.Structure)
        assert wsframe._fields_ == [
            ("fin", ctypes.c_uint8),
            ("opcode", ctypes.c_uint8),
            ("payload_len", ctypes.c_size_t),
            ("payload", ctypes.POINTER(ctypes.c_uint8)),
        ]
        assert callable(namespace.get("main")), "fuzzer.py must provide main()"
        namespace["main"]()
        assert len(calls) == 1, "generate_frame_bytes must be called exactly once"
        with open(OUTPUT, "r") as f:
            assert f.read().strip() == produced.hex(), "wrapper did not write returned bytes as lowercase hex"
    finally:
        ctypes.CDLL = original_cdll
        # Restore and independently verify the required final artifact using the real library.
        run(["python3", FUZZER], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def test_frame_output_hex_content_after_real_execution():
    assert os.path.isfile(OUTPUT), f"File {OUTPUT} is missing. Did you run the Python script?"
    with open(OUTPUT, "r") as f:
        content = f.read().strip()
    assert content == EXPECTED, f"Expected {OUTPUT} to contain '{EXPECTED}', but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
