#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import collections
import os
import random
import secrets
import socket
import struct
import subprocess
import threading
import time

import pytest


def encode_payload(data: bytes) -> bytes:
    xored = bytes(b ^ 0x5A for b in data)
    b64 = base64.b64encode(xored)
    return struct.pack('>I', len(b64)) + b64


def encoded_body(data: bytes) -> bytes:
    return base64.b64encode(bytes(b ^ 0x5A for b in data))


def test_proxy_exists():
    assert os.path.exists('/home/user/proxy.py'), 'Proxy script /home/user/proxy.py does not exist.'
    assert os.path.isfile('/home/user/proxy.py'), 'Proxy script /home/user/proxy.py is not a regular file.'


def test_proxy_f1_score():
    subprocess.run(['fuser', '-k', '8001/tcp'], capture_output=True)
    time.sleep(0.5)

    received_payloads = []
    stop_event = threading.Event()
    ready_event = threading.Event()
    consumer_errors = []

    def consumer_thread():
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            try:
                s.bind(('127.0.0.1', 8001))
                s.listen(20)
                s.settimeout(0.25)
                ready_event.set()
            except Exception as exc:
                consumer_errors.append(exc)
                ready_event.set()
                return

            while not stop_event.is_set():
                try:
                    conn, _ = s.accept()
                except socket.timeout:
                    continue
                except Exception:
                    break

                with conn:
                    conn.settimeout(0.25)
                    buffer = b''
                    while not stop_event.is_set():
                        try:
                            chunk = conn.recv(65536)
                            if not chunk:
                                break
                            buffer += chunk
                            while len(buffer) >= 4:
                                length = struct.unpack('>I', buffer[:4])[0]
                                if len(buffer) < 4 + length:
                                    break
                                received_payloads.append(buffer[4:4 + length])
                                buffer = buffer[4 + length:]
                        except socket.timeout:
                            continue
                        except Exception:
                            break

    consumer = threading.Thread(target=consumer_thread, daemon=True)
    consumer.start()
    assert ready_event.wait(3), 'Mock consumer did not start.'
    assert not consumer_errors, f'Mock consumer failed to start: {consumer_errors}'

    submitted_proxy = None
    try:
        # Preserve the original requirement that the agent left a proxy running.
        try:
            with socket.create_connection(('127.0.0.1', 8000), timeout=3):
                pass
        except Exception as exc:
            pytest.fail(f'Connection to proxy on 127.0.0.1:8000 was refused. Is the proxy running? ({exc})')

        # Then execute the submitted artifact itself so another process cannot stand in for it.
        subprocess.run(['fuser', '-k', '8000/tcp'], capture_output=True)
        time.sleep(0.5)
        submitted_proxy = subprocess.Popen(
            ['python3', '/home/user/proxy.py'],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        deadline = time.time() + 5
        while True:
            try:
                with socket.create_connection(('127.0.0.1', 8000), timeout=0.25):
                    break
            except OSError:
                if time.time() >= deadline:
                    pytest.fail('The submitted /home/user/proxy.py did not listen on port 8000.')
                time.sleep(0.1)

        fixture_benign = b'SENSOR_DATA_99.8_OK'
        fixture_malicious = b'SYSTEM_INIT_CRASH_OVERRIDE_V1_TRIGGER'

        # Retain the original fixture traffic and add unpredictable, varied messages.
        cases = [(fixture_benign, False)] * 100
        cases += [(fixture_malicious, True)] * 20

        nonce = secrets.token_hex(16).encode()
        for i in range(80):
            padding = bytes([65 + (i % 26)]) * (i % 41)
            payload = b'TELEMETRY_' + nonce + b'_' + str(i).encode() + b'_' + padding + b'_OK'
            assert b'CRASH_OVERRIDE_V1' not in payload
            cases.append((payload, False))

        marker = b'CRASH_OVERRIDE_V1'
        for i in range(40):
            prefix = b'ALERT_' + nonce + b'_' + str(i).encode() + b'_'
            suffix = b'_' + bytes([97 + (i % 26)]) * (i % 37) + b'_END'
            if i % 3 == 0:
                payload = marker + prefix + suffix
            elif i % 3 == 1:
                payload = prefix + marker + suffix
            else:
                payload = prefix + suffix + marker
            cases.append((payload, True))

        random.SystemRandom().shuffle(cases)

        # Exercise multiple consecutive producer connections with mixed frame types.
        connection_count = 12
        batches = [cases[i::connection_count] for i in range(connection_count)]
        for batch in batches:
            with socket.create_connection(('127.0.0.1', 8000), timeout=5) as client:
                client.settimeout(5)
                for payload, _ in batch:
                    client.sendall(encode_payload(payload))
            time.sleep(0.03)

        time.sleep(2)

        expected_benign = collections.Counter(
            encoded_body(payload) for payload, malicious in cases if not malicious
        )
        expected_malicious = collections.Counter(
            encoded_body(payload) for payload, malicious in cases if malicious
        )
        actual = collections.Counter(received_payloads)
        expected_all = expected_benign + expected_malicious

        unexpected = {
            payload: count
            for payload, count in actual.items()
            if payload not in expected_all or count > expected_all[payload]
        }
        assert not unexpected, 'Proxy forwarded altered, fabricated, or duplicate payloads.'

        benign_received = sum(
            min(actual[payload], count) for payload, count in expected_benign.items()
        )
        malicious_received = sum(
            min(actual[payload], count) for payload, count in expected_malicious.items()
        )
        num_benign = sum(expected_benign.values())
        num_malicious = sum(expected_malicious.values())

        # True Positives = Dropped Malicious
        tp = num_malicious - malicious_received
        # False Positives = Dropped Benign
        fp = num_benign - benign_received
        # False Negatives = Forwarded Malicious
        fn = malicious_received

        precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
        recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
        f1 = 2 * (precision * recall) / (precision + recall) if (precision + recall) > 0 else 0.0

        assert f1 >= 0.99, f'F1 score {f1:.4f} is below threshold 0.99. TP={tp}, FP={fp}, FN={fn}. Benign received: {benign_received}/{num_benign}, Malicious received: {malicious_received}/{num_malicious}.'
    finally:
        if submitted_proxy is not None and submitted_proxy.poll() is None:
            submitted_proxy.terminate()
            try:
                submitted_proxy.wait(timeout=2)
            except subprocess.TimeoutExpired:
                submitted_proxy.kill()
        subprocess.run(['fuser', '-k', '8000/tcp'], capture_output=True)
        stop_event.set()
        consumer.join(timeout=3)


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
