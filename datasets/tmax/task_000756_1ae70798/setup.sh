#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libssl-dev
    pip3 install pytest numpy scipy

    mkdir -p /app
    mkdir -p /home/user

    # Generate DTMF audio
    cat << 'EOF' > /tmp/gen_audio.py
import numpy as np
from scipy.io import wavfile

sample_rate = 8000
duration = 0.1
silence = 0.05
digits = "5938210476"

dtmf_freqs = {
    '1': (697, 1209), '2': (697, 1336), '3': (697, 1477),
    '4': (770, 1209), '5': (770, 1336), '6': (770, 1477),
    '7': (852, 1209), '8': (852, 1336), '9': (852, 1477),
    '*': (941, 1209), '0': (941, 1336), '#': (941, 1477)
}

audio = []
for d in digits:
    f1, f2 = dtmf_freqs[d]
    t = np.linspace(0, duration, int(sample_rate * duration), endpoint=False)
    signal = np.sin(2 * np.pi * f1 * t) + np.sin(2 * np.pi * f2 * t)
    audio.extend(signal)
    audio.extend(np.zeros(int(sample_rate * silence)))

wavfile.write('/app/dtmf_intercept.wav', sample_rate, np.int16(np.array(audio) * 16383))
EOF
    python3 /tmp/gen_audio.py

    # Create oracle binary
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <openssl/hmac.h>

int hex2bin(const char *hex, unsigned char *out) {
    size_t len = strlen(hex);
    if (len % 2 != 0) return -1;
    for (size_t i = 0; i < len / 2; i++) {
        unsigned int val;
        if (sscanf(hex + 2 * i, "%2x", &val) != 1) return -1;
        out[i] = val;
    }
    return len / 2;
}

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    unsigned char data[8192];
    int len = hex2bin(argv[1], data);
    if (len < 38) { puts("FORMAT_ERROR"); return 0; }
    if (memcmp(data, "REDI", 4) != 0) { puts("FORMAT_ERROR"); return 0; }

    int url_len = (data[4] << 8) | data[5];
    if (len != 6 + url_len + 32) { puts("FORMAT_ERROR"); return 0; }

    unsigned char expected_mac[32];
    memcpy(expected_mac, data + len - 32, 32);

    unsigned char mac[32];
    unsigned int mac_len;
    HMAC(EVP_sha256(), "5938210476", 10, data, len - 32, mac, &mac_len);

    if (memcmp(mac, expected_mac, 32) != 0) { puts("INVALID_SIG"); return 0; }

    char url[8192];
    memcpy(url, data + 6, url_len);
    url[url_len] = '\0';

    for (int i=0; i<url_len; i++) {
        if (url[i] < 0 || url[i] > 127) { puts("FORMAT_ERROR"); return 0; }
    }

    if (strncmp(url, "https://secure.internal/", 24) != 0) { puts("INVALID_URL"); return 0; }
    if (strchr(url, '@') || strchr(url, '?')) { puts("INVALID_URL"); return 0; }

    const char *p = url + 8; // skip https://
    if (strstr(p, "//")) { puts("INVALID_URL"); return 0; }

    printf("ALLOW: %s\n", url);
    return 0;
}
EOF
    gcc -O2 /tmp/oracle.c -o /app/oracle_bin -lcrypto

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
