#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import os
import re
import shutil
import subprocess
import time
import uuid


def test_config_file_fixed():
    """Verify the config file has the bug fixed."""
    config_path = '/home/user/curator_config.ini'
    assert os.path.isfile(config_path), f"Config file {config_path} is missing."

    with open(config_path, 'r') as f:
        content = f.read()

    assert '# BUG: ' not in content, "The '# BUG: ' prefix was not removed from the config file."
    assert re.search(r'^DESTINATION=/home/user/curated_repo$', content, re.MULTILINE), "The DESTINATION line is missing or incorrect."


def test_cpp_source_code_exists_and_uses_flock():
    """Verify the C++ source code exists and uses flock with LOCK_SH."""
    cpp_path = '/home/user/curator.cpp'
    assert os.path.isfile(cpp_path), f"C++ source file {cpp_path} is missing."

    with open(cpp_path, 'r') as f:
        content = f.read()

    assert 'flock' in content, "The C++ program does not use 'flock'."
    assert 'LOCK_SH' in content, "The C++ program does not use 'LOCK_SH' for shared locking."


def test_binary_exists():
    """Verify the compiled binary exists and is executable."""
    bin_path = '/home/user/curator_bin'
    assert os.path.isfile(bin_path), f"Compiled binary {bin_path} is missing."
    assert os.access(bin_path, os.X_OK), f"Binary {bin_path} is not executable."


def test_stable_files_output():
    """Verify the output file contains the correct stable artifact paths."""
    out_path = '/home/user/stable_files.out'
    assert os.path.isfile(out_path), f"Output file {out_path} is missing."

    with open(out_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        '/home/user/incoming/libA_v1.so',
        '/home/user/incoming/libC_v1.so'
    ]

    assert lines == expected_lines, f"Expected output {expected_lines}, but got {lines}."


def _record(artifact_id, status, path):
    return (
        'START_ARTIFACT\n'
        f'ID={artifact_id}\n'
        f'STATUS={status}\n'
        f'FILE={path}\n'
        'END_ARTIFACT\n'
    )


def _read_output():
    out_path = '/home/user/stable_files.out'
    assert os.path.isfile(out_path), 'Program did not create /home/user/stable_files.out'
    with open(out_path, 'r') as f:
        return f.read().splitlines()


def _run_while_exclusively_locked(executable, final_log, expected):
    """The reader must wait for LOCK_EX and then read data written before unlock."""
    log_path = '/home/user/upload_log.txt'
    out_path = '/home/user/stable_files.out'
    if os.path.exists(out_path):
        os.unlink(out_path)

    proc = None
    with open(log_path, 'r+') as locked_log:
        fcntl.flock(locked_log.fileno(), fcntl.LOCK_EX)
        locked_log.seek(0)
        locked_log.truncate()
        locked_log.write(_record(999999, 'STABLE', '/tmp/locked-decoy'))
        locked_log.flush()
        os.fsync(locked_log.fileno())

        try:
            proc = subprocess.Popen([executable], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            time.sleep(0.4)
            assert proc.poll() is None, f'{executable} did not wait for the exclusive writer lock'

            locked_log.seek(0)
            locked_log.truncate()
            locked_log.write(final_log)
            locked_log.flush()
            os.fsync(locked_log.fileno())
            fcntl.flock(locked_log.fileno(), fcntl.LOCK_UN)

            stdout, stderr = proc.communicate(timeout=5)
            assert proc.returncode == 0, f'{executable} failed: stdout={stdout!r}, stderr={stderr!r}'
        finally:
            try:
                fcntl.flock(locked_log.fileno(), fcntl.LOCK_UN)
            except OSError:
                pass
            if proc is not None and proc.poll() is None:
                proc.kill()
                proc.communicate()

    assert _read_output() == expected, f'{executable} produced incorrect output for changed log data'


def _run_while_shared_locked(executable, log_content, expected):
    """A genuine LOCK_SH reader must be able to run concurrently with another reader."""
    log_path = '/home/user/upload_log.txt'
    out_path = '/home/user/stable_files.out'
    with open(log_path, 'w') as f:
        f.write(log_content)
        f.flush()
        os.fsync(f.fileno())

    if os.path.exists(out_path):
        os.unlink(out_path)

    proc = None
    with open(log_path, 'r') as shared_log:
        fcntl.flock(shared_log.fileno(), fcntl.LOCK_SH)
        try:
            proc = subprocess.Popen([executable], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                stdout, stderr = proc.communicate(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.communicate()
                raise AssertionError(f'{executable} blocked behind a shared lock instead of using LOCK_SH')
            assert proc.returncode == 0, f'{executable} failed: stdout={stdout!r}, stderr={stderr!r}'
        finally:
            fcntl.flock(shared_log.fileno(), fcntl.LOCK_UN)
            if proc is not None and proc.poll() is None:
                proc.kill()
                proc.communicate()

    assert _read_output() == expected, f'{executable} produced incorrect output while sharing the log lock'


def test_program_executes_source_logic_on_changed_input_and_really_locks():
    config_path = '/home/user/curator_config.ini'
    log_path = '/home/user/upload_log.txt'
    out_path = '/home/user/stable_files.out'
    rebuilt = '/tmp/curator_rebuilt'

    with open(config_path, 'rb') as f:
        old_config = f.read()
    with open(log_path, 'rb') as f:
        old_log = f.read()
    old_output = None
    if os.path.exists(out_path):
        with open(out_path, 'rb') as f:
            old_output = f.read()

    token = uuid.uuid4().hex
    dynamic_destination = f'/tmp/curated_{token}'
    os.mkdir(dynamic_destination)
    created_files = []

    try:
        build = subprocess.run(
            ['g++', '-std=c++17', '-O2', '/home/user/curator.cpp', '-o', rebuilt],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        assert build.returncode == 0, f'curator.cpp does not compile: {build.stderr}'

        with open(config_path, 'w') as f:
            f.write('[DEFAULT]\n')
            f.write('LOG_FILE=/home/user/upload_log.txt\n')
            f.write(f'DESTINATION={dynamic_destination}\n')
            f.write('MAX_RETRIES=7\n')

        executables = ['/home/user/curator_bin', rebuilt]
        for index, executable in enumerate(executables):
            paths = [f'/home/user/incoming/{token}_{index}_{i}.bin' for i in range(5)]
            for path in paths:
                open(path, 'a').close()
                created_files.append(path)

            log_one = ''.join([
                _record(7000 + index * 10, 'UNSTABLE', paths[0]),
                _record(7001 + index * 10, 'STABLE', paths[1]),
                _record(7002 + index * 10, 'STABLE', paths[2]),
                _record(7003 + index * 10, 'UNSTABLE', paths[3]),
                _record(7004 + index * 10, 'STABLE', paths[4]),
            ])
            _run_while_exclusively_locked(executable, log_one, [paths[1], paths[2], paths[4]])

            log_two = ''.join([
                _record(8000 + index * 10, 'STABLE', paths[3]),
                _record(8001 + index * 10, 'UNSTABLE', paths[2]),
                _record(8002 + index * 10, 'STABLE', paths[0]),
            ])
            _run_while_shared_locked(executable, log_two, [paths[3], paths[0]])
    finally:
        with open(config_path, 'wb') as f:
            f.write(old_config)
        with open(log_path, 'wb') as f:
            f.write(old_log)
        if old_output is None:
            if os.path.exists(out_path):
                os.unlink(out_path)
        else:
            with open(out_path, 'wb') as f:
                f.write(old_output)
        for path in created_files:
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
        shutil.rmtree(dynamic_destination, ignore_errors=True)
        try:
            os.unlink(rebuilt)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
