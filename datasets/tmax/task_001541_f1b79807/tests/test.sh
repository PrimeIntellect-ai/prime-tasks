#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import signal
import socket
import struct
import subprocess
import time
import wave


def test_rms_features_csv():
    path = '/home/user/rms_features.csv'
    assert os.path.exists(path), f"Features file {path} is missing."
    assert os.path.isfile(path), f"{path} is not a file."

    with open(path, 'r') as f:
        content = f.read().strip().split('\n')

    assert len(content) >= 10, "Not enough rows in rms_features.csv. Expected at least 10."

    # Check first row format (could be header or data, but spec says "starting with window_index 0")
    has_header = content[0].startswith('window_index')
    start_idx = 1 if has_header else 0

    for i in range(10):
        row = content[start_idx + i].split(',')
        assert len(row) == 2, f"Invalid format in rms_features.csv at row {start_idx + i}"
        assert int(row[0]) == i, f"Expected window_index {i}, got {row[0]}"
        rms = float(row[1])

        amp = 1000 + i * 500
        expected_rms = amp / math.sqrt(2)
        assert math.isclose(rms, expected_rms, rel_tol=0.05), f"RMS value mismatch at window {i}: expected ~{expected_rms}, got {rms}"


def test_tcp_server_auth_failure():
    try:
        s = socket.create_connection(('127.0.0.1', 9000), timeout=2)
        s.sendall(b"AUTH: wrong_token\n")
        response = s.recv(1024)
        assert not response, "Server should close connection on incorrect auth without responding"
        s.close()
    except ConnectionRefusedError:
        assert False, "Server is not listening on 127.0.0.1:9000"
    except socket.timeout:
        pass


def test_tcp_server_success():
    try:
        s = socket.create_connection(('127.0.0.1', 9000), timeout=2)
        s.sendall(b"AUTH: ds_agent_2024\n")
        s.sendall(b"GET_CORRELATION\n")
        response = s.recv(1024).decode('utf-8')
        s.close()
    except ConnectionRefusedError:
        assert False, "Server is not listening on 127.0.0.1:9000"
    except socket.timeout:
        assert False, "Server timed out waiting for response"

    assert response == "RESULT: 1.0000\n", f"Expected 'RESULT: 1.0000\\n', got {repr(response)}"


def _listener_inodes(port):
    wanted = f'{port:04X}'
    result = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].split(':')[-1].upper() == wanted and fields[3] == '0A':
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def _stop_port(port):
    inodes = _listener_inodes(port)
    if not inodes:
        return
    victims = set()
    for pid in os.listdir('/proc'):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        fd_dir = f'/proc/{pid}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f'{fd_dir}/{fd}')
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    victims.add(int(pid))
                    break
        except OSError:
            continue
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and _listener_inodes(port):
        time.sleep(0.05)
    assert not _listener_inodes(port), 'Could not stop the original port 9000 listener'


def _find_source():
    candidates = []
    for root in ('/home/user', '/app'):
        for base, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if not d.startswith('.')]
            for name in files:
                if name.endswith('.c'):
                    candidates.append(os.path.join(base, name))
    assert candidates, 'No C source file was found under /home/user or /app'
    preferred = [p for p in candidates if os.path.basename(p) == 'pipeline.c']
    if preferred:
        preferred.sort(key=lambda p: (p != '/home/user/pipeline.c', len(p), p))
        return preferred[0]
    assert len(candidates) == 1, f'Cannot identify the pipeline C source among: {candidates}'
    return candidates[0]


def _recv_to_close(sock):
    chunks = []
    while True:
        part = sock.recv(1024)
        if not part:
            return b''.join(chunks)
        chunks.append(part)


