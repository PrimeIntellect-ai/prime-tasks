#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import signal
import socket
import ssl
import stat
import subprocess
import tempfile
import time
import urllib.request
import uuid
import wave
from pathlib import Path

import pytest

HOME = Path('/home/user')
CONFIG = HOME / 'config/sensor.conf'
WAV = Path('/app/machine_audio.wav')
CSV_PATH = HOME / 'www/events.csv'
LOG_PATH = HOME / 'logs/sensor.log'
BIN_PATH = HOME / 'bin/processor'
SRC_PATH = HOME / 'src/processor.c'


def uncommented(text):
    return '\n'.join(line.split('#', 1)[0] for line in text.splitlines())


def test_directories_exist():
    dirs = ['src', 'bin', 'logs', 'www', 'tls', 'config']
    for d in dirs:
        path = f'/home/user/{d}'
        assert os.path.isdir(path), f'Directory {path} does not exist.'


def test_sensor_config():
    conf_path = '/home/user/config/sensor.conf'
    assert os.path.isfile(conf_path), f'Config file {conf_path} does not exist.'
    content = Path(conf_path).read_text()
    assert 'THRESHOLD=12000' in content, 'THRESHOLD=12000 not found in sensor.conf'
    assert 'MIN_DURATION_S=0.05' in content, 'MIN_DURATION_S=0.05 not found in sensor.conf'
    assert 'LOGFILE=/home/user/logs/sensor.log' in content, 'LOGFILE not found in sensor.conf'


def test_logrotate_config():
    conf_path = Path('/home/user/config/logrotate.conf')
    assert conf_path.is_file(), f'Logrotate config {conf_path} does not exist.'
    content = conf_path.read_text()
    assert '/home/user/logs/sensor.log' in content, 'Target log file not found in logrotate.conf'
    assert 'daily' in content, 'daily rotation not found in logrotate.conf'
    assert 'rotate 7' in content, 'rotate 7 not found in logrotate.conf'
    assert 'compress' in content, 'compress not found in logrotate.conf'

    active = uncommented(content)
    assert re.search(r'/home/user/logs/sensor\.log\s*\{', active)
    assert re.search(r'^\s*daily\s*$', active, re.M)
    assert re.search(r'^\s*rotate\s+7\s*$', active, re.M)
    assert re.search(r'^\s*compress\s*$', active, re.M)
    with tempfile.TemporaryDirectory() as td:
        test_log = Path(td) / 'sensor.log'
        test_log.touch()
        test_conf = Path(td) / 'logrotate.conf'
        test_conf.write_text(active.replace('/home/user/logs/sensor.log', str(test_log)))
        result = subprocess.run(
            ['logrotate', '-d', str(test_conf)], text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10
        )
        assert result.returncode == 0, f'Invalid logrotate configuration:\n{result.stdout}'


def test_deploy_script():
    script_path = Path('/home/user/deploy.sh')
    assert script_path.is_file(), f'Deploy script {script_path} does not exist.'
    st = script_path.stat()
    assert bool(st.st_mode & stat.S_IXUSR), f'Deploy script {script_path} is not executable.'
    content = script_path.read_text()
    assert 'gcc' in content, 'gcc not found in deploy.sh'
    assert '-O3' in content, '-O3 optimization flag not found in deploy.sh'
    active = uncommented(content)
    assert re.search(r'\bgcc\b[^\n]*-O3|-O3[^\n]*\bgcc\b', active), 'deploy.sh does not compile with gcc -O3'
    assert 'processor.c' in active, 'deploy.sh does not compile processor.c'
    assert 'processor.bak' in active, 'deploy.sh does not back up processor'


def test_tls_certs():
    cert_path = '/home/user/tls/cert.pem'
    key_path = '/home/user/tls/key.pem'
    assert os.path.isfile(cert_path), f'TLS cert {cert_path} does not exist.'
    assert os.path.isfile(key_path), f'TLS key {key_path} does not exist.'
    cert_pub = subprocess.run(
        ['openssl', 'x509', '-in', cert_path, '-pubkey', '-noout'],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    ).stdout
    key_pub = subprocess.run(
        ['openssl', 'pkey', '-in', key_path, '-pubout'],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    ).stdout
    assert cert_pub == key_pub, 'TLS certificate and key do not match'
    verified = subprocess.run(
        ['openssl', 'verify', '-CAfile', cert_path, cert_path],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=10
    )
    assert verified.returncode == 0, f'Certificate is not a valid self-signed certificate: {verified.stdout}'


