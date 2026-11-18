#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import secrets
import struct
import subprocess

import pytest

BASE = '/home/user/math_feature'
LIB_PATH = os.path.join(BASE, 'libprimes.so')
OUTPUT_PATH = os.path.join(BASE, 'output.txt')
BUILD_PATH = os.path.join(BASE, 'build.sh')


@pytest.fixture(scope='session', autouse=True)
def rebuild_from_script():
    # Ensure the verifier tests artifacts produced by this invocation rather than
    # files left behind by the agent.
    for path in (LIB_PATH, OUTPUT_PATH, os.path.join(BASE, 'libprimes.h')):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        ['/bin/bash', BUILD_PATH],
        cwd=BASE,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, (
        f'build.sh failed with exit code {result.returncode}\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def test_libprimes_so_exists():
    assert os.path.exists(LIB_PATH), f"{LIB_PATH} was not generated. The build script might still be broken or not executed."
    assert os.path.isfile(LIB_PATH), f"{LIB_PATH} is not a regular file."

    with open(LIB_PATH, 'rb') as f:
        header = f.read(20)
    assert header[:4] == b'\x7fELF', f"{LIB_PATH} is not an ELF shared library."
    assert len(header) >= 18 and header[5] in (1, 2), f"{LIB_PATH} has an invalid ELF header."
    byte_order = '<' if header[5] == 1 else '>'
    assert struct.unpack(byte_order + 'H', header[16:18])[0] == 3, f"{LIB_PATH} is not an ELF shared object."

    info = subprocess.run(
        ['go', 'version', '-m', LIB_PATH],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert info.returncode == 0, f"{LIB_PATH} does not contain valid Go build information: {info.stderr}"
    assert '-buildmode=c-shared' in info.stdout, f"{LIB_PATH} was not actually built using Go's c-shared build mode."


def test_output_txt_correct():
    assert os.path.exists(OUTPUT_PATH), f"{OUTPUT_PATH} was not generated. Did you run the build script?"

    with open(OUTPUT_PATH, 'r') as f:
        content = f.read().strip()

    expected = "2,3,3,5,3607,3803"
    assert content == expected, f"Expected {OUTPUT_PATH} to contain '{expected}', but got '{content}'."


def test_build_sh_fixed():
    assert os.path.exists(BUILD_PATH), f"{BUILD_PATH} is missing."

    with open(BUILD_PATH, 'r') as f:
        content = f.read()

    assert "-buildmode=c-shared" in content, "build.sh does not use the '-buildmode=c-shared' flag to compile the Go code into a shared library."


def expected_factorization(value):
    factors = []
    divisor = 2
    while divisor * divisor <= value:
        while value % divisor == 0:
            factors.append(str(divisor))
            value //= divisor
        divisor += 1
    if value > 1:
        factors.append(str(value))
    return ','.join(factors)


def test_shared_library_can_be_loaded_and_factorizes_dynamic_inputs():
    lib = ctypes.CDLL(LIB_PATH)
    factorize = lib.Factorize
    factorize.argtypes = [ctypes.c_int64]
    factorize.restype = ctypes.c_char_p

    rng = secrets.SystemRandom()
    values = [2, 97, 360, 1234567890, 10007 * 10009]
    values.extend(rng.randrange(2, 10_000_000) for _ in range(12))

    for value in values:
        result = factorize(value)
        assert result is not None, f'Factorize({value}) returned NULL.'
        actual = result.decode('utf-8')
        expected = expected_factorization(value)
        assert actual == expected, f'Factorize({value}) returned {actual!r}, expected {expected!r}.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
