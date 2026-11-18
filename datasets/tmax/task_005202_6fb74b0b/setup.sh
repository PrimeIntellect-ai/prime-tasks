#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/audio_service
    mkdir -p /app/bin

    cat << 'EOF' > /home/user/audio_service/requirements.txt
numpy==1.22.0
scipy>=1.8.0
audio_core
EOF

    cat << 'EOF' > /home/user/audio_service/math_core.py
from typing import List

def compute_signature(audio_array: List[float]) -> List[float]:
    denominator = 1.0 - sum(audio_array)
    return [x / denominator for x in audio_array]
EOF

    touch /app/traffic.pcap
    touch /app/corrupted_transmission.wav

    cat << 'EOF' > /app/bin/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    double sum = 0.0;
    for (int i = 1; i < argc; i++) {
        sum += atof(argv[i]);
    }
    double denominator = 1.0 - sum;
    if (fabs(denominator) < 1e-9) {
        denominator = denominator < 0 ? -1e-9 : 1e-9;
    }
    for (int i = 1; i < argc; i++) {
        printf("%f ", atof(argv[i]) / denominator);
    }
    printf("\n");
    return 0;
}
EOF
    gcc /app/bin/oracle.c -o /app/bin/oracle_audio_sig
    chmod +x /app/bin/oracle_audio_sig

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
