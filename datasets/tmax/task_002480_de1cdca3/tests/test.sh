#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'WRAPPER_EOF' > /tmp/run_instrumented.py
import builtins
import io
import json
import os
import runpy
import sys

script, input_dir, report = sys.argv[1:4]
input_dir = os.path.realpath(input_dir)
full_reads = set()
fd_paths = {}

real_builtin_open = builtins.open
real_io_open = io.open
real_os_open = os.open
real_os_read = os.read
real_os_fdopen = os.fdopen

def tracked_path(path):
    try:
        path = os.path.realpath(os.fspath(path))
    except (TypeError, ValueError):
        return None
    if os.path.dirname(path) == input_dir and os.path.isfile(path):
        return path
    return None

class TrackedFile:
    def __init__(self, wrapped, path):
        self._wrapped = wrapped
        self._path = path

    def _check_eof(self, data=None):
        try:
            if data in ('', b'') or self._wrapped.tell() >= os.path.getsize(self._path):
                full_reads.add(self._path)
        except (OSError, ValueError):
            pass

    def read(self, *args, **kwargs):
        data = self._wrapped.read(*args, **kwargs)
        self._check_eof(data)
        return data

    def readline(self, *args, **kwargs):
        data = self._wrapped.readline(*args, **kwargs)
        self._check_eof(data)
        return data

    def readlines(self, *args, **kwargs):
        data = self._wrapped.readlines(*args, **kwargs)
        self._check_eof()
        return data

    def __iter__(self):
        return self

    def __next__(self):
        try:
            data = next(self._wrapped)
        except StopIteration:
            full_reads.add(self._path)
            raise
        self._check_eof(data)
        return data

    def __enter__(self):
        self._wrapped.__enter__()
        return self

    def __exit__(self, *args):
        return self._wrapped.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._wrapped, name)

def wrap_open(real_open):
    def replacement(file, mode='r', *args, **kwargs):
        wrapped = real_open(file, mode, *args, **kwargs)
        path = tracked_path(file)
        if path is not None and ('r' in mode or '+' in mode):
            return TrackedFile(wrapped, path)
        return wrapped
    return replacement

def replacement_os_open(path, flags, *args, **kwargs):
    fd = real_os_open(path, flags, *args, **kwargs)
    candidate = tracked_path(path)
    access_mode = flags & os.O_ACCMODE
    if candidate is not None and access_mode in (os.O_RDONLY, os.O_RDWR):
        fd_paths[fd] = candidate
    return fd

def replacement_os_read(fd, size):
    data = real_os_read(fd, size)
    path = fd_paths.get(fd)
    if path is not None:
        try:
            if data == b'' or os.lseek(fd, 0, os.SEEK_CUR) >= os.path.getsize(path):
                full_reads.add(path)
        except OSError:
            pass
    return data

def replacement_os_fdopen(fd, *args, **kwargs):
    wrapped = real_os_fdopen(fd, *args, **kwargs)
    path = fd_paths.get(fd)
    if path is not None:
        return TrackedFile(wrapped, path)
    return wrapped

builtins.open = wrap_open(real_builtin_open)
io.open = wrap_open(real_io_open)
os.open = replacement_os_open
os.read = replacement_os_read
os.fdopen = replacement_os_fdopen
sys.argv = [script, input_dir]

try:
    runpy.run_path(script, run_name='__main__')
finally:
    with real_builtin_open(report, 'w') as output:
        json.dump(sorted(full_reads), output)
WRAPPER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess

BUGGY_LINE = '10.0.0.5 [12/Nov/2023:03:14:15] "GET /weird path with spaces HTTP/1.1" 404 532'

