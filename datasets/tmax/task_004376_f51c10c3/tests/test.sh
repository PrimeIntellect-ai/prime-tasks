#!/bin/bash
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import shutil
import struct
import subprocess
import time
import urllib.request

import pytest

WORKSPACE = '/home/user/workspace'
LIB_PATH = os.path.join(WORKSPACE, 'libcompute.so')
APP_PATH = os.path.join(WORKSPACE, 'app.py')
NGINX_CONF = os.path.join(WORKSPACE, 'nginx.conf')


def post(url, payload, timeout=3):
    data = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(url, data=data, method='POST')
    req.add_header('Content-Type', 'application/json')
    req.add_header('Content-Length', str(len(data)))
    with urllib.request.urlopen(req, timeout=timeout) as response:
        assert response.status == 200
        return response.read().decode('utf-8').strip()


def expected_result(payload):
    total = 0.0
    for record in payload:
        value32 = struct.unpack('<f', struct.pack('<f', record['value']))[0]
        total += record['id'] * value32
    return f'{total:.4f}'


def stop_existing_services():
    subprocess.run("pkill -9 -f '[p]ython3 .*app.py'", shell=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(['pkill', '-9', 'nginx'], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)
    time.sleep(0.3)


def wait_for_app(proc, expected, payload):
    last_error = None
    for _ in range(50):
        if proc.poll() is not None:
            raise AssertionError('app.py exited before accepting requests')
        try:
            actual = post('http://127.0.0.1:8080/process', payload, timeout=0.5)
            assert actual == expected
            return
        except Exception as exc:
            last_error = exc
            time.sleep(0.1)
    raise AssertionError(f'app.py did not become ready: {last_error}')


@pytest.fixture(scope='session', autouse=True)
def execute_submission():
    assert os.path.isfile(LIB_PATH), 'Shared library libcompute.so was not compiled or is missing.'
    backup = '/tmp/submitted_libcompute.so'
    shutil.copy2(LIB_PATH, backup)
    app_proc = None
    nginx_proc = None
    stop_existing_services()

    try:
        # Temporarily use an independently built probe library. Its result depends on
        # every serialized byte, so this verifies app.py's packing, length, library
        # invocation, and double return-value ABI rather than trusting its source.
        probe_source = '/tmp/libcompute_probe.c'
        with open(probe_source, 'w') as f:
            f.write(r'''
double process_records(const unsigned char *data, int length) {
    double result = 1000.25 + ((double)length * 0.125);
    for (int i = 0; i < length; ++i)
        result += ((double)data[i]) * ((double)(i + 1));
    return result;
}
''')
        subprocess.run(['gcc', '-shared', '-fPIC', probe_source, '-o', LIB_PATH], check=True)

        rng = random.SystemRandom()
        probe_payload = [
            {'id': rng.randrange(0, 65536), 'value': rng.randrange(-200, 201) / 8.0}
            for _ in range(4)
        ]
        packed = b''.join(struct.pack('<Hf', r['id'], r['value']) for r in probe_payload)
        probe_value = 1000.25 + len(packed) * 0.125
        probe_value += sum(byte * (index + 1) for index, byte in enumerate(packed))
        probe_expected = f'{probe_value:.4f}'

        app_proc = subprocess.Popen(
            ['python3', APP_PATH], cwd=WORKSPACE,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        wait_for_app(app_proc, probe_expected, probe_payload)
        app_proc.terminate()
        try:
            app_proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            app_proc.kill()
            app_proc.wait()
        app_proc = None

        # Restore and execute the submitted shared library and services.
        shutil.copy2(backup, LIB_PATH)
        subprocess.run(['nginx', '-t', '-c', NGINX_CONF,
                        '-p', os.path.join(WORKSPACE, 'nginx_prefix/')], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        app_proc = subprocess.Popen(
            ['python3', APP_PATH], cwd=WORKSPACE,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        readiness_payload = [{'id': 7, 'value': 1.25}, {'id': 19, 'value': -2.5}]
        wait_for_app(app_proc, expected_result(readiness_payload), readiness_payload)

        nginx_proc = subprocess.Popen(
            ['nginx', '-c', NGINX_CONF,
             '-p', os.path.join(WORKSPACE, 'nginx_prefix/')],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(0.8)
        if nginx_proc.poll() not in (None, 0):
            raise AssertionError('Nginx failed to start with the submitted configuration')
        running = subprocess.run(['pgrep', '-x', 'nginx'], stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL)
        assert running.returncode == 0, 'No Nginx process is running'
        yield
    finally:
        if os.path.isfile(backup):
            shutil.copy2(backup, LIB_PATH)
        if app_proc is not None and app_proc.poll() is None:
            app_proc.terminate()
            try:
                app_proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                app_proc.kill()
        if nginx_proc is not None and nginx_proc.poll() is None:
            nginx_proc.terminate()
        subprocess.run(['pkill', '-9', 'nginx'], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)


def test_libcompute_so_exists():
    assert os.path.isfile(LIB_PATH), 'Shared library libcompute.so was not compiled or is missing.'
    with open(LIB_PATH, 'rb') as f:
        header = f.read(18)
    assert header[:4] == b'\x7fELF', 'libcompute.so is not an ELF binary.'
    endian = '<' if header[5] == 1 else '>'
    assert struct.unpack(endian + 'H', header[16:18])[0] == 3, 'libcompute.so is not an ELF shared object.'

    lib = ctypes.CDLL(LIB_PATH)
    function = lib.process_records
    function.argtypes = [ctypes.POINTER(ctypes.c_ubyte), ctypes.c_int]
    function.restype = ctypes.c_double

    rng = random.SystemRandom()
    for _ in range(8):
        payload = [
            {'id': rng.randrange(0, 65536), 'value': rng.randrange(-500, 501) / 8.0}
            for _ in range(rng.randrange(1, 9))
        ]
        blob = b''.join(struct.pack('<Hf', r['id'], r['value']) for r in payload)
        buffer = (ctypes.c_ubyte * len(blob)).from_buffer_copy(blob)
        actual = function(buffer, len(blob))
        expected = float(expected_result(payload))
        assert actual == pytest.approx(expected, abs=0.00005)

    invalid = (ctypes.c_ubyte * 1)(0)
    assert function(invalid, 1) == pytest.approx(-1.0)


def test_result_log_content():
    log_path = '/home/user/workspace/result.log'
    assert os.path.isfile(log_path), 'result.log is missing.'
    with open(log_path, 'r') as f:
        content = f.read().strip()
    assert content == '65.0000', f'result.log contains incorrect value: {content}, expected 65.0000'


def test_services_running_and_correct():
    # Preserve the original fixed assertion.
    payload = [{'id': 2, 'value': 3.0}, {'id': 3, 'value': 4.0}]
    try:
        res_body = post('http://127.0.0.1:8000/api/process', payload, timeout=5)
        assert res_body == '18.0000', f'Expected Nginx/Python pipeline to return 18.0000 for test payload, but got {res_body}'
    except Exception as exc:
        pytest.fail(f'Failed to communicate with Nginx or Python app: {exc}')

    # Exercise both the Python endpoint and Nginx proxy on unpredictable inputs.
    rng = random.SystemRandom()
    for _ in range(10):
        dynamic_payload = [
            {'id': rng.randrange(0, 65536), 'value': rng.randrange(-1000, 1001) / 8.0}
            for _ in range(rng.randrange(1, 10))
        ]
        expected = expected_result(dynamic_payload)
        direct = post('http://127.0.0.1:8080/process', dynamic_payload, timeout=5)
        proxied = post('http://127.0.0.1:8000/api/process', dynamic_payload, timeout=5)
        assert direct == expected
        assert proxied == expected
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
fi
