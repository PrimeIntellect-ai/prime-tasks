#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/generate_wav.py
import wave
import struct
import math

with wave.open('/app/diagnostic_recording.wav', 'wb') as wf:
    wf.setnchannels(1)
    wf.setsampwidth(2)
    wf.setframerate(44100)
    frames = []
    for i in range(44100 * 2): # 2 seconds
        val = int(32767.0 * math.sin(2.0 * math.pi * 440.0 * i / 44100.0))
        frames.append(struct.pack('<h', val))
    wf.writeframes(b''.join(frames))
EOF
    python3 /app/generate_wav.py

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/pipeline

    cat << 'EOF' > /home/user/pipeline/run.sh
#!/bin/bash
cd /home/user/pipeline
g++ -o aggregate aggregate.cpp
python3 extract.py /app/diagnostic_recording.wav | ./aggregate | python3 analyze.py
EOF
    chmod +x /home/user/pipeline/run.sh

    cat << 'EOF' > /home/user/pipeline/extract.py
import sys
import wave
import struct

def main():
    if len(sys.argv) < 2:
        sys.exit(1)
    wav_path = sys.argv[1]
    with wave.open(wav_path, 'rb') as wf:
        n_frames = wf.getnframes()
        data = wf.readframes(n_frames)
        samples = struct.unpack(f"<{n_frames}h", data)
        for s in samples:
            # Normalize to [-1.0, 1.0]
            sys.stdout.write(f"{s / 32768.0:.8f}\n")

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > /home/user/pipeline/aggregate.cpp
#include <iostream>
#include <string>

int main() {
    // BUG 1: Using 32-bit floats causes catastrophic cancellation/precision loss over large files
    float cumulative_energy = 0.0f;
    float sample;
    long count = 0;

    while (std::cin >> sample) {
        cumulative_energy += (sample * sample);
        count++;

        // BUG 2: Logging intermediate state to stdout instead of stderr
        if (count % 10000 == 0) {
            std::cout << "TRACE: Processed " << count << " samples, current energy: " << cumulative_energy << "\n";
        }

        // Output metric
        // BUG 3: Printing with default precision loses digits. Should be std::stod friendly.
        std::cout << cumulative_energy << "\n";
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/pipeline/analyze.py
import sys

def main():
    output = []
    for line_num, line in enumerate(sys.stdin):
        line = line.strip()
        if not line:
            continue
        try:
            val = float(line)
            output.append(val)
        except ValueError:
            print(f"Traceback (most recent call last):", file=sys.stderr)
            print(f"  File 'analyze.py', line 10, in main", file=sys.stderr)
            print(f"ValueError: could not convert string to float: '{line}' at line {line_num}", file=sys.stderr)
            sys.exit(1)

    with open("final_output.txt", "w") as f:
        for val in output:
            f.write(f"{val:.10f}\n")

if __name__ == "__main__":
    main()
EOF

    chmod -R 777 /home/user