def test_start_server_script():
    script_path = Path('/home/user/start_server.sh')
    assert script_path.is_file(), f'Start server script {script_path} does not exist.'
    st = script_path.stat()
    assert bool(st.st_mode & stat.S_IXUSR), f'Start server script {script_path} is not executable.'
    content = script_path.read_text()
    assert '8443' in content, 'Port 8443 not found in start_server.sh'

    name = f'verifier-{uuid.uuid4().hex}.txt'
    challenge = HOME / 'www' / name
    body = uuid.uuid4().hex.encode()
    challenge.write_bytes(body)
    proc = subprocess.Popen(
        [str(script_path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        preexec_fn=os.setsid
    )
    context = ssl._create_unverified_context()
    received = None
    error = None
    try:
        deadline = time.time() + 8
        while time.time() < deadline:
            try:
                with urllib.request.urlopen(f'https://127.0.0.1:8443/{name}', context=context, timeout=1) as response:
                    received = response.read()
                break
            except Exception as exc:
                error = exc
                time.sleep(0.2)
        assert received == body, f'start_server.sh did not serve /home/user/www over HTTPS on 8443: {error}'
    finally:
        challenge.unlink(missing_ok=True)
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def test_c_processor_exists():
    src_path = '/home/user/src/processor.c'
    bin_path = '/home/user/bin/processor'
    assert os.path.isfile(src_path), f'C source {src_path} does not exist.'
    assert os.path.isfile(bin_path), f'Compiled binary {bin_path} does not exist.'
    st = os.stat(bin_path)
    assert bool(st.st_mode & stat.S_IXUSR), f'Binary {bin_path} is not executable.'


def write_wav(samples, rate=44100):
    with wave.open(str(WAV), 'wb') as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(rate)
        output.writeframes(b''.join(int(v).to_bytes(2, 'little', signed=True) for v in samples))


def truth_events(samples, rate, threshold, min_duration):
    min_samples = int(min_duration * rate)
    events = []
    in_event = False
    event_start = 0
    consecutive_over = 0
    consecutive_under = 0
    for i, value in enumerate(samples):
        over = abs(value) >= threshold
        if over:
            consecutive_over += 1
            consecutive_under = 0
            if not in_event and consecutive_over >= min_samples:
                in_event = True
                event_start = i - min_samples + 1
        else:
            consecutive_under += 1
            consecutive_over = 0
            if in_event and consecutive_under >= min_samples:
                in_event = False
                event_end = i - min_samples
                events.append((event_start / rate, (event_end - event_start + 1) / rate))
    if in_event:
        event_end = len(samples) - 1
        events.append((event_start / rate, (event_end - event_start + 1) / rate))
    return events


def configure(threshold, minimum):
    CONFIG.write_text(
        f'THRESHOLD={threshold}\nMIN_DURATION_S={minimum}\n'
        'LOGFILE=/home/user/logs/sensor.log\n'
    )


def assert_processor_run(executable, samples, threshold, minimum):
    configure(threshold, minimum)
    write_wav(samples)
    CSV_PATH.unlink(missing_ok=True)
    LOG_PATH.unlink(missing_ok=True)
    result = subprocess.run(
        [str(executable)], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=15
    )
    assert result.returncode == 0, f'Processor failed: {result.stderr}'
    assert CSV_PATH.is_file(), 'Processor did not generate events.csv'
    assert LOG_PATH.is_file(), 'Processor did not generate sensor.log'

    expected = truth_events(samples, 44100, threshold, minimum)
    lines = CSV_PATH.read_text().splitlines()
    assert lines and lines[0] == 'event_id,start_time,duration', 'Incorrect CSV header'
    rows = list(csv.DictReader(lines))
    assert len(rows) == len(expected), f'Processor generated {len(rows)} events, expected {len(expected)}'
    for index, (row, (start, duration)) in enumerate(zip(rows, expected), 1):
        assert row['event_id'] == str(index), 'Event IDs must be sequential'
        assert re.fullmatch(r'-?\d+\.\d{3}', row['start_time']), 'start_time is not formatted to 3 decimals'
        assert re.fullmatch(r'-?\d+\.\d{3}', row['duration']), 'duration is not formatted to 3 decimals'
        assert float(row['start_time']) == pytest.approx(round(start, 3), abs=0.0001)
        assert float(row['duration']) == pytest.approx(round(duration, 3), abs=0.0001)

    log_lines = [line for line in LOG_PATH.read_text().splitlines() if line.strip()]
    assert len(log_lines) == len(expected), 'Processor must append one log entry per event'
    for index, (line, (start, duration)) in enumerate(zip(log_lines, expected), 1):
        pattern = (
            rf'^\[\d{{4}}-\d{{2}}-\d{{2}} \d{{2}}:\d{{2}}:\d{{2}}\] Event {index} detected at '
            rf'{round(start, 3):.3f}s for {round(duration, 3):.3f}s$'
        )
        assert re.fullmatch(pattern, line), f'Invalid event log entry: {line}'


def test_source_binary_and_deployment_execute_real_processor():
    original_wav = WAV.read_bytes()
    original_config = CONFIG.read_bytes()
    compiled_source = Path('/tmp/verifier-source-processor')
    marker = os.urandom(64)
    try:
        compile_result = subprocess.run(
            ['gcc', '-O3', str(SRC_PATH), '-o', str(compiled_source), '-lm'],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
        )
        assert compile_result.returncode == 0, f'processor.c does not compile: {compile_result.stderr}'
        assert compiled_source.read_bytes()[:4] == b'\x7fELF', 'Compiled processor.c is not a native executable'

        samples1 = [0] * 10000
        samples1[1000:2000] = [10000] * 1000
        samples1[2200:3000] = [-10000] * 800
        samples1[5000:5300] = [15000] * 300
        samples1[7000:7600] = [-12000] * 600
        configure(10000, 0.01)
        write_wav(samples1)
        CSV_PATH.unlink(missing_ok=True)
        LOG_PATH.unlink(missing_ok=True)

        BIN_PATH.unlink(missing_ok=True)
        BIN_PATH.write_bytes(marker)
        BIN_PATH.chmod(0o755)
        backup = Path(str(BIN_PATH) + '.bak')
        backup.unlink(missing_ok=True)
        deployed = subprocess.run(
            ['/home/user/deploy.sh'], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=40
        )
        assert deployed.returncode == 0, f'deploy.sh failed: {deployed.stderr}'
        assert backup.is_file() and backup.read_bytes() == marker, 'deploy.sh did not back up the existing processor'
        assert BIN_PATH.is_file() and os.access(BIN_PATH, os.X_OK), 'deploy.sh did not install an executable processor'
        assert BIN_PATH.read_bytes()[:4] == b'\x7fELF', 'deployed processor is not a compiled native binary'
        # deploy.sh itself must have executed the newly installed processor.
        expected1 = truth_events(samples1, 44100, 10000, 0.01)
        assert CSV_PATH.is_file() and len(list(csv.DictReader(CSV_PATH.read_text().splitlines()))) == len(expected1)
        assert LOG_PATH.is_file() and len(LOG_PATH.read_text().splitlines()) == len(expected1)
        assert_processor_run(BIN_PATH, samples1, 10000, 0.01)

        samples2 = [0] * 12000
        samples2[400:1500] = [15000] * 1100       # below the new threshold
        samples2[3000:4100] = [20000] * 1100      # equality must trigger
        samples2[4140:5100] = [-25000] * 960       # short low gap must not end it
        samples2[8000:9000] = [-25000] * 1000
        assert_processor_run(compiled_source, samples2, 20000, 0.02)
    finally:
        WAV.write_bytes(original_wav)
        CONFIG.write_bytes(original_config)
        CSV_PATH.unlink(missing_ok=True)
        LOG_PATH.unlink(missing_ok=True)
        compiled_source.unlink(missing_ok=True)
        if BIN_PATH.is_file() and BIN_PATH.read_bytes()[:4] == b'\x7fELF':
            try:
                subprocess.run([str(BIN_PATH)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)
            except Exception:
                pass


def get_truth_events(wav_path, threshold=12000, min_duration_s=0.05):
    with wave.open(wav_path, 'rb') as source:
        rate = source.getframerate()
        assert source.getnchannels() == 1 and source.getsampwidth() == 2
        raw = source.readframes(source.getnframes())
    data = [int.from_bytes(raw[i:i+2], 'little', signed=True) for i in range(0, len(raw), 2)]
    return truth_events(data, rate, threshold, min_duration_s)


def test_events_csv_f1_score():
    csv_path = '/home/user/www/events.csv'
    wav_path = '/app/machine_audio.wav'
    assert os.path.isfile(csv_path), f'Events CSV {csv_path} does not exist.'
    assert os.path.isfile(wav_path), f'Audio file {wav_path} does not exist.'
    truth = get_truth_events(wav_path)
    agent_events = []
    try:
        with open(csv_path, 'r') as source:
            reader = csv.DictReader(source)
            for row in reader:
                agent_events.append((float(row['start_time']), float(row['duration'])))
    except Exception as exc:
        pytest.fail(f'Failed to parse {csv_path}: {exc}')

    if not agent_events and not truth:
        f1 = 1.0
    elif not agent_events or not truth:
        f1 = 0.0
    else:
        matches = 0
        for t_start, t_dur in truth:
            for a_start, a_dur in agent_events:
                if abs(t_start - a_start) <= 0.05 and abs(t_dur - a_dur) <= 0.05:
                    matches += 1
                    break
        precision = matches / len(agent_events) if agent_events else 0
        recall = matches / len(truth) if truth else 0
        f1 = 0.0 if precision + recall == 0 else 2 * precision * recall / (precision + recall)
    assert f1 >= 0.95, f'F1 score {f1:.4f} is below the threshold of 0.95. Agent found {len(agent_events)} events, expected {len(truth)}.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
