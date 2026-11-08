#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import os
import re
import shutil
import stat
import subprocess
import time
import uuid

import pytest


def test_01_processed_authbase_log():
    log_path = '/home/user/processed/AuthBase.log'
    assert os.path.isfile(log_path), f"File {log_path} is missing."
    with open(log_path, 'r') as f:
        content = f.read().strip()
    expected = "2023-10-01 10:00:01 | AuthBase | FATAL | Keymaster disconnected"
    assert expected in content, f"Expected FATAL line missing in {log_path}."


def test_02_processed_dbcore_log():
    log_path = '/home/user/processed/DB_Core.log'
    assert os.path.isfile(log_path), f"File {log_path} is missing."
    with open(log_path, 'r') as f:
        content = f.read().strip()
    expected = "2023-10-01 10:00:03 | DB_Core | FATAL | Table corruption detected"
    assert expected in content, f"Expected FATAL line missing in {log_path}."


def test_03_processed_network_log():
    log_path = '/home/user/processed/Network.log'
    assert os.path.isfile(log_path), f"File {log_path} is missing."
    with open(log_path, 'r') as f:
        content = f.read().strip()
    expected = "2023-10-01 10:00:04 | Network | FATAL | Socket bind failed"
    assert expected in content, f"Expected FATAL line missing in {log_path}."


def test_04_archived_files():
    archive_dir = '/home/user/archive'
    assert os.path.isfile(os.path.join(archive_dir, 'batch1.log')), "batch1.log was not moved to archive."
    assert os.path.isfile(os.path.join(archive_dir, 'batch2.gz')), "batch2.gz was not moved to archive."


