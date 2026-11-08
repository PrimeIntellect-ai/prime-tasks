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
import hashlib
import os
import secrets
import shutil
import signal
import stat
import subprocess
import time

import requests

SETUP = '/home/user/setup_fs.sh'
LAUNCH = '/home/user/launch.sh'
API = '/home/user/video_api.py'
CACHE = '/home/user/frame_cache'
FRAME = '/home/user/frame_cache/frame_12.jpg'
BASE = 'http://127.0.0.1:9090'
AUTH = {'Authorization': 'Bearer vault-key-2024'}


def listener_pids():
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    address, state, inode = fields[1], fields[3], fields[9]
                    if state != '0A':
                        continue
                    host, port = address.rsplit(':', 1)
                    if int(port, 16) != 9090:
                        continue
                    # The service must use the IPv4 loopback address, not a wildcard.
                    if table.endswith('tcp') and host == '0100007F':
                        inodes.add(inode)
        except FileNotFoundError:
            pass

    pids = set()
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        fd_dir = f'/proc/{name}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    pids.add(int(name))
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def wait_for_health(timeout=15):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.get(BASE + '/health', timeout=1)
            if response.status_code == 200:
                return response
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(0.2)
    raise AssertionError(f'API did not become healthy: {last_error}')


def test_filesystem_preparation():
    for path in (SETUP, LAUNCH, API):
        assert os.path.isfile(path), f'{path} does not exist.'

    for path in (SETUP, LAUNCH):
        mode = os.stat(path).st_mode
        assert mode & stat.S_IXUSR, f'{path} is not executable.'

    assert os.path.isdir(CACHE), f'{CACHE} directory does not exist.'
    assert stat.S_IMODE(os.stat(CACHE).st_mode) == 0o700

    # Verify setup is repeatable and aggressively repairs existing permissions.
    os.chmod(CACHE, 0o777)
    subprocess.run(['runuser', '-u', 'user', '--', SETUP], check=True, timeout=10)
    assert os.path.isdir(CACHE)
    assert stat.S_IMODE(os.stat(CACHE).st_mode) == 0o700
    subprocess.run(['runuser', '-u', 'user', '--', SETUP], check=True, timeout=10)
    assert stat.S_IMODE(os.stat(CACHE).st_mode) == 0o700


def test_launch_script_starts_service_idempotently():
    # Stop the submitted service so launch.sh must actually perform startup.
    for pid in listener_pids():
        os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 8
    while listener_pids() and time.time() < deadline:
        time.sleep(0.1)
    for pid in listener_pids():
        os.kill(pid, signal.SIGKILL)
    time.sleep(0.2)
    assert not listener_pids(), 'Could not stop pre-existing service on port 9090.'

    os.chmod(CACHE, 0o755)
    subprocess.run(['runuser', '-u', 'user', '--', LAUNCH], check=True, timeout=45)
    wait_for_health()
    first = listener_pids()
    assert len(first) == 1, f'Expected one loopback listener on port 9090, got {first}'
    assert stat.S_IMODE(os.stat(CACHE).st_mode) == 0o700, 'launch.sh did not run setup_fs.sh.'
    assert os.path.isfile('/home/user/api.log'), 'launch.sh did not create /home/user/api.log.'

    subprocess.run(['runuser', '-u', 'user', '--', LAUNCH], check=True, timeout=45)
    time.sleep(1)
    second = listener_pids()
    assert second == first, f'Idempotent launch changed the listening process: {first} -> {second}'


def test_api_healthcheck():
    try:
        response = requests.get(BASE + '/health', timeout=5)
    except requests.RequestException as exc:
        assert False, f'Failed to connect to API healthcheck endpoint: {exc}'
    assert response.status_code == 200
    try:
        data = response.json()
    except ValueError:
        assert False, 'Response from /health is not valid JSON.'
    assert data.get('status') == 'running'
    assert data == {'status': 'running'}


def test_api_auth_enforcement():
    for headers in ({}, {'Authorization': 'Bearer wrong-key'},
                    {'Authorization': 'bearer vault-key-2024'}):
        try:
            response = requests.get(BASE + '/frame_hash', headers=headers, timeout=5)
        except requests.RequestException as exc:
            assert False, f'Failed to connect to /frame_hash: {exc}'
        assert response.status_code == 401, (
            f'Expected 401 for unauthorized request, got {response.status_code}')


