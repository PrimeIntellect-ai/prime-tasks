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
import glob
import os
import pathlib
import socket
import subprocess
import tempfile
import uuid
import zipfile

import pytest
import requests

DATASET = pathlib.Path('/home/user/dataset')
EXPECTED_FILES = {
    'processed_101.txt': b'data payload A\nVERIFIED\n',
    'processed_202.txt': b'data payload B\nVERIFIED\n',
}


def test_symlinks_cleaned():
    assert not os.path.lexists(DATASET / 'loop1'), '/home/user/dataset/loop1 should have been deleted'
    assert not os.path.lexists(DATASET / 'loop2'), '/home/user/dataset/loop2 should have been deleted'
    assert not os.path.lexists(DATASET / 'broken_link'), '/home/user/dataset/broken_link should have been deleted'


def test_archives_moved_and_valid_archive_preserved():
    bad_old = DATASET / 'archives/bad_data.zip'
    bad_new = DATASET / 'corrupt/bad_data.zip'
    valid = DATASET / 'archives/valid_data.zip'

    assert not bad_old.exists(), 'bad_data.zip should not be in archives directory'
    assert bad_new.is_file(), 'bad_data.zip should be moved to corrupt directory'
    assert bad_new.read_bytes() == b'This is not a valid zip file, it is corrupted data.\n', 'corrupt archive contents changed'

    assert valid.is_file(), 'valid_data.zip must remain in the archives directory'
    with zipfile.ZipFile(valid, 'r') as zf:
        assert zf.testzip() is None, 'valid_data.zip fails its integrity check'
        file_names = sorted(i.filename for i in zf.infolist() if not i.is_dir())
        assert file_names == ['raw_data_101.dat', 'raw_data_202.dat'], 'valid archive entries changed'
        assert zf.read('raw_data_101.dat') == b'data payload A\n'
        assert zf.read('raw_data_202.dat') == b'data payload B\n'


def test_files_renamed_and_modified_exactly():
    extracted = DATASET / 'extracted'
    for name, expected in EXPECTED_FILES.items():
        path = extracted / name
        assert path.is_file(), f'{path} does not exist'
        assert path.read_bytes() == expected, f'{path} did not preserve its payload and append exactly one VERIFIED line'

    assert not glob.glob(str(extracted / '**/raw_data_*.dat'), recursive=True), 'not all raw_data_<ID>.dat files were renamed'


