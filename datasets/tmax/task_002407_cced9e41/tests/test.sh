#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import hashlib
import json
import os
import re
import socket
import subprocess
import time
import uuid

import websockets

SANITIZER = '/home/user/patch_sanitizer.py'
SERVER = '/home/user/build_server.py'
BENCHMARK = '/home/user/benchmark.py'
REPORT = '/home/user/memory_report.log'
PORT = 8765
LIMIT_MB = 50.0


def run_sanitizer(path):
    return subprocess.run(
        ['python3', SANITIZER, path], capture_output=True, text=True, timeout=5
    )


def write_patch(directory, name, content):
    path = os.path.join(directory, name)
    with open(path, 'w') as f:
        f.write(content)
    return path


def listener_pid(port):
    wanted = f'{port:04X}'
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[1].split(':')[-1].upper() == wanted and fields[3] == '0A':
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        fd_dir = f'/proc/{entry}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    return int(entry)
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return None


def rss_mb(pid):
    try:
        with open(f'/proc/{pid}/statm') as f:
            resident_pages = int(f.read().split()[1])
        return resident_pages * os.sysconf('SC_PAGE_SIZE') / (1024 * 1024)
    except (FileNotFoundError, ProcessLookupError, IndexError, ValueError):
        return None


def read_events(path):
    if not os.path.exists(path):
        return []
    events = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                events.append(json.loads(line))
    return events


def wait_for_events(path, minimum, timeout=10):
    deadline = time.time() + timeout
    events = []
    while time.time() < deadline:
        events = read_events(path)
        if len(events) >= minimum:
            return events
        time.sleep(0.05)
    return events


async def send_messages(messages):
    async with websockets.connect(
        f'ws://127.0.0.1:{PORT}', open_timeout=3, close_timeout=2
    ) as ws:
        for message in messages:
            await ws.send(message)
    await asyncio.sleep(0.2)


