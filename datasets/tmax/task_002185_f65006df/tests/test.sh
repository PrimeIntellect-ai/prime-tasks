#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import json
import os
import re
import secrets
import subprocess
import sys
import time
from pathlib import Path

import pytest
from scapy.all import Raw, rdpcap

WAL_PATH = Path('/home/user/data/cache.wal')
RECOVERED_PATH = Path('/home/user/data/recovered.json')
PCAP_PATH = Path('/home/user/logs/traffic.pcap')
LOG_PATH = Path('/home/user/logs/build.log')
SERVER_SOURCE = Path('/app/async-build-cache-1.0.0/async_build_cache/server.py')
PACKAGE_ROOT = '/app/async-build-cache-1.0.0'


def acknowledged_txn_id():
    pcap_acks = []
    for packet in rdpcap(str(PCAP_PATH)):
        if Raw in packet:
            payload = bytes(packet[Raw].load).decode('utf-8', errors='ignore')
            pcap_acks.extend(int(x) for x in re.findall(r'ACK\s+TXN_ID:\s*(\d+)', payload))

    log_text = LOG_PATH.read_text()
    log_acks = [int(x) for x in re.findall(r'Cache response OK for TXN\s+(\d+)', log_text)]
    common = set(pcap_acks).intersection(log_acks)
    assert common, 'No fully acknowledged transaction was found in both the log and pcap'
    return max(common)


def parse_expected_wal(wal_text, cutoff):
    state = {}
    pattern = re.compile(r'^\[[^\]]+\]\s+\[(\d+)\]\s+SET\s+(\S+)\s+(\S+)\s*$')
    for line in wal_text.splitlines():
        match = pattern.match(line)
        if not match:
            continue
        txn_id, key, value = match.groups()
        if int(txn_id) <= cutoff:
            state[key] = value
    return state


def test_recovered_json_state():
    """Keep the original final-state assertion."""
    assert RECOVERED_PATH.exists(), f'File not found: {RECOVERED_PATH}'
    try:
        with RECOVERED_PATH.open() as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f'Failed to parse {RECOVERED_PATH} as JSON: {exc}')

    expected_data = {
        'build_hash_A': '99283',
        'build_hash_B': '11223'
    }
    assert data == expected_data, (
        f'Recovered JSON state is incorrect. Expected: {expected_data}; got: {data}'
    )


def test_recovery_script_actually_parses_wal():
    cutoff = acknowledged_txn_id()
    assert cutoff == 1045

    candidates = []
    for root in ('/home/user', '/app'):
        for path in Path(root).rglob('*.py'):
            if not path.is_file() or path == SERVER_SOURCE:
                continue
            try:
                source = path.read_text(errors='ignore')
            except OSError:
                continue
            if 'cache.wal' in source and 'recovered.json' in source:
                candidates.append(path)

    assert candidates, 'No Python WAL recovery script was found'

    token = secrets.token_hex(8)
    test_wal = (
        f'[2026-01-01T00:00:01] [1044] SET key_{token}_a value_{token}_a\n'
        f'[2026-01-01T00:00:02] [1045] SET key_{token}_b value_{token}_b\n'
        f'[2026-01-01T00:00:03] [1046] SET key_{token}_unacked bad_{token}\n'
        '[2026-01-01T00:00:04] [1047] SET truncated\n'
    )
    expected = parse_expected_wal(test_wal, cutoff)

    original_wal = WAL_PATH.read_bytes()
    original_recovered = RECOVERED_PATH.read_bytes() if RECOVERED_PATH.exists() else None
    successes = []
    try:
        for candidate in candidates:
            WAL_PATH.write_text(test_wal)
            RECOVERED_PATH.unlink(missing_ok=True)
            try:
                result = subprocess.run(
                    [sys.executable, str(candidate)],
                    cwd='/home/user',
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=10,
                )
            except (subprocess.TimeoutExpired, OSError):
                continue
            if result.returncode != 0 or not RECOVERED_PATH.is_file():
                continue
            try:
                produced = json.loads(RECOVERED_PATH.read_text())
            except (OSError, json.JSONDecodeError):
                continue
            if produced == expected:
                successes.append(str(candidate))
                break
    finally:
        WAL_PATH.write_bytes(original_wal)
        if original_recovered is None:
            RECOVERED_PATH.unlink(missing_ok=True)
        else:
            RECOVERED_PATH.write_bytes(original_recovered)

    assert successes, (
        'No recovery script produced state derived from a changed WAL while excluding '
        'transactions after the acknowledged cutoff'
    )


