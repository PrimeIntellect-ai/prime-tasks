#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import shutil
import signal
import subprocess
import time
from collections import defaultdict

import requests

CSV_PATH = '/home/user/data/telemetry.csv'
DECODER = '/app/log_decoder'
REAL_DECODER = '/app/log_decoder.verifier-real'
STATE_PATH = '/tmp/log_decoder_parallel_state'
BASE_URL = 'http://127.0.0.1:8080/api/temperature'


def expected_from_original_csv():
    hourly = defaultdict(list)
    with open(CSV_PATH, 'r', encoding='utf-8') as f:
        for row in csv.DictReader(f):
            hour = row['timestamp'][:13] + ':00:00Z'
            try:
                raw = bytes.fromhex(row['raw_payload'])
                decoded = raw.decode('utf-8', errors='ignore')
                out = subprocess.check_output([DECODER, decoded], text=True)
                for part in out.strip().split('|'):
                    if part.startswith('CPU_TEMP='):
                        hourly[hour].append(float(part.split('=', 1)[1]))
            except Exception:
                continue
    return {h: round(sum(v) / len(v), 2) for h, v in hourly.items() if v}


def assert_valid_response(hour, expected, timeout=5):
    try:
        response = requests.get(BASE_URL, params={'hour': hour}, timeout=timeout)
    except requests.RequestException as exc:
        raise AssertionError(f'Failed to connect to API for hour {hour}: {exc}')
    assert response.status_code == 200, \
        f'Expected status code 200 for hour {hour}, got {response.status_code}'
    try:
        data = response.json()
    except ValueError:
        raise AssertionError(f'Response for hour {hour} is not valid JSON: {response.text}')
    assert 'hour' in data, f"Missing 'hour' key in JSON response for {hour}"
    assert data['hour'] == hour, f"Expected hour {hour}, got {data['hour']}"
    assert 'avg_cpu_temp' in data, f"Missing 'avg_cpu_temp' key in JSON response for {hour}"
    assert isinstance(data['avg_cpu_temp'], (int, float)), 'avg_cpu_temp must be numeric'
    assert abs(data['avg_cpu_temp'] - expected) <= 0.02, \
        f"Expected avg_cpu_temp {expected} for {hour}, got {data['avg_cpu_temp']}"


def assert_invalid_response(hour):
    try:
        response = requests.get(BASE_URL, params={'hour': hour}, timeout=5)
    except requests.RequestException as exc:
        raise AssertionError(f'Failed to connect to API for invalid hour: {exc}')
    assert response.status_code == 404, \
        f'Expected status code 404 for invalid hour, got {response.status_code}'
    try:
        data = response.json()
    except ValueError:
        raise AssertionError(f'Invalid-hour response is not JSON: {response.text}')
    assert 'error' in data, "Missing 'error' key in 404 JSON response"
    assert data == {'error': 'Not found'}, f'Unexpected 404 response: {data}'


def listening_pid(port=8080):
    inode = None
    wanted = f'{port:04X}'
    for path in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(path) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].split(':')[-1].upper() == wanted and fields[3] == '0A':
                        inode = fields[9]
                        break
        except OSError:
            pass
        if inode:
            break
    if not inode:
        return None
    target = f'socket:[{inode}]'
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        fd_dir = f'/proc/{entry}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(f'{fd_dir}/{fd}') == target:
                        return int(entry)
                except OSError:
                    pass
        except OSError:
            pass
    return None


def process_launch_info(pid):
    with open(f'/proc/{pid}/cmdline', 'rb') as f:
        argv = [x.decode(errors='surrogateescape') for x in f.read().split(b'\0') if x]
    cwd = os.readlink(f'/proc/{pid}/cwd')
    env = {}
    with open(f'/proc/{pid}/environ', 'rb') as f:
        for item in f.read().split(b'\0'):
            if b'=' in item:
                key, value = item.split(b'=', 1)
                env[key.decode(errors='surrogateescape')] = value.decode(errors='surrogateescape')
    assert argv, 'Could not determine how to restart the submitted server'
    return argv, cwd, env


def stop_server(pid):
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.time() + 5
    while time.time() < deadline:
        if listening_pid() != pid:
            return
        time.sleep(0.1)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    time.sleep(0.3)


def install_instrumented_decoder():
    assert os.path.isfile(DECODER) and os.access(DECODER, os.X_OK), \
        '/app/log_decoder is missing or not executable'
    os.rename(DECODER, REAL_DECODER)
    wrapper = r'''#!/usr/bin/env python3
import fcntl
import os
import subprocess
import sys
import time
state = '/tmp/log_decoder_parallel_state'
def update(delta):
    with open(state, 'a+') as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        f.seek(0)
        try:
            active, maximum, calls = map(int, (f.read().strip() or '0 0 0').split())
        except Exception:
            active, maximum, calls = 0, 0, 0
        active += delta
        if delta > 0:
            calls += 1
            maximum = max(maximum, active)
        f.seek(0)
        f.truncate()
        f.write(f'{active} {maximum} {calls}')
        f.flush()
        fcntl.flock(f, fcntl.LOCK_UN)
update(1)
try:
    time.sleep(0.06)
    result = subprocess.run(['/app/log_decoder.verifier-real'] + sys.argv[1:])
    raise SystemExit(result.returncode)
finally:
    update(-1)
'''
    with open(DECODER, 'w') as f:
        f.write(wrapper)
    os.chmod(DECODER, 0o755)
    with open(STATE_PATH, 'w') as f:
        f.write('0 0 0')


