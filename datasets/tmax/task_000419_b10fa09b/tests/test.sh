#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
import tempfile
from pathlib import Path

KV_DIR = Path('/home/user/kv_store')
RECOVERED = Path('/home/user/recovered_data.txt')
WAL = KV_DIR / 'data.wal'


def run(cmd, **kwargs):
    defaults = dict(capture_output=True, text=True, timeout=30)
    defaults.update(kwargs)
    return subprocess.run(cmd, **defaults)


def function_body(source, signature):
    start = source.find(signature)
    assert start >= 0, f'{signature} missing'
    opening = source.find('{', start)
    assert opening >= 0, f'body for {signature} missing'
    depth = 0
    for pos in range(opening, len(source)):
        if source[pos] == '{':
            depth += 1
        elif source[pos] == '}':
            depth -= 1
            if depth == 0:
                return source[opening + 1:pos]
    raise AssertionError(f'unterminated body for {signature}')


def strip_comments(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    return re.sub(r'//[^\n]*', '', text)


def test_kv_store_cpp_fixed():
    path = '/home/user/kv_store/kv_store.cpp'
    assert os.path.isfile(path), f'{path} is missing'

    with open(path, 'r') as f:
        content = f.read()

    assert 'void KVStore::put' in content, 'put method missing in kv_store.cpp'

    # Preserve the original assertion.
    put_section = content.split('void KVStore::put')[1]
    assert 'lock' in put_section or 'mtx' in put_section, 'No lock or mutex usage found in KVStore::put method.'

    # Check only put's actual body, excluding comments, and require the store
    # mutation to be preceded by acquisition of KVStore's mutex.
    body = strip_comments(function_body(content, 'void KVStore::put'))
    mutation = body.find('store[')
    assert mutation >= 0, 'KVStore::put no longer updates the store'
    prefix = body[:mutation]
    guarded = (
        re.search(r'(?:lock_guard|unique_lock|scoped_lock)\s*<[^;]+>\s+\w+\s*\(\s*mtx\s*\)', prefix)
        or re.search(r'\bmtx\s*\.\s*lock\s*\(\s*\)', prefix)
    )
    assert guarded, 'KVStore::put does not acquire mtx before modifying store'

    # Compile and exercise the submitted implementation independently of the
    # user-provided regression script.
    harness = r'''
#include "kv_store.h"
#include <atomic>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

int main() {
    KVStore kv;
    const int threads = 16;
    const int count = 2500;
    std::atomic<bool> start(false);
    std::vector<std::thread> workers;
    for (int t = 0; t < threads; ++t) {
        workers.emplace_back([&, t]() {
            while (!start.load(std::memory_order_acquire)) {}
            for (int i = 0; i < count; ++i) {
                std::string key = "thread_" + std::to_string(t) + "_" + std::to_string(i);
                kv.put(key, "value_" + std::to_string(i));
                if ((i % 31) == 0) (void)kv.get(key);
            }
        });
    }
    start.store(true, std::memory_order_release);
    for (auto &worker : workers) worker.join();
    for (int t = 0; t < threads; ++t) {
        for (int i = 0; i < count; ++i) {
            std::string key = "thread_" + std::to_string(t) + "_" + std::to_string(i);
            if (kv.get(key) != "value_" + std::to_string(i)) return 2;
        }
    }
    return 0;
}
'''
    with tempfile.TemporaryDirectory() as td:
        src = Path(td) / 'race_harness.cpp'
        exe = Path(td) / 'race_harness'
        src.write_text(harness)
        result = run([
            'g++', '-O2', '-pthread', '-std=c++11', '-I', str(KV_DIR),
            str(src), str(KV_DIR / 'kv_store.cpp'), '-o', str(exe)
        ])
        assert result.returncode == 0, f'kv_store.cpp failed to compile:\n{result.stderr}'
        for _ in range(3):
            result = run([str(exe)], timeout=30)
            assert result.returncode == 0, f'concurrent KVStore test failed with {result.returncode}:\n{result.stderr}'


def test_recovered_data():
    path = '/home/user/recovered_data.txt'
    assert os.path.isfile(path), f'{path} is missing'

    with open(path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected = ['foo=bar', 'hello=world', 'test=123']
    assert lines == expected, f'Content of {path} does not match the expected sorted entries. Got: {lines}'


def entry(key, value):
    key = key.encode('ascii')
    value = value.encode('ascii')
    return bytes([0xAA, len(key)]) + key + bytes([len(value)]) + value + bytes([0xBB])


def parser_candidates():
    candidates = []
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        for name in files:
            path = Path(root) / name
            if path == RECOVERED or path == WAL or path.name == 'stress_test':
                continue
            try:
                data = path.read_bytes()
            except OSError:
                continue
            lowered_name = name.lower()
            named = any(word in lowered_name for word in ('recover', 'parser', 'wal'))
            mentions_io = b'data.wal' in data and b'recovered_data.txt' in data
            if named or mentions_io:
                candidates.append((path, data))
    return candidates


def candidate_commands(path, data, build_dir):
    commands = []
    suffix = path.suffix.lower()
    if suffix == '.py':
        commands.extend([
            ['python3', str(path)],
            ['python3', str(path), str(WAL), str(RECOVERED)],
        ])
    elif suffix in ('.sh', '.bash'):
        commands.extend([
            ['bash', str(path)],
            ['bash', str(path), str(WAL), str(RECOVERED)],
        ])
    elif suffix in ('.cpp', '.cc', '.cxx'):
        exe = build_dir / ('parser_' + str(abs(hash(str(path)))))
        compiled = run(['g++', '-std=c++11', str(path), '-o', str(exe)])
        if compiled.returncode == 0:
            commands.extend([[str(exe)], [str(exe), str(WAL), str(RECOVERED)]])
    elif data.startswith(b'\x7fELF') or os.access(path, os.X_OK):
        commands.extend([[str(path)], [str(path), str(WAL), str(RECOVERED)]])
    return commands


def test_recovery_parser_on_unseen_wal():
    original_wal = WAL.read_bytes()
    original_output = RECOVERED.read_bytes() if RECOVERED.exists() else None

    # Valid records are deliberately unsorted and separated by garbage and a
    # malformed record, so copying the original expected output or stopping at
    # the first corruption cannot pass.
    hidden_wal = (
        b'garbage\x00\x17' + entry('zulu', 'last') +
        bytes([0xAA, 3]) + b'bad' + bytes([4]) + b'xx' +
        b'noise' + entry('alpha', 'first') + b'\x10\x20' +
        entry('middle', 'value') + bytes([0xAA, 8]) + b'partial'
    )
    expected = ['alpha=first', 'middle=value', 'zulu=last']
    succeeded = False

    try:
        candidates = parser_candidates()
        assert candidates, 'No WAL recovery script or program was found'
        with tempfile.TemporaryDirectory() as td:
            build_dir = Path(td)
            for candidate, data in candidates:
                for command in candidate_commands(candidate, data, build_dir):
                    WAL.write_bytes(hidden_wal)
                    if RECOVERED.exists():
                        RECOVERED.unlink()
                    try:
                        result = run(command, cwd=str(candidate.parent), timeout=20)
                    except (subprocess.TimeoutExpired, OSError):
                        continue
                    if result.returncode != 0 or not RECOVERED.is_file():
                        continue
                    lines = [line.strip() for line in RECOVERED.read_text().splitlines() if line.strip()]
                    if lines == expected:
                        succeeded = True
                        break
                if succeeded:
                    break
        assert succeeded, 'No submitted parser correctly recovered an unseen WAL containing interspersed corruption'
    finally:
        WAL.write_bytes(original_wal)
        if original_output is None:
            if RECOVERED.exists():
                RECOVERED.unlink()
        else:
            RECOVERED.write_bytes(original_output)


def test_race_script_execution():
    path = '/home/user/test_race.sh'
    assert os.path.isfile(path), f'{path} is missing'

    script = Path(path).read_text()
    assert re.search(r'(^|[;&|]\s*|\n\s*)(make\b|(?:g\+\+|c\+\+|clang\+\+)\b)', script), 'test_race.sh does not compile the C++ code'
    assert re.search(r'(^|[;&|]\s*|\n\s*)(?:\./|[^\s]*/)?stress_test(?:\s|$)', script), 'test_race.sh does not run stress_test'

    stress = KV_DIR / 'stress_test'
    if stress.exists():
        stress.unlink()

    # Preserve the original execution assertion.
    result = subprocess.run(['bash', path], capture_output=True, text=True, cwd='/home/user', timeout=60)
    assert result.returncode == 0, f'{path} failed with exit code {result.returncode}.\nStdout:\n{result.stdout}\nStderr:\n{result.stderr}'

    assert stress.is_file(), 'test_race.sh did not create /home/user/kv_store/stress_test'
    assert stress.read_bytes()[:4] == b'\x7fELF', 'stress_test is not a compiled executable'
    result = run([str(stress)], cwd=str(KV_DIR), timeout=30)
    assert result.returncode == 0, f'compiled stress_test failed with {result.returncode}:\n{result.stderr}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
