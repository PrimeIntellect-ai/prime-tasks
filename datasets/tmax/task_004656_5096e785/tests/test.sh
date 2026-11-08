#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import stat
import wave
import struct

def test_redacted_wav_exists():
    assert os.path.isfile("/home/user/redacted.wav"), "The file /home/user/redacted.wav is missing."

def test_redacted_wav_permissions():
    target_file = "/home/user/redacted.wav"
    assert os.path.isfile(target_file), "The file /home/user/redacted.wav is missing."
    mode = os.stat(target_file).st_mode
    assert stat.S_IMODE(mode) == 0o600, f"Expected permissions 600, got {oct(stat.S_IMODE(mode))}"

def test_redacted_wav_accuracy():
    target_file = "/home/user/redacted.wav"
    ref_file = "/app/token.wav"

    assert os.path.isfile(target_file), "The file /home/user/redacted.wav is missing."
    assert os.path.isfile(ref_file), "The reference file /app/token.wav is missing."

    with wave.open(target_file, 'rb') as w_target, wave.open(ref_file, 'rb') as w_ref:
        target_frames = w_target.readframes(w_target.getnframes())
        ref_frames = w_ref.readframes(w_ref.getnframes())

        target_samples = list(struct.unpack('<' + 'h' * (len(target_frames) // 2), target_frames))
        ref_samples = list(struct.unpack('<' + 'h' * (len(ref_frames) // 2), ref_frames))

        assert len(target_samples) == len(ref_samples), f"Frame count mismatch: target has {len(target_samples)}, ref has {len(ref_samples)}"

        SR = 44100
        intervals = [
            (int(1.500 * SR), int(2.000 * SR)),
            (int(4.125 * SR), int(5.000 * SR)),
            (int(8.000 * SR), int(9.000 * SR)),
        ]

        matches = 0
        total = len(ref_samples)

        for i in range(total):
            in_leak = any(start <= i < end for start, end in intervals)
            expected_val = 0 if in_leak else ref_samples[i]
            if target_samples[i] == expected_val:
                matches += 1

        accuracy = matches / total
        assert accuracy >= 0.999, f"Accuracy {accuracy:.4f} is below the threshold of 0.999"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