def test_05_filter_executable_exists():
    filter_path = '/home/user/filter'
    assert os.path.isfile(filter_path), f"Compiled filter {filter_path} is missing."
    st = os.stat(filter_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Filter {filter_path} is not executable."
    with open(filter_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "The compiled filter is not an ELF executable."


def test_06_watcher_script_exists_and_executable():
    script_path = '/home/user/watch.sh'
    assert os.path.isfile(script_path), f"Watcher script {script_path} is missing."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Watcher script {script_path} is not executable."


def reset_runtime_dirs():
    for path in ('/home/user/incoming', '/home/user/processed', '/home/user/archive'):
        if os.path.exists(path):
            shutil.rmtree(path)
        os.makedirs(path, mode=0o777)


def exercise_filter(binary, suffix):
    reset_runtime_dirs()
    token = uuid.uuid4().hex[:10]
    module_a = f'Plain_{token}_{suffix}'
    module_b = f'Gzip_{token}_{suffix}'
    plain_fatal = f'2041-02-03 04:05:06 |  {module_a}  | FATAL | generated plain event {token}'
    gzip_fatal_a = f'2041-02-03 04:05:07 | {module_a} | FATAL | generated compressed followup {token}'
    gzip_fatal_b = f'2041-02-03 04:05:08 | {module_b} | FATAL | generated compressed event {token}'

    plain_path = f'/tmp/filter-{token}.log'
    gzip_path = f'/tmp/filter-{token}.gz'
    plain_data = '\n'.join([
        f'2041-02-03 04:05:05 | {module_a} | INFO | ignore {token}',
        plain_fatal,
        f'2041-02-03 04:05:06 | {module_b} | FATALITY | not an exact level {token}',
    ]) + '\n'
    gzip_data = '\n'.join([
        gzip_fatal_a,
        f'2041-02-03 04:05:08 | {module_b} | WARN | ignore compressed {token}',
        gzip_fatal_b,
    ]) + '\n'

    with open(plain_path, 'w') as f:
        f.write(plain_data)
    with gzip.open(gzip_path, 'wb') as f:
        f.write(gzip_data.encode())

    try:
        first = subprocess.run([binary, plain_path], capture_output=True, text=True, timeout=10)
        assert first.returncode == 0, f"Filter failed on plain input: {first.stderr}"
        second = subprocess.run([binary, gzip_path], capture_output=True, text=True, timeout=10)
        assert second.returncode == 0, f"Filter failed on gzip input: {second.stderr}"

        with open(f'/home/user/processed/{module_a}.log') as f:
            assert f.read().splitlines() == [plain_fatal, gzip_fatal_a]
        with open(f'/home/user/processed/{module_b}.log') as f:
            assert f.read().splitlines() == [gzip_fatal_b]
        assert sorted(os.listdir('/home/user/processed')) == sorted([module_a + '.log', module_b + '.log'])
    finally:
        for path in (plain_path, gzip_path):
            if os.path.exists(path):
                os.unlink(path)


def test_07_filter_source_and_dynamic_behavior():
    source_path = '/home/user/filter.cpp'
    assert os.path.isfile(source_path), "C++ source /home/user/filter.cpp is missing."
    with open(source_path, 'r', errors='replace') as f:
        source = f.read()
    source_without_comments = re.sub(r'/\*.*?\*/|//[^\n]*', '', source, flags=re.S)
    assert re.search(r'\bpopen\s*\(', source_without_comments), "filter.cpp does not use popen for streamed decompression."

    rebuilt = '/tmp/rebuilt-filter'
    result = subprocess.run(
        ['g++', '-std=c++11', source_path, '-o', rebuilt],
        capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, f"filter.cpp does not compile: {result.stderr}"

    exercise_filter('/home/user/filter', 'installed')
    exercise_filter(rebuilt, 'rebuilt')


def test_08_watcher_dynamic_behavior_and_eof():
    reset_runtime_dirs()
    token = uuid.uuid4().hex[:12]
    module_plain = f'WatchPlain_{token}'
    module_gzip = f'WatchGzip_{token}'
    plain_name = f'live-{token}.log'
    gzip_name = f'live-{token}.gz'
    plain_line = f'2052-06-07 08:09:10 | {module_plain} | FATAL | watcher plain {token}'
    gzip_line = f'2052-06-07 08:09:11 | {module_gzip} | FATAL | watcher gzip {token}'
    plain_bytes = (plain_line + '\n' + f'2052-06-07 08:09:12 | {module_plain} | INFO | ignored {token}\n').encode()
    gzip_payload = (f'2052-06-07 08:09:13 | {module_gzip} | WARN | ignored {token}\n' + gzip_line + '\n').encode()
    compressed_bytes = gzip.compress(gzip_payload)

    proc = subprocess.Popen(
        ['/bin/bash', '/home/user/watch.sh'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    try:
        time.sleep(0.5)
        assert proc.poll() is None, "Watcher exited before any input or EOF arrived."

        with open(os.path.join('/home/user/incoming', plain_name), 'wb') as f:
            f.write(plain_bytes)
        with open(os.path.join('/home/user/incoming', gzip_name), 'wb') as f:
            f.write(compressed_bytes)

        deadline = time.time() + 15
        archived_plain = os.path.join('/home/user/archive', plain_name)
        archived_gzip = os.path.join('/home/user/archive', gzip_name)
        while time.time() < deadline:
            if os.path.isfile(archived_plain) and os.path.isfile(archived_gzip):
                break
            if proc.poll() is not None:
                break
            time.sleep(0.2)

        assert os.path.isfile(archived_plain), "Watcher did not process and archive the new .log file."
        assert os.path.isfile(archived_gzip), "Watcher did not process and archive the new .gz file."
        assert proc.poll() is None, "Watcher did not continue monitoring while waiting for EOF.txt."
        with open(archived_plain, 'rb') as f:
            assert f.read() == plain_bytes
        with open(archived_gzip, 'rb') as f:
            assert f.read() == compressed_bytes

        with open(f'/home/user/processed/{module_plain}.log') as f:
            assert f.read().splitlines() == [plain_line]
        with open(f'/home/user/processed/{module_gzip}.log') as f:
            assert f.read().splitlines() == [gzip_line]

        open('/home/user/incoming/EOF.txt', 'w').close()
        stdout, stderr = proc.communicate(timeout=10)
        assert proc.returncode == 0, f"Watcher did not exit gracefully on EOF.txt: {stderr}"
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
