#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import shutil
import signal
import subprocess
import tempfile
import time
import unicodedata
from pathlib import Path

import pytest
import requests

SCRIPT = Path('/home/user/etl_server.sh')
AUDIO = Path('/app/audio/transmission.wav')
TELEMETRY = Path('/app/data/telemetry')
URL = 'http://127.0.0.1:8080/'


def request_server(retries=8):
    last_error = None
    for _ in range(retries):
        try:
            response = requests.get(URL, timeout=3)
            return response
        except requests.exceptions.RequestException as exc:
            last_error = exc
            time.sleep(0.75)
    pytest.fail(f'Failed to connect to the ETL server at {URL}. Last error: {last_error}')


def parse_payload(response):
    assert response.status_code == 200, f'Expected HTTP 200 OK, got {response.status_code}'
    assert response.raw.version == 11, 'Expected an HTTP/1.1 response'
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f'Response is not valid JSON. Response text: {response.text}')
    assert 'global_max' in data, "JSON payload missing 'global_max' key"
    assert 'transcript' in data, "JSON payload missing 'transcript' key"
    return data


def assert_ascii(value):
    try:
        value.encode('ascii')
    except UnicodeEncodeError:
        pytest.fail(f'Transcript contains non-ASCII characters despite normalization requirement: {value}')


def matching_processes():
    result = []
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit() or int(proc.name) == os.getpid():
            continue
        try:
            argv = (proc / 'cmdline').read_bytes().split(b'\0')
        except (OSError, PermissionError):
            continue
        if any(arg == b'/home/user/etl_server.sh' for arg in argv):
            result.append(int(proc.name))
    return result


def listener_pids(port=8080):
    inodes = set()
    wanted_port = f'{port:04X}'
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].rsplit(':', 1)[-1].upper() == wanted_port and fields[3] == '0A':
                inodes.add(fields[9])
    pids = set()
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / 'fd').iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                match = re.fullmatch(r'socket:\[(\d+)\]', target)
                if match and match.group(1) in inodes:
                    pids.add(int(proc.name))
        except (OSError, PermissionError):
            continue
    return pids


def stop_server():
    for _ in range(8):
        pids = set(matching_processes()) | listener_pids()
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        time.sleep(0.25)
    for pid in set(matching_processes()) | listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.4)


def derive_resampled_max(directory):
    maxima = []
    saw_gap = False
    for csv_path in sorted(directory.glob('*.csv')):
        points = {}
        with csv_path.open() as handle:
            for line in handle:
                timestamp, value = line.strip().split(',', 1)
                points[int(timestamp)] = float(value)
        assert points, f'Empty test fixture: {csv_path}'
        start, end = min(points), max(points)
        last = None
        for timestamp in range(start, end + 1):
            if timestamp in points:
                last = points[timestamp]
            else:
                saw_gap = True
            if last is not None:
                maxima.append(last)
    assert saw_gap, 'Dynamic fixture must contain resampling gaps'
    return max(maxima)


