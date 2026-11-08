#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import hashlib
import os
import signal
import socket
import subprocess
import tempfile
import time

import pytest

HOST = '127.0.0.1'
PORT = 8888
VIDEO_PATH = '/app/deployment_feed.mp4'
FRAMES_DIR = '/home/user/frames'
SOURCE_PATH = '/home/user/streamer.c'
STREAMER_PATH = '/home/user/streamer'


@pytest.fixture(scope='module')
def truth_frames():
    temp_dir = tempfile.mkdtemp()
    cmd = [
        'ffmpeg', '-y', '-i', VIDEO_PATH,
        '-vf', 'fps=1',
        os.path.join(temp_dir, 'frame_%04d.jpg')
    ]
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)

    frames = {}
    for filename in os.listdir(temp_dir):
        if filename.startswith('frame_') and filename.endswith('.jpg'):
            frame_num = filename[6:10]
            filepath = os.path.join(temp_dir, filename)
            with open(filepath, 'rb') as f:
                frames[frame_num] = f.read()
    return frames


def listener_pids():
    inodes = set()
    try:
        with open('/proc/net/tcp', 'r') as f:
            for line in f.readlines()[1:]:
                fields = line.split()
                if len(fields) >= 10 and fields[1] == '0100007F:22B8' and fields[3] == '0A':
                    inodes.add(fields[9])
    except FileNotFoundError:
        return set()

    pids = set()
    for proc_dir in glob.glob('/proc/[0-9]*'):
        pid = int(os.path.basename(proc_dir))
        for fd in glob.glob(os.path.join(proc_dir, 'fd', '*')):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                pids.add(pid)
                break
    return pids


def pid_runs_file(pid, path):
    try:
        return os.path.samefile(f'/proc/{pid}/exe', path)
    except OSError:
        return False


