#!/bin/bash
set -e
mkdir -p /logs/verifier

# The ARM64 artifact must be exercised, not merely inspected.
if ! command -v qemu-aarch64 >/dev/null 2>&1; then
    apt-get update >/dev/null 2>&1 || true
    apt-get install -y qemu-user >/dev/null 2>&1 || true
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import struct
import subprocess
import tempfile

import pytest


def check_elf(filepath, expected_machine):
    assert os.path.exists(filepath), f"{filepath} does not exist."
    assert os.access(filepath, os.X_OK), f"{filepath} is not executable."

    with open(filepath, 'rb') as f:
        elf_header = f.read(64)

    assert elf_header[:4] == b'\x7fELF', f"{filepath} is not a valid ELF file."
    assert elf_header[4] == 2, f"{filepath} is not a 64-bit ELF."
    assert elf_header[5] == 1, f"{filepath} is not Little Endian (LSB)."

    e_machine = struct.unpack_from('<H', elf_header, 18)[0]
    assert e_machine == expected_machine, (
        f"{filepath} has incorrect architecture. Expected {expected_machine}, got {e_machine}."
    )

    e_phoff = struct.unpack_from('<Q', elf_header, 32)[0]
    e_phentsize = struct.unpack_from('<H', elf_header, 54)[0]
    e_phnum = struct.unpack_from('<H', elf_header, 56)[0]

    with open(filepath, 'rb') as f:
        f.seek(e_phoff)
        for _ in range(e_phnum):
            phdr = f.read(e_phentsize)
            if len(phdr) < 4:
                continue
            p_type = struct.unpack_from('<I', phdr, 0)[0]
            assert p_type != 3, (
                f"{filepath} appears to be dynamically linked (found PT_INTERP program header). "
                "It must be statically linked."
            )


def expected_valid(data):
    if len(data) < 11 or data[:4] != b'MOBI':
        return False
    if int.from_bytes(data[4:6], 'little') != 1:
        return False
    size = int.from_bytes(data[6:10], 'little')
    if len(data) != 10 + size + 1:
        return False
    checksum = 0
    for value in data[10:10 + size]:
        checksum ^= value
    return checksum == data[-1]


def valid_blob(payload):
    checksum = 0
    for value in payload:
        checksum ^= value
    return b'MOBI' + struct.pack('<H', 1) + struct.pack('<I', len(payload)) + payload + bytes([checksum])


@pytest.fixture(scope='session')
def generated_cases():
    rng = random.SystemRandom()
    directory = tempfile.mkdtemp(prefix='mobi-validator-')
    cases = []

    payloads = [b'', os.urandom(1), os.urandom(7), os.urandom(257), bytes(range(256))]
    blobs = [valid_blob(payload) for payload in payloads]

    # Derive expected answers from the format, including independent randomized
    # valid files and mutations of every structural field.
    candidates = list(blobs)
    base = bytearray(valid_blob(os.urandom(31)))

    bad_magic = bytearray(base)
    bad_magic[rng.randrange(4)] ^= 0x20
    candidates.append(bytes(bad_magic))

    bad_version = bytearray(base)
    bad_version[4:6] = struct.pack('<H', rng.choice([0, 2, 65535]))
    candidates.append(bytes(bad_version))

    bad_size = bytearray(base)
    bad_size[6:10] = struct.pack('<I', len(base) + rng.randrange(1, 1000))
    candidates.append(bytes(bad_size))

    bad_checksum = bytearray(base)
    bad_checksum[-1] ^= rng.randrange(1, 256)
    candidates.append(bytes(bad_checksum))

    candidates.extend([
        bytes(base[:-1]),
        bytes(base) + os.urandom(1),
        os.urandom(rng.randrange(0, 11)),
        b'MOBI' + struct.pack('<H', 1) + struct.pack('<I', 0xffffffff) + b'\x00',
        os.urandom(73),
    ])

    rng.shuffle(candidates)
    for index, data in enumerate(candidates):
        name = ''.join(rng.choice('abcdefghijklmnopqrstuvwxyz0123456789') for _ in range(24))
        path = os.path.join(directory, f'{name}-{index}.dat')
        with open(path, 'wb') as f:
            f.write(data)
        cases.append((path, 0 if expected_valid(data) else 1))

    yield cases
    shutil.rmtree(directory, ignore_errors=True)


def run_validator(command, path):
    result = subprocess.run(command + [path], capture_output=True, timeout=15)
    return result.returncode