def test_etl_pipeline_and_server():
    assert SCRIPT.is_file(), f'Required script does not exist: {SCRIPT}'
    assert not SCRIPT.is_symlink(), 'etl_server.sh must be a real script, not a symlink'
    subprocess.run(['bash', '-n', str(SCRIPT)], check=True)

    source = SCRIPT.read_text(errors='replace')
    uncommented = '\n'.join(line for line in source.splitlines() if not re.match(r'^\s*#', line))

    parallel = (
        re.search(r'\bxargs\b[^\n]*(?:-P\s*\d*|--max-procs)', uncommented)
        or re.search(r'\bfind\b[^\n]*-exec', uncommented)
        or (re.search(r'(^|[;&]\s*)[^\n]+&\s*$', uncommented, re.M) and re.search(r'\bwait\b', uncommented))
    )
    assert parallel, 'Script does not contain a parallel-processing mechanism for telemetry files'

    resampling = (
        re.search(r'\bseq\b', uncommented)
        or re.search(r'\bwhile\b[^\n]*(?:-le|<=)', uncommented)
        or re.search(r'\bfor\s*\([^\n;]*;[^\n;]*(?:<=|<[^;]*\+\s*1)[^;]*;[^\n)]*(?:\+\+|\+=\s*1)', uncommented)
    )
    assert resampling, 'Script does not contain a per-second resampling loop'

    # Preserve the original response assertions against the supplied fixtures.
    response = request_server()
    data = parse_payload(response)
    try:
        global_max = float(data['global_max'])
    except (TypeError, ValueError):
        pytest.fail(f"global_max is not a valid number: {data['global_max']}")
    assert global_max == 22.4, f'Expected global_max to be 22.4, got {global_max}'

    transcript = data['transcript']
    assert isinstance(transcript, str), 'transcript must be a JSON string'
    assert 'Motorhead' in transcript, f"Expected 'Motorhead' in transcript, got: {transcript}"
    assert 'resume' in transcript, f"Expected 'resume' in transcript, got: {transcript}"
    assert 'cafe' in transcript, f"Expected 'cafe' in transcript, got: {transcript}"
    assert 'ö' not in transcript, "Found 'ö' in transcript, it should have been normalized to ASCII"
    assert 'é' not in transcript, "Found 'é' in transcript, it should have been normalized to ASCII"
    assert_ascii(transcript)

    # Confirm the already-running service stays alive for multiple requests.
    parse_payload(request_server())

    backup_root = Path(tempfile.mkdtemp(prefix='etl-verifier-'))
    backup_audio = backup_root / 'transmission.wav'
    backup_telemetry = backup_root / 'telemetry'
    shutil.copy2(AUDIO, backup_audio)
    shutil.copytree(TELEMETRY, backup_telemetry)
    launched = None

    try:
        stop_server()

        nonce = 'VERIFY_' + secrets.token_hex(8).upper()
        raw_transcript = f'Mötörhead résumé café coördinator {nonce}'
        expected_transcript = unicodedata.normalize('NFKD', raw_transcript).encode('ascii', 'ignore').decode('ascii')
        wav_header = b'RIFF\x24\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\x44\xAC\x00\x00\x88\x58\x01\x00\x02\x00\x10\x00data\x00\x00\x00\x00'
        AUDIO.write_bytes(wav_header + b'TRANSCRIPT_DATA:' + raw_transcript.encode('utf-8'))

        shutil.rmtree(TELEMETRY)
        TELEMETRY.mkdir(parents=True)
        base = 1800000000 + secrets.randbelow(100000)
        dynamic_max = float(400 + secrets.randbelow(500)) + 0.37
        fixtures = {
            'sensor_001.csv': [(base, -8.5), (base + 3, 11.25), (base + 9, 7.0)],
            'sensor_002.csv': [(base + 1, 19.0), (base + 6, 18.5), (base + 12, 23.0)],
            'sensor_003.csv': [(base + 2, 3.5), (base + 8, 44.125)],
            'sensor_004.csv': [(base, 0.25), (base + 5, -1.0), (base + 11, 2.0)],
            'sensor_005.csv': [(base + 4, 31.0), (base + 10, 30.0)],
            'sensor_006.csv': [(base, 15.0), (base + 7, 16.0)],
            'sensor_007.csv': [(base + 3, -20.0), (base + 13, -2.0)],
            'sensor_008.csv': [(base + 1, 5.75), (base + 14, 6.25)],
            'sensor_009.csv': [(base + 2, 12.0), (base + 15, dynamic_max), (base + 17, dynamic_max - 1.0)],
        }
        for name, rows in fixtures.items():
            (TELEMETRY / name).write_text(''.join(f'{timestamp},{value}\n' for timestamp, value in rows))

        expected_max = derive_resampled_max(TELEMETRY)
        assert expected_max == dynamic_max

        launched = subprocess.Popen(
            ['su', '-s', '/bin/bash', 'user', '-c', 'exec bash /home/user/etl_server.sh'],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            preexec_fn=os.setsid,
        )

        dynamic_response = request_server(retries=12)
        dynamic_data = parse_payload(dynamic_response)
        try:
            actual_max = float(dynamic_data['global_max'])
        except (TypeError, ValueError):
            pytest.fail(f"global_max is not a valid number: {dynamic_data['global_max']}")
        assert actual_max == expected_max, f'Expected dynamically derived global_max {expected_max}, got {actual_max}'

        dynamic_transcript = dynamic_data['transcript']
        assert isinstance(dynamic_transcript, str), 'transcript must be a JSON string'
        assert expected_transcript in dynamic_transcript, (
            f'Expected normalized dynamic transcript {expected_transcript!r}, got {dynamic_transcript!r}'
        )
        assert nonce in dynamic_transcript, 'Server did not process the dynamically replaced audio artifact'
        assert_ascii(dynamic_transcript)

        # The restarted implementation must also continue serving requests.
        repeated = parse_payload(request_server())
        assert float(repeated['global_max']) == expected_max
        assert nonce in repeated['transcript']
    finally:
        stop_server()
        if launched is not None:
            try:
                os.killpg(launched.pid, signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
        shutil.copy2(backup_audio, AUDIO)
        shutil.rmtree(TELEMETRY, ignore_errors=True)
        shutil.copytree(backup_telemetry, TELEMETRY)
        shutil.rmtree(backup_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
