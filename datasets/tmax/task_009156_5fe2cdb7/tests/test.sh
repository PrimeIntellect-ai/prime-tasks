#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import random
import struct
import subprocess

APP = "/home/user/app"
LIB_PATH = os.path.join(APP, "libsemver.so")
LOG_PATH = "/home/user/test_result.log"
TEST_PATH = os.path.join(APP, "test_semver.py")

ORIGINAL_TEST = '''import ctypes
import struct
from packaging import version
from hypothesis import given, settings
import hypothesis.strategies as st
import os

# Load the C library
lib = ctypes.CDLL(os.path.abspath(os.path.join(os.path.dirname(__file__), 'libsemver.so')))

lib.is_greater_or_equal.argtypes = [ctypes.c_char_p, ctypes.c_uint16, ctypes.c_uint16, ctypes.c_uint16]
lib.is_greater_or_equal.restype = ctypes.c_int

@settings(max_examples=1000)
@given(
    st.tuples(
        st.integers(min_value=0, max_value=100),
        st.integers(min_value=0, max_value=100),
        st.integers(min_value=0, max_value=100)
    ),
    st.tuples(
        st.integers(min_value=0, max_value=100),
        st.integers(min_value=0, max_value=100),
        st.integers(min_value=0, max_value=100)
    )
)
def test_semver_comparison(v1, v2):
    # Pack v1 into custom struct bytes (uint16 little endian)
    raw_bytes = struct.pack('<HHH', v1[0], v1[1], v1[2])

    # Call C function
    c_res = lib.is_greater_or_equal(raw_bytes, v2[0], v2[1], v2[2])

    # Python source of truth
    pv1 = version.parse(f"{v1[0]}.{v1[1]}.{v1[2]}")
    pv2 = version.parse(f"{v2[0]}.{v2[1]}.{v2[2]}")
    expected = 1 if pv1 >= pv2 else 0

    assert c_res == expected, f"Failed for {v1} >= {v2}. Expected {expected}, got {c_res}"
'''


def test_libsemver_exists_and_is_elf():
    assert os.path.isfile(LIB_PATH), f"Shared library {LIB_PATH} does not exist. Did you run make?"
    with open(LIB_PATH, "rb") as f:
        magic = f.read(4)
    assert magic == b"\x7fELF", f"{LIB_PATH} is not a valid ELF file. Check your Makefile compilation flags."


def test_test_result_log_exists_and_passed():
    assert os.path.isfile(LOG_PATH), f"Test log {LOG_PATH} does not exist. Did you redirect the pytest output?"
    with open(LOG_PATH, "r") as f:
        content = f.read()
    assert "1 passed" in content or "passed" in content.lower(), f"Test log does not indicate success. Content:\n{content}"


def test_original_property_suite_was_not_modified():
    assert os.path.isfile(TEST_PATH), f"Property-based test suite {TEST_PATH} is missing"
    with open(TEST_PATH, "r") as f:
        actual = f.read()
    assert actual == ORIGINAL_TEST, "Do not modify /home/user/app/test_semver.py"


def test_make_rebuilds_shared_library():
    if os.path.lexists(LIB_PATH):
        os.unlink(LIB_PATH)
    result = subprocess.run(
        ["make"], cwd=APP, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
    )
    assert result.returncode == 0, f"make failed:\n{result.stdout}"
    assert os.path.isfile(LIB_PATH), "make did not create libsemver.so"
    with open(LIB_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "make did not produce a valid ELF shared library"


def test_property_suite_really_passes_and_generates_log():
    with open(LOG_PATH, "w") as log:
        result = subprocess.run(
            ["python3", "-m", "pytest", TEST_PATH],
            cwd=APP,
            stdout=log,
            stderr=subprocess.STDOUT,
            text=True,
        )
    with open(LOG_PATH, "r") as f:
        content = f.read()
    assert result.returncode == 0, f"The instructed property-based suite failed:\n{content}"
    assert "1 passed" in content, f"The property-based suite did not report its test passing:\n{content}"


def test_c_logic_correctness():
    assert os.path.isfile(LIB_PATH), "Cannot test C logic because libsemver.so is missing."

    lib = ctypes.CDLL(LIB_PATH)
    lib.is_greater_or_equal.argtypes = [ctypes.c_char_p, ctypes.c_uint16, ctypes.c_uint16, ctypes.c_uint16]
    lib.is_greater_or_equal.restype = ctypes.c_int

    test_cases = [
        ((1, 0, 0), (1, 0, 0), 1),
        ((2, 0, 0), (1, 9, 9), 1),
        ((1, 2, 0), (1, 1, 9), 1),
        ((1, 1, 2), (1, 1, 1), 1),
        ((1, 1, 1), (1, 1, 2), 0),
        ((1, 1, 9), (1, 2, 0), 0),
        ((1, 9, 9), (2, 0, 0), 0),
    ]

    for v1, v2, expected in test_cases:
        raw_bytes = struct.pack('<HHH', v1[0], v1[1], v1[2])
        res = lib.is_greater_or_equal(raw_bytes, v2[0], v2[1], v2[2])
        assert res == expected, f"Logic error: {v1} >= {v2} should be {expected}, but got {res}"

    boundaries = [0, 1, 2, 99, 100, 101, 255, 256, 32767, 65534, 65535]
    generated = []
    for value in boundaries:
        generated.extend([
            ((value, 0, 0), (value, 0, 0)),
            ((value, 1, 0), (value, 0, 65535)),
            ((value, 0, 1), (value, 0, 2)),
            ((value, 65535, 0), (value, 65534, 65535)),
        ])

    rng = random.SystemRandom()
    for _ in range(5000):
        generated.append(
            (tuple(rng.randrange(65536) for _ in range(3)),
             tuple(rng.randrange(65536) for _ in range(3)))
        )

    for v1, v2 in generated:
        expected = int(v1 >= v2)
        raw_bytes = struct.pack("<HHH", *v1)
        result = lib.is_greater_or_equal(raw_bytes, *v2)
        assert result == expected, f"Logic error: {v1} >= {v2} should be {expected}, but got {result}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
