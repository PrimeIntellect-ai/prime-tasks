#!/bin/bash
mkdir -p /logs/verifier

RUN_STATUS=0
rm -f /home/user/transformed_artifacts.json /home/user/benchmark.log
if [ ! -x /home/user/run.sh ]; then
    RUN_STATUS=126
else
    timeout 180s /home/user/run.sh >/tmp/orchestrator.out 2>/tmp/orchestrator.err || RUN_STATUS=$?
fi
printf '%s\n' "$RUN_STATUS" > /tmp/orchestrator_status

cat << 'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import json
import math
import os
import random
import re
import socket
import subprocess
import threading
import time

import pytest

BENCHMARK_PATTERN = re.compile(
    r"^Processed 10000 messages in (\d+\.\d{4}) seconds\. "
    r"Throughput: (\d+\.\d{4}) msgs/sec\.$"
)


def read_benchmark():
    with open('/home/user/benchmark.log', 'r') as f:
        content = f.read().strip()
    match = BENCHMARK_PATTERN.fullmatch(content)
    assert match, f"Benchmark log format is incorrect. Got: '{content}'"
    return float(match.group(1)), float(match.group(2))


def test_orchestrator_was_executed_and_cleaned_up():
    with open('/tmp/orchestrator_status', 'r') as f:
        status = int(f.read().strip())
    assert status == 0, (
        f"/home/user/run.sh did not complete successfully (status {status}).\n"
        f"stdout:\n{open('/tmp/orchestrator.out').read()}\n"
        f"stderr:\n{open('/tmp/orchestrator.err').read()}"
    )
    assert os.access('/home/user/run.sh', os.X_OK), '/home/user/run.sh is not executable.'

    # The orchestrator must not leave its server listening after the client exits.
    with socket.socket() as sock:
        sock.settimeout(0.5)
        assert sock.connect_ex(('127.0.0.1', 8888)) != 0, (
            'run.sh left a WebSocket server running on port 8888.'
        )


def test_transformed_artifacts_json():
    """Verify the transformed_artifacts.json file exists and has the correct structure."""
    file_path = '/home/user/transformed_artifacts.json'
    assert os.path.exists(file_path), f"File {file_path} does not exist."

    with open(file_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} is not valid JSON.")

    assert isinstance(data, list), "JSON data should be an array."
    assert len(data) == 10000, f"Expected 10000 entries, found {len(data)}."

    # Keep the original first-entry assertions.
    first_entry = data[0]
    assert first_entry.get('id') == 1, f"Expected first entry id to be 1, got {first_entry.get('id')}."
    assert first_entry.get('filename') == 'build_bin_1.zip', f"Expected first entry filename to be 'build_bin_1.zip', got '{first_entry.get('filename')}'."
    assert isinstance(first_entry.get('total_coverage'), (int, float)), "total_coverage should be a number."

    # Keep the original last-entry assertions.
    last_entry = data[-1]
    assert last_entry.get('id') == 10000, f"Expected last entry id to be 10000, got {last_entry.get('id')}."
    assert last_entry.get('filename') == 'build_bin_10000.zip', f"Expected last entry filename to be 'build_bin_10000.zip', got '{last_entry.get('filename')}'."
    assert isinstance(last_entry.get('total_coverage'), (int, float)), "total_coverage should be a number."

    # Validate every entry rather than only the fixed endpoints.
    for expected_id, entry in enumerate(data, 1):
        assert isinstance(entry, dict), f'Entry {expected_id} is not an object.'
        assert set(entry) == {'id', 'filename', 'total_coverage'}, (
            f'Entry {expected_id} has an incorrect flattened structure.'
        )
        assert entry['id'] == expected_id, f'Entry {expected_id} has the wrong id.'
        assert entry['filename'] == f'build_bin_{expected_id}.zip', (
            f'Entry {expected_id} has the wrong filename.'
        )
        coverage = entry['total_coverage']
        assert isinstance(coverage, (int, float)) and not isinstance(coverage, bool)
        assert math.isfinite(coverage) and 0 <= coverage <= 200, (
            f'Entry {expected_id} has invalid total_coverage.'
        )


def test_benchmark_log():
    """Verify the benchmark.log file exists and matches the required format."""
    file_path = '/home/user/benchmark.log'
    assert os.path.exists(file_path), f"File {file_path} does not exist."

    with open(file_path, 'r') as f:
        log_content = f.read().strip()

    pattern = re.compile(r"^Processed 10000 messages in \d+\.\d{4} seconds\. Throughput: \d+\.\d{4} msgs/sec\.$")
    assert pattern.match(log_content), f"Benchmark log format is incorrect. Got: '{log_content}'"
    elapsed, rate = read_benchmark()
    assert elapsed > 0 and rate > 0, 'Benchmark values must be positive.'


def test_scripts_exist():
    """Verify that the required scripts were created."""
    scripts = [
        "/home/user/ws_server.py",
        "/home/user/ws_client.py",
        "/home/user/run.sh"
    ]
    for script in scripts:
        assert os.path.exists(script), f"Required script {script} does not exist."