def make_mixed_fixture():
    nonce = secrets.randbelow(1000000)
    year = 2030 + nonce % 20
    month = 1 + (nonce // 20) % 12
    day = 1 + (nonce // 240) % 20
    first_hour = (nonce // 4800) % 16
    hours = [f'{year:04d}-{month:02d}-{day:02d}T{first_hour+i:02d}:00:00Z' for i in range(4)]
    rows = []
    expected_values = defaultdict(list)

    for hour_index, hour in enumerate(hours):
        minute = 0
        for encoding_index, encoding in enumerate(('utf-8', 'utf-16le', 'cp1252')):
            for item in range(5):
                pad = 2 * (1 + ((nonce + hour_index * 11 + encoding_index * 7 + item * 3) % 17))
                if encoding == 'utf-8':
                    text = f'UTF8 snowman ☃ bucket {hour_index} item {item} ' + ('u' * pad)
                elif encoding == 'utf-16le':
                    text = f'wide Ω bucket {hour_index} item {item} ' + ('w' * pad)
                else:
                    # The euro and accented character make this invalid UTF-8; the
                    # even padding keeps the total CP1252 byte count odd.
                    text = f'café € b{hour_index} i{item} ' + ('c' * pad)
                raw = text.encode(encoding)
                timestamp = hour[:14] + f'{minute:02d}:00Z'
                rows.append([timestamp, f'10.0.{hour_index}.{item}', raw.hex()])
                out = subprocess.check_output([REAL_DECODER, text], text=True)
                temp = None
                for part in out.strip().split('|'):
                    if part.startswith('CPU_TEMP='):
                        temp = float(part.split('=', 1)[1])
                assert temp is not None
                expected_values[hour].append(temp)
                minute += 1

        # Malformed hexadecimal must be ignored and must not affect the average.
        rows.append([hour[:14] + '58:00Z', '10.255.255.1', 'not-valid-hex'])

    with open(CSV_PATH, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['timestamp', 'source_ip', 'raw_payload'])
        writer.writerows(rows)

    expected = {h: round(sum(v) / len(v), 2) for h, v in expected_values.items()}
    return expected, hours


def wait_for_dynamic_api(expected):
    deadline = time.time() + 25
    last_error = None
    first_hour = next(iter(expected))
    while time.time() < deadline:
        try:
            response = requests.get(BASE_URL, params={'hour': first_hour}, timeout=1)
            if response.status_code == 200:
                data = response.json()
                if abs(data.get('avg_cpu_temp', -100000) - expected[first_hour]) <= 0.02:
                    return
        except Exception as exc:
            last_error = exc
        time.sleep(0.25)
    raise AssertionError(f'Submitted server did not process the replacement CSV: {last_error}')


def main():
    # Preserve all original behavioral checks against the supplied CSV.
    original_expected = expected_from_original_csv()
    assert original_expected, 'No expected data could be generated from the CSV.'
    for hour, expected in original_expected.items():
        assert_valid_response(hour, expected)
    assert_invalid_response('2099-01-01T12:00:00Z')

    pid = listening_pid()
    assert pid is not None, 'No server is listening on 127.0.0.1:8080'
    argv, cwd, env = process_launch_info(pid)

    csv_backup = '/tmp/telemetry.csv.verifier-backup'
    shutil.copy2(CSV_PATH, csv_backup)
    launched = None
    decoder_installed = False
    try:
        stop_server(pid)
        install_instrumented_decoder()
        decoder_installed = True
        expected, hours = make_mixed_fixture()

        # If a supervisor did not restart it, execute the same submitted artifact
        # again so it must ingest the verifier-generated fixture.
        time.sleep(0.5)
        if listening_pid() is None:
            launched = subprocess.Popen(argv, cwd=cwd, env=env,
                                        stdout=subprocess.DEVNULL,
                                        stderr=subprocess.DEVNULL,
                                        start_new_session=True)

        wait_for_dynamic_api(expected)
        for hour, value in expected.items():
            assert_valid_response(hour, value)
        assert_invalid_response(f'{hours[0][:11]}23:00:00Z')

        with open(STATE_PATH) as f:
            active, maximum, calls = map(int, f.read().split())
        assert calls >= 60, \
            f'Expected the pipeline to invoke /app/log_decoder for every valid row; observed {calls} calls'
        assert maximum >= 2, \
            f'Binary invocations were not processed in parallel (maximum concurrency was {maximum})'
    finally:
        shutil.copy2(csv_backup, CSV_PATH)
        if decoder_installed:
            try:
                os.unlink(DECODER)
            except FileNotFoundError:
                pass
            if os.path.exists(REAL_DECODER):
                os.rename(REAL_DECODER, DECODER)
        if launched is not None and launched.poll() is None:
            try:
                os.killpg(launched.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