EXPECTED_LOGS = {
    'access_01.log': (
        '192.168.1.1 [10/Oct/2023:13:55:36] "GET /index.html HTTP/1.1" 200 1024\n'
        '192.168.1.2 [10/Oct/2023:13:56:01] "POST /api/login HTTP/1.1" 200 512\n'
        '192.168.1.3 [10/Oct/2023:13:57:11] "GET /images/logo.png HTTP/1.1" 304 0\n'
    ),
    'access_02.log': (
        '10.0.0.5 [12/Nov/2023:03:10:00] "GET /dashboard HTTP/1.1" 200 2048\n'
        '10.0.0.6 [12/Nov/2023:03:12:45] "GET /assets/app.js HTTP/1.1" 200 4096\n'
        '10.0.0.5 [12/Nov/2023:03:14:15] "GET /weird path with spaces HTTP/1.1" 404 532\n'
        '10.0.0.8 [12/Nov/2023:03:15:00] "GET /logout HTTP/1.1" 302 0\n'
    ),
}

def test_buggy_line_isolated():
    buggy_file = '/home/user/buggy_line.txt'
    assert os.path.isfile(buggy_file), f'The file {buggy_file} was not created.'

    with open(buggy_file, 'r') as f:
        content = f.read().strip()

    assert content == BUGGY_LINE, f"The isolated buggy line is incorrect. Expected: '{BUGGY_LINE}', but got: '{content}'"

def test_script_fixed():
    script_file = '/home/user/process_logs.py'
    logs_dir = '/home/user/logs'

    assert os.path.isfile(script_file), f'The script file {script_file} is missing.'
    assert os.path.isdir(logs_dir), f'The directory {logs_dir} is missing.'

    result = subprocess.run(
        ['python3', script_file, logs_dir],
        capture_output=True,
        text=True,
        timeout=10,
    )

    assert result.returncode == 0, f'The script failed to execute successfully. Exit code: {result.returncode}\nStderr: {result.stderr}'

def test_script_processes_generated_logs_and_malformed_lines(tmp_path):
    script_file = '/home/user/process_logs.py'
    generated_dir = tmp_path / ('logs_' + secrets.token_hex(6))
    generated_dir.mkdir()

    expected_paths = []
    for index in range(3):
        token = secrets.token_hex(8)
        path = generated_dir / f'access_{token}_{index}.log'
        malformed = (
            f'172.16.{index}.9 [0{index + 1}/Jan/2024:01:02:03] '
            f'"GET /generated/{token} path with spaces HTTP/1.1" 4{index}4 {100 + index}'
        )
        path.write_text(
            f'172.16.{index}.1 [0{index + 1}/Jan/2024:01:00:00] "GET /ok/{token} HTTP/1.1" 200 10\n'
            + malformed + '\n'
            + f'172.16.{index}.2 [0{index + 1}/Jan/2024:01:03:00] "POST /done/{token} HTTP/1.1" 503 20\n'
        )
        expected_paths.append(os.path.realpath(path))

    report = tmp_path / 'read_report.json'
    result = subprocess.run(
        ['python3', '/tmp/run_instrumented.py', script_file, str(generated_dir), str(report)],
        capture_output=True,
        text=True,
        timeout=10,
    )

    assert result.returncode == 0, (
        'The script did not gracefully process generated logs containing malformed lines. '
        f'Exit code: {result.returncode}\nStdout: {result.stdout}\nStderr: {result.stderr}'
    )
    assert report.is_file(), 'The instrumented execution did not produce a read report.'
    fully_read = set(json.loads(report.read_text()))
    assert fully_read == set(expected_paths), (
        'The script must actually read every generated log file through the end; '
        f'expected {sorted(expected_paths)}, observed {sorted(fully_read)}'
    )

def test_original_logs_unmodified():
    log_file = '/home/user/logs/access_02.log'
    assert os.path.isfile(log_file), f'The log file {log_file} was deleted or moved.'

    with open(log_file, 'r') as f:
        content = f.read()

    assert BUGGY_LINE in content, f'The original log file {log_file} was modified and the buggy line is missing.'

    for filename, expected in EXPECTED_LOGS.items():
        path = os.path.join('/home/user/logs', filename)
        assert os.path.isfile(path), f'The original log file {path} was deleted or moved.'
        with open(path, 'r') as f:
            actual = f.read()
        assert actual == expected, f'The original log file {path} was modified.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