def wait_for_server(process, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if process.poll() is not None:
            pytest.fail('Cache server exited during startup')
        try:
            import socket
            with socket.create_connection(('127.0.0.1', 8888), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    pytest.fail('Cache server did not listen on 127.0.0.1:8888')


def test_handler_releases_writer_when_cancelled():
    assert SERVER_SOURCE.is_file(), f'Missing server source: {SERVER_SOURCE}'
    probe = r'''import asyncio
import importlib.util
import os

spec = importlib.util.spec_from_file_location('submitted_server', '/app/async-build-cache-1.0.0/async_build_cache/server.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class Reader:
    def __init__(self):
        self.started = asyncio.Event()
    async def read(self, n):
        self.started.set()
        await asyncio.Event().wait()

class Writer:
    def __init__(self):
        self.closed = False
    def write(self, data):
        pass
    async def drain(self):
        pass
    def close(self):
        self.closed = True
    async def wait_closed(self):
        pass
    def is_closing(self):
        return self.closed
    def get_extra_info(self, *args, **kwargs):
        return None

async def check():
    reader, writer = Reader(), Writer()
    task = asyncio.create_task(module.handle_client(reader, writer))
    await reader.started.wait()
    task.cancel()
    done, pending = await asyncio.wait({task}, timeout=0.5)
    if pending:
        os._exit(20)
    try:
        task.result()
    except asyncio.CancelledError:
        pass
    except Exception:
        os._exit(21)
    if not writer.closed:
        os._exit(22)
    os._exit(0)

asyncio.run(check())
'''
    result = subprocess.run(
        [sys.executable, '-c', probe],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=3,
    )
    assert result.returncode == 0, (
        'handle_client did not terminate promptly and close its writer when cancelled. '
        f'Exit code: {result.returncode}; stderr: {result.stderr}'
    )


async def exercise_server():
    async def cancelled_client():
        reader, writer = await asyncio.open_connection('127.0.0.1', 8888)
        writer.write(b'CANCEL\n')
        await writer.drain()
        writer.transport.abort()

    await asyncio.gather(*(cancelled_client() for _ in range(150)))
    await asyncio.sleep(0.25)

    requests_per_client = 80
    clients = 32

    async def load_client():
        reader, writer = await asyncio.open_connection('127.0.0.1', 8888)
        try:
            for _ in range(requests_per_client):
                writer.write(b'GET key\n')
                await writer.drain()
                response = await asyncio.wait_for(reader.readline(), timeout=2)
                assert response == b'ACK\n'
        finally:
            writer.close()
            await writer.wait_closed()

    start = time.perf_counter()
    await asyncio.wait_for(
        asyncio.gather(*(load_client() for _ in range(clients))),
        timeout=20,
    )
    elapsed = time.perf_counter() - start
    return (requests_per_client * clients) / elapsed


def test_server_throughput_and_leak_fix():
    subprocess.run(['pkill', '-f', 'async_build_cache.server'], check=False)
    time.sleep(0.5)

    env = os.environ.copy()
    env['PYTHONPATH'] = PACKAGE_ROOT + os.pathsep + env.get('PYTHONPATH', '')
    server_process = subprocess.Popen(
        [sys.executable, '-m', 'async_build_cache.server'],
        cwd=PACKAGE_ROOT,
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        wait_for_server(server_process)
        throughput = asyncio.run(exercise_server())
        assert server_process.poll() is None, 'Server crashed during cancellation/load testing'
        assert throughput >= 800.0, (
            f'Throughput requirement not met. Expected >= 800.0 req/sec, '
            f'but measured {throughput:.2f} req/sec'
        )
    finally:
        server_process.terminate()
        try:
            server_process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            server_process.kill()
            server_process.wait(timeout=5)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
