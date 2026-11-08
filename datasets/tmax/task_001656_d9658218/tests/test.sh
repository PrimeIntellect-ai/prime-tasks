#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sys
import json
import wave
import struct
import tempfile
import secrets
import requests
import pytest

SERVICE_URL = 'http://127.0.0.1:8000/analyze'
SOURCE_DIR = '/home/user/voicemail_analyzer'


def post_audio(filepath, filename='test.wav'):
    with open(filepath, 'rb') as f:
        try:
            return requests.post(
                SERVICE_URL,
                files={'audio': (filename, f, 'audio/wav')},
                timeout=8,
            )
        except requests.exceptions.RequestException as e:
            pytest.fail(f'Failed to connect to the service at 127.0.0.1:8000: {e}')


def assert_success_response(response, expected_duration, expected_samples, tolerance=1e-12):
    assert response.status_code == 200, (
        f'Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}'
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f'Service did not return valid JSON. Response text: {response.text}')

    assert data.get('status') == 'success', f"Expected status 'success', got {data.get('status')}"
    assert data.get('samples') == expected_samples, (
        f"Expected {expected_samples} samples, got {data.get('samples')}"
    )
    assert isinstance(data.get('duration'), (int, float)), 'duration must be numeric'
    assert abs(data['duration'] - expected_duration) <= tolerance, (
        f"Expected duration {expected_duration}, got {data.get('duration')}"
    )
    return data


def test_evidence_result():
    evidence_path = '/app/evidence.wav'
    result_path = '/home/user/evidence_result.json'

    assert os.path.exists(result_path), (
        f'File {result_path} does not exist. Did you save the result of evidence.wav?'
    )

    with wave.open(evidence_path, 'rb') as w:
        frames = w.getnframes()
        rate = w.getframerate()
        expected_duration = frames / rate
        expected_samples = frames

    with open(result_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'File {result_path} does not contain valid JSON.')

    assert data.get('status') == 'success', f"Expected status 'success', got {data.get('status')}"
    assert data.get('samples') == expected_samples, (
        f"Expected {expected_samples} samples, got {data.get('samples')}"
    )
    assert abs(data.get('duration', 0) - expected_duration) < 1e-4, (
        f"Expected duration ~{expected_duration}, got {data.get('duration')}"
    )

    live_data = assert_success_response(
        post_audio(evidence_path, 'evidence.wav'),
        expected_duration,
        expected_samples,
    )
    assert live_data == data, 'evidence_result.json does not match the live service response'


def create_test_wav_with_fact_chunk(filepath):
    num_channels = 1
    sample_width = 2
    framerate = 44100
    num_frames = 44100
    audio_data = b'\x00\x00' * num_frames

    fmt_chunk = struct.pack(
        '<HHIIHH', 1, num_channels, framerate,
        framerate * num_channels * sample_width,
        num_channels * sample_width, sample_width * 8,
    )
    fmt_chunk_full = b'fmt ' + struct.pack('<I', len(fmt_chunk)) + fmt_chunk
    fact_chunk_data = struct.pack('<I', num_frames)
    fact_chunk_full = b'fact' + struct.pack('<I', len(fact_chunk_data)) + fact_chunk_data
    data_chunk_full = b'data' + struct.pack('<I', len(audio_data)) + audio_data
    riff_data = b'WAVE' + fmt_chunk_full + fact_chunk_full + data_chunk_full

    with open(filepath, 'wb') as f:
        f.write(b'RIFF' + struct.pack('<I', len(riff_data)) + riff_data)
    return 1.0, num_frames


def test_service_analyze_with_fact_chunk():
    with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp:
        filepath = tmp.name
    try:
        expected_duration, expected_samples = create_test_wav_with_fact_chunk(filepath)
        response = post_audio(filepath, 'test_fact.wav')
        assert_success_response(response, expected_duration, expected_samples, 1e-4)
    finally:
        os.remove(filepath)


def wav_chunk(name, payload):
    assert len(name) == 4
    return name + struct.pack('<I', len(payload)) + payload + (b'\x00' if len(payload) & 1 else b'')


