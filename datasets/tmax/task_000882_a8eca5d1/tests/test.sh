#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import socket
import struct
import secrets
import wave
import pytest


def compute_max_sum(filepath, window_size=500):
    with open(filepath, 'rb') as f:
        f.read(44)  # skip header
        data = f.read()

    num_samples = len(data) // 2
    if num_samples == 0:
        return 0

    samples = struct.unpack(f'<{num_samples}h', data)
    abs_samples = [abs(s) for s in samples]

    if num_samples < window_size:
        return sum(abs_samples)

    current_sum = sum(abs_samples[:window_size])
    max_sum = current_sum

    for i in range(window_size, num_samples):
        current_sum += abs_samples[i] - abs_samples[i - window_size]
        if current_sum > max_sum:
            max_sum = current_sum

    return max_sum


def request_server(request_str):
    try:
        s = socket.create_connection(("127.0.0.1", 7777), timeout=5.0)
        s.settimeout(5.0)
    except Exception as e:
        pytest.fail(f"Failed to connect to the server at 127.0.0.1:7777: {e}")

    chunks = []
    try:
        s.sendall(request_str.encode('utf-8'))
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            chunks.append(chunk)
    except Exception as e:
        pytest.fail(f"Failed to send/receive data or server did not close the connection: {e}")
    finally:
        s.close()

    response_bytes = b''.join(chunks)
    assert response_bytes, "Received empty response from the server."
    return response_bytes.decode('utf-8').strip()


def test_server_compiled():
    assert os.path.isfile("/home/user/server"), "The server executable /home/user/server is missing."
    assert os.access("/home/user/server", os.X_OK), "The server executable is not executable."


def test_server_response():
    audio_path = "/app/audio.wav"
    assert os.path.isfile(audio_path), f"Audio file {audio_path} is missing."

    expected_max = compute_max_sum(audio_path, 500)

    host = "127.0.0.1"
    port = 7777

    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(5.0)
        s.connect((host, port))
    except Exception as e:
        pytest.fail(f"Failed to connect to the server at {host}:{port}: {e}")

    request_str = '{"text": "Data \\u03A9"}\n'
    try:
        s.sendall(request_str.encode('utf-8'))
        response_bytes = s.recv(4096)
    except Exception as e:
        s.close()
        pytest.fail(f"Failed to send/receive data: {e}")
    finally:
        s.close()

    assert response_bytes, "Received empty response from the server."

    response_str = response_bytes.decode('utf-8').strip()
    expected_response = f'{{"decoded": "Data Ω", "max_sum": {expected_max}}}'

    assert response_str == expected_response, f"Expected response '{expected_response}', but got '{response_str}'"


def test_dynamic_unicode_and_audio_processing():
    audio_path = "/app/audio.wav"
    with open(audio_path, 'rb') as f:
        original_audio = f.read()
    original_max = compute_max_sum(audio_path, 500)

    try:
        # Replace the WAV after the server has started so a precomputed maximum
        # cannot satisfy the test. A conforming server reads it per request.
        while True:
            samples = [secrets.randbelow(65536) - 32768 for _ in range(2000)]
            with wave.open(audio_path, 'wb') as w:
                w.setnchannels(1)
                w.setsampwidth(2)
                w.setframerate(44100)
                w.writeframes(struct.pack('<' + 'h' * len(samples), *samples))
            expected_max = compute_max_sum(audio_path, 500)
            if expected_max != original_max:
                break

        ranges = [(0x0100, 0x017F), (0x0370, 0x03FF), (0x0400, 0x04FF)]
        for _ in range(3):
            lo1, hi1 = ranges[secrets.randbelow(len(ranges))]
            lo2, hi2 = ranges[secrets.randbelow(len(ranges))]
            cp1 = lo1 + secrets.randbelow(hi1 - lo1 + 1)
            cp2 = lo2 + secrets.randbelow(hi2 - lo2 + 1)
            nonce = secrets.token_hex(6)

            escaped_text = f"Probe-{nonce} \\u{cp1:04X}/\\u{cp2:04X}"
            decoded_text = f"Probe-{nonce} {chr(cp1)}/{chr(cp2)}"
            request_str = '{"text": "' + escaped_text + '"}\n'
            expected_response = f'{{"decoded": "{decoded_text}", "max_sum": {expected_max}}}'
            response_str = request_server(request_str)

            assert response_str == expected_response, (
                f"Expected response '{expected_response}', but got '{response_str}'"
            )
    finally:
        with open(audio_path, 'wb') as f:
            f.write(original_audio)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
