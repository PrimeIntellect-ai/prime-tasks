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
import hashlib
import json
import os
import re
import shutil
import signal
import subprocess
import tempfile
import time

import pytest
import requests

FRAMES_DIR = '/home/user/data/frames'
PROJECT_DIR = '/home/user/frame_service'
SERVICE_URL = 'http://127.0.0.1:9090/metrics'


def test_active_mounts():
    """Verify /home/user/active_mounts.txt contains correct mount points."""
    fstab_path = '/app/fstab.mock'
    output_path = '/home/user/active_mounts.txt'

    assert os.path.isfile(output_path), f"Missing {output_path}"

    expected_mounts = []
    if os.path.isfile(fstab_path):
        with open(fstab_path, 'r') as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) >= 3 and parts[2] in ['ext4', 'xfs']:
                    expected_mounts.append(parts[1])

    with open(output_path, 'r') as f:
        actual_mounts = [line.strip() for line in f if line.strip()]

    assert sorted(actual_mounts) == sorted(expected_mounts), "active_mounts.txt does not contain the correct mount points"


def _extract_reference_frames(destination):
    subprocess.run([
        'ffmpeg', '-hide_banner', '-loglevel', 'error', '-y',
        '-i', '/app/test_video.mp4', '-vf', 'fps=2',
        os.path.join(destination, 'frame_%04d.jpg')
    ], check=True, timeout=60)
    return sorted(glob.glob(os.path.join(destination, 'frame_*.jpg')))


def get_expected_frame_count():
    with tempfile.TemporaryDirectory() as tmpdir:
        return len(_extract_reference_frames(tmpdir))


def _decode_rgb(path):
    return subprocess.check_output([
        'ffmpeg', '-hide_banner', '-loglevel', 'error', '-i', path,
        '-frames:v', '1', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'
    ], timeout=20)


def test_extracted_frames():
    """Verify the complete 2 fps JPEG sequence was extracted from the supplied video."""
    assert os.path.isdir(FRAMES_DIR), f"Directory {FRAMES_DIR}/ does not exist"

    frames = sorted(glob.glob(os.path.join(FRAMES_DIR, 'frame_*.jpg')))
    assert len(frames) > 0, "No frames extracted"

    expected_count = get_expected_frame_count()
    expected_names = [f'frame_{i:04d}.jpg' for i in range(1, expected_count + 1)]
    actual_names = [os.path.basename(path) for path in frames]
    assert actual_names == expected_names, "Frame count or frame_%04d.jpg numbering does not match 2 fps extraction"

    with tempfile.TemporaryDirectory() as tmpdir:
        references = _extract_reference_frames(tmpdir)
        assert len(frames) == len(references) == expected_count
        for submitted, reference in zip(frames, references):
            with open(submitted, 'rb') as f:
                assert f.read(2) == b'\xff\xd8', f"{submitted} is not a JPEG image"
            submitted_rgb = _decode_rgb(submitted)
            reference_rgb = _decode_rgb(reference)
            assert len(submitted_rgb) == len(reference_rgb) and len(submitted_rgb) > 0, "Extracted frame dimensions are incorrect"
            mean_error = sum(abs(a - b) for a, b in zip(submitted_rgb, reference_rgb)) / len(reference_rgb)
            assert mean_error < 20.0, f"{submitted} does not correspond to the expected source-video frame"


def _listener_pids(port=9090):
    inodes = set()
    wanted = f'{port:04X}'
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[1].rsplit(':', 1)[-1].upper() == wanted and fields[3] == '0A':
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for proc in glob.glob('/proc/[0-9]*'):
        pid = int(proc.rsplit('/', 1)[-1])
        try:
            for fd in os.listdir(os.path.join(proc, 'fd')):
                try:
                    target = os.readlink(os.path.join(proc, 'fd', fd))
                except OSError:
                    continue
                match = re.fullmatch(r'socket:\[(\d+)\]', target)
                if match and match.group(1) in inodes:
                    pids.add(pid)
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return pids


def _stop_existing_listener():
    pids = _listener_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 5
    while time.time() < deadline and _listener_pids():
        time.sleep(0.1)
    for pid in _listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and _listener_pids():
        time.sleep(0.1)
    assert not _listener_pids(), "Could not stop the pre-existing listener on port 9090"


def test_run_sh_exists():
    """Verify run.sh exists and is executable."""
    script_path = '/home/user/run.sh'
    assert os.path.isfile(script_path), f"Missing {script_path}"
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable"


