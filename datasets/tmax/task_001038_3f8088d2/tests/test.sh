#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import ctypes
import tempfile
import random


def test_project_structure():
    assert os.path.isdir("/home/user/dsp_server/src"), "src/ directory not found."
    assert os.path.isdir("/home/user/dsp_server/include"), "include/ directory not found."

    assert os.path.isfile("/home/user/dsp_server/src/main.c"), "main.c not in src/"
    assert os.path.isfile("/home/user/dsp_server/src/server.c"), "server.c not in src/"
    assert os.path.isfile("/home/user/dsp_server/src/validator.c"), "validator.c not in src/"

    assert os.path.isfile("/home/user/dsp_server/include/server.h"), "server.h not in include/"
    assert os.path.isfile("/home/user/dsp_server/include/validator.h"), "validator.h not in include/"


def test_cmake_build():
    build_dir = "/home/user/dsp_server/build_test"
    os.makedirs(build_dir, exist_ok=True)

    cmake_res = subprocess.run(["cmake", ".."], cwd=build_dir, capture_output=True, text=True)
    assert cmake_res.returncode == 0, f"CMake configuration failed:\n{cmake_res.stderr}"

    make_res = subprocess.run(["make"], cwd=build_dir, capture_output=True, text=True)
    assert make_res.returncode == 0, f"Make build failed:\n{make_res.stderr}"

    assert os.path.isfile(os.path.join(build_dir, "dsp_server")), "dsp_server executable not built."


def test_validator_logic():
    validator_c = "/home/user/dsp_server/src/validator.c"
    assert os.path.isfile(validator_c), f"{validator_c} not found."

    with tempfile.TemporaryDirectory() as tmpdir:
        shared_lib = os.path.join(tmpdir, "validator.so")
        compile_res = subprocess.run(
            ["gcc", "-shared", "-fPIC", "-o", shared_lib, validator_c],
            capture_output=True,
            text=True,
        )
        assert compile_res.returncode == 0, f"Failed to compile validator.c to shared library:\n{compile_res.stderr}"

        lib = ctypes.CDLL(shared_lib)
        lib.validate_bytecode.argtypes = [ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t]
        lib.validate_bytecode.restype = ctypes.c_int

        def validate(data: bytes) -> int:
            arr = (ctypes.c_uint8 * len(data))(*data)
            return lib.validate_bytecode(arr, len(data))

        def expected(data: bytes) -> int:
            if len(data) > 128:
                return 0
            if 0xFF in data:
                return 0
            if any(data[i] == 0x1A and data[i + 1] == 0x2B for i in range(len(data) - 1)):
                return 0
            return 1

        cases = []

        # Exercise every opcode and every adjacent opcode pair.
        cases.extend(bytes([value]) for value in range(256))
        cases.extend(bytes([left, right]) for left in range(256) for right in range(256))

        # Exercise every relevant size, including both sides of the limit.
        cases.extend(bytes([0x40]) * length for length in range(161))

        rng = random.SystemRandom()

        # Place each forbidden construct at varying positions and lengths.
        for _ in range(300):
            length = rng.randrange(1, 129)
            data = bytearray([0x40] * length)
            data[rng.randrange(length)] = 0xFF
            cases.append(bytes(data))

        for _ in range(300):
            length = rng.randrange(2, 129)
            data = bytearray([0x40] * length)
            position = rng.randrange(length - 1)
            data[position:position + 2] = b"\x1a\x2b"
            cases.append(bytes(data))

        # Unpredictable mixed inputs prevent a validator tailored to a fixed corpus.
        for _ in range(4000):
            length = rng.randrange(0, 321)
            cases.append(bytes(rng.getrandbits(8) for _ in range(length)))

        failures = []
        for index, data in enumerate(cases):
            want = expected(data)
            got = validate(data)
            if got != want:
                failures.append(
                    f"case {index}: len={len(data)}, expected={want}, got={got}, data={data[:24].hex()}"
                )
                if len(failures) >= 10:
                    break

        assert not failures, "Validator classification failures:\n" + "\n".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
