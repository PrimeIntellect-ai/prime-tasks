#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import math
import os
import secrets
import struct
import subprocess
import wave

import pytest

DECODER_PATH = "/home/user/decoder.cpp"
EXECUTABLE_PATH = "/tmp/agent_decoder"
ENTROPY_PATH = "/home/user/entropy.txt"
EVIDENCE_PATH = "/app/evidence.wav"

DTMF_FREQS = {
    '1': (697, 1209), '2': (697, 1336), '3': (697, 1477), 'A': (697, 1633),
    '4': (770, 1209), '5': (770, 1336), '6': (770, 1477), 'B': (770, 1633),
    '7': (852, 1209), '8': (852, 1336), '9': (852, 1477), 'C': (852, 1633),
    '*': (941, 1209), '0': (941, 1336), '#': (941, 1477), 'D': (941, 1633),
}
PAIR_TO_SYMBOL = {pair: symbol for symbol, pair in DTMF_FREQS.items()}
LOW_FREQS = (697, 770, 852, 941)
HIGH_FREQS = (1209, 1336, 1477, 1633)


def calc_entropy(data):
    if not data:
        return 0
    entropy = 0
    for x in set(data):
        p_x = float(data.count(x)) / len(data)
        entropy += -p_x * math.log(p_x, 2)
    return entropy


def encode_raw_input(payload):
    digest = hashlib.sha256(payload.encode('ascii')).hexdigest()
    hex_data = payload.encode('ascii').hex() + digest
    return ''.join({'e': '*', 'f': '#'}.get(c, c).upper() for c in hex_data)


def frequency_power(samples, sample_rate, frequency):
    real = 0.0
    imag = 0.0
    scale = 2.0 * math.pi * frequency / sample_rate
    for index, sample in enumerate(samples):
        angle = scale * index
        real += sample * math.cos(angle)
        imag -= sample * math.sin(angle)
    return real * real + imag * imag


