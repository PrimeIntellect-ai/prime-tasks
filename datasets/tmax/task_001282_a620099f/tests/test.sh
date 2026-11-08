#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import socket
import subprocess
import time
import pytest


def run_sanitizer(binary, data):
    proc = subprocess.run([binary], input=data, text=True, capture_output=True, timeout=5)
    assert proc.returncode == 0, f'Sanitizer exited with {proc.returncode}: {proc.stderr}'
    return proc.stdout


def generated_case():
    token = secrets.randbelow(800000) + 100000
    valid = [
        f'{token},12.25,-88.50,c{token % 10000}',
        f'{token + 1},-1000.0,1000.0,z{token % 1000}',
        f'{token + 2},0.0,-0.25,k{token % 100000}',
        f'{token + 3},999.99,-999.99,q{token % 10000}',
    ]
    invalid = [
        f'{token + 10},1.0,2.0',
        f'{token + 11},1.0,2.0,ok,extra',
        f'{token + 12},NaN,2.0,bad',
        f'{token + 13},1e2,2.0,bad',
        f'{token + 14},12.3.4,2.0,bad',
        f'{token + 15},--4.0,2.0,bad',
        f'{token + 16},4.0,minus-2,bad',
        f'{token + 17},1000.01,2.0,bad',
        f'{token + 18},-1000.01,2.0,bad',
        f'{token + 19},2.0,1000.01,bad',
        f'{token + 20},2.0,-1000.01,bad',
        f'{token + 21},2.0,3.0,abcdefghijk',
        f'notanid,2.0,3.0,bad',
        f'{token + 22},+2.0,3.0,bad',
    ]
    rows = valid + invalid
    random.SystemRandom().shuffle(rows)
    expected = [row for row in rows if row in valid]
    return '\n'.join(rows) + '\n', expected


def test_sanitizer_binary_corpus():
    c_file = '/home/user/sanitizer.c'
    assert os.path.exists(c_file), f'Sanitizer source code missing at {c_file}'

    binary = '/home/user/sanitizer_test'
    compile_proc = subprocess.run(['gcc', c_file, '-o', binary], capture_output=True, text=True)
    assert compile_proc.returncode == 0, f'Compilation failed: {compile_proc.stderr}'

    delivered = '/home/user/sanitizer'
    assert os.path.isfile(delivered), 'Compiled sanitizer missing at /home/user/sanitizer'
    assert os.access(delivered, os.X_OK), 'Compiled sanitizer is not executable'
    with open(delivered, 'rb') as fin:
        assert fin.read(4) == b'\x7fELF', 'The compiled sanitizer must be an ELF executable'

    clean_dir = '/app/tests/corpus/clean'
    evil_dir = '/app/tests/corpus/evil'

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir)]
    for path in clean_files:
        with open(path, 'r') as fin:
            expected = fin.read().strip()
        with open(path, 'r') as fin:
            out = subprocess.check_output([binary], stdin=fin, text=True).strip()
        assert out == expected, f'Clean file {os.path.basename(path)} was modified or rejected. Expected:\n{expected}\nGot:\n{out}'

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir)]
    for path in evil_files:
        with open(path, 'r') as fin:
            out = subprocess.check_output([binary], stdin=fin, text=True).strip()
        assert '1,45.5,12.2,catA' in out, f'Valid row in {os.path.basename(path)} was incorrectly rejected.'
        assert 'NaN' not in out, f'Evil row with NaN in {os.path.basename(path)} bypassed sanitizer.'
        assert '1000.1' not in out, f'Evil row with out-of-bounds value in {os.path.basename(path)} bypassed sanitizer.'
        assert 'toolongcategoryname' not in out, f'Evil row with long category in {os.path.basename(path)} bypassed sanitizer.'
        assert 'extra_column' not in out, f'Evil row with extra column in {os.path.basename(path)} bypassed sanitizer.'
        assert 'drop table' not in out, f'Evil row with non-numeric feature in {os.path.basename(path)} bypassed sanitizer.'

    for _ in range(8):
        data, expected = generated_case()
        for candidate in (binary, delivered):
            actual = run_sanitizer(candidate, data).splitlines()
            assert actual == expected, f'{candidate} mishandled generated rows. Expected {expected}, got {actual}'


def cleanup_services():
    subprocess.run(['pkill', '-f', 'redis-server'], check=False)
    subprocess.run(['pkill', '-f', 'nc'], check=False)
    time.sleep(0.3)


