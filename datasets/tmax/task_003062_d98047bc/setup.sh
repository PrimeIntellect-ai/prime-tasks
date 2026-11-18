#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libseccomp-dev
    pip3 install pytest

    mkdir -p /app

    # Generate the audio file with hidden LSB steganography
    cat << 'EOF' > /tmp/gen_wav.py
import wave
import struct

msg = b"GET /admin/dashboard HTTP/1.1\r\nHost: internal.corp\r\nCookie: auth_token=admin_bypass_9921; role=superuser\r\nUser-Agent: Mozilla/5.0\r\n\r\n\x00"

bits = []
for byte in msg:
    for i in range(8):
        bits.append((byte >> i) & 1)

num_samples = 44100
samples = [0] * num_samples

for i, b in enumerate(bits):
    samples[i] = (samples[i] & ~1) | b

with wave.open('/app/exfil_audio.wav', 'w') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(44100)
    data = b''.join(struct.pack('<h', s) for s in samples)
    w.writeframes(data)
EOF
    python3 /tmp/gen_wav.py

    # Create the backdoor probe binary
    cat << 'EOF' > /tmp/probe.c
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
int main() {
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("Probe started.\n");
    // Attempt an illegal syscall that should trigger the seccomp kill
    int fd = open("/etc/shadow", O_RDONLY);
    if (fd >= 0) {
        printf("Error: Allowed to open files!\n");
    } else {
        printf("Error: Open failed but not killed!\n");
    }
    return 0;
}
EOF
    gcc /tmp/probe.c -o /app/backdoor_probe
    chmod +x /app/backdoor_probe

    # Clean up temporary files
    rm /tmp/gen_wav.py /tmp/probe.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
