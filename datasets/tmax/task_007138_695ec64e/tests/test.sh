#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import string
import subprocess
import pytest


def test_sensor_utf8_log():
    """Check that sensor_utf8.log exists, is UTF-8, and is the exact conversion of the raw file."""
    file_path = '/home/user/sensor_utf8.log'
    assert os.path.exists(file_path), f"The file {file_path} is missing."

    try:
        with open(file_path, 'rb') as f:
            raw_bytes = f.read()
        content = raw_bytes.decode('utf-8')
    except UnicodeDecodeError:
        pytest.fail(f"The file {file_path} is not properly encoded in UTF-8.")

    assert '[BEGIN]' in content, "The UTF-8 file does not contain expected content."

    with open('/home/user/raw_sensor.log', 'rb') as f:
        source_bytes = f.read()
    expected_bytes = source_bytes.decode('utf-16le').encode('utf-8')
    assert raw_bytes == expected_bytes, "sensor_utf8.log is not the exact UTF-8 conversion of raw_sensor.log."


def test_sensor_clean_log():
    """Check that sensor_clean.log exists, is fully cleaned, and derives from sensor_utf8.log."""
    file_path = '/home/user/sensor_clean.log'
    assert os.path.exists(file_path), f"The file {file_path} is missing."

    with open(file_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    for i, line in enumerate(lines):
        assert '\r' not in line, f"Line {i+1} in {file_path} contains a carriage return (\\r)."
        line_no_newline = line.strip('\n')
        if line_no_newline:
            assert line_no_newline == line_no_newline.strip(), f"Line {i+1} in {file_path} has leading or trailing spaces."

    with open('/home/user/sensor_utf8.log', 'r', encoding='utf-8', newline='') as f:
        source = f.read()
    expected = '\n'.join(line.strip(' ') for line in source.replace('\r', '').split('\n'))
    with open(file_path, 'r', encoding='utf-8', newline='') as f:
        actual = f.read()
    assert actual == expected, "sensor_clean.log is not the exact cleaned form of sensor_utf8.log."


def test_cpp_file_exists():
    """Check that the C++ source file exists."""
    file_path = '/home/user/parse_logs.cpp'
    assert os.path.exists(file_path), f"The C++ program {file_path} is missing."
    assert os.path.isfile(file_path), f"The C++ program {file_path} is not a regular file."
    assert os.path.getsize(file_path) > 0, f"The C++ program {file_path} is empty."


def test_clean_data_csv():
    """Check that clean_data.csv exists and contains the correct filtered data."""
    file_path = '/home/user/clean_data.csv'
    assert os.path.exists(file_path), f"The CSV file {file_path} is missing."

    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read().strip().split('\n')

    expected = [
        "Timestamp,Station,Temp",
        "2023-05-12 08:00:00,Alpha,22.5",
        "2023-05-12 08:30:00,Alpha,23.1"
    ]

    assert len(content) == len(expected), f"Expected {len(expected)} lines in {file_path}, found {len(content)}."

    for i, (actual_line, expected_line) in enumerate(zip(content, expected)):
        assert actual_line.strip() == expected_line, f"Line {i+1} in {file_path} is incorrect. Expected '{expected_line}', got '{actual_line.strip()}'."


def test_compile_and_execute_parser_on_unseen_records():
    """Compile the submitted source and exercise it on verifier-generated records."""
    source = '/home/user/parse_logs.cpp'
    executable = '/tmp/parse_logs_submission'
    clean_path = '/home/user/sensor_clean.log'
    csv_path = '/home/user/clean_data.csv'

    build = subprocess.run(
        ['g++', '-std=c++17', '-O2', source, '-o', executable],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert build.returncode == 0, f"parse_logs.cpp did not compile:\n{build.stderr}"

    token = ''.join(secrets.choice(string.ascii_letters) for _ in range(12))
    station1 = 'Station' + token
    station2 = 'Remote' + token[::-1]
    station_bad = 'Faulty' + token
    day = secrets.randbelow(18) + 10
    minute1 = secrets.randbelow(50)
    minute2 = minute1 + 1
    ts1 = f"2041-07-{day:02d} 11:{minute1:02d}:13"
    ts2 = f"2041-07-{day:02d} 11:{minute2:02d}:47"
    temp1 = f"{secrets.randbelow(300) + 10}.{secrets.randbelow(9) + 1}"
    temp2 = f"-{secrets.randbelow(30) + 1}.{secrets.randbelow(9) + 1}"

    records = [
        (ts1, station1, temp1, '0'),
        (f"2041-07-{day:02d} 12:01:00", station_bad, '999.9', '00'),
        (f"2041-07-{day:02d} 12:02:00", station_bad, '888.8', '1'),
        (ts2, station2, temp2, '0'),
        (f"2041-07-{day:02d} 12:03:00", station_bad, '777.7', '-1'),
    ]
    generated = ''.join(
        '[BEGIN]\n'
        f'Timestamp: {timestamp}\n'
        f'Station: {station}\n'
        f'Temp: {temp}\n'
        f'FaultCode: {fault}\n'
        '[END]\n'
        for timestamp, station, temp, fault in records
    )
    expected = (
        'Timestamp,Station,Temp\n'
        f'{ts1},{station1},{temp1}\n'
        f'{ts2},{station2},{temp2}\n'
    )

    with open(clean_path, 'rb') as f:
        old_clean = f.read()
    old_csv = None
    if os.path.exists(csv_path):
        with open(csv_path, 'rb') as f:
            old_csv = f.read()

    try:
        with open(clean_path, 'w', encoding='utf-8', newline='') as f:
            f.write(generated)
        if os.path.exists(csv_path):
            os.remove(csv_path)

        run = subprocess.run(
            [executable],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert run.returncode == 0, f"Compiled parser exited with {run.returncode}:\n{run.stderr}"
        assert os.path.isfile(csv_path), "Compiled parser did not create /home/user/clean_data.csv."
        with open(csv_path, 'r', encoding='utf-8', newline='') as f:
            actual = f.read().replace('\r\n', '\n')
        assert actual == expected, (
            "Compiled parser produced incorrect output for verifier-generated records.\n"
            f"Expected:\n{expected}\nActual:\n{actual}"
        )
    finally:
        with open(clean_path, 'wb') as f:
            f.write(old_clean)
        if old_csv is None:
            if os.path.exists(csv_path):
                os.remove(csv_path)
        else:
            with open(csv_path, 'wb') as f:
                f.write(old_csv)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
