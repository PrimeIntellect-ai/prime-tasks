#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip multimon-ng gcc
    pip3 install pytest

    # Create necessary directories
    mkdir -p /app/auth_logs
    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/clean

    # 1. Create the legacy validator binary
    cat << 'EOF' > /tmp/legacy.c
#include <stdio.h>
int main() {
    const char* backdoor = "bckd_s3cr3t_key99";
    printf("Legacy validator running...\n");
    return 0;
}
EOF
    gcc -o /app/legacy_validator /tmp/legacy.c
    rm /tmp/legacy.c

    # 2. Create the auth logs
    cat << 'EOF' > /app/auth_logs/auth.log
[2023-10-12] FAILED_ATTEMPT: cGFzc3dvcmQxMjM=
[2023-10-12] FAILED_ATTEMPT: cXdlcnR5dWlvcA==
EOF

    # 3. Generate the DTMF voicemail audio file using Python
    cat << 'EOF' > /tmp/gen_dtmf.py
import wave, math, struct

sample_rate = 8000
duration = 0.2
pause = 0.1

tones = {
    '8': (852, 1336), '6': (770, 1477), '7': (852, 1209),
    '5': (770, 1336), '3': (697, 1477), '0': (941, 1336), '9': (852, 1477)
}
sequence = "8675309"

with wave.open('/app/voicemail.wav', 'w') as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(sample_rate)

    for digit in sequence:
        f1, f2 = tones[digit]
        for i in range(int(sample_rate * duration)):
            t = float(i) / sample_rate
            val = int(32767.0 * 0.5 * (math.sin(2*math.pi*f1*t) + math.sin(2*math.pi*f2*t)))
            f.writeframes(struct.pack('<h', val))
        for i in range(int(sample_rate * pause)):
            f.writeframes(struct.pack('<h', 0))
EOF
    python3 /tmp/gen_dtmf.py
    rm /tmp/gen_dtmf.py

    # 4. Populate the corpus directories
    echo -n "8675309safe" > /app/corpus/evil/1.txt
    echo -n "admin_bckd_s3cr3t_key99_pass" > /app/corpus/evil/2.txt
    echo -n "password123" > /app/corpus/evil/3.txt
    echo -n "qwertyuiop" > /app/corpus/evil/4.txt
    echo -n "short" > /app/corpus/evil/5.txt

    echo -n "SuperSecureP@ssw0rd!" > /app/corpus/clean/1.txt
    echo -n "CorrectHorseBatteryStaple" > /app/corpus/clean/2.txt
    echo -n "Another1Long!ValidPass" > /app/corpus/clean/3.txt

    # 5. Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
