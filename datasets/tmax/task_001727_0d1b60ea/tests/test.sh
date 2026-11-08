#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import datetime
import os
import secrets
import stat
import subprocess


def test_processed_sensors_csv():
    file_path = '/home/user/processed_sensors.csv'
    assert os.path.exists(file_path), f"File {file_path} is missing."

    expected_lines = [
        "2023-10-01 10:05:00,Café_Front,22.5",
        "2023-10-01 11:25:00,Café_Back,24.1",
        "2023-10-01 12:55:00,Café_Ext,-10.0"
    ]

    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read().strip().split('\n')

    content = [line.strip() for line in content if line.strip()]
    assert content[-3:] == expected_lines, f"The processed data in {file_path} does not match the expected output. Got: {content[-3:]}"


def test_etl_log():
    file_path = '/home/user/etl.log'
    assert os.path.exists(file_path), f"File {file_path} is missing."

    with open(file_path, 'r', encoding='utf-8') as f:
        lines = f.read().strip().split('\n')

    lines = [line.strip() for line in lines if line.strip()]
    assert len(lines) > 0, f"Log file {file_path} is empty."

    expected_log = "SUCCESS: Extracted 3 samples."
    assert lines[-1] == expected_log, f"The last line of {file_path} does not match the expected log. Got: {lines[-1]}"


def test_cron_job():
    try:
        result = subprocess.run(['crontab', '-l', '-u', 'user'], capture_output=True, text=True, check=True)
        crontab_content = result.stdout
    except subprocess.CalledProcessError:
        spool_path = '/var/spool/cron/crontabs/user'
        assert os.path.exists(spool_path), "Crontab for user 'user' not found."
        with open(spool_path, 'r') as f:
            crontab_content = f.read()

    expected_command = "/usr/local/go/bin/go run /home/user/etl.go"

    found = False
    for line in crontab_content.split('\n'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if line.startswith('*/15 * * * *') and expected_command in line:
            found = True
            break

    assert found, f"Crontab for 'user' does not contain the expected cron job. Crontab content:\n{crontab_content}"


def test_etl_go_script_exists():
    file_path = '/home/user/etl.go'
    assert os.path.exists(file_path), f"Go script {file_path} is missing."
    info = os.stat(file_path)
    assert stat.S_ISREG(info.st_mode), f"Go script {file_path} is not a regular file."
    assert info.st_size > 0, f"Go script {file_path} is empty."


def test_etl_script_behavior_on_fresh_input():
    raw_path = '/home/user/raw_sensors.csv'
    processed_path = '/home/user/processed_sensors.csv'
    log_path = '/home/user/etl.log'
    paths = [raw_path, processed_path, log_path]

    saved = {}
    for path in paths:
        st = os.stat(path)
        with open(path, 'rb') as f:
            data = f.read()
        saved[path] = (data, st.st_uid, st.st_gid, stat.S_IMODE(st.st_mode))

    token = secrets.token_hex(6)
    day = 10 + secrets.randbelow(10)
    base = datetime.datetime(2024, 7, day, 8, 0, 0)
    records = [
        (base + datetime.timedelta(minutes=1), f'Café_bad_{token}', '-50.1'),
        (base + datetime.timedelta(minutes=5), f'Café_{token}', '-50.0'),
        (base + datetime.timedelta(minutes=40), f'Après_{token}', '31.75'),
        (base + datetime.timedelta(hours=1, minutes=2), f'Niño_bad_{token}', '150.1'),
        (base + datetime.timedelta(hours=1, minutes=20), f'Niño_{token}', '150.0'),
        (base + datetime.timedelta(hours=1, minutes=50), f'Olé_{token}', '12.5'),
        (base + datetime.timedelta(days=1, minutes=7), f'Ångström_{token}', '18.25'),
    ]

    expected = []
    seen_hours = set()
    for timestamp, name, temperature in records:
        value = float(temperature)
        if value < -50.0 or value > 150.0:
            continue
        hour = timestamp.strftime('%Y-%m-%d %H')
        if hour in seen_hours:
            continue
        seen_hours.add(hour)
        expected.append((timestamp.strftime('%Y-%m-%d %H:%M:%S'), name, value))

    raw_lines = ['timestamp,sensor_name,temperature']
    raw_lines.extend(f"{ts.strftime('%Y-%m-%d %H:%M:%S')},{name},{temp}" for ts, name, temp in records)
    raw_data = ('\n'.join(raw_lines) + '\n').encode('iso-8859-1')
    sentinel_output = f'SENTINEL,{token},0\n'.encode('utf-8')
    sentinel_log = f'PREVIOUS: {token}\n'.encode('utf-8')

    try:
        for path, data in ((raw_path, raw_data), (processed_path, sentinel_output), (log_path, sentinel_log)):
            with open(path, 'wb') as f:
                f.write(data)
            os.chown(path, saved[path][1], saved[path][2])
            os.chmod(path, saved[path][3])

        result = subprocess.run(
            ['runuser', '-u', 'user', '--', '/usr/local/go/bin/go', 'run', '/home/user/etl.go'],
            capture_output=True,
            text=True,
            timeout=45,
        )
        assert result.returncode == 0, f"ETL script failed on fresh input. stdout={result.stdout!r}, stderr={result.stderr!r}"

        with open(processed_path, 'r', encoding='utf-8', newline='') as f:
            output_lines = f.read().splitlines()
        assert output_lines and output_lines[0] == f'SENTINEL,{token},0', "ETL did not append to processed_sensors.csv."
        assert len(output_lines) == 1 + len(expected), f"ETL wrote an unexpected number of rows: {output_lines!r}"

        parsed = []
        for line in output_lines[1:]:
            fields = next(csv.reader([line]))
            assert len(fields) == 3, f"Malformed output row: {line!r}"
            parsed.append((fields[0], fields[1], float(fields[2])))
        assert parsed == expected, f"ETL output for generated fixture was incorrect. Expected {expected!r}, got {parsed!r}"

        with open(log_path, 'r', encoding='utf-8') as f:
            log_lines = f.read().splitlines()
        assert log_lines == [f'PREVIOUS: {token}', f'SUCCESS: Extracted {len(expected)} samples.'], f"ETL logging was incorrect: {log_lines!r}"
    finally:
        for path, (data, uid, gid, mode) in saved.items():
            with open(path, 'wb') as f:
                f.write(data)
            os.chown(path, uid, gid)
            os.chmod(path, mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