def extract_evidence():
    with wave.open(EVIDENCE_PATH, 'rb') as wav_file:
        assert wav_file.getnchannels() == 1
        assert wav_file.getsampwidth() == 2
        sample_rate = wav_file.getframerate()
        frame_count = wav_file.getnframes()
        frames = wav_file.readframes(frame_count)

    samples = struct.unpack('<{}h'.format(frame_count), frames)
    block_size = max(1, sample_rate // 100)
    blocks = [samples[i:i + block_size] for i in range(0, len(samples), block_size)]
    energies = [sum(float(x) * x for x in block) / max(1, len(block)) for block in blocks]
    assert energies and max(energies) > 0
    threshold = max(energies) * 0.05
    active = [energy > threshold for energy in energies]

    runs = []
    start = None
    for index, is_active in enumerate(active + [False]):
        if is_active and start is None:
            start = index
        elif not is_active and start is not None:
            runs.append((start * block_size, min(index * block_size, len(samples))))
            start = None

    assert runs, "No DTMF tones were found in the evidence"
    symbols = []
    for start, end in runs:
        tone = samples[start:end]
        low = max(LOW_FREQS, key=lambda f: frequency_power(tone, sample_rate, f))
        high = max(HIGH_FREQS, key=lambda f: frequency_power(tone, sample_rate, f))
        symbols.append(PAIR_TO_SYMBOL[(low, high)])

    raw_symbols = ''.join(symbols)
    normalized = ''.join({'*': 'e', '#': 'f'}.get(c, c.lower()) for c in raw_symbols)
    assert len(normalized) > 64 and (len(normalized) - 64) % 2 == 0
    payload_hex, supplied_digest = normalized[:-64], normalized[-64:]
    payload_bytes = bytes.fromhex(payload_hex)
    assert hashlib.sha256(payload_bytes).hexdigest() == supplied_digest
    return raw_symbols, payload_bytes.decode('ascii')


def run_decoder(executable, raw_input):
    return subprocess.run(
        [executable, raw_input],
        input=raw_input + '\n',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd='/home/user',
        timeout=10,
    )


@pytest.fixture(scope='session')
def executable():
    result = subprocess.run(
        ['g++', '-std=c++17', '-O2', DECODER_PATH, '-o', EXECUTABLE_PATH, '-lcrypto'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"decoder.cpp failed to compile:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(EXECUTABLE_PATH)
    return EXECUTABLE_PATH


def read_entropy():
    assert os.path.exists(ENTROPY_PATH), f"File not found: {ENTROPY_PATH}"
    with open(ENTROPY_PATH, 'r') as entropy_file:
        content = entropy_file.read().strip()
    try:
        value = float(content)
    except ValueError:
        pytest.fail(f"Could not parse a floating-point number from {ENTROPY_PATH}. Content was: '{content}'")
    assert math.isfinite(value), f"Entropy must be finite, got {value}"
    return value


def test_decoder_cpp_exists():
    """Verify that the user created the decoder.cpp file."""
    decoder_path = "/home/user/decoder.cpp"
    assert os.path.exists(decoder_path), f"File not found: {decoder_path}"
    assert os.path.isfile(decoder_path), f"Path is not a file: {decoder_path}"


def test_decoder_decodes_and_verifies_sha256(executable):
    alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    payload = 'DYNAMIC_PAYLOAD_' + ''.join(secrets.choice(alphabet) for _ in range(24))
    valid_raw = encode_raw_input(payload)

    normalized = ''.join({'*': 'e', '#': 'f'}.get(c, c.lower()) for c in valid_raw)
    replacement = '0' if normalized[-1] != '0' else '1'
    invalid_normalized = normalized[:-1] + replacement
    invalid_raw = ''.join({'e': '*', 'f': '#'}.get(c, c).upper() for c in invalid_normalized)

    if os.path.exists(ENTROPY_PATH):
        os.unlink(ENTROPY_PATH)
    invalid_result = run_decoder(executable, invalid_raw)
    assert payload not in invalid_result.stdout, "Decoder emitted a payload whose SHA-256 checksum was invalid"

    if os.path.exists(ENTROPY_PATH):
        os.unlink(ENTROPY_PATH)
    valid_result = run_decoder(executable, valid_raw)
    assert valid_result.returncode == 0, f"Decoder rejected valid input:\n{valid_result.stdout}\n{valid_result.stderr}"
    assert payload in valid_result.stdout, "Decoder did not output the decoded payload"

    agent_entropy = read_entropy()
    expected_entropy = calc_entropy(payload)
    assert abs(expected_entropy - agent_entropy) <= 1e-6, (
        f"Entropy for dynamic payload was {agent_entropy}; expected {expected_entropy}"
    )


def test_entropy_calculation_accuracy(executable):
    """Verify that the entropy calculated by the agent is within the acceptable tolerance."""
    raw_evidence, decoded_evidence = extract_evidence()
    if os.path.exists(ENTROPY_PATH):
        os.unlink(ENTROPY_PATH)

    result = run_decoder(executable, raw_evidence)
    assert result.returncode == 0, f"Decoder failed on extracted evidence:\n{result.stdout}\n{result.stderr}"
    assert decoded_evidence in result.stdout, "Decoder did not output the payload extracted from evidence.wav"

    entropy_file_path = "/home/user/entropy.txt"
    assert os.path.exists(entropy_file_path), f"File not found: {entropy_file_path}"

    try:
        with open(entropy_file_path, 'r') as f:
            content = f.read().strip()
            agent_entropy = float(content)
    except ValueError:
        pytest.fail(f"Could not parse a floating-point number from {entropy_file_path}. Content was: '{content}'")
    except Exception as e:
        pytest.fail(f"Failed to read {entropy_file_path}: {e}")

    true_string = decoded_evidence
    true_entropy = calc_entropy(true_string)

    diff = abs(true_entropy - agent_entropy)
    tolerance = 0.01

    assert diff <= tolerance, (
        f"Metric failed: Absolute difference between true entropy ({true_entropy}) "
        f"and agent entropy ({agent_entropy}) is {diff}, which is greater than the tolerance of {tolerance}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
