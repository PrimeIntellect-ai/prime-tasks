#!/bin/bash
mkdir -p /logs/verifier

cat << 'KILL_EOF' > /tmp/kill_port_8080.py
import os
import signal
import time

inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        with open(table) as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) >= 10 and fields[1].endswith(':1F90') and fields[3] == '0A':
                    inodes.add(fields[9])
    except OSError:
        pass

for pid in os.listdir('/proc'):
    if not pid.isdigit():
        continue
    fd_dir = f'/proc/{pid}/fd'
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(os.path.join(fd_dir, fd))
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                try:
                    os.kill(int(pid), signal.SIGTERM)
                except (ProcessLookupError, PermissionError):
                    pass
                break
    except OSError:
        pass

time.sleep(1)
KILL_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import io
import os
import subprocess
import time
import uuid
import zipfile

import pytest
import requests

URL = 'http://127.0.0.1:8080/generate-backup'
VIDEO = '/app/surveillance.mp4'
BACKUP = '/home/user/backup.zip'
FRAME_BYTES = 32 * 24 * 3


def source_frames():
    result = subprocess.run([
        'ffmpeg', '-v', 'error', '-i', VIDEO,
        '-vf', 'scale=32:24', '-pix_fmt', 'rgb24',
        '-f', 'rawvideo', '-vsync', '0', 'pipe:1'
    ], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30, check=True)
    assert len(result.stdout) >= FRAME_BYTES * 61, 'Video did not contain the required frames'
    assert len(result.stdout) % FRAME_BYTES == 0, 'Unexpected decoded video size'
    return [result.stdout[i:i + FRAME_BYTES]
            for i in range(0, len(result.stdout), FRAME_BYTES)]


SOURCE_FRAMES = source_frames()


def decode_jpeg(data):
    result = subprocess.run([
        'ffmpeg', '-v', 'error', '-f', 'image2pipe', '-i', 'pipe:0',
        '-vf', 'scale=32:24', '-frames:v', '1', '-pix_fmt', 'rgb24',
        '-f', 'rawvideo', 'pipe:1'
    ], input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
    assert result.returncode == 0, 'JPEG could not be decoded by ffmpeg'
    assert len(result.stdout) == FRAME_BYTES, 'JPEG did not decode to a complete image'
    return result.stdout


def assert_extracted_frame(jpeg, requested):
    decoded = decode_jpeg(jpeg)
    errors = [sum(abs(a - b) for a, b in zip(decoded, frame)) / FRAME_BYTES
              for frame in SOURCE_FRAMES]
    best = min(range(len(errors)), key=errors.__getitem__)
    # Permit both common conventions: zero-based ffmpeg frame n and human one-based frame number.
    permitted = {requested - 1, requested}
    assert best in permitted, (
        f'frame_{requested}.jpg most closely matches source frame {best}, not frame {requested}'
    )
    assert min(errors[i] for i in permitted) < 12.0, (
        f'frame_{requested}.jpg is not a faithful JPEG extraction of the requested video frame'
    )


def expected_configs(dynamic_name, dynamic_content):
    return {
        'app.conf': b'server=nginx\n',
        'db.conf': b'db=postgres\n',
        dynamic_name: dynamic_content,
    }


def validate_archive(blob, configs, check_frames=True):
    try:
        with zipfile.ZipFile(io.BytesIO(blob)) as z:
            names = z.namelist()
            assert len(names) == len(set(names)), 'Archive contains duplicate paths'
            assert all(name == os.path.basename(name) and '/' not in name and '\\' not in name
                       for name in names), 'All ZIP entries must be at the archive root'

            expected_names = set(configs) | {'header.bin', 'frame_30.jpg', 'frame_60.jpg'}
            assert set(names) == expected_names, (
                f'Archive entries mismatch: expected {sorted(expected_names)}, got {sorted(names)}'
            )

            # Retain the original fixed configuration assertions.
            assert z.read('app.conf').decode('utf-8').strip() == 'server=nginx'
            assert z.read('db.conf').decode('utf-8').strip() == 'db=postgres'
            for name, content in configs.items():
                assert z.read(name) == content, f'{name} content mismatch'

            header = z.read('header.bin')
            assert len(header) == 24, f'Expected header.bin to be exactly 24 bytes, got {len(header)}'
            with open(VIDEO, 'rb') as vf:
                assert header == vf.read(24), 'header.bin does not match the first 24 video bytes'

            frame30 = z.read('frame_30.jpg')
            frame60 = z.read('frame_60.jpg')
            assert frame30 and frame30.startswith(b'\xff\xd8'), 'frame_30.jpg is not a JPEG'
            assert frame60 and frame60.startswith(b'\xff\xd8'), 'frame_60.jpg is not a JPEG'
            if check_frames:
                assert_extracted_frame(frame30, 30)
                assert_extracted_frame(frame60, 60)
    except zipfile.BadZipFile:
        pytest.fail('Response body is not a valid ZIP archive')


def wait_for_server():
    response = None
    for _ in range(30):
        try:
            response = requests.get(URL, timeout=10)
            if response.status_code == 200:
                return response
        except requests.RequestException:
            pass
        time.sleep(1)
    assert response is not None, 'Failed to connect to the server or no response received'
    assert response.status_code == 200, f'Expected HTTP 200, got {response.status_code}'


def test_server_generates_backup_and_handles_concurrency():
    # First request proves the freshly built submitted Go artifact is serving.
    initial = wait_for_server()
    assert initial.status_code == 200
    initial_type = initial.headers.get('Content-Type', '')
    assert 'application/zip' in initial_type or 'application/x-zip-compressed' in initial_type

    # Add an unpredictable nested configuration after the first generation. A fixed ZIP response
    # cannot pass, and the existing and new back-links exercise loop-safe traversal.
    token = uuid.uuid4().hex
    dynamic_name = f'audit_{token}.conf'
    dynamic_content = f'audit-token={token}\n'.encode()
    dynamic_dir = f'/app/configs/audit_{token}'
    os.makedirs(dynamic_dir)
    dynamic_path = os.path.join(dynamic_dir, dynamic_name)
    with open(dynamic_path, 'wb') as f:
        f.write(dynamic_content)
    os.symlink('/app/configs', os.path.join(dynamic_dir, 'loop_to_root'))
    configs = expected_configs(dynamic_name, dynamic_content)

    def request_backup(_):
        return requests.get(URL, timeout=60)

    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        responses = list(pool.map(request_backup, range(6)))

    for response in responses:
        assert response.status_code == 200, f'Expected HTTP 200, got {response.status_code}'
        content_type = response.headers.get('Content-Type', '')
        assert 'application/zip' in content_type or 'application/x-zip-compressed' in content_type, \
            f'Expected Content-Type application/zip, got {content_type}'
        validate_archive(response.content, configs, check_frames=True)

    assert os.path.isfile(BACKUP), f'{BACKUP} was not created on disk'
    assert os.path.getsize(BACKUP) > 0, f'{BACKUP} is empty'
    with open(BACKUP, 'rb') as f:
        validate_archive(f.read(), configs, check_frames=True)
TEST_EOF

status=1
server_pid=''
if test -f /home/user/server.go && test -s /home/user/server.go \
   && go build -o /tmp/submitted_backup_server /home/user/server.go \
   && python3 /tmp/kill_port_8080.py; then
    /tmp/submitted_backup_server >/tmp/submitted_backup_server.log 2>&1 &
    server_pid=$!
    if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
        status=0
    fi
fi

if [ -n "$server_pid" ]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
