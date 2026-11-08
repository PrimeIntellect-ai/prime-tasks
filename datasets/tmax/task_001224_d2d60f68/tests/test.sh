#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import math
import os
import random
import re
import signal
import socket
import struct
import subprocess
import time
import wave
from pathlib import Path

import pytest

APP = Path('/app')
FLOAT_RE = re.compile(r'[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?')


def get_expected_features(wav_path):
    with wave.open(str(wav_path), 'rb') as wf:
        assert wf.getnchannels() == 1
        assert wf.getsampwidth() == 2
        assert wf.getframerate() == 16000
        num_frames = wf.getnframes()
        raw_data = wf.readframes(num_frames)

    samples = struct.unpack(f'<{num_frames}h', raw_data)
    if not samples:
        return 0.0, 0.0, 0.0, 0.0

    avg_amp = sum(abs(s) for s in samples) / num_frames
    max_amp = float(max(abs(s) for s in samples))
    zcr = sum(
        1 for a, b in zip(samples, samples[1:])
        if (b >= 0 and a < 0) or (b < 0 and a >= 0)
    )
    rms = math.sqrt(sum(s * s for s in samples) / num_frames)
    return avg_amp, max_amp, zcr / num_frames, rms


def parse_embedding(path):
    text = Path(path).read_text()
    values = [float(x) for x in FLOAT_RE.findall(text)]
    assert len(values) == 4, f'{path} must contain exactly four numeric values, got: {text!r}'
    assert all(math.isfinite(x) for x in values), 'Embedding contains a non-finite value'
    return values


def assert_vector_close(actual, expected, label):
    assert len(actual) == 4
    for i, (got, want) in enumerate(zip(actual, expected)):
        assert math.isclose(got, want, rel_tol=1e-4, abs_tol=1e-3), \
            f'{label}, component {i}: expected {want}, got {got}'


def file_state():
    state = {}
    for p in APP.rglob('*'):
        try:
            if p.is_file():
                st = p.stat()
                state[str(p)] = (st.st_mtime_ns, st.st_size)
        except OSError:
            pass
    return state


def assert_hash_logged(output, before):
    binary = APP / 'extract_features'
    assert binary.is_file(), 'run_pipeline.sh did not create /app/extract_features'
    assert os.access(binary, os.X_OK), '/app/extract_features is not executable'

    data = binary.read_bytes()
    hashes = {
        hashlib.sha256(data).hexdigest().lower(),
        hashlib.sha1(data).hexdigest().lower(),
        hashlib.md5(data).hexdigest().lower(),
    }
    searchable = output.lower()
    after = file_state()
    for name, state in after.items():
        if name == str(binary) or before.get(name) == state:
            continue
        try:
            p = Path(name)
            if p.stat().st_size <= 1024 * 1024:
                searchable += '\n' + p.read_text(errors='strict').lower()
        except (OSError, UnicodeError):
            pass

    assert any(digest in searchable for digest in hashes), \
        'run_pipeline.sh did not log a computed hash of the compiled extract_features binary'


def run_pipeline_and_check(expected):
    before = file_state()
    proc = subprocess.run(
        ['bash', '/app/run_pipeline.sh'], cwd='/app', text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert proc.returncode == 0, f'run_pipeline.sh failed:\n{proc.stdout}'
    results = APP / 'experiment_results.txt'
    assert results.is_file(), 'Missing /app/experiment_results.txt'
    assert_vector_close(parse_embedding(results), expected, 'pipeline embedding')
    assert_hash_logged(proc.stdout, before)


def request_distance(query, timeout=5):
    query_str = ','.join(format(x, '.17g') for x in query) + '\n'
    try:
        with socket.create_connection(('127.0.0.1', 8080), timeout=timeout) as sock:
            sock.sendall(query_str.encode('ascii'))
            sock.shutdown(socket.SHUT_WR)
            chunks = []
            while True:
                chunk = sock.recv(1024)
                if not chunk:
                    break
                chunks.append(chunk)
    except ConnectionRefusedError:
        pytest.fail('TCP server is not listening on 127.0.0.1:8080')
    except socket.timeout:
        pytest.fail('TCP server timed out or did not respond and close the connection')

    response = b''.join(chunks).decode('utf-8')
    assert response.startswith('Distance: '), f'Unexpected response format: {response!r}'
    try:
        actual = float(response.strip().split('Distance: ', 1)[1])
    except (IndexError, ValueError):
        pytest.fail(f'Could not parse distance from response: {response!r}')
    return actual


def assert_server_queries(embedding, queries):
    for query in queries:
        expected = math.sqrt(sum((e - q) ** 2 for e, q in zip(embedding, query)))
        actual = request_distance(query)
        assert math.isclose(actual, expected, rel_tol=1e-3, abs_tol=1e-2), \
            f'Expected distance ~{expected:.6f}, got {actual:.6f} for query {query}'


def listening_inodes():
    result = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].rsplit(':', 1)[-1].upper() == '1F90' and fields[3] == '0A':
                result.add(fields[9])
    return result