def test_api_executes_required_ffmpeg_and_hashes_runtime_video():
    source = '/app/dashcam.mp4'
    backup = '/tmp/dashcam.verifier-backup.mp4'
    alternate = '/tmp/dashcam.verifier-alternate.mp4'
    truth_img = '/tmp/truth_frame_12.jpg'
    ffmpeg = '/usr/bin/ffmpeg'
    real_ffmpeg = '/usr/bin/ffmpeg.verifier-real'
    call_log = '/tmp/ffmpeg-verifier-calls.bin'

    for path in (backup, alternate, truth_img, call_log, real_ffmpeg):
        if os.path.lexists(path):
            os.unlink(path)

    # Build an unpredictable video, preventing a fixed digest implementation.
    color = '0x' + secrets.token_hex(3)
    subprocess.run([
        ffmpeg, '-y', '-f', 'lavfi', '-i',
        f'color=c={color}:size=320x240:rate=2:duration=14',
        '-pix_fmt', 'yuv420p', alternate
    ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)

    os.rename(source, backup)
    wrapper_installed = False
    try:
        if os.path.exists(FRAME):
            os.unlink(FRAME)

        # Required robust failure behavior when the input is absent.
        response = requests.get(BASE + '/frame_hash', headers=AUTH, timeout=10)
        assert response.status_code == 500, (
            f'Expected 500 when video is missing, got {response.status_code}')

        shutil.copy2(alternate, source)
        os.chmod(source, 0o644)

        subprocess.run([
            ffmpeg, '-y', '-ss', '00:00:12', '-i', source,
            '-vframes', '1', '-q:v', '2', truth_img
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
        with open(truth_img, 'rb') as f:
            truth_hash = hashlib.sha256(f.read()).hexdigest()

        # Interpose ffmpeg for the request and record the actual argument vector.
        os.rename(ffmpeg, real_ffmpeg)
        with open(call_log, 'wb'):
            pass
        os.chmod(call_log, 0o666)
        with open(ffmpeg, 'w') as f:
            f.write('#!/bin/sh\n')
            f.write("{ printf '__CALL__\\000'; printf '%s\\000' \"$@\"; } >> " + call_log + "\n")
            f.write('exec ' + real_ffmpeg + ' "$@"\n')
        os.chmod(ffmpeg, 0o755)
        wrapper_installed = True

        if os.path.exists(FRAME):
            os.unlink(FRAME)
        request_started = time.time_ns()
        response = requests.get(BASE + '/frame_hash', headers=AUTH, timeout=20)
        assert response.status_code == 200, response.text
        try:
            data = response.json()
        except ValueError:
            assert False, 'Response from /frame_hash is not valid JSON.'
        assert 'hash' in data
        assert data['hash'] == truth_hash, f"Expected {truth_hash}, got {data['hash']}"

        assert os.path.isfile(FRAME), 'The required frame_12.jpg was not generated.'
        assert os.stat(FRAME).st_mtime_ns >= request_started, 'Frame was not freshly extracted.'
        with open(FRAME, 'rb') as f:
            assert hashlib.sha256(f.read()).hexdigest() == truth_hash

        with open(call_log, 'rb') as f:
            fields = f.read().split(b'\0')
        calls = []
        current = None
        for field in fields:
            if field == b'__CALL__':
                if current is not None:
                    calls.append(current)
                current = []
            elif current is not None and field:
                current.append(field.decode())
        if current is not None:
            calls.append(current)

        required = [
            '-y', '-ss', '00:00:12', '-i', '/app/dashcam.mp4',
            '-vframes', '1', '-q:v', '2', '/home/user/frame_cache/frame_12.jpg'
        ]
        assert required in calls, f'Required ffmpeg invocation was not executed; calls were {calls}'
    finally:
        if wrapper_installed:
            try:
                os.unlink(ffmpeg)
            finally:
                os.rename(real_ffmpeg, ffmpeg)
        if os.path.exists(source):
            os.unlink(source)
        if os.path.exists(backup):
            os.rename(backup, source)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