def test_complete_build_system(tmp_path):
    # Preserve the original fixed-corpus assertions.
    assert os.path.isfile(SANITIZER), f'Sanitizer script missing at {SANITIZER}'
    assert os.path.isfile(SERVER), f'Build server missing at {SERVER}'
    assert os.path.isfile(BENCHMARK), f'Benchmark script missing at {BENCHMARK}'

    clean_dir = '/app/corpora/clean_patches/'
    evil_dir = '/app/corpora/evil_patches/'
    assert os.path.isdir(clean_dir), f'Clean corpus missing at {clean_dir}'
    assert os.path.isdir(evil_dir), f'Evil corpus missing at {evil_dir}'

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir)
                   if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir)
                  if os.path.isfile(os.path.join(evil_dir, f))]
    assert clean_files, 'No files found in clean corpus.'
    assert evil_files, 'No files found in evil corpus.'

    clean_failed = [os.path.basename(p) for p in clean_files if run_sanitizer(p).returncode != 0]
    evil_failed = [os.path.basename(p) for p in evil_files if run_sanitizer(p).returncode != 1]
    errors = []
    if evil_failed:
        errors.append(f'{len(evil_failed)} of {len(evil_files)} evil bypassed: {", ".join(evil_failed)}')
    if clean_failed:
        errors.append(f'{len(clean_failed)} of {len(clean_files)} clean modified: {", ".join(clean_failed)}')
    assert not errors, ' | '.join(errors)

    # Exercise fresh, unpredictable paths rather than only the setup corpus.
    token = uuid.uuid4().hex
    safe_patches = [
        f'''--- src/{token}.c\n+++ src/{token}.c\n@@ -1 +1 @@\n-old\n+new\n''',
        f'''--- /dev/null\n+++ src/generated/{token}.py\n@@ -0,0 +1 @@\n+print("ok")\n''',
        f'''--- src/nested/../{token}.txt\n+++ src/nested/../{token}.txt\n@@ -1 +1 @@\n-a\n+b\n''',
    ]
    evil_patches = [
        f'''--- src/../../../../etc/{token}\n+++ src/../../../../etc/{token}\n@@ -1 +1 @@\n-a\n+b\n''',
        f'''--- /tmp/{token}\n+++ /tmp/{token}\n@@ -1 +1 @@\n-a\n+b\n''',
        f'''--- src/.git/{token}\n+++ src/.git/{token}\n@@ -1 +1 @@\n-a\n+b\n''',
        f'''--- docs/{token}.md\n+++ docs/{token}.md\n@@ -1 +1 @@\n-a\n+b\n''',
        f'''--- src/sub/../../../root/{token}\n+++ src/sub/../../../root/{token}\n@@ -1 +1 @@\n-a\n+b\n''',
    ]

    for i, patch in enumerate(safe_patches):
        result = run_sanitizer(write_patch(str(tmp_path), f'safe_{i}.diff', patch))
        assert result.returncode == 0, f'Fresh safe patch rejected: {result.stderr}'
    for i, patch in enumerate(evil_patches):
        result = run_sanitizer(write_patch(str(tmp_path), f'evil_{i}.diff', patch))
        assert result.returncode == 1, f'Fresh evil patch bypassed (code {result.returncode})'
        assert result.stderr.strip(), 'Rejected evil patch did not print a reason to stderr'

    # Preserve the original TCP-listener assertion, then identify the actual server.
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(2.0)
    try:
        assert sock.connect_ex(('127.0.0.1', PORT)) == 0, (
            f'Could not connect to WebSocket server on port {PORT}. Is the server running?'
        )
    finally:
        sock.close()

    pid = listener_pid(PORT)
    assert pid is not None, f'No process owns the listener on port {PORT}'
    with open(f'/proc/{pid}/cmdline', 'rb') as f:
        cmdline = f.read().replace(b'\0', b' ').decode(errors='replace')
    assert 'build_server.py' in cmdline, f'Port {PORT} is not served by build_server.py: {cmdline}'

    # Interpose a transparent sanitizer wrapper. This proves WebSocket payloads and
    # all benchmark messages are written to files and passed to the required script.
    backup = f'/tmp/patch_sanitizer_original_{token}.py'
    event_log = f'/tmp/sanitizer_events_{token}.jsonl'
    os.replace(SANITIZER, backup)
    wrapper = f'''#!/usr/bin/env python3
import hashlib, json, subprocess, sys
payload = b""
if len(sys.argv) == 2:
    try:
        payload = open(sys.argv[1], "rb").read()
    except OSError:
        pass
result = subprocess.run([sys.executable, {backup!r}] + sys.argv[1:], capture_output=True)
with open({event_log!r}, "a") as log:
    log.write(json.dumps({{"sha256": hashlib.sha256(payload).hexdigest(), "returncode": result.returncode}}) + "\\n")
sys.stdout.buffer.write(result.stdout)
sys.stderr.buffer.write(result.stderr)
sys.exit(result.returncode)
'''
    with open(SANITIZER, 'w') as f:
        f.write(wrapper)
    os.chmod(SANITIZER, 0o755)

    try:
        ws_messages = [safe_patches[0], evil_patches[0], safe_patches[1], evil_patches[2]]
        asyncio.run(send_messages(ws_messages))
        events = wait_for_events(event_log, len(ws_messages))
        assert len(events) == len(ws_messages), (
            'WebSocket server did not invoke patch_sanitizer.py once for each payload'
        )
        observed = {event['sha256']: event['returncode'] for event in events}
        for message in ws_messages:
            digest = hashlib.sha256(message.encode()).hexdigest()
            expected = 0 if message in safe_patches else 1
            assert observed.get(digest) == expected, 'WebSocket payload was not correctly sanitized'

        # Start with a clean event log and report, then execute the demanded benchmark.
        time.sleep(0.3)
        open(event_log, 'w').close()
        if os.path.exists(REPORT):
            os.unlink(REPORT)
        benchmark_started = time.time()
        process = subprocess.Popen(
            ['python3', BENCHMARK], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        peak_observed_rss = rss_mb(pid) or 0.0
        deadline = time.time() + 40
        while process.poll() is None and time.time() < deadline:
            current = rss_mb(pid)
            if current is not None:
                peak_observed_rss = max(peak_observed_rss, current)
            time.sleep(0.05)
        if process.poll() is None:
            process.kill()
            stdout, stderr = process.communicate()
            raise AssertionError(f'benchmark.py timed out. stdout={stdout!r}, stderr={stderr!r}')
        stdout, stderr = process.communicate()
        assert process.returncode == 0, (
            f'benchmark.py failed with code {process.returncode}. stdout={stdout!r}, stderr={stderr!r}'
        )

        events = wait_for_events(event_log, 100)
        time.sleep(0.3)
        events = read_events(event_log)
        assert len(events) == 100, f'Benchmark caused {len(events)} sanitizer calls instead of 100'
        returncodes = [event['returncode'] for event in events]
        assert 0 in returncodes and 1 in returncodes, (
            'Benchmark did not send a mix of safe and unsafe patches'
        )

        deadline = time.time() + 5
        while not os.path.isfile(REPORT) and time.time() < deadline:
            time.sleep(0.05)
        assert os.path.isfile(REPORT), f'Memory report missing at {REPORT}'
        assert os.path.getmtime(REPORT) >= benchmark_started - 0.1, (
            'Memory report was not generated during this benchmark run'
        )
        with open(REPORT) as f:
            content = f.read().strip()
        match = re.search(r'Peak Memory:\s*([0-9]*\.?[0-9]+)\s*MB', content, re.IGNORECASE)
        assert match is not None, f"Could not parse Peak Memory from {REPORT}. File content: '{content}'"
        reported_peak = float(match.group(1))
        assert reported_peak > 0.0, 'Peak memory must be a measured positive value, not zero'
        assert reported_peak < LIMIT_MB, (
            f'Peak memory {reported_peak} MB is not strictly less than the {LIMIT_MB} MB limit.'
        )
        assert peak_observed_rss > 0.0, 'Could not independently sample server memory'
        assert peak_observed_rss < LIMIT_MB, (
            f'Observed server RSS {peak_observed_rss:.2f} MB exceeded the {LIMIT_MB} MB limit'
        )
    finally:
        try:
            os.unlink(SANITIZER)
        except FileNotFoundError:
            pass
        if os.path.exists(backup):
            os.replace(backup, SANITIZER)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