def stop_port_8080():
    inodes = listening_inodes()
    if not inodes:
        return
    victims = set()
    for proc_dir in Path('/proc').iterdir():
        if not proc_dir.name.isdigit():
            continue
        fd_dir = proc_dir / 'fd'
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    victims.add(int(proc_dir.name))
                    break
        except OSError:
            pass
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listening_inodes():
        time.sleep(0.05)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.1)


def wait_for_server(proc):
    deadline = time.time() + 5
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f'embedding_server exited early with status {proc.returncode}')
        try:
            with socket.create_connection(('127.0.0.1', 8080), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    pytest.fail('embedding_server did not listen on 127.0.0.1:8080')


def make_hidden_wav(path):
    rng = random.SystemRandom()
    samples = []
    for i in range(911):
        base = ((i * 7919 + 1237) % 50001) - 25000
        if i % 13 == 0:
            base = rng.randrange(-30000, 30001)
        samples.append(base)
    with wave.open(str(path), 'wb') as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(16000)
        wf.writeframes(struct.pack(f'<{len(samples)}h', *samples))


def test_complete_pipeline_and_server():
    fixture = APP / 'fixture.wav'
    results = APP / 'experiment_results.txt'
    pipeline = APP / 'run_pipeline.sh'
    extractor_source = APP / 'extract_features.c'
    server_source = APP / 'embedding_server.c'

    assert fixture.is_file(), 'Missing /app/fixture.wav'
    assert results.is_file(), 'Missing /app/experiment_results.txt'
    assert pipeline.is_file(), 'Missing /app/run_pipeline.sh'
    assert extractor_source.is_file(), 'Missing /app/extract_features.c'
    assert server_source.is_file(), 'Missing /app/embedding_server.c'

    expected_fixture = get_expected_features(fixture)

    # Preserve the original server assertion and add unpredictable queries so a
    # one-response hardcoded listener cannot pass.
    rng = random.SystemRandom()
    initial_queries = [[10.0, 20.0, 30.0, 40.0]]
    initial_queries += [[rng.uniform(-5000, 40000) for _ in range(4)] for _ in range(3)]
    assert_server_queries(expected_fixture, initial_queries)

    fixture_backup = fixture.read_bytes()
    hidden = Path('/tmp/verifier_hidden.wav')
    try:
        run_pipeline_and_check(expected_fixture)
        make_hidden_wav(hidden)
        fixture.write_bytes(hidden.read_bytes())
        run_pipeline_and_check(get_expected_features(fixture))
    finally:
        fixture.write_bytes(fixture_backup)

    # Restore the required final result for fixture.wav.
    run_pipeline_and_check(expected_fixture)
    original_results = results.read_bytes()

    server_binary = APP / 'embedding_server'
    assert server_binary.is_file(), 'Missing compiled /app/embedding_server'
    assert os.access(server_binary, os.X_OK), '/app/embedding_server is not executable'

    # Compile the submitted server source ourselves, load a verifier-chosen
    # embedding, and exercise several independent connections.
    test_server = Path('/tmp/embedding_server_under_test')
    compile_proc = subprocess.run(
        ['gcc', '-std=c11', '-O2', str(server_source), '-o', str(test_server), '-lm'],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20
    )
    assert compile_proc.returncode == 0, f'embedding_server.c does not compile:\n{compile_proc.stdout}'

    custom_embedding = [rng.uniform(-1000, 1000) for _ in range(4)]
    custom_embedding[2] = rng.uniform(-1, 1)
    stop_port_8080()
    proc = None
    try:
        results.write_text(','.join(format(x, '.17g') for x in custom_embedding) + '\n')
        proc = subprocess.Popen(
            [str(test_server)], cwd='/app', stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        wait_for_server(proc)
        queries = [[rng.uniform(-2000, 2000) for _ in range(4)] for _ in range(4)]
        assert_server_queries(custom_embedding, queries)
    finally:
        stop_port_8080()
        if proc is not None and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
        results.write_bytes(original_results)

    # Leave the submitted server running, as required by the instruction.
    final_proc = subprocess.Popen(
        [str(server_binary)], cwd='/app', stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True
    )
    wait_for_server(final_proc)
    assert_server_queries(expected_fixture, [[10.0, 20.0, 30.0, 40.0]])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
