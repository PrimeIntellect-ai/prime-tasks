#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install --default-timeout=100 pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Generate ELF binary
    cat << 'EOF' > /tmp/auth_service.c
#include <stdio.h>
const char salt[] = "SALT_x9K2mP4vL8sQ1wE7";
int main() {
    printf("%s\n", salt);
    return 0;
}
EOF
    gcc /tmp/auth_service.c -o /app/auth_service_dump
    rm /tmp/auth_service.c

    # Generate DTMF audio
    cat << 'EOF' > /tmp/gen_audio.py
import wave
import math
import struct

def generate_dtmf(sequence, filename):
    sample_rate = 8000
    duration = 0.2
    pause = 0.1

    frequencies = {
        '1': (697, 1209), '2': (697, 1336), '3': (697, 1477),
        '4': (770, 1209), '5': (770, 1336), '6': (770, 1477),
        '7': (852, 1209), '8': (852, 1336), '9': (852, 1477),
        '*': (941, 1209), '0': (941, 1336), '#': (941, 1477),
    }

    with wave.open(filename, 'w') as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)

        for char in sequence:
            f1, f2 = frequencies[char]
            for i in range(int(sample_rate * duration)):
                t = float(i) / sample_rate
                value = int(32767.0 * 0.5 * (math.sin(2.0 * math.pi * f1 * t) + math.sin(2.0 * math.pi * f2 * t)))
                wav_file.writeframesraw(struct.pack('<h', value))

            for i in range(int(sample_rate * pause)):
                wav_file.writeframesraw(struct.pack('<h', 0))

generate_dtmf('84920155', '/app/intercepted_comms.wav')
EOF
    python3 /tmp/gen_audio.py
    rm /tmp/gen_audio.py

    # Generate corpus
    # Clean
    echo -n "8492x9K2mP4vL8sQ1wE70123456789AB" > /app/corpus/clean/valid1.bin
    echo -n "8492x9K2mP4vL8sQ1wE7CDEF01234567" > /app/corpus/clean/valid2.bin

    # Evil
    echo -n "8492x9K2mP4vL8sQ1wE70123456789A" > /app/corpus/evil/short.bin
    echo -n "8493x9K2mP4vL8sQ1wE70123456789AB" > /app/corpus/evil/bad_pin.bin
    echo -n "8492x9K2mP4vL8sQ1wE80123456789AB" > /app/corpus/evil/bad_salt.bin
    echo -n "8492x9K2mP4vL8sQ1wE70123456789AG" > /app/corpus/evil/bad_hex.bin
    echo -n "8492x9K2mP4vL8sQ1wE70123456789ABC" > /app/corpus/evil/long.bin

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
