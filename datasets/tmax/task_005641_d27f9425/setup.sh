#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/legacy_processor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const int b64index[256] = {
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,62,63,62,62,63,52,53,54,55,56,57,58,59,60,61,0,0,0,0,0,0,
    0,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,0,0,0,0,0,
    0,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,0,0,0,0,0
};

int b64decode(const char* b64, char* dest) {
    int len = strlen(b64);
    int pad = 0;
    if (len > 0 && b64[len-1] == '=') pad++;
    if (len > 1 && b64[len-2] == '=') pad++;
    int L = (len * 3) / 4 - pad;
    for (int i=0, j=0; i < len; i+=4, j+=3) {
        int n = b64index[(int)b64[i]] << 18 | b64index[(int)b64[i+1]] << 12 | b64index[(int)b64[i+2]] << 6 | b64index[(int)b64[i+3]];
        dest[j] = n >> 16;
        if (j+1 < L) dest[j+1] = n >> 8 & 0xFF;
        if (j+2 < L) dest[j+2] = n & 0xFF;
    }
    dest[L] = '\0';
    return L;
}

unsigned int custom_hash(const char* pin) {
    unsigned int h = 0x1337BEEF;
    for(int i = 0; i < 4; i++) {
        h = (h << 4) ^ (h >> 28) ^ pin[i];
    }
    return h;
}

int main(int argc, char** argv) {
    if (argc != 2) return 1;
    char decoded[256] = {0};
    b64decode(argv[1], decoded);

    if (strlen(decoded) < 5) return 1;

    char pin[5];
    strncpy(pin, decoded, 4);
    pin[4] = '\0';

    if (custom_hash(pin) == 0x1337cfeb) {
        if (strcmp(decoded + 5, "DUMP_AUDIT") == 0) {
            FILE *f = fopen("/home/user/audit_trail.log", "w");
            if (f) {
                fprintf(f, "AUDIT_SUCCESS: COMPLIANCE_DATA_EXTRACTED\n");
                fclose(f);
                return 0;
            }
        }
    }
    return 1;
}
EOF

    gcc -O2 /home/user/legacy_processor.c -o /home/user/legacy_processor
    strip /home/user/legacy_processor
    rm /home/user/legacy_processor.c

    chmod -R 777 /home/user