def test_rust_project_and_run_script_launches_it():
    """Build the Cargo project, then require run.sh to launch its Rust binary."""
    manifest = os.path.join(PROJECT_DIR, 'Cargo.toml')
    source_dir = os.path.join(PROJECT_DIR, 'src')
    assert os.path.isfile(manifest), "Missing Rust Cargo.toml"
    assert os.path.isdir(source_dir), "Missing Rust src directory"
    rust_sources = glob.glob(os.path.join(source_dir, '**', '*.rs'), recursive=True)
    assert rust_sources, "Rust project contains no .rs source files"

    metadata_run = subprocess.run(
        ['cargo', 'metadata', '--format-version', '1', '--no-deps', '--manifest-path', manifest],
        cwd=PROJECT_DIR, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert metadata_run.returncode == 0, f"Invalid Cargo project: {metadata_run.stderr}"
    metadata = json.loads(metadata_run.stdout)
    bin_names = {
        target['name']
        for package in metadata.get('packages', [])
        for target in package.get('targets', [])
        if 'bin' in target.get('kind', [])
    }
    assert bin_names, "Cargo project has no binary target"

    build = subprocess.run(
        ['cargo', 'build', '--manifest-path', manifest], cwd=PROJECT_DIR,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120
    )
    assert build.returncode == 0, f"Rust project does not compile: {build.stderr}"

    _stop_existing_listener()
    started = subprocess.run(
        ['/home/user/run.sh'], cwd='/home/user', text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60
    )
    assert started.returncode == 0, f"run.sh failed: {started.stderr}"

    deadline = time.time() + 30
    pids = set()
    while time.time() < deadline:
        pids = _listener_pids()
        if pids:
            break
        time.sleep(0.25)
    assert pids, "run.sh did not start a listener on 127.0.0.1:9090"

    target_dir = os.path.realpath(metadata['target_directory'])
    valid_process = False
    for pid in pids:
        try:
            executable = os.path.realpath(f'/proc/{pid}/exe')
        except OSError:
            continue
        if os.path.commonpath([target_dir, executable]) == target_dir and os.path.basename(executable) in bin_names:
            valid_process = True
            break
    assert valid_process, "The port 9090 listener is not a binary produced by the submitted Cargo project"


def _request(headers=None):
    try:
        return requests.get(SERVICE_URL, headers=headers or {}, timeout=3)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to microservice: {exc}")


def test_rust_microservice_http():
    """Verify authentication, exact JSON, dynamic counting, and per-request logs."""
    log_path = '/home/user/logs/microservice.log'
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    if not os.path.exists(log_path):
        open(log_path, 'a').close()
    initial_size = os.path.getsize(log_path)

    resp_unauth = _request({'X-Service-Auth': 'wrong-token'})
    assert resp_unauth.status_code == 401, f"Expected 401 Unauthorized, got {resp_unauth.status_code}"

    resp_missing = _request()
    assert resp_missing.status_code == 401, f"Expected 401 Unauthorized for missing auth, got {resp_missing.status_code}"

    resp_auth = _request({'X-Service-Auth': 'v1-alpha-xyz'})
    assert resp_auth.status_code == 200, f"Expected 200 OK, got {resp_auth.status_code}"
    try:
        data = resp_auth.json()
    except ValueError:
        pytest.fail("Response is not valid JSON")
    assert data.get('fps') == 2, "JSON response 'fps' should be 2"

    actual_frames = len(glob.glob(os.path.join(FRAMES_DIR, 'frame_*.jpg')))
    assert data.get('extracted_frames') == actual_frames, f"JSON 'extracted_frames' should be {actual_frames}"
    expected_body = f'{{"fps": 2, "extracted_frames": {actual_frames}}}'
    assert resp_auth.text == expected_body, "Authenticated response body is not in the exact required format"

    sentinel = os.path.join(FRAMES_DIR, f'verifier_dynamic_{os.getpid()}_{time.time_ns()}')
    try:
        with open(sentinel, 'wb') as f:
            f.write(os.urandom(31))
        all_files = sum(
            1 for name in os.listdir(FRAMES_DIR)
            if os.path.isfile(os.path.join(FRAMES_DIR, name))
        )
        changed = _request({'X-Service-Auth': 'v1-alpha-xyz'})
        assert changed.status_code == 200
        assert changed.text == f'{{"fps": 2, "extracted_frames": {all_files}}}', "Service does not dynamically count all files currently in the frames directory"
    finally:
        if os.path.exists(sentinel):
            os.unlink(sentinel)

    deadline = time.time() + 3
    new_log = ''
    while time.time() < deadline:
        with open(log_path, 'r', errors='replace') as f:
            f.seek(initial_size)
            new_log = f.read()
        entries = re.findall(r'^\[[^\]\r\n]+\] GET /metrics (401|200)$', new_log, re.MULTILINE)
        if entries.count('401') >= 2 and entries.count('200') >= 2:
            break
        time.sleep(0.1)
    assert entries.count('401') >= 2 and entries.count('200') >= 2, "Not every verification request was logged in the required format with its status"
    assert _listener_pids(), "Microservice stopped instead of listening continuously"


def _strip_logrotate_comments(content):
    lines = []
    for raw in content.splitlines():
        line = raw.split('#', 1)[0].strip()
        if line:
            lines.append(line)
    return lines


def test_logrotate_conf():
    """Verify logrotate directives are active, structured, and syntactically valid."""
    conf_path = '/home/user/logrotate.conf'
    assert os.path.isfile(conf_path), f"Missing {conf_path}"

    with open(conf_path, 'r') as f:
        content = f.read()

    # Preserve the original assertions.
    assert '/home/user/logs/microservice.log' in content, "Log file path missing in logrotate.conf"
    assert 'size 1M' in content or 'size=1M' in content or '1M' in content, "Size 1M missing in logrotate.conf"
    assert 'rotate 3' in content, "rotate 3 missing in logrotate.conf"
    assert 'compress' in content, "compress missing in logrotate.conf"
    assert 'create 0644 user user' in content or 'create 644 user user' in content, "create permissions missing in logrotate.conf"

    lines = _strip_logrotate_comments(content)
    assert lines, "logrotate.conf contains no active configuration"
    assert lines[0] in ('/home/user/logs/microservice.log {', '"/home/user/logs/microservice.log" {'), "Expected a logrotate block specifically for microservice.log"
    assert lines[-1] == '}', "logrotate block is not properly closed"
    assert sum(line.count('{') for line in lines) == 1 and sum(line.count('}') for line in lines) == 1, "Malformed logrotate braces"

    directives = lines[1:-1]
    assert any(re.fullmatch(r'size\s+1M', line, re.IGNORECASE) for line in directives), "Active size 1M directive missing"
    assert any(re.fullmatch(r'rotate\s+3', line) for line in directives), "Active rotate 3 directive missing"
    assert any(re.fullmatch(r'compress', line) for line in directives), "Active compress directive missing"
    assert any(re.fullmatch(r'create\s+0?644\s+user\s+user', line) for line in directives), "Active create 0644 user user directive missing"

    logrotate = shutil.which('logrotate')
    if logrotate:
        with tempfile.NamedTemporaryFile() as state:
            checked = subprocess.run(
                [logrotate, '--debug', '--state', state.name, conf_path],
                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20
            )
        assert checked.returncode == 0, f"Invalid logrotate configuration:\n{checked.stdout}"
    else:
        simple = [
            r'size\s+\S+', r'rotate\s+\d+', r'compress', r'nocompress',
            r'create(?:\s+\S+){0,3}', r'missingok', r'notifempty', r'ifempty',
            r'copytruncate', r'nocopytruncate', r'daily', r'weekly', r'monthly',
            r'yearly', r'hourly', r'delaycompress', r'nodelaycompress',
            r'dateext', r'nodateext', r'sharedscripts', r'nosharedscripts',
            r'su\s+\S+\s+\S+', r'extension\s+\S+', r'addextension\s+\S+',
            r'olddir\s+\S+', r'maxage\s+\d+', r'minage\s+\d+',
            r'minsize\s+\S+', r'maxsize\s+\S+'
        ]
        for directive in directives:
            assert any(re.fullmatch(pattern, directive, re.IGNORECASE) for pattern in simple), f"Malformed or unsupported logrotate directive: {directive}"


def test_microservice_log_exists():
    """Verify microservice.log exists and has entries."""
    log_path = '/home/user/logs/microservice.log'
    assert os.path.isfile(log_path), f"Missing {log_path}"

    with open(log_path, 'r') as f:
        content = f.read()
        assert "GET" in content and "/metrics" in content, "Log file does not contain expected HTTP request entries"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
