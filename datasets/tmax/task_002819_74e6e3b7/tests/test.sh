#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import py_compile
import random
import socket
import stat
import struct
import subprocess
import threading
import time

import redis

APP = '/home/user/app/aggregator.py'
HOST = '127.0.0.1'
PORT = 8081


def ensure_redis():
    client = redis.Redis(host='localhost', port=6379, db=0)
    try:
        client.ping()
    except Exception:
        subprocess.run(['redis-server', '--daemonize', 'yes'], check=True)
        deadline = time.time() + 5
        while True:
            try:
                client.ping()
                break
            except Exception:
                if time.time() >= deadline:
                    raise
                time.sleep(0.1)
    return client


def float32(value):
    return struct.unpack('<f', struct.pack('<f', value))[0]


def population_variance(values):
    mean = math.fsum(values) / len(values)
    return math.fsum((value - mean) ** 2 for value in values) / len(values)


def test_aggregator_parses_stream_and_computes_variances():
    assert os.path.exists(APP), 'aggregator.py is missing'
    assert stat.S_ISREG(os.stat(APP).st_mode), 'aggregator.py must be a regular file'
    py_compile.compile(APP, doraise=True)

    subprocess.run(['pkill', '-f', '/home/user/app/aggregator.py'], check=False)
    subprocess.run(['pkill', '-f', '/home/user/app/sensor_sim.py'], check=False)

    client = ensure_redis()
    client.delete('batch_variances')

    # Generate fresh, high-offset inputs at verification time. Expected answers are
    # derived from the exact float32 values sent over the wire.
    rng = random.SystemRandom()
    scales = [0.02, 0.05, 0.12, 0.25, 0.5, 0.9, 1.4, 2.0, 0.08, 0.35, 0.7, 1.7]
    batches = []
    for scale in scales:
        values = [float32(100000.0 + rng.uniform(-scale, scale)) for _ in range(100)]
        batches.append(values)
    expected = [population_variance(values) for values in batches]
    assert max(expected) - min(expected) > 0.2

    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind((HOST, PORT))
    listener.listen(1)
    listener.settimeout(10)
    server_errors = []

    def serve():
        try:
            conn, _ = listener.accept()
            with conn:
                conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                for index, values in enumerate(batches):
                    if index in (0, 2, 5, 7, 10):
                        # Fragment the heartbeat so correct code cannot rely on recv
                        # preserving send boundaries.
                        for piece in (b'\x00', b'\x00\xff', b'\xff'):
                            conn.sendall(piece)
                            time.sleep(0.003)

                    payload = struct.pack('<100f', *values)
                    header = struct.pack('<H', len(payload))
                    # Deliberately split the two-byte packet header as well.
                    conn.sendall(header[:1])
                    time.sleep(0.003)
                    conn.sendall(header[1:])
                    time.sleep(0.002)

                    position = 0
                    while position < len(payload):
                        size = rng.randint(1, 31)
                        conn.sendall(payload[position:position + size])
                        position += size
                        time.sleep(0.0002)
                try:
                    conn.shutdown(socket.SHUT_WR)
                except OSError:
                    pass
        except Exception as exc:
            server_errors.append(exc)
        finally:
            listener.close()

    thread = threading.Thread(target=serve, daemon=True)
    thread.start()
    process = subprocess.Popen(
        ['python3', APP],
        cwd='/home/user/app',
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )

    try:
        try:
            output, _ = process.communicate(timeout=20)
        except subprocess.TimeoutExpired:
            process.kill()
            output, _ = process.communicate()
            raise AssertionError('aggregator.py did not terminate after the sensor stream closed')

        thread.join(timeout=3)
        assert not thread.is_alive(), 'test sensor server did not finish'
        assert not server_errors, f'test sensor server failed: {server_errors}'
        assert process.returncode == 0, f'aggregator.py exited with {process.returncode}:\n{output}'

        raw_results = client.lrange('batch_variances', 0, -1)
        assert len(raw_results) == len(expected), (
            f'expected {len(expected)} variance results, got {len(raw_results)}; '
            f'aggregator output:\n{output}'
        )
        actual = [float(value) for value in raw_results]
        assert all(math.isfinite(value) for value in actual), f'non-finite results: {actual}'

        mse = math.fsum((got - want) ** 2 for got, want in zip(actual, expected)) / len(expected)
        assert mse <= 1e-6, (
            f'MSE is {mse}, greater than 1e-6. Actual={actual}; expected={expected}'
        )
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        subprocess.run(['pkill', '-f', '/home/user/app/aggregator.py'], check=False)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
