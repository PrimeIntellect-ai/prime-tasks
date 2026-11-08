#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /app
    # Generate test_audio.wav
    python3 -c "
import numpy as np
import scipy.io.wavfile as wav
rate = 44100
t = np.linspace(0, 5, 5*rate, endpoint=False)
# 5 seconds of mixed sine waves
data = np.sin(2*np.pi*440*t) + np.sin(2*np.pi*100*t)
data = (data * 10000).astype(np.int16)
wav.write('/app/test_audio.wav', rate, data)
"

    mkdir -p /home/user/audio_biquad

    cat << 'EOF' > /home/user/audio_biquad/biquad.py
import numpy as np

class BiquadFilter:
    def __init__(self, b0, b1, b2, a1, a2):
        self.b0, self.b1, self.b2 = b0, b1, b2
        self.a1, self.a2 = a1, a2
        self.x1 = self.x2 = 0.0
        self.y1 = self.y2 = 0.0

    def process(self, input_signal):
        # BUG: The internal arrays are forced to float32, and the accumulation 
        # suffers from catastrophic cancellation for certain extreme signals.
        input_signal = np.asarray(input_signal, dtype=np.float32)
        output = np.zeros_like(input_signal, dtype=np.float32)

        for i in range(len(input_signal)):
            x0 = input_signal[i]
            # Floating point truncation/explosion happens here due to float32
            y0 = np.float32(self.b0 * x0 + self.b1 * self.x1 + self.b2 * self.x2 
                            - self.a1 * self.y1 - self.a2 * self.y2)

            output[i] = y0
            self.x2 = self.x1
            self.x1 = x0
            self.y2 = self.y1
            self.y1 = y0

        return output
EOF

    cat << 'EOF' > /home/user/audio_biquad/fuzz_test.py
import numpy as np
import pytest
from biquad import BiquadFilter

def test_fuzz_biquad_stability():
    # Extreme low frequency resonance coefficients
    # This filter is marginally stable and requires float64 precision
    b0, b1, b2 = 0.0001, 0.0002, 0.0001
    a1, a2 = -1.98, 0.9801

    np.random.seed(42)
    for _ in range(100):
        # Fuzzer generates high amplitude low frequency noise
        signal = np.random.randn(1000) * 10000 

        filt = BiquadFilter(b0, b1, b2, a1, a2)
        out = filt.process(signal)

        assert not np.any(np.isnan(out)), "NaN detected in output!"
        assert not np.any(np.isinf(out)), "Inf detected in output!"
        assert np.max(np.abs(out)) < 1e7, "Output exploded numerically!"
EOF

    cat << 'EOF' > /home/user/audio_biquad/apply_filter.py
import argparse
import numpy as np
import scipy.io.wavfile as wav
from biquad import BiquadFilter

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input_wav")
    parser.add_argument("output_wav")
    args = parser.parse_args()

    rate, data = wav.read(args.input_wav)
    # Convert to float for processing
    if data.dtype == np.int16:
        data = data.astype(np.float32) / 32768.0

    # Apply a standard low-pass filter (marginally stable)
    b0, b1, b2 = 0.0001, 0.0002, 0.0001
    a1, a2 = -1.98, 0.9801
    filt = BiquadFilter(b0, b1, b2, a1, a2)

    out = filt.process(data)

    # Clip and convert back
    out = np.clip(out, -1.0, 1.0)
    out_int16 = (out * 32767).astype(np.int16)
    wav.write(args.output_wav, rate, out_int16)

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
