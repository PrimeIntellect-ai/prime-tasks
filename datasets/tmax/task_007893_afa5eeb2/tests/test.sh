#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import subprocess
import tempfile


def test_extract_c_exists():
    assert os.path.exists('/home/user/extract.c'), "The C source file /home/user/extract.c is missing."
    assert os.path.isfile('/home/user/extract.c'), "/home/user/extract.c is not a file."


def test_extract_executable_exists():
    assert os.path.exists('/home/user/extract'), "The executable /home/user/extract is missing."
    assert os.path.isfile('/home/user/extract'), "/home/user/extract is not a file."
    assert os.access('/home/user/extract', os.X_OK), "The file /home/user/extract is not executable."
    with open('/home/user/extract', 'rb') as f:
        assert f.read(4) == b'\x7fELF', "/home/user/extract is not a compiled ELF executable."


def parse_records(data):
    rows = []
    for offset in range(0, len(data) - 24, 25):
        tid, raw_user, amount, status = struct.unpack('<I16sfB', data[offset:offset + 25])
        if status == 1:
            user = raw_user.split(b'\0', 1)[0].decode('ascii')
            rows.append((tid, user, amount))
    return rows


def expected_extract_output(data):
    return ''.join(f'{tid},{user},{amount:.2f}\n' for tid, user, amount in parse_records(data))


def run_with_data(executable, data):
    dat_path = '/home/user/transactions.dat'
    with open(dat_path, 'rb') as f:
        original = f.read()
    try:
        with open(dat_path, 'wb') as f:
            f.write(data)
        result = subprocess.run(
            [executable], cwd='/home/user', stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=5, check=False
        )
        assert result.returncode == 0, (
            f'{executable} exited with status {result.returncode}: '
            f'{result.stderr.decode(errors="replace")}'
        )
        actual = result.stdout.decode('utf-8').replace('\r\n', '\n')
        assert actual == expected_extract_output(data), (
            f'{executable} did not correctly parse and filter packed records.'
        )
    finally:
        with open(dat_path, 'wb') as f:
            f.write(original)


def make_unpredictable_records():
    ids = []
    while len(ids) < 7:
        candidate = secrets.randbelow(2**32)
        if candidate not in ids:
            ids.append(candidate)

    names = [
        b'ABCDEFGHIJKLMNOP',  # exactly 16 bytes, with no terminator in the record
        b'A', b'packed_user', b'Zed', b'pending', b'failed', b'last_user'
    ]
    statuses = [1, 0, 2, 1, 255, 1, 3]
    amounts = []
    for _ in ids:
        value = secrets.randbelow(80001) - 40000
        if value == 0:
            value = 1
        amounts.append(value / 4.0)  # exactly representable as binary32

    order = list(range(len(ids)))
    for i in range(len(order) - 1, 0, -1):
        j = secrets.randbelow(i + 1)
        order[i], order[j] = order[j], order[i]

    return b''.join(
        struct.pack('<I16sfB', ids[i], names[i], amounts[i], statuses[i])
        for i in order
    )


def test_installed_executable_processes_packed_records():
    run_with_data('/home/user/extract', make_unpredictable_records())


def test_c_source_compiles_and_processes_packed_records_independently():
    fd, compiled_path = tempfile.mkstemp(prefix='compiled_extract_', dir='/tmp')
    os.close(fd)
    os.unlink(compiled_path)

    compile_result = subprocess.run(
        ['gcc', '/home/user/extract.c', '-o', compiled_path],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15, check=False
    )
    assert compile_result.returncode == 0, (
        'The submitted C source does not compile: ' +
        compile_result.stderr.decode(errors='replace')
    )

    hidden_installed = f'/tmp/original_extract_{secrets.token_hex(12)}'
    os.replace('/home/user/extract', hidden_installed)
    try:
        run_with_data(compiled_path, make_unpredictable_records())
    finally:
        os.replace(hidden_installed, '/home/user/extract')
        if os.path.exists(compiled_path):
            os.unlink(compiled_path)


def test_successful_amounts_csv():
    csv_path = '/home/user/successful_amounts.csv'
    dat_path = '/home/user/transactions.dat'

    assert os.path.exists(csv_path), f"The output file {csv_path} is missing."
    assert os.path.isfile(csv_path), f"{csv_path} is not a file."

    # Derive expected output from the binary file
    assert os.path.exists(dat_path), f"The input file {dat_path} is missing."

    expected_rows = []
    with open(dat_path, 'rb') as f:
        while True:
            chunk = f.read(25)
            if not chunk:
                break
            if len(chunk) < 25:
                break

            tid, user, amount, status = struct.unpack('<I16sfB', chunk)
            if status == 1:
                expected_rows.append((tid, amount))

    expected_rows.sort(key=lambda x: x[0])

    expected_csv_lines = ["id,amount\n"]
    for tid, amount in expected_rows:
        expected_csv_lines.append(f"{tid},{amount:.2f}\n")

    expected_content = "".join(expected_csv_lines)

    with open(csv_path, 'r') as f:
        actual_content = f.read()

    # Normalize line endings
    actual_content = actual_content.replace('\r\n', '\n').strip() + '\n'
    expected_content = expected_content.replace('\r\n', '\n').strip() + '\n'

    assert actual_content == expected_content, f"The contents of {csv_path} do not match the expected output."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