def _decode_rgb(path):
    result = subprocess.run(
        ['ffmpeg', '-v', 'error', '-i', str(path), '-frames:v', '1', '-f', 'rawvideo', '-pix_fmt', 'rgb24', 'pipe:1'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    return result.stdout


def _reference_frame(video, frame_number):
    result = subprocess.run(
        ['ffmpeg', '-v', 'error', '-i', str(video), '-vf', f'select=eq(n\\,{frame_number})',
         '-vsync', '0', '-frames:v', '1', '-f', 'rawvideo', '-pix_fmt', 'rgb24', 'pipe:1'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    return result.stdout


def _mae(a, b):
    assert len(a) == len(b)
    return sum(abs(x - y) for x, y in zip(a, b)) / len(a)


def test_video_frame_extracted_at_two_seconds():
    frame = DATASET / 'video_frame.jpg'
    assert frame.exists(), 'video_frame.jpg was not extracted'
    assert frame.is_file(), 'video_frame.jpg must be a regular file'
    assert frame.stat().st_size > 0, 'video_frame.jpg is empty'
    assert frame.read_bytes()[:2] == b'\xff\xd8', 'video_frame.jpg is not a JPEG image'

    with tempfile.TemporaryDirectory() as td:
        reference_video = pathlib.Path(td) / 'reference.mp4'
        subprocess.run(
            ['ffmpeg', '-v', 'error', '-y', '-f', 'lavfi', '-i',
             'testsrc=duration=5:size=640x480:rate=30', '-c:v', 'libx264', str(reference_video)],
            check=True,
        )
        submitted = _decode_rgb(frame)
        expected_length = 640 * 480 * 3
        assert len(submitted) == expected_length, 'video_frame.jpg must decode to the source video dimensions (640x480)'

        references = {n: _reference_frame(reference_video, n) for n in range(58, 63)}
        assert all(len(raw) == expected_length for raw in references.values())
        errors = {n: _mae(submitted, raw) for n, raw in references.items()}
        assert errors[60] <= 10.0, f'video_frame.jpg does not match the frame at 2 seconds (error {errors[60]:.3f})'
        assert errors[60] == min(errors.values()), f'video_frame.jpg is closer to a neighboring frame than the frame at exactly 2 seconds: {errors}'


def _listening_inodes(port):
    wanted_port = f'{port:04X}'
    inodes = set()
    with open('/proc/net/tcp', 'r') as f:
        next(f)
        for line in f:
            fields = line.split()
            address, found_port = fields[1].split(':')
            if address == '00000000' and found_port == wanted_port and fields[3] == '0A':
                inodes.add(fields[9])
    return inodes


def _scripts_owning(inodes):
    scripts = set()
    for proc in pathlib.Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            owns_socket = any(
                os.readlink(fd).startswith('socket:[') and os.readlink(fd)[8:-1] in inodes
                for fd in (proc / 'fd').iterdir()
            )
            if not owns_socket:
                continue
            args = (proc / 'cmdline').read_bytes().split(b'\0')
            decoded = [arg.decode(errors='replace') for arg in args if arg]
            if decoded and 'python' in os.path.basename(decoded[0]).lower():
                for arg in decoded[1:]:
                    if arg.endswith('.py') and pathlib.Path(arg).is_file():
                        scripts.add(str(pathlib.Path(arg).resolve()))
        except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
            continue
    return scripts


def test_services_are_python_script_bound_to_all_interfaces():
    http_inodes = _listening_inodes(8080)
    tcp_inodes = _listening_inodes(8081)
    assert http_inodes, 'HTTP service is not listening on IPv4 0.0.0.0:8080'
    assert tcp_inodes, 'TCP service is not listening on IPv4 0.0.0.0:8081'
    http_scripts = _scripts_owning(http_inodes)
    tcp_scripts = _scripts_owning(tcp_inodes)
    assert http_scripts, 'HTTP listener is not being run by a written Python script'
    assert tcp_scripts, 'TCP listener is not being run by a written Python script'
    assert http_scripts & tcp_scripts, 'the Python data-service script must expose both requested protocols'


def test_http_service_serves_dataset_generically():
    file_101 = DATASET / 'extracted/processed_101.txt'
    try:
        resp_txt = requests.get('http://127.0.0.1:8080/extracted/processed_101.txt', timeout=5)
        assert resp_txt.status_code == 200, f'HTTP GET /extracted/processed_101.txt returned {resp_txt.status_code}'
        assert resp_txt.content == EXPECTED_FILES['processed_101.txt'], 'HTTP response did not return the exact organized file'

        resp_img = requests.get('http://127.0.0.1:8080/video_frame.jpg', timeout=5)
        assert resp_img.status_code == 200, f'HTTP GET /video_frame.jpg returned {resp_img.status_code}'
        assert resp_img.content == (DATASET / 'video_frame.jpg').read_bytes(), 'HTTP response did not return the actual frame file'

        token = uuid.uuid4().hex
        challenge_dir = DATASET / f'verifier_{token}'
        challenge_file = challenge_dir / 'nested.bin'
        challenge_data = os.urandom(257)
        challenge_dir.mkdir()
        challenge_file.write_bytes(challenge_data)
        try:
            resp_dynamic = requests.get(f'http://127.0.0.1:8080/verifier_{token}/nested.bin', timeout=5)
            assert resp_dynamic.status_code == 200, 'HTTP service does not serve newly created files from the entire dataset tree'
            assert resp_dynamic.content == challenge_data, 'HTTP service changed or fabricated the dynamically requested file'
        finally:
            challenge_file.unlink(missing_ok=True)
            challenge_dir.rmdir()
    except requests.exceptions.RequestException as e:
        pytest.fail(f'HTTP service check failed: {e}')


def _tcp_request(chunks):
    with socket.create_connection(('127.0.0.1', 8081), timeout=5) as s:
        s.settimeout(5)
        for chunk in chunks:
            s.sendall(chunk)
        s.shutdown(socket.SHUT_WR)
        response = bytearray()
        while True:
            part = s.recv(1024)
            if not part:
                break
            response.extend(part)
        return bytes(response)


def test_tcp_service_reports_current_size_and_closes():
    frame = DATASET / 'video_frame.jpg'
    original_size = frame.stat().st_size

    response = _tcp_request([b'GET_FRAME_SIZE', b'\n'])
    assert response == f'{original_size}\n'.encode(), f'TCP service returned {response!r}, expected exact size and newline'

    try:
        with frame.open('ab') as f:
            f.write(b'X')
            f.flush()
            os.fsync(f.fileno())
        changed_size = frame.stat().st_size
        response = _tcp_request([b'GET_', b'FRAME_', b'SIZE\n'])
        assert response == f'{changed_size}\n'.encode(), 'TCP service did not compute the current frame size for each request'
    finally:
        with frame.open('r+b') as f:
            f.truncate(original_size)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