def test_validator_x86_binary():
    """Verify the x86_64 binary exists, is executable, 64-bit, statically linked, and x86_64."""
    check_elf('/home/user/validator_x86', 62)


def test_validator_arm64_binary():
    """Verify the arm64 binary exists, is executable, 64-bit, statically linked, and aarch64."""
    check_elf('/home/user/validator_arm64', 183)


def test_validator_x86_execution():
    """Retain the original checks against the supplied files."""
    validator_path = '/home/user/validator_x86'
    valid_bin = '/home/user/valid.bin'
    invalid_bin = '/home/user/invalid.bin'

    assert os.path.exists(valid_bin), f"{valid_bin} is missing."
    assert os.path.exists(invalid_bin), f"{invalid_bin} is missing."

    res_valid = subprocess.run([validator_path, valid_bin], capture_output=True)
    assert res_valid.returncode == 0, f"Expected exit code 0 for {valid_bin}, got {res_valid.returncode}."

    res_invalid = subprocess.run([validator_path, invalid_bin], capture_output=True)
    assert res_invalid.returncode == 1, f"Expected exit code 1 for {invalid_bin}, got {res_invalid.returncode}."


def test_x86_on_generated_cases(generated_cases):
    command = ['/home/user/validator_x86']
    for path, expected in generated_cases:
        actual = run_validator(command, path)
        assert actual == expected, f"x86 validator returned {actual}, expected {expected}, for generated input {path}"


def test_arm64_on_generated_cases(generated_cases):
    qemu = shutil.which('qemu-aarch64')
    assert qemu is not None, 'qemu-aarch64 is required to execute the ARM64 validator.'
    command = [qemu, '/home/user/validator_arm64']
    for path, expected in generated_cases:
        actual = run_validator(command, path)
        assert actual == expected, f"ARM64 validator returned {actual}, expected {expected}, for generated input {path}"


def test_missing_file_and_missing_argument():
    missing = os.path.join(tempfile.gettempdir(), 'missing-' + os.urandom(12).hex())
    commands = [['/home/user/validator_x86']]
    qemu = shutil.which('qemu-aarch64')
    assert qemu is not None, 'qemu-aarch64 is required to execute the ARM64 validator.'
    commands.append([qemu, '/home/user/validator_arm64'])

    for command in commands:
        no_arg = subprocess.run(command, capture_output=True, timeout=15)
        assert no_arg.returncode == 1
        nonexistent = subprocess.run(command + [missing], capture_output=True, timeout=15)
        assert nonexistent.returncode == 1


def test_run_tests_script_exists():
    """Ensure run_tests.sh exists."""
    script_path = '/home/user/run_tests.sh'
    assert os.path.exists(script_path), f"{script_path} does not exist."


def test_run_tests_script_executes_validators_and_writes_log():
    script_path = '/home/user/run_tests.sh'
    validator_path = '/home/user/validator_x86'
    log_path = '/home/user/test_results.log'
    workdir = tempfile.mkdtemp(prefix='.verifier-run-', dir='/home/user')
    real_validator = os.path.join(workdir, 'validator_x86.real')
    call_log = os.path.join(workdir, 'calls.log')

    if os.path.exists(log_path):
        os.unlink(log_path)

    os.replace(validator_path, real_validator)
    try:
        with open(validator_path, 'w') as f:
            f.write('#!/bin/bash\n')
            f.write("printf '%s\\n' \"$@\" >> " + repr(call_log) + '\n')
            f.write('exec ' + repr(real_validator) + ' "$@"\n')
        os.chmod(validator_path, 0o755)
        subprocess.run(['/bin/bash', script_path], capture_output=True, timeout=30)
    finally:
        if os.path.exists(real_validator):
            os.replace(real_validator, validator_path)

    try:
        assert os.path.exists(call_log), 'run_tests.sh did not execute validator_x86.'
        with open(call_log, 'r') as f:
            calls = f.read().splitlines()
        assert calls == ['/home/user/valid.bin', '/home/user/invalid.bin'], (
            f'run_tests.sh made incorrect validator calls: {calls}'
        )

        assert os.path.exists(log_path), f"{log_path} does not exist. Did run_tests.sh generate it?"
        with open(log_path, 'r') as f:
            content = f.read().strip()

        expected_content = 'valid_exit: 0\ninvalid_exit: 1'
        assert content == expected_content, (
            f"Log content in {log_path} is incorrect.\nExpected:\n{expected_content}\nGot:\n{content}"
        )
    finally:
        shutil.rmtree(workdir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
