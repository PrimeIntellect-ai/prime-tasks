#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import io
import json
import os
import signal
import socket
import tarfile
import threading
import time
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest


def test_analytics_score():
    url = "http://127.0.0.1:5001/score"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=5) as response:
            data = json.loads(response.read().decode("utf-8"))
            score = float(data.get("score", 0.0))
    except Exception as e:
        pytest.fail(
            f"Failed to fetch score from analytics service at {url}: {e}\n"
            "Ensure that your Rust worker is running, processed the archives, "
            "and reported the results to the Analytics Service."
        )
    assert score >= 1.0, f"Metric threshold not met: expected score >= 1.0, but got {score}"


def test_organizer_project_exists():
    assert os.path.isdir('/home/user/organizer'), (
        "The Rust project directory /home/user/organizer/ does not exist. "
        "Did you create your Rust program in the correct location?"
    )


def test_projects_extracted():
    projects_dir = '/home/user/projects'
    assert os.path.isdir(projects_dir), f"The extraction directory {projects_dir} does not exist."
    contents = os.listdir(projects_dir)
    assert len(contents) > 0, (
        f"No extracted projects found in {projects_dir}. "
        "Your worker should extract the tar files into this directory."
    )


def test_rust_worker_present_and_running():
    sources = glob.glob('/home/user/organizer/**/*.rs', recursive=True)
    assert any(os.path.isfile(p) and os.path.getsize(p) > 0 for p in sources), (
        "No nonempty Rust source file was found under /home/user/organizer."
    )

    running = False
    organizer = os.path.realpath('/home/user/organizer') + os.sep
    for proc in glob.glob('/proc/[0-9]*'):
        try:
            exe = os.path.realpath(os.readlink(os.path.join(proc, 'exe')))
            cwd = os.path.realpath(os.readlink(os.path.join(proc, 'cwd')))
            with open(exe, 'rb') as f:
                is_elf = f.read(4) == b'\x7fELF'
            if is_elf and (exe.startswith(organizer) or cwd.startswith(organizer)):
                running = True
                break
        except (OSError, PermissionError):
            continue
    assert running, "No running ELF worker associated with /home/user/organizer was found."


reports = []
report_event = threading.Event()


class ReportHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != '/report':
            self.send_response(404)
            self.end_headers()
            return
        try:
            length = int(self.headers.get('Content-Length', '0'))
            data = json.loads(self.rfile.read(length).decode('utf-8'))
            reports.append(data)
            report_event.set()
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'OK')
        except Exception:
            self.send_response(400)
            self.end_headers()

    def log_message(self, fmt, *args):
        pass


def listener_inodes(port):
    wanted = f'{port:04X}'
    result = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].split(':')[-1].upper() == wanted and fields[3] == '0A':
                        result.add(fields[9])
        except OSError:
            pass
    return result


def stop_port_listeners(port):
    inodes = listener_inodes(port)
    if not inodes:
        return
    victims = set()
    for proc in glob.glob('/proc/[0-9]*'):
        pid = int(proc.rsplit('/', 1)[1])
        for fd in glob.glob(proc + '/fd/*'):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                victims.add(pid)
                break
    for pid in victims:
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    time.sleep(0.5)
    for pid in victims:
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def add_regular(tar, name, data):
    info = tarfile.TarInfo(name)
    info.size = len(data)
    info.mode = 0o644
    tar.addfile(info, io.BytesIO(data))


def files_under(path):
    found = []
    if os.path.isdir(path):
        for root, _, names in os.walk(path):
            for name in names:
                full = os.path.join(root, name)
                if os.path.isfile(full):
                    found.append(full)
    return found


def test_fresh_archive_is_really_processed_safely_and_reported():
    stop_port_listeners(5001)

    class ReusableHTTPServer(HTTPServer):
        allow_reuse_address = True

    server = ReusableHTTPServer(('127.0.0.1', 5001), ReportHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    token = uuid.uuid4().hex
    archive_name = f'verifier_{token}.tar'
    stem = archive_name[:-4]
    incoming = '/home/user/incoming'
    project = os.path.join('/home/user/projects', stem)
    outside_relative = f'/tmp/organizer_escape_{token}'
    outside_absolute = f'/tmp/organizer_absolute_{token}'

    for path in (outside_relative, outside_absolute):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
    if os.path.exists(project):
        pytest.fail(f'Fresh randomized project path unexpectedly already exists: {project}')

    bin_data = b'\x7fELF' + os.urandom(24)
    src1_data = f'fresh UTF-8 source {token}\n'.encode()
    src2_data = 'another valid UTF-8 file: café\n'.encode('utf-8')
    db_data = b'SQLite format 3\x00' + os.urandom(24)
    wal_data = os.urandom(32)
    evil_data = f'escape-{token}'.encode()

    os.makedirs(incoming, exist_ok=True)
    temporary = os.path.join(incoming, f'.{archive_name}.partial')
    final_path = os.path.join(incoming, archive_name)
    with tarfile.open(temporary, 'w') as tar:
        add_regular(tar, 'native_program', bin_data)
        add_regular(tar, 'first_source', src1_data)
        add_regular(tar, 'nested/second_source.txt', src2_data)
        add_regular(tar, 'database_payload', db_data)
        add_regular(tar, 'journal.wal', wal_data)
        add_regular(tar, f'../../../../tmp/organizer_escape_{token}', evil_data)
        add_regular(tar, outside_absolute, evil_data)
    os.rename(temporary, final_path)

    expected_report = {
        'archive': archive_name,
        'extracted_bin': 1,
        'extracted_src': 2,
        'extracted_db': 2,
        'ignored_malicious': 2,
    }

    deadline = time.time() + 35
    matching_report = None
    while time.time() < deadline:
        matching_report = next((r for r in reports if r.get('archive') == archive_name), None)
        category_files = sum(
            (files_under(os.path.join(project, category)) for category in ('bin', 'src', 'db')),
            [],
        )
        if matching_report is not None and len(category_files) >= 5:
            break
        report_event.wait(0.25)
        report_event.clear()

    try:
        assert os.path.isdir(project), "The running worker did not create the randomized project directory."
        assert matching_report is not None, "The worker did not report the randomized archive."
        for key, value in expected_report.items():
            assert matching_report.get(key) == value, (
                f"Incorrect report field {key}: expected {value!r}, got {matching_report.get(key)!r}"
            )

        expected = {
            'bin': {'native_program': bin_data},
            'src': {'first_source': src1_data, 'second_source.txt': src2_data},
            'db': {'database_payload': db_data, 'journal.wal': wal_data},
        }
        categorized = set()
        for category, wanted in expected.items():
            actual_files = files_under(os.path.join(project, category))
            assert len(actual_files) == len(wanted), (
                f"Expected {len(wanted)} files in {category}/, found {len(actual_files)}"
            )
            actual = {}
            for path in actual_files:
                with open(path, 'rb') as f:
                    actual[os.path.basename(path)] = f.read()
                categorized.add(os.path.realpath(path))
            assert actual == wanted, f"Files in {category}/ were not categorized correctly."

        all_project_files = set(files_under(project))
        assert all_project_files == categorized, "Safe files were left outside bin/, src/, or db/."
        assert not os.path.exists(outside_relative), "A relative tar-slip entry escaped the project directory."
        assert not os.path.exists(outside_absolute), "An absolute tar-slip entry escaped the project directory."
    finally:
        server.shutdown()
        server.server_close()


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
