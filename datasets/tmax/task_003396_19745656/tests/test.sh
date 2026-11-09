#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import cv2
import time
import socket
import signal
import pathlib
import subprocess
import numpy as np

PORT = 9090


def kahan_mean(arr):
    total = 0.0
    compensation = 0.0
    for x in arr:
        y = float(x) - compensation
        temp = total + y
        compensation = (temp - total) - y
        total = temp
    return total / len(arr)


def kahan_var(arr, mean):
    total = 0.0
    compensation = 0.0
    for x in arr:
        y = (float(x) - mean) ** 2 - compensation
        temp = total + y
        compensation = (temp - total) - y
        total = temp
    return total / len(arr)


def expected_signal_and_metrics():
    cap = cv2.VideoCapture('/app/binding_kinetics.mp4')
    assert cap.isOpened(), 'Could not open source video'
    values = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        values.append(float(np.mean(gray)))
    cap.release()
    assert values, 'Source video contained no frames'

    mean = kahan_mean(values)
    variance = kahan_var(values, mean)
    spectrum = np.abs(np.fft.fft(np.asarray(values, dtype=np.float64)))
    spectrum[0] = 0
    dominant = int(np.argmax(spectrum))
    return values, f'{dominant},{variance:.6f}'


def natural_key(path):
    return [int(x) if x.isdigit() else x.lower()
            for x in re.split(r'(\d+)', os.path.basename(path))]


def verify_extracted_frames(expected_values):
    extensions = {'.png', '.jpg', '.jpeg', '.bmp', '.tif', '.tiff', '.pgm', '.ppm'}
    groups = []
    for root in ('/home/user', '/app', '/tmp', '/root'):
        if not os.path.isdir(root):
            continue
        for directory, subdirs, files in os.walk(root):
            subdirs[:] = [d for d in subdirs if not d.startswith('.')]
            images = [os.path.join(directory, f) for f in files
                      if pathlib.Path(f).suffix.lower() in extensions]
            if len(images) == len(expected_values):
                groups.append(sorted(images, key=natural_key))

    for images in groups:
        observed = []
        valid = True
        for image_path in images:
            image = cv2.imread(image_path, cv2.IMREAD_GRAYSCALE)
            if image is None:
                valid = False
                break
            observed.append(float(np.mean(image)))
        if valid and np.allclose(observed, expected_values, rtol=0.0, atol=2.5):
            return
    raise AssertionError('No directory contains all extracted video frames in frame order')


def strip_comments_and_literals(source):
    source = re.sub(r'/\*.*?\*/', ' ', source, flags=re.S)
    source = re.sub(r'//[^\n]*', ' ', source)
    source = re.sub(r'"(?:\\.|[^"\\])*"', '""', source)
    source = re.sub(r"'(?:\\.|[^'\\])*'", "''", source)
    return source


def listener_pids(port):
    socket_inodes = set()
    wanted = f'{port:04X}'
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local = fields[1]
            state = fields[3]
            if local.rsplit(':', 1)[-1].upper() == wanted and state == '0A':
                socket_inodes.add(fields[9])

    result = set()
    for pid in os.listdir('/proc'):
        if not pid.isdigit():
            continue
        fd_dir = f'/proc/{pid}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f'{fd_dir}/{fd}')
                except OSError:
                    continue
                match = re.fullmatch(r'socket:\[(\d+)\]', target)
                if match and match.group(1) in socket_inodes:
                    result.add(int(pid))
                    break
        except OSError:
            pass
    return result


def stop_pids(pids):
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and any(os.path.exists(f'/proc/{p}') for p in pids):
        time.sleep(0.05)
    for pid in pids:
        if os.path.exists(f'/proc/{pid}'):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def request_metrics():
    with socket.create_connection(('127.0.0.1', PORT), timeout=5) as sock:
        sock.settimeout(5)
        sock.sendall(b'GET_METRICS\n')
        chunks = []
        while True:
            data = sock.recv(1024)
            if not data:
                break
            chunks.append(data)
            if b'\n' in data:
                break
    return b''.join(chunks).decode('utf-8').strip()


