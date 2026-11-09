#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_task.py
import base64
import os
import random
import subprocess
from pathlib import Path

WORKSPACE = Path('/home/user/workspace')
RESULT = Path('/home/user/result.log')
BUILD = Path('/tmp/verifier_build')
EXPECTED_ORIGINAL = b'Migration to Python 3 complete! Protocol buffers and semver decoded.'


def run(cmd, **kwargs):
    kwargs.setdefault('timeout', 60)
    kwargs.setdefault('check', True)
    return subprocess.run(cmd, **kwargs)


# Preserve the original CMake assertion.
cmakelists = WORKSPACE / 'CMakeLists.txt'
assert cmakelists.is_file(), f'File {cmakelists} is missing.'
cmake_content = cmakelists.read_text()
assert 'target_link_libraries' in cmake_content, (
    "CMakeLists.txt does not contain 'target_link_libraries'. "
    'The linker error must be fixed by linking against the protobuf-c library.'
)

# Build from source in a clean directory, which verifies that CMake really links app.
if BUILD.exists():
    import shutil
    shutil.rmtree(BUILD)
run(['cmake', '-S', str(WORKSPACE), '-B', str(BUILD)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
run(['cmake', '--build', str(BUILD), '--clean-first', '-j2'], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
app = BUILD / 'app'
assert app.is_file() and os.access(app, os.X_OK), 'CMake did not produce an executable app target.'


def execute(config_path):
    try:
        RESULT.unlink()
    except FileNotFoundError:
        pass
    cp = run([str(app), str(config_path)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert cp.returncode == 0
    assert RESULT.is_file(), 'The application did not create /home/user/result.log.'
    return RESULT.read_bytes()


# Preserve the original result assertion, but produce the file by running the built app.
original = execute(WORKSPACE / 'config.bin')
assert original.rstrip(b'\r\n') == EXPECTED_ORIGINAL, (
    f'File content mismatch in {RESULT}. Expected {EXPECTED_ORIGINAL!r}, got {original!r}'
)

# Compile a small harness against the submitted semver_compare implementation.
# Including main.c keeps static implementations testable while renaming its application main.
harness_source = Path('/tmp/semver_harness.c')
harness_source.write_text(r'''
#include <stdio.h>
#include <stdlib.h>
#define main verifier_app_main
#include "/home/user/workspace/main.c"
#undef main
int main(int argc, char **argv) {
    if (argc != 4) return 2;
    int got = semver_compare(argv[1], argv[2]);
    int expected = atoi(argv[3]);
    if (got != expected) {
        fprintf(stderr, "semver_compare(%s, %s) returned %d, expected %d\n",
                argv[1], argv[2], got, expected);
        return 1;
    }
    return 0;
}
''')
harness = Path('/tmp/semver_harness')
run([
    'cc', '-std=c99', '-ffunction-sections', '-fdata-sections',
    '-I', str(WORKSPACE), str(harness_source),
    '-Wl,--gc-sections', '-o', str(harness)
], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

pairs = [
    ((2, 10, 0), (2, 2, 0)),
    ((2, 2, 0), (2, 10, 0)),
    ((2, 0, 0), (2, 0, 0)),
    ((10, 0, 1), (9, 99, 99)),
    ((1, 99, 99), (2, 0, 0)),
    ((3, 4, 8), (3, 5, 0)),
]
rng = random.SystemRandom()
for _ in range(20):
    pairs.append((tuple(rng.randrange(0, 100) for _ in range(3)),
                  tuple(rng.randrange(0, 100) for _ in range(3))))
for left, right in pairs:
    expected = (left > right) - (left < right)
    v1 = '.'.join(map(str, left))
    v2 = '.'.join(map(str, right))
    run([str(harness), v1, v2, str(expected)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def varint(value):
    out = bytearray()
    while value >= 0x80:
        out.append((value & 0x7f) | 0x80)
        value >>= 7
    out.append(value)
    return bytes(out)


def make_config(path, version, decoded_payload):
    version_bytes = version.encode('ascii')
    encoded_payload = base64.b64encode(decoded_payload)
    wire = (b'\x0a' + varint(len(version_bytes)) + version_bytes +
            b'\x12' + varint(len(encoded_payload)) + encoded_payload)
    path.write_bytes(wire)

# Exercise protobuf parsing, threshold behavior, and Base64 decoding on fresh inputs.
cases = [
    ((2, 0, 0), True),
    ((2, 10, 5), True),
    ((12, 1, 3), True),
    ((1, 99, 99), False),
    ((0, 10, 0), False),
]
for index, (version_tuple, is_new) in enumerate(cases):
    version = '.'.join(map(str, version_tuple))
    token = os.urandom(18).hex().encode('ascii')
    decoded = b'verifier-payload-' + str(index).encode() + b'-' + token
    config = Path(f'/tmp/verifier_config_{index}.bin')
    make_config(config, version, decoded)
    actual = execute(config)
    expected = decoded if is_new else b'VERSION_TOO_OLD'
    assert actual == expected, (
        f'Incorrect output for version {version}: expected {expected!r}, got {actual!r}'
    )
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