def wait_for_redis():
    deadline = time.time() + 8
    while time.time() < deadline:
        proc = subprocess.run(['redis-cli', 'ping'], capture_output=True, text=True)
        if proc.returncode == 0 and proc.stdout.strip() == 'PONG':
            return
        time.sleep(0.1)
    pytest.fail('Redis did not start on the default port')


def send_connection(data):
    deadline = time.time() + 8
    while True:
        try:
            with socket.create_connection(('127.0.0.1', 9000), timeout=1) as sock:
                sock.sendall(data)
                sock.shutdown(socket.SHUT_WR)
            return
        except OSError as exc:
            if time.time() >= deadline:
                pytest.fail(f'Failed to send data to pipeline on port 9000: {exc}')
            time.sleep(0.1)


def redis_lrange_exact():
    with socket.create_connection(('127.0.0.1', 6379), timeout=2) as sock:
        sock.sendall(b'*4\r\n$6\r\nLRANGE\r\n$10\r\nclean_data\r\n$1\r\n0\r\n$2\r\n-1\r\n')
        stream = sock.makefile('rb')

        def parse():
            marker = stream.read(1)
            line = stream.readline()
            assert marker, 'Unexpected end of Redis response'
            if marker == b'*':
                return [parse() for _ in range(int(line))]
            if marker == b'$':
                size = int(line)
                if size == -1:
                    return None
                value = stream.read(size)
                assert stream.read(2) == b'\r\n'
                return value
            if marker == b':':
                return int(line)
            if marker == b'+':
                return line.rstrip(b'\r\n')
            raise AssertionError(f'Redis returned an error or invalid response: {marker + line!r}')

        return [item.decode() for item in parse()]


def test_pipeline_integration():
    script_path = '/app/start_pipeline.sh'
    assert os.path.exists(script_path), f'Pipeline script missing at {script_path}'

    cleanup_services()
    subprocess.run(['redis-cli', 'del', 'clean_data'], check=False)
    p = subprocess.Popen(['bash', script_path])

    try:
        wait_for_redis()
        subprocess.run(['redis-cli', 'del', 'clean_data'], check=True, capture_output=True)

        clean_dir = '/app/tests/corpus/clean'
        for name in os.listdir(clean_dir):
            with open(os.path.join(clean_dir, name), 'rb') as fin:
                send_connection(fin.read())
            time.sleep(0.3)

        evil_dir = '/app/tests/corpus/evil'
        for name in os.listdir(evil_dir):
            with open(os.path.join(evil_dir, name), 'rb') as fin:
                send_connection(fin.read())
            time.sleep(0.3)

        time.sleep(2)
        out = subprocess.check_output(['redis-cli', 'lrange', 'clean_data', '0', '-1'], text=True)
        lines = [line.strip() for line in out.split('\n') if line.strip()]
        assert len(lines) == 4, f'Expected exactly 4 valid rows in Redis clean_data list, got {len(lines)}. Contents: {lines}'
        assert '1,45.5,12.2,catA' in lines, 'Missing expected row from clean/evil corpus'
        assert '2,-900.1,0.0,catB' in lines, 'Missing expected row from clean corpus'
        assert '3,1000.0,-1000.0,catC' in lines, 'Missing expected row from clean corpus'

        subprocess.run(['redis-cli', 'del', 'clean_data'], check=True, capture_output=True)
        expected_values = []
        for _ in range(12):
            data, valid_rows = generated_case()
            assert len(valid_rows) == 4
            chosen = secrets.choice(valid_rows)
            mixed_rows = [chosen]
            all_rows = data.splitlines()
            mixed_rows.extend(row for row in all_rows if row not in valid_rows)
            random.SystemRandom().shuffle(mixed_rows)
            send_connection(('\n'.join(mixed_rows) + '\n').encode())
            expected_values.append(chosen)
            time.sleep(0.15)

        deadline = time.time() + 8
        actual_values = []
        while time.time() < deadline:
            actual_values = [value.rstrip('\r\n') for value in redis_lrange_exact()]
            if len(actual_values) >= len(expected_values):
                break
            time.sleep(0.15)

        assert actual_values == expected_values, f'Pipeline Redis data was not derived from the generated TCP input. Expected {expected_values}, got {actual_values}'
    finally:
        p.kill()
        try:
            p.wait(timeout=2)
        except subprocess.TimeoutExpired:
            p.terminate()
        cleanup_services()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo 1 > /logs/verifier/reward.txt
else
    echo 0 > /logs/verifier/reward.txt
fi
