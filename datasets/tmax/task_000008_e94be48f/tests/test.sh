#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import struct
import subprocess
import tempfile
import pytest

DATA_DIR = '/home/user/data'
SOURCE = '/home/user/clean_join.c'
PROCESS = '/home/user/process.sh'


def test_required_files_exist():
    """Verify that the user created the required scripts and output files."""
    assert os.path.isfile('/home/user/clean_join.c'), "/home/user/clean_join.c is missing."
    assert os.path.isfile('/home/user/process.sh'), "/home/user/process.sh is missing."
    assert os.path.isfile('/home/user/data/summary.txt'), "/home/user/data/summary.txt is missing."
    assert os.path.isfile('/home/user/data/cleaned.bin'), "/home/user/data/cleaned.bin is missing."


def test_summary_txt_content():
    """Verify that summary.txt contains the correct count of valid joined records."""
    with open('/home/user/data/summary.txt', 'r') as f:
        content = f.read().strip()
    assert content == "2", f"summary.txt should contain exactly '2', but found '{content}'."


def test_cleaned_bin_content():
    """Verify that cleaned.bin contains the correct binary data as per the struct definition."""
    with open('/home/user/data/cleaned.bin', 'rb') as f:
        data = f.read()

    assert len(data) == 48, f"cleaned.bin should be exactly 48 bytes (2 records * 24 bytes), but is {len(data)} bytes."

    records = []
    for i in range(2):
        chunk = data[i*24:(i+1)*24]
        ts, sid, adj, stat = struct.unpack('<QIf8s', chunk)
        stat_str = stat.decode('ascii', errors='ignore').rstrip('\x00')
        records.append((ts, sid, adj, stat_str))

    expected_record_1 = (1000, 1, 12.0, 'OK')
    expected_record_2 = (1001, 2, 4.0, 'WARN')

    assert records[0] == expected_record_1, f"Record 1 is incorrect. Expected {expected_record_1}, got {records[0]}"
    assert records[1] == expected_record_2, f"Record 2 is incorrect. Expected {expected_record_2}, got {records[1]}"


def f32(value):
    return struct.unpack('<f', struct.pack('<f', value))[0]


def make_fixture(variant):
    nonce = secrets.randbelow(500000000)
    sid_a = 1000000000 + nonce
    sid_b = sid_a + 1
    sid_c = sid_a + 2
    unknown = sid_a + 99
    ts = 7000000000000000000 + secrets.randbelow(1000000)

    raw_a = 8 + variant
    raw_b = 7 + 2 * variant
    raw_c = -(3 + variant)

    sensors = f'''sensor_id,location,calibration_factor
{sid_a},alpha,1.5
{sid_b},beta,0.5
{sid_c},gamma,-2.0
{sid_a + 3},broken,3oops
4294967296,overflow,1.0
,missing,1.0
'''
    readings = f'''timestamp,sensor_id,raw_value,status
{ts},{sid_a},{raw_a},OK
{ts + 1},{sid_b},{raw_b},SEVEN77
{ts + 2},{sid_c},{raw_c},NEG
{ts + 3},{sid_a},-1.0,DROP
{ts + 4},{sid_a},0.0,ZERO
{ts + 5},{unknown},5.0,NOJOIN
{ts + 6},{sid_a},bad,PARSE
{ts + 7},{sid_a},nan,NAN
18446744073709551616,{sid_a},2.0,BADTS
{ts + 8},4294967296,2.0,BADSID
{ts + 9},{sid_a},2.0,TOO-LONG
{ts + 10},{sid_a},2.0
'''

    expected = [
        struct.pack('<QIf8s', ts, sid_a, f32(f32(raw_a) * f32(1.5)), b'OK'.ljust(8, b'\0')),
        struct.pack('<QIf8s', ts + 1, sid_b, f32(f32(raw_b) * f32(0.5)), b'SEVEN77\0'),
        struct.pack('<QIf8s', ts + 2, sid_c, f32(f32(raw_c) * f32(-2.0)), b'NEG'.ljust(8, b'\0')),
    ]
    return sensors, readings, b''.join(expected)


def install_fixture(variant):
    sensors, readings, expected = make_fixture(variant)
    with open(os.path.join(DATA_DIR, 'sensors.csv'), 'w', newline='') as f:
        f.write(sensors)
    with open(os.path.join(DATA_DIR, 'readings.csv'), 'w', newline='') as f:
        f.write(readings)
    for name in ('cleaned.bin', 'summary.txt'):
        path = os.path.join(DATA_DIR, name)
        if os.path.lexists(path):
            os.remove(path)
    return expected


def assert_binary(expected):
    path = os.path.join(DATA_DIR, 'cleaned.bin')
    assert os.path.isfile(path), 'Execution did not create cleaned.bin.'
    with open(path, 'rb') as f:
        actual = f.read()
    assert actual == expected, 'cleaned.bin is incorrect for a verifier-generated fixture.'


def test_compiled_program_and_process_script_on_generated_inputs():
    # Independently compile and execute the submitted C source, so static fixture
    # outputs or an unrelated process.sh implementation cannot satisfy the task.
    exe = os.path.join('/tmp', 'clean_join_verify_' + secrets.token_hex(8))
    compile_result = subprocess.run(
        ['/usr/bin/gcc', SOURCE, '-O2', '-std=c11', '-o', exe],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert compile_result.returncode == 0, 'clean_join.c does not compile with gcc:\n' + compile_result.stderr

    expected = install_fixture(1)
    run_result = subprocess.run(
        [exe], cwd='/home/user', stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=20
    )
    assert run_result.returncode == 0, 'The compiled C program failed:\n' + run_result.stderr
    assert_binary(expected)
    os.remove(exe)

    # Exercise process.sh independently on a second unpredictable fixture and
    # put a logging gcc wrapper first in PATH to verify that the script compiles.
    expected = install_fixture(2)
    wrapper_dir = tempfile.mkdtemp(prefix='verifier-gcc-')
    marker = os.path.join(wrapper_dir, 'called')
    wrapper = os.path.join(wrapper_dir, 'gcc')
    with open(wrapper, 'w') as f:
        f.write('#!/bin/bash\nprintf called > "$VERIFIER_GCC_MARKER"\nexec /usr/bin/gcc "$@"\n')
    os.chmod(wrapper, 0o755)

    env = os.environ.copy()
    env['PATH'] = wrapper_dir + ':' + env.get('PATH', '')
    env['VERIFIER_GCC_MARKER'] = marker
    process_result = subprocess.run(
        ['/bin/bash', '-x', PROCESS], cwd='/home/user', env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert process_result.returncode == 0, 'process.sh failed:\n' + process_result.stderr

    absolute_gcc_call = any(
        line.startswith('+') and re.search(r'(^|\s)/(?:usr/)?bin/gcc(?:\s|$)', line)
        for line in process_result.stderr.splitlines()
    )
    assert os.path.isfile(marker) or absolute_gcc_call, 'process.sh did not invoke gcc to compile the program.'
    assert_binary(expected)

    summary = os.path.join(DATA_DIR, 'summary.txt')
    assert os.path.isfile(summary), 'process.sh did not create summary.txt.'
    with open(summary, 'r') as f:
        content = f.read().strip()
    assert content == '3', f"summary.txt should contain exactly '3' for the generated fixture, found {content!r}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
