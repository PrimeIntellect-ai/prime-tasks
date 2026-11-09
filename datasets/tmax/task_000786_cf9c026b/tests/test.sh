#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import struct
import subprocess
from decimal import Decimal, localcontext, ROUND_HALF_EVEN

EXECUTABLE_PATH = '/home/user/calc_e'
RESULT_PATH = '/home/user/result.txt'


def derived_expected_value():
    """Calculate e independently from its factorial series."""
    with localcontext() as ctx:
        ctx.prec = 60
        total = Decimal(1)
        term = Decimal(1)
        n = 1
        while term > Decimal('1e-50'):
            term /= Decimal(n)
            total += term
            n += 1
        return format(total.quantize(Decimal('0.000000001'), rounding=ROUND_HALF_EVEN), 'f')


def test_executable_exists():
    """Check if the compiled executable exists and is executable."""
    executable_path = EXECUTABLE_PATH
    assert os.path.isfile(executable_path), f"The executable {executable_path} does not exist."

    # Check if the file is executable
    st = os.stat(executable_path)
    assert bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)), f"The file {executable_path} is not executable."


def test_executable_is_native_compiled_elf():
    """Reject scripts and other non-compiled stand-ins."""
    with open(EXECUTABLE_PATH, 'rb') as f:
        header = f.read(64)

    assert len(header) >= 20, "calc_e is too short to be a valid ELF executable."
    assert header[:4] == b'\x7fELF', "calc_e is not a compiled ELF program."
    assert header[4] in (1, 2), "calc_e has an invalid ELF class."
    assert header[5] in (1, 2), "calc_e has an invalid ELF byte order."

    byte_order = '<' if header[5] == 1 else '>'
    elf_type = struct.unpack(byte_order + 'H', header[16:18])[0]
    assert elf_type in (2, 3), "calc_e is not an executable or PIE ELF file."


def test_result_file_exists():
    """Check if the result file exists."""
    result_path = RESULT_PATH
    assert os.path.isfile(result_path), f"The result file {result_path} does not exist."


def test_result_content():
    """Check if the result file contains the correct value of 'e'."""
    result_path = RESULT_PATH
    with open(result_path, 'r') as f:
        content = f.read()

    expected_value = "2.718281828"
    assert expected_value in content, f"The file {result_path} does not contain the expected value '{expected_value}'. Found: {content.strip()}"


def test_executable_runs_and_produced_saved_output():
    """Run calc_e and require its output to match both derived e and result.txt."""
    expected_value = derived_expected_value()
    completed = subprocess.run(
        [EXECUTABLE_PATH],
        cwd='/home/user',
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
        check=False,
    )

    assert completed.returncode == 0, (
        f"calc_e exited with status {completed.returncode}; "
        f"stderr: {completed.stderr.decode('utf-8', errors='replace')}"
    )
    expected_output = (expected_value + '\n').encode('ascii')
    assert completed.stdout == expected_output, (
        f"calc_e output {completed.stdout!r}, expected {expected_output!r}."
    )

    with open(RESULT_PATH, 'rb') as f:
        saved_output = f.read()
    assert saved_output == completed.stdout, (
        "result.txt is not exactly the standard output produced by calc_e."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
