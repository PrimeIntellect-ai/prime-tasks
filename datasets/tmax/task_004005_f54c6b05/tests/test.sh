#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import struct
import subprocess
import sys
import tempfile
import wave

import numpy as np
import pytest
from scipy.io import wavfile


def run(cmd):
    return subprocess.run(cmd, check=True, timeout=15, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


@pytest.fixture(scope='session', autouse=True)
def build_and_exercise_toolchain():
    encoder_src = '/app/encoder.cpp'
    decoder_src = '/app/decoder.cpp'
    original_path = '/app/suspicious_payload.wav'
    recovered_path = '/home/user/recovered.wav'

    assert os.path.isfile(encoder_src), f"Encoder source missing: {encoder_src}"
    assert os.path.isfile(decoder_src), f"Decoder source missing: {decoder_src}"

    with tempfile.TemporaryDirectory(prefix='toolchain_verify_') as td:
        encoder_bin = os.path.join(td, 'encoder')
        decoder_bin = os.path.join(td, 'decoder')
        run(['g++', '-std=c++17', '-O2', encoder_src, '-o', encoder_bin])
        run(['g++', '-std=c++17', '-O2', decoder_src, '-o', decoder_bin])

        # Exercise the encoder on verifier-generated WAV data and verify the
        # required size-header-plus-bytes serialization, rather than trusting
        # an output supplied by the agent.
        probe_wav = os.path.join(td, 'probe.wav')
        probe_encoded = os.path.join(td, 'probe.bin')
        probe_decoded = os.path.join(td, 'probe_decoded.wav')
        pcm = os.urandom(4096)
        with wave.open(probe_wav, 'wb') as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(22050)
            wav.writeframes(pcm)

        with open(probe_wav, 'rb') as f:
            probe_bytes = f.read()
        run([encoder_bin, probe_wav, probe_encoded])
        with open(probe_encoded, 'rb') as f:
            encoded_bytes = f.read()

        size_width = ctypes.sizeof(ctypes.c_size_t)
        expected_header = len(probe_bytes).to_bytes(size_width, byteorder=sys.byteorder, signed=False)
        assert encoded_bytes == expected_header + probe_bytes, 'Encoder did not serialize the size and actual file bytes correctly'

        run([decoder_bin, probe_encoded, probe_decoded])
        with open(probe_decoded, 'rb') as f:
            assert f.read() == probe_bytes, 'Compiled encoder/decoder round trip corrupted verifier-generated input'

        # Test the decoder independently using an encoded payload constructed
        # by the verifier.
        independent_data = os.urandom(8193)
        independent_encoded = os.path.join(td, 'independent.bin')
        independent_decoded = os.path.join(td, 'independent.out')
        with open(independent_encoded, 'wb') as f:
            f.write(len(independent_data).to_bytes(size_width, byteorder=sys.byteorder, signed=False))
            f.write(independent_data)
        run([decoder_bin, independent_encoded, independent_decoded])
        with open(independent_decoded, 'rb') as f:
            assert f.read() == independent_data, 'Decoder failed on a verifier-constructed encoded payload'

        # Produce the required final artifact by actually running both freshly
        # compiled submitted programs on the supplied payload.
        final_encoded = os.path.join(td, 'suspicious_payload.bin')
        run([encoder_bin, original_path, final_encoded])
        run([decoder_bin, final_encoded, recovered_path])

    yield


def test_recovered_wav_matches_original():
    original_path = '/app/suspicious_payload.wav'
    recovered_path = '/home/user/recovered.wav'

    assert os.path.isfile(original_path), f"Original file missing: {original_path}"
    assert os.path.isfile(recovered_path), f"Recovered file missing: {recovered_path}"

    try:
        sr1, data1 = wavfile.read(original_path)
    except Exception as e:
        assert False, f"Failed to read original wav file: {e}"

    try:
        sr2, data2 = wavfile.read(recovered_path)
    except Exception as e:
        assert False, f"Failed to read recovered wav file: {e}"

    assert sr1 == sr2, f"Sample rate mismatch: {sr1} != {sr2}"
    assert len(data1) == len(data2), f"Length mismatch: {len(data1)} != {len(data2)}"

    data1 = data1.astype(np.float64)
    data2 = data2.astype(np.float64)

    mse = np.mean((data1 - data2) ** 2)
    threshold = 0.0001

    assert mse <= threshold, f"MSE {mse} exceeds threshold {threshold}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