def test_z_pipeline_on_unseen_audio_and_labels():
    source = _find_source()
    binary = '/tmp/submitted_pipeline'
    build = subprocess.run(
        ['gcc', source, '-o', binary, '-lm'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert build.returncode == 0, f'C source did not compile with gcc: {build.stderr}'
    assert os.path.isfile(binary) and os.access(binary, os.X_OK), 'Compiled pipeline is not executable'

    _stop_port(9000)

    rng = random.SystemRandom()
    window_count = 7
    sample_rate = 16000
    all_windows = []
    expected_rms = []
    for _ in range(window_count):
        scale = rng.randint(1800, 14500)
        pattern = [rng.randint(-scale, scale) for _ in range(257)]
        samples = [pattern[i % len(pattern)] for i in range(sample_rate)]
        all_windows.append(samples)
        expected_rms.append(math.sqrt(sum(x * x for x in samples) / sample_rate))

    with wave.open('/app/audio/signal.wav', 'wb') as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(sample_rate)
        for samples in all_windows:
            wav.writeframesraw(struct.pack('<' + 'h' * len(samples), *samples))

    while True:
        click_rates = [rng.uniform(0.05, 0.95) for _ in range(window_count)]
        mean_x = sum(expected_rms) / window_count
        mean_y = sum(click_rates) / window_count
        numerator = sum((x - mean_x) * (y - mean_y) for x, y in zip(expected_rms, click_rates))
        denominator = math.sqrt(
            sum((x - mean_x) ** 2 for x in expected_rms)
            * sum((y - mean_y) ** 2 for y in click_rates)
        )
        expected_corr = numerator / denominator
        if abs(expected_corr) < 0.85 and abs(expected_corr) > 0.05:
            break

    order = list(range(window_count))
    rng.shuffle(order)
    with open('/app/data/labels.csv', 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['window_index', 'click_rate'])
        for index in order:
            writer.writerow([index, format(click_rates[index], '.17g')])

    try:
        os.remove('/home/user/rms_features.csv')
    except FileNotFoundError:
        pass

    proc = subprocess.Popen(
        [binary],
        cwd='/home/user',
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )
    try:
        deadline = time.time() + 6
        while time.time() < deadline:
            if os.path.exists('/home/user/rms_features.csv') and _listener_inodes(9000):
                break
            if proc.poll() is not None:
                err = proc.stderr.read().decode('utf-8', errors='replace')
                assert False, f'Compiled pipeline exited before serving: {err}'
            time.sleep(0.05)
        assert os.path.exists('/home/user/rms_features.csv'), 'Pipeline did not generate rms_features.csv'
        assert _listener_inodes(9000), 'Recompiled pipeline did not listen on port 9000'

        with open('/home/user/rms_features.csv', newline='') as f:
            rows = list(csv.reader(f))
        if rows and rows[0] and rows[0][0] == 'window_index':
            rows = rows[1:]
        assert len(rows) == window_count, f'Expected exactly {window_count} feature rows, got {len(rows)}'
        for index, row in enumerate(rows):
            assert len(row) == 2, f'Invalid feature row: {row}'
            assert int(row[0]) == index, f'Expected feature index {index}, got {row[0]}'
            actual = float(row[1])
            assert math.isfinite(actual), f'Non-finite RMS at window {index}'
            assert math.isclose(actual, expected_rms[index], rel_tol=1e-5, abs_tol=0.01), \
                f'RMS mismatch at unseen window {index}: expected {expected_rms[index]}, got {actual}'

        bad = socket.create_connection(('127.0.0.1', 9000), timeout=2)
        bad.settimeout(2)
        bad.sendall(b'AUTH: not_the_token\n')
        assert bad.recv(1024) == b'', 'Incorrect authentication was not immediately closed'
        bad.close()

        good = socket.create_connection(('127.0.0.1', 9000), timeout=2)
        good.settimeout(2)
        for piece in (b'AUTH: ds_', b'agent_2024', b'\n', b'GET_COR', b'RELATION\n'):
            good.sendall(piece)
            time.sleep(0.02)
        response = _recv_to_close(good)
        good.close()
        expected_response = f'RESULT: {expected_corr:.4f}\n'.encode()
        assert response == expected_response, \
            f'Expected correlation response {expected_response!r}, got {response!r}'
    finally:
        _stop_port(9000)
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