def wait_for_listener(timeout=5.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if listener_pids():
            return True
        time.sleep(0.05)
    return False


def wait_for_no_listener(timeout=5.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if not listener_pids():
            return True
        time.sleep(0.05)
    return False


def send_request_and_read_response(request_str):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(5.0)
        s.connect((HOST, PORT))
        s.sendall(request_str.encode('ascii'))

        header = b''
        while b'\n' not in header:
            chunk = s.recv(1)
            if not chunk:
                break
            header += chunk
            if len(header) > 100:
                break

        if not header.endswith(b'\n'):
            return header, b''

        header_str = header.decode('ascii').strip()
        body = b''
        if header_str.startswith('OK '):
            try:
                size = int(header_str.split(' ')[1])
            except (ValueError, IndexError):
                return header_str, b''

            while len(body) < size:
                chunk = s.recv(min(4096, size - len(body)))
                if not chunk:
                    break
                body += chunk

        # Every response must contain exactly the declared bytes and then close.
        tail = s.recv(1)
        assert tail == b'', 'Server did not close the connection or sent extra response bytes.'
        return header_str, body


def assert_valid_response(frame_num, expected_data):
    header, body = send_request_and_read_response(f'{frame_num}\n')
    assert header.startswith('OK '), f'Expected OK header, got: {header}'
    parts = header.split(' ')
    assert len(parts) == 2, f'Malformed OK header: {header}'
    assert parts[0] == 'OK', f'Malformed OK header: {header}'
    assert parts[1].isdigit(), f'Malformed size in header: {header}'
    assert int(parts[1]) == len(expected_data), f'Expected size {len(expected_data)}, got {parts[1]}'
    assert len(body) == len(expected_data), f'Expected body length {len(expected_data)}, got {len(body)}'
    assert body == expected_data, f'Returned data for frame {frame_num} differs from the video extraction.'


def test_frames_extracted_correctly(truth_frames):
    assert os.path.exists(FRAMES_DIR), f'Directory {FRAMES_DIR} does not exist.'
    assert os.path.isdir(FRAMES_DIR), f'{FRAMES_DIR} is not a directory.'
    assert truth_frames, 'No truth frames extracted.'

    for frame_num, truth_data in truth_frames.items():
        user_frame_path = os.path.join(FRAMES_DIR, f'frame_{frame_num}.jpg')
        assert os.path.exists(user_frame_path), f'Expected frame {user_frame_path} not found.'
        assert os.path.isfile(user_frame_path), f'{user_frame_path} is not a regular file.'
        with open(user_frame_path, 'rb') as f:
            user_data = f.read()
        assert len(user_data) > 0, f'Frame {user_frame_path} is empty.'
        assert user_data == truth_data, f'Frame {user_frame_path} does not match the required ffmpeg extraction.'


def test_tcp_server_valid_frame(truth_frames):
    assert truth_frames, 'No truth frames extracted.'

    for frame_num in sorted(truth_frames):
        expected_data = truth_frames[frame_num]
        try:
            header, body = send_request_and_read_response(f'{frame_num}\n')
        except ConnectionRefusedError:
            pytest.fail(f'Could not connect to {HOST}:{PORT}. Is the server running?')
        except socket.timeout:
            pytest.fail('Server connection or read timed out.')

        assert header.startswith('OK '), f'Expected OK header, got: {header}'
        parts = header.split(' ')
        assert len(parts) == 2, f'Malformed OK header: {header}'
        assert int(parts[1]) == len(expected_data), f'Expected size {len(expected_data)}, got {parts[1]}'
        assert len(body) == len(expected_data), f'Expected body length {len(expected_data)}, got {len(body)}'

        expected_hash = hashlib.sha256(expected_data).hexdigest()
        actual_hash = hashlib.sha256(body).hexdigest()
        assert actual_hash == expected_hash, f'Returned frame {frame_num} has the wrong checksum.'

        user_frame_path = f'{FRAMES_DIR}/frame_{frame_num}.jpg'
        with open(user_frame_path, 'rb') as f:
            user_data = f.read()
        assert body == user_data, 'Returned binary data does not match the frame file on disk.'
        assert body == expected_data, 'Returned binary data does not match the verifier extraction.'


def test_tcp_server_invalid_frame():
    try:
        header, body = send_request_and_read_response('9999\n')
    except ConnectionRefusedError:
        pytest.fail(f'Could not connect to {HOST}:{PORT}. Is the server running?')
    except socket.timeout:
        pytest.fail('Server connection or read timed out.')

    assert header == 'ERR', f'Expected ERR response, got: {header}'
    assert body == b'', 'Expected no body for ERR response.'


def test_tcp_server_malformed_request():
    for request in ('abc\n', '12345\n', '12 3\n', '0001x\n', '\n'):
        try:
            header, body = send_request_and_read_response(request)
        except ConnectionRefusedError:
            pytest.fail(f'Could not connect to {HOST}:{PORT}. Is the server running?')
        except socket.timeout:
            pytest.fail('Server connection or read timed out.')

        assert header == 'ERR', f'Expected ERR response for malformed input {request!r}, got: {header}'
        assert body == b'', 'Expected no body for ERR response.'


def test_streamer_is_the_compiled_c_service(truth_frames):
    assert os.path.isfile(SOURCE_PATH), f'{SOURCE_PATH} does not exist or is not a regular file.'
    assert os.path.isfile(STREAMER_PATH), f'{STREAMER_PATH} does not exist or is not a regular file.'
    assert os.access(STREAMER_PATH, os.X_OK), f'{STREAMER_PATH} is not executable.'
    with open(STREAMER_PATH, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f'{STREAMER_PATH} is not a compiled ELF executable.'

    running = listener_pids()
    assert running, f'No process is listening on {HOST}:{PORT}.'
    matching = {pid for pid in running if pid_runs_file(pid, STREAMER_PATH)}
    assert matching, f'The listener on {HOST}:{PORT} is not {STREAMER_PATH}.'

    # Recompile and execute the submitted C source to ensure the source itself
    # implements the tested service rather than merely accompanying another server.
    with tempfile.TemporaryDirectory() as temp_dir:
        rebuilt = os.path.join(temp_dir, 'streamer-rebuilt')
        result = subprocess.run(
            ['gcc', '-O2', '-o', rebuilt, SOURCE_PATH],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        assert result.returncode == 0, f'Failed to compile {SOURCE_PATH}: {result.stderr}'

        for pid in matching:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        assert wait_for_no_listener(), 'The submitted streamer did not stop cleanly for source verification.'

        rebuilt_proc = None
        try:
            rebuilt_proc = subprocess.Popen(
                [rebuilt], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                start_new_session=True
            )
            assert wait_for_listener(), 'The executable rebuilt from streamer.c did not start listening.'
            rebuilt_listeners = listener_pids()
            assert any(pid_runs_file(pid, rebuilt) for pid in rebuilt_listeners), \
                'The executable rebuilt from streamer.c is not the listening service.'

            for frame_num, expected_data in sorted(truth_frames.items()):
                assert_valid_response(frame_num, expected_data)
            header, body = send_request_and_read_response('9999\n')
            assert header == 'ERR', f'Rebuilt C server returned {header!r} for a missing frame.'
            assert body == b'', 'Rebuilt C server returned a body for ERR.'
            header, body = send_request_and_read_response('abc\n')
            assert header == 'ERR', f'Rebuilt C server returned {header!r} for malformed input.'
            assert body == b'', 'Rebuilt C server returned a body for malformed input.'
        finally:
            if rebuilt_proc is not None and rebuilt_proc.poll() is None:
                rebuilt_proc.terminate()
                try:
                    rebuilt_proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    rebuilt_proc.kill()
                    rebuilt_proc.wait(timeout=3)
            wait_for_no_listener()
            subprocess.Popen(
                [STREAMER_PATH], cwd='/home/user',
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                start_new_session=True
            )
            assert wait_for_listener(), 'The deployed streamer could not be restarted after verification.'
            assert any(pid_runs_file(pid, STREAMER_PATH) for pid in listener_pids()), \
                'The restarted listener is not /home/user/streamer.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