def test_complete_c_submission():
    source_path = '/home/user/analyze.c'
    assert os.path.isfile(source_path), 'Missing /home/user/analyze.c'
    source = open(source_path, encoding='utf-8', errors='replace').read()
    code = strip_comments_and_literals(source)
    lower = code.lower()

    # Preserve the implementation requirements rather than accepting an unrelated server.
    assert re.search(r'\bdouble\b', code), 'Analysis must use double precision'
    compensation_updates = re.findall(
        r'\b([A-Za-z_]\w*)\s*=\s*\(\s*([A-Za-z_]\w*)\s*-\s*([A-Za-z_]\w*)\s*\)\s*-\s*([A-Za-z_]\w*)',
        code)
    assert any(a == d for _, a, _, d in compensation_updates), \
        'No Kahan compensation update of the form (temporary - sum) - addend was found'
    assert 'mean' in lower and ('variance' in lower or re.search(r'\bvar\w*\b', lower)), \
        'Mean and variance calculations are missing'
    assert ('sin(' in lower or 'cos(' in lower or 'cexp(' in lower), \
        'No DFT trigonometric calculation was found'
    assert len(re.findall(r'\bfor\s*\(', lower)) >= 2, 'DFT/time-series loops are missing'
    assert ('dominant' in lower or 'max_mag' in lower or 'max_power' in lower), \
        'Dominant-frequency selection is missing'
    for token in ('socket(', 'bind(', 'listen(', 'accept('):
        assert token in lower, f'C TCP server is missing {token}'

    expected_values, expected = expected_signal_and_metrics()
    verify_extracted_frames(expected_values)

    # Reject the simplest precomputed-answer implementation while retaining behavioral checks.
    uncommented = re.sub(r'/\*.*?\*/|//[^\n]*', ' ', source, flags=re.S)
    assert expected not in uncommented, 'Source contains the complete precomputed answer'
    variance_literal = expected.split(',', 1)[1]
    assert variance_literal not in uncommented, 'Source contains the precomputed variance literal'

    # The server left by the agent must itself be a native executable, not Python or a utility proxy.
    old_pids = listener_pids(PORT)
    assert old_pids, 'No server is listening on 127.0.0.1:9090'
    native_found = False
    for pid in old_pids:
        try:
            exe = os.readlink(f'/proc/{pid}/exe')
            cmdline = open(f'/proc/{pid}/cmdline', 'rb').read().replace(b'\0', b' ').lower()
            with open(exe, 'rb') as f:
                is_elf = f.read(4) == b'\x7fELF'
            forbidden = (b'python', b'node', b'perl', b'ruby', b'socat', b' nc ')
            if is_elf and not any(x in cmdline for x in forbidden):
                native_found = True
        except OSError:
            pass
    assert native_found, 'Port 9090 is not served by a native compiled program'

    stop_pids(old_pids)
    binary = '/tmp/analyze_verified'
    compile_result = subprocess.run(
        ['gcc', '-std=c11', '-O2', source_path, '-lm', '-o', binary],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert compile_result.returncode == 0, f'analyze.c does not compile:\n{compile_result.stderr}'
    assert open(binary, 'rb').read(4) == b'\x7fELF'

    proc = subprocess.Popen([binary], cwd='/home/user', stdout=subprocess.DEVNULL,
                            stderr=subprocess.PIPE)
    try:
        deadline = time.time() + 6
        while time.time() < deadline and not listener_pids(PORT):
            if proc.poll() is not None:
                stderr = proc.stderr.read().decode(errors='replace') if proc.stderr else ''
                raise AssertionError(f'Freshly compiled C server exited early: {stderr}')
            time.sleep(0.05)
        assert listener_pids(PORT), 'Freshly compiled analyze.c did not listen on port 9090'

        # Keep the original exact behavioral assertion and sequential-request check.
        for i in range(2):
            actual = request_metrics()
            assert actual == expected, f'Request {i+1}: expected {expected!r}, got {actual!r}'
    finally:
        stop_pids(listener_pids(PORT))
        if proc.poll() is None:
            proc.kill()
            proc.wait(timeout=2)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
