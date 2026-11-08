#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import random
import re
import signal
import socket
import subprocess
import time
import uuid

import pytest

HOST = '127.0.0.1'
PORT = 9000
LIB_DIR = '/app/bayes_infer'
LIB_PATH = '/app/bayes_infer/libbayes.so'
LOG_PATH = '/home/user/experiment_log.txt'
SOURCE_PATH = '/home/user/tracker.cpp'


def send_req(payload: str) -> str:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(2.0)
    try:
        s.connect((HOST, PORT))
        s.sendall(payload.encode())
        return s.recv(1024).decode()
    finally:
        s.close()


def wait_for_server(timeout=5.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection((HOST, PORT), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    pytest.fail('TCP server did not begin listening on 127.0.0.1:9000')


def listener_pids():
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == '0A' and int(local.rsplit(':', 1)[1], 16) == PORT:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    result = set()
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
                match = re.fullmatch(r'socket:\[(\d+)\]', target)
                if match and match.group(1) in inodes:
                    result.add(int(name))
                    break
        except OSError:
            continue
    return result


def assert_linked_executable(path):
    elf = subprocess.run(
        ['readelf', '-h', path], text=True, capture_output=True, check=True
    ).stdout
    assert 'ELF' in elf and re.search(r'Type:\s+DYN|Type:\s+EXEC', elf), \
        f'{path} is not an ELF executable'

    dynamic = subprocess.run(
        ['readelf', '-d', path], text=True, capture_output=True, check=True
    ).stdout
    assert re.search(r'NEEDED.*libbayes\.so', dynamic), \
        f'{path} does not dynamically link against libbayes.so'

    symbols = subprocess.run(
        ['nm', '-D', path], text=True, capture_output=True, check=True
    ).stdout
    assert any(' U ' in f' {line} ' and 'compute_posterior_mean' in line
               for line in symbols.splitlines()), \
        f'{path} does not call the dynamically linked compute_posterior_mean symbol'


def test_library_is_rebuildable_valid_and_computes():
    # Force the submitted Makefile to perform the build rather than trusting a
    # pre-created file.
    subprocess.run(
        ['make', '-B'], cwd=LIB_DIR, text=True, capture_output=True,
        timeout=20, check=True
    )

    # Preserve the original existence assertion and additionally require a real
    # loadable ELF shared object.
    assert os.path.isfile(LIB_PATH), 'libbayes.so was not created in /app/bayes_infer'
    header = subprocess.run(
        ['readelf', '-h', LIB_PATH], text=True, capture_output=True, check=True
    ).stdout
    assert re.search(r'Type:\s+DYN', header), 'libbayes.so is not an ELF shared object'

    lib = ctypes.CDLL(LIB_PATH)
    fn = lib.compute_posterior_mean
    fn.argtypes = [ctypes.POINTER(ctypes.c_double), ctypes.c_int]
    fn.restype = ctypes.c_double

    rng = random.SystemRandom()
    for _ in range(10):
        values = [rng.uniform(-1000.0, 1000.0) for _ in range(rng.randint(1, 12))]
        array = (ctypes.c_double * len(values))(*values)
        expected = sum(values) / (len(values) + 1.0)
        actual = fn(array, len(values))
        assert actual == pytest.approx(expected, rel=1e-12, abs=1e-12)


def test_running_and_submitted_tracker():
    assert os.path.isfile(SOURCE_PATH), f'{SOURCE_PATH} does not exist'

    # Exercise the service the agent left running, retaining the original fixed
    # response and log assertions.
    wait_for_server()
    pids = listener_pids()
    assert pids, 'No process owns the listening socket on port 9000'
    for pid in pids:
        exe = os.readlink(f'/proc/{pid}/exe')
        assert_linked_executable(exe)

    resp1 = send_req('1.0,2.0,3.0')
    assert resp1 == 'POSITIVE\n', \
        f"Expected 'POSITIVE\\n' for '1.0,2.0,3.0', got {resp1!r}"
    resp2 = send_req('-5.0,-1.0')
    assert resp2 == 'NEGATIVE\n', \
        f"Expected 'NEGATIVE\\n' for '-5.0,-1.0', got {resp2!r}"

    time.sleep(0.5)
    assert os.path.isfile(LOG_PATH), f'{LOG_PATH} does not exist'
    with open(LOG_PATH) as f:
        initial_log = f.read()
    expected_line1 = '[Data size: 3] Posterior Mean: 1.5000, Result: POSITIVE'
    expected_line2 = '[Data size: 2] Posterior Mean: -2.0000, Result: NEGATIVE'
    assert expected_line1 in initial_log, f"Expected log line '{expected_line1}' not found in {LOG_PATH}"
    assert expected_line2 in initial_log, f"Expected log line '{expected_line2}' not found in {LOG_PATH}"

    # Compile the submitted source itself. This prevents an unrelated fake
    # process from standing in for tracker.cpp.
    verified_exe = f'/tmp/tracker_verified_{uuid.uuid4().hex}'
    build = subprocess.run(
        ['g++', '-std=c++11', SOURCE_PATH, '-I' + LIB_DIR, '-L' + LIB_DIR,
         '-Wl,-rpath,' + LIB_DIR, '-lbayes', '-o', verified_exe],
        text=True, capture_output=True, timeout=30
    )
    assert build.returncode == 0, f'tracker.cpp failed to compile/link:\n{build.stderr}'
    assert_linked_executable(verified_exe)

    # Interpose the required library function while preserving its semantics.
    # The private marker proves that the submitted server invokes that function
    # for every request rather than duplicating or hard-coding its answers.
    marker = f'/tmp/bayes_calls_{uuid.uuid4().hex}'
    shim_src = f'/tmp/bayes_shim_{uuid.uuid4().hex}.cpp'
    shim_so = f'/tmp/bayes_shim_{uuid.uuid4().hex}.so'
    with open(shim_src, 'w') as f:
        f.write(r'''#include <cstdio>
#include <cstdlib>
extern "C" double compute_posterior_mean(const double* data, int size) {
    const char* marker = std::getenv("VERIFY_BAYES_CALLS");
    if (marker) {
        FILE* fp = std::fopen(marker, "a");
        if (fp) { std::fprintf(fp, "%d\n", size); std::fclose(fp); }
    }
    if (size == 0) return 0.0;
    double sum = 0.0;
    for (int i = 0; i < size; ++i) sum += data[i];
    return sum / (size + 1.0);
}
''')
    subprocess.run(
        ['g++', '-shared', '-fPIC', shim_src, '-o', shim_so],
        text=True, capture_output=True, timeout=20, check=True
    )

    # Stop the original listener so the freshly compiled submitted source can
    # be executed on its required port.
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while listener_pids() and time.time() < deadline:
        time.sleep(0.05)
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.1)

    # Remove any prewritten answers before unpredictable requests are chosen.
    with open(LOG_PATH, 'w'):
        pass

    env = os.environ.copy()
    env['LD_LIBRARY_PATH'] = LIB_DIR
    env['LD_PRELOAD'] = shim_so
    env['VERIFY_BAYES_CALLS'] = marker
    proc = subprocess.Popen(
        [verified_exe], env=env, stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True
    )
    wait_for_server()
    assert proc.poll() is None, 'Compiled tracker.cpp exited instead of serving requests'

    rng = random.SystemRandom()
    cases = [
        [1.0, 2.0, 3.0],
        [-5.0, -1.0],
        [float(rng.randint(20, 200)), float(rng.randint(1, 50))],
        [float(-rng.randint(20, 200)), float(-rng.randint(1, 50))],
        [float(rng.randint(1, 100)), float(-rng.randint(1, 100)), 0.0],
    ]
    # Add unpredictable payload lengths and values, avoiding an accidental zero
    # sum except where zero is naturally classified as NEGATIVE.
    for _ in range(9):
        n = rng.randint(1, 10)
        cases.append([float(rng.randint(-500, 500)) for _ in range(n)])
    rng.shuffle(cases)

    expected_lines = []
    expected_sizes = []
    for values in cases:
        payload = ','.join(f'{value:.1f}' for value in values)
        total = sum(values)
        mean = total / (len(values) + 1.0)
        result = 'POSITIVE' if mean > 0.0 else 'NEGATIVE'
        response = send_req(payload)
        assert response == result + '\n', \
            f'Wrong response for unpredictable payload {payload!r}: {response!r}'
        expected_lines.append(
            f'[Data size: {len(values)}] Posterior Mean: {mean:.4f}, Result: {result}'
        )
        expected_sizes.append(len(values))

    time.sleep(0.5)
    with open(LOG_PATH) as f:
        fresh_log = f.read()
    for line in expected_lines:
        assert line in fresh_log, f"Expected freshly generated log line '{line}' not found"

    assert os.path.isfile(marker), 'compute_posterior_mean was never called by tracker.cpp'
    with open(marker) as f:
        calls = [int(line.strip()) for line in f if line.strip()]
    assert calls == expected_sizes, \
        'tracker.cpp did not call compute_posterior_mean exactly once with each parsed dataset size'


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