def test_websocket_server_streams_all_required_messages():
    import websockets

    process = subprocess.Popen(
        ['python3', '/home/user/ws_server.py'],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )

    async def collect():
        deadline = time.monotonic() + 10
        websocket = None
        while time.monotonic() < deadline:
            if process.poll() is not None:
                pytest.fail(f'ws_server.py exited early: {process.stderr.read()}')
            try:
                websocket = await websockets.connect('ws://127.0.0.1:8888')
                break
            except (OSError, websockets.exceptions.WebSocketException):
                await asyncio.sleep(0.05)
        assert websocket is not None, 'ws_server.py did not listen on ws://127.0.0.1:8888.'

        messages = []
        try:
            while True:
                try:
                    messages.append(await asyncio.wait_for(websocket.recv(), timeout=10))
                except websockets.exceptions.ConnectionClosed:
                    break
        finally:
            await websocket.close()
        return messages

    try:
        raw_messages = asyncio.run(asyncio.wait_for(collect(), timeout=60))
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)

    assert len(raw_messages) == 10000, (
        f'Server sent {len(raw_messages)} messages instead of exactly 10000.'
    )
    for expected_id, raw in enumerate(raw_messages, 1):
        try:
            message = json.loads(raw)
        except (TypeError, json.JSONDecodeError) as exc:
            pytest.fail(f'Server message {expected_id} is not valid JSON: {exc}')

        assert set(message) == {'build_id', 'artifact', 'test_coverage'}
        assert message['build_id'] == expected_id

        artifact = message['artifact']
        assert isinstance(artifact, dict) and set(artifact) == {'name', 'size_bytes'}
        assert artifact['name'] == f'build_bin_{expected_id}.zip'
        size = artifact['size_bytes']
        assert isinstance(size, int) and not isinstance(size, bool)
        assert 1000 <= size <= 50000

        coverage = message['test_coverage']
        assert isinstance(coverage, dict) and set(coverage) == {'unit', 'integration'}
        for key in ('unit', 'integration'):
            value = coverage[key]
            assert isinstance(value, float), f'{key} coverage in message {expected_id} is not a float.'
            assert math.isfinite(value) and 0 <= value <= 100


def test_websocket_client_transforms_verifier_generated_messages():
    import websockets

    rng = random.SystemRandom()
    source_messages = []
    expected = []
    for build_id in range(1, 10001):
        unit = rng.randrange(0, 1000001) / 10000.0
        integration = rng.randrange(0, 1000001) / 10000.0
        name = f'build_bin_{build_id}.zip'
        source_messages.append({
            'build_id': build_id,
            'artifact': {
                'name': name,
                'size_bytes': rng.randint(1000, 50000),
            },
            'test_coverage': {
                'unit': unit,
                'integration': integration,
            },
        })
        expected.append({
            'id': build_id,
            'filename': name,
            'total_coverage': unit + integration,
        })

    ready = threading.Event()
    errors = []

    def server_thread():
        async def run_server():
            completed = asyncio.Event()

            async def handler(websocket, *args):
                try:
                    # This delay detects clients that start timing before the first message.
                    await asyncio.sleep(2.0)
                    await websocket.send(json.dumps(source_messages[0]))
                    # This delay must be included because it occurs after the first message.
                    await asyncio.sleep(0.25)
                    for message in source_messages[1:]:
                        await websocket.send(json.dumps(message))
                    await websocket.close()
                finally:
                    completed.set()

            async with websockets.serve(handler, '127.0.0.1', 8888):
                ready.set()
                await asyncio.wait_for(completed.wait(), timeout=60)

        try:
            asyncio.run(run_server())
        except BaseException as exc:
            errors.append(exc)
            ready.set()

    thread = threading.Thread(target=server_thread, daemon=True)
    thread.start()
    assert ready.wait(10), 'Verifier-controlled WebSocket server failed to start.'
    assert not errors, f'Verifier-controlled server failed: {errors}'

    os.remove('/home/user/transformed_artifacts.json') if os.path.exists('/home/user/transformed_artifacts.json') else None
    os.remove('/home/user/benchmark.log') if os.path.exists('/home/user/benchmark.log') else None

    result = subprocess.run(
        ['python3', '/home/user/ws_client.py'],
        capture_output=True,
        text=True,
        timeout=90,
    )
    thread.join(timeout=10)
    assert result.returncode == 0, (
        f'ws_client.py failed. stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert not thread.is_alive(), 'ws_client.py did not consume the stream through server closure.'
    assert not errors, f'Controlled server failed while serving the client: {errors}'

    with open('/home/user/transformed_artifacts.json', 'r') as f:
        actual = json.load(f)
    assert isinstance(actual, list) and len(actual) == 10000

    for index, (got, wanted) in enumerate(zip(actual, expected), 1):
        assert isinstance(got, dict) and set(got) == {'id', 'filename', 'total_coverage'}
        assert got['id'] == wanted['id'], f'Wrong id at client output entry {index}.'
        assert got['filename'] == wanted['filename'], f'Wrong filename at entry {index}.'
        assert got['total_coverage'] == pytest.approx(wanted['total_coverage'], abs=1e-12), (
            f'Client did not sum the transmitted coverage values at entry {index}.'
        )

    elapsed, rate = read_benchmark()
    assert elapsed >= 0.20, 'Client stopped its timer before the connection closed.'
    assert elapsed < 1.90, 'Client appears to have started timing before the first message.'
    expected_rate = 10000 / elapsed
    assert abs(rate - expected_rate) / expected_rate < 0.02, (
        'Reported throughput is inconsistent with the reported processing time.'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

# Avoid leaving an agent server behind after a failed cleanup assertion.
pkill -f '^python3 /home/user/ws_server.py$' >/dev/null 2>&1 || true
