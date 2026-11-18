#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import signal
import socket
import subprocess
import time

VIDEO = '/app/sensor_feed.mp4'
CSV_PATH = '/home/user/cleaned_data.csv'
LOG_PATH = '/home/user/pipeline.log'
PROCESSOR_SOURCE = '/home/user/processor.c'
SERVER_SOURCE = '/home/user/server.c'
FRAME_SIZE = 320 * 240


def expected_series():
    proc = subprocess.run(
        ['ffmpeg', '-v', 'error', '-i', VIDEO, '-f', 'rawvideo', '-pix_fmt', 'gray', '-'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
        timeout=30,
    )
    raw = proc.stdout
    assert raw and len(raw) % FRAME_SIZE == 0, 'ffmpeg produced an invalid grayscale stream.'

    rows = []
    previous = None
    frame_count = len(raw) // FRAME_SIZE
    for index in range(frame_count):
        frame = raw[index * FRAME_SIZE:(index + 1) * FRAME_SIZE]
        brightness = sum(frame) // FRAME_SIZE
        if previous is None or brightness != previous:
            rows.append((index * 100, brightness))
            previous = brightness
    return frame_count, rows, raw


def read_csv_rows():
    with open(CSV_PATH, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ['timestamp_ms', 'brightness'], f'CSV header {header} is incorrect.'
        rows = []
        for row in reader:
            assert len(row) == 2, f'CSV row {row} does not have exactly 2 columns.'
            assert row[0].isdigit(), f"Timestamp '{row[0]}' is not an integer."
            assert row[1].isdigit(), f"Brightness '{row[1]}' is not an integer."
            rows.append((int(row[0]), int(row[1])))
        return rows


def fetch_response():
    host = '127.0.0.1'
    port = 9000
    try:
        with socket.create_connection((host, port), timeout=5) as s:
            s.sendall(b'FETCH_SERIES\n')
            response = b''
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                response += chunk
            return response
    except ConnectionRefusedError:
        assert False, f'TCP server is not listening on {host}:{port}.'
    except Exception as e:
        assert False, f'Error communicating with TCP server: {e}'


def listener_pids(port):
    inodes = set()
    wanted = f'{port:04X}'
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].split(':')[-1].upper() == wanted and fields[3] == '0A':
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        fd_dir = f'/proc/{name}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f'{fd_dir}/{fd}')
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    pids.add(int(name))
        except (FileNotFoundError, PermissionError):
            pass
    return pids


def stop_port_9000():
    for sig in (signal.SIGTERM, signal.SIGKILL):
        pids = listener_pids(9000)
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        time.sleep(0.4)


def test_pipeline_log_exists_and_format():
    assert os.path.exists(LOG_PATH), f'Log file {LOG_PATH} is missing.'
    with open(LOG_PATH, 'r') as f:
        content = f.read().strip()
    pattern = r'^Processed \d+ raw frames, saved \d+ cleaned frames\.$'
    assert re.match(pattern, content), f"Log file content '{content}' does not match expected format."


def test_cleaned_data_csv_exists_and_format():
    assert os.path.exists(CSV_PATH), f'CSV file {CSV_PATH} is missing.'
    read_csv_rows()


def test_tcp_server_response():
    response_bytes = fetch_response()
    assert response_bytes, 'TCP server returned empty response.'
    try:
        response_str = response_bytes.decode('utf-16le')
    except UnicodeDecodeError:
        assert False, 'Response is not valid UTF-16LE encoded.'
    try:
        data = json.loads(response_str)
    except json.JSONDecodeError:
        assert False, f'Decoded response is not valid JSON: {response_str}'
    assert isinstance(data, list), 'JSON response should be a list of objects.'

    csv_data = []
    if os.path.exists(CSV_PATH):
        with open(CSV_PATH, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                csv_data.append({'t': int(row['timestamp_ms']), 'v': int(row['brightness'])})
    assert data == csv_data, 'JSON response data does not match CSV data.'


def test_outputs_match_video_and_log_counts():
    frame_count, expected, _ = expected_series()
    actual = read_csv_rows()
    assert actual, 'CSV contains no data rows.'
    assert actual == expected, 'CSV does not contain the correctly averaged and deduplicated video frames.'

    with open(LOG_PATH, 'r') as f:
        raw_log = f.read()
    lines = raw_log.splitlines()
    assert len(lines) == 1, 'Pipeline log must contain exactly one line.'
    expected_log = f'Processed {frame_count} raw frames, saved {len(expected)} cleaned frames.'
    assert lines[0] == expected_log, f'Pipeline log counts are incorrect: {lines[0]!r}'


def test_c_sources_compile_and_processor_executes():
    for path in (PROCESSOR_SOURCE, SERVER_SOURCE):
        assert os.path.isfile(path), f'{path} is missing or is not a regular file.'
        assert os.path.getsize(path) > 0, f'{path} is empty.'

    processor_bin = '/tmp/verifier_processor'
    server_bin = '/tmp/verifier_server'
    for source, output in ((PROCESSOR_SOURCE, processor_bin), (SERVER_SOURCE, server_bin)):
        result = subprocess.run(
            ['gcc', source, '-O2', '-o', output, '-lm'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f'{source} does not compile with gcc:\n{result.stderr}'

    frame_count, expected, raw = expected_series()
    raw_path = '/tmp/verifier_sensor.raw'
    with open(raw_path, 'wb') as f:
        f.write(raw)

    succeeded = False
    errors = []
    for args in ([processor_bin], [processor_bin, raw_path]):
        for output in (CSV_PATH, LOG_PATH):
            try:
                os.remove(output)
            except FileNotFoundError:
                pass
        try:
            result = subprocess.run(
                args,
                input=raw,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=30,
            )
            if result.returncode == 0 and os.path.exists(CSV_PATH) and os.path.exists(LOG_PATH):
                if read_csv_rows() == expected:
                    with open(LOG_PATH) as f:
                        log = f.read().splitlines()
                    if log == [f'Processed {frame_count} raw frames, saved {len(expected)} cleaned frames.']:
                        succeeded = True
                        break
            errors.append(f'{args!r} returned {result.returncode}')
        except (subprocess.TimeoutExpired, AssertionError, OSError) as e:
            errors.append(f'{args!r}: {e}')
    assert succeeded, 'Freshly compiled processor did not produce the required output: ' + '; '.join(errors)


def test_freshly_compiled_server_serves_exact_response_repeatedly():
    server_bin = '/tmp/verifier_server'
    assert os.path.isfile(server_bin), 'Freshly compiled server binary is missing.'
    _, expected, _ = expected_series()
    expected_json = json.dumps(
        [{'t': t, 'v': v} for t, v in expected],
        separators=(',', ':'),
    )
    expected_bytes = expected_json.encode('utf-16le')

    stop_port_9000()
    proc = subprocess.Popen(
        [server_bin],
        cwd='/home/user',
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        deadline = time.time() + 5
        while time.time() < deadline:
            if listener_pids(9000):
                break
            if proc.poll() is not None:
                break
            time.sleep(0.1)
        assert listener_pids(9000), 'Freshly compiled server.c did not listen on port 9000.'
        for _ in range(2):
            response = fetch_response()
            assert response == expected_bytes, 'Server response is not the exact required UTF-16LE JSON payload.'
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
        stop_port_9000()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
