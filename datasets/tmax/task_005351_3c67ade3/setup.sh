#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sox multimon-ng socat netcat-openbsd curl
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user/run

    # Generate the DTMF audio file for "8025"
    python3 -c "
import wave
import struct
import math

def generate_dtmf(sequence, filename):
    freqs = {
        '1': (697, 1209), '2': (697, 1336), '3': (697, 1477), 'A': (697, 1633),
        '4': (770, 1209), '5': (770, 1336), '6': (770, 1477), 'B': (770, 1633),
        '7': (852, 1209), '8': (852, 1336), '9': (852, 1477), 'C': (852, 1633),
        '*': (941, 1209), '0': (941, 1336), '#': (941, 1477), 'D': (941, 1633)
    }

    sample_rate = 8000
    duration = 0.2
    pause = 0.1

    with wave.open(filename, 'w') as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)

        for char in sequence:
            f1, f2 = freqs[char]
            for i in range(int(sample_rate * duration)):
                t = float(i) / sample_rate
                val = int(32767.0 * 0.5 * (math.sin(2 * math.pi * f1 * t) + math.sin(2 * math.pi * f2 * t)))
                wav_file.writeframes(struct.pack('h', val))
            for i in range(int(sample_rate * pause)):
                wav_file.writeframes(struct.pack('h', 0))

generate_dtmf('8025', '/app/voicemail.wav')
"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod 777 /app/voicemail.wav