def make_wav(path, channels, sample_width, rate, frames, unknown_chunks, silent=False):
    frame_size = channels * sample_width
    if silent:
        audio = b'\x00' * (frames * frame_size)
    else:
        audio = secrets.token_bytes(frames * frame_size)

    fmt = struct.pack(
        '<HHIIHH', 1, channels, rate, rate * frame_size,
        frame_size, sample_width * 8,
    )
    body = b'WAVE' + wav_chunk(b'fmt ', fmt)
    for name, payload in unknown_chunks:
        body += wav_chunk(name, payload)
    body += wav_chunk(b'data', audio)
    with open(path, 'wb') as f:
        f.write(b'RIFF' + struct.pack('<I', len(body)) + body)


def test_service_on_varied_unpredictable_wavs():
    rng = secrets.SystemRandom()
    cases = [
        (2, 2, rng.randrange(12000, 48001), rng.randrange(2301, 7900),
         [(b'JUNK', secrets.token_bytes(7))], False),
        (1, 1, rng.randrange(8000, 32001), rng.randrange(3001, 9000) | 1,
         [(b'fact', struct.pack('<I', rng.randrange(1, 100000))),
          (b'JUNK', secrets.token_bytes(13))], False),
        (2, 3, rng.randrange(16000, 50001), rng.randrange(1700, 6200),
         [(b'LIST', secrets.token_bytes(10)), (b'JUNK', secrets.token_bytes(5))], False),
        (1, 2, 44117, 250003,
         [(b'JUNK', secrets.token_bytes(9)), (b'fact', struct.pack('<I', 250003))], True),
    ]

    for i, (channels, width, rate, frames, chunks, silent) in enumerate(cases):
        with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp:
            path = tmp.name
        try:
            make_wav(path, channels, width, rate, frames, chunks, silent)
            response = post_audio(path, f'random_{i}_{secrets.token_hex(6)}.wav')
            assert_success_response(response, frames / rate, frames)
        finally:
            os.remove(path)


def test_implementation_functions_are_repaired():
    assert os.path.isfile(os.path.join(SOURCE_DIR, 'wav_parser.py'))
    assert os.path.isfile(os.path.join(SOURCE_DIR, 'analyzer.py'))
    sys.path.insert(0, SOURCE_DIR)
    try:
        from wav_parser import parse_wav
        from analyzer import trim_silence, calculate_duration
    finally:
        sys.path.pop(0)

    frames = 3217
    rate = 22037
    with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp:
        path = tmp.name
    try:
        make_wav(
            path, 2, 3, rate, frames,
            [(b'JUNK', secrets.token_bytes(11)), (b'fact', struct.pack('<I', frames))],
        )
        with open(path, 'rb') as f:
            parsed = parse_wav(f.read())
        assert parsed['sample_rate'] == rate
        assert parsed['num_channels'] == 2
        assert parsed['bits_per_sample'] == 24
        assert parsed['data_size'] == frames * 2 * 3
    finally:
        os.remove(path)

    long_silence = b'\x00' * 20000 + b'\x01\x02'
    assert trim_silence(long_silence) == b'\x01\x02'

    precise_frames = 1000003
    precise_rate = 44117
    duration = calculate_duration(precise_frames * 4, precise_rate, 2, 16)
    assert duration == precise_frames / precise_rate, (
        'Duration must be calculated directly from total frames and frame rate'
    )


def test_malformed_multipart_is_handled_without_server_error():
    boundary = '----VerifierBoundary' + secrets.token_hex(8)
    body = (
        f'--{boundary}\r\n'
        'Content-Disposition: form-data; name="wrong_field"\r\n\r\n'
        'not audio\r\n'
        f'--{boundary}--\r\n'
    ).encode()
    try:
        response = requests.post(
            SERVICE_URL,
            data=body,
            headers={'Content-Type': f'multipart/form-data; boundary={boundary}'},
            timeout=5,
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f'Failed to connect to the service: {e}')
    assert 400 <= response.status_code < 500, (
        f'Malformed multipart request should be rejected cleanly, got '
        f'{response.status_code}: {response.text}'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
