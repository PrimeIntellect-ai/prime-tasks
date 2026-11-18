#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils
pip3 install pytest flask requests

mkdir -p /app
cat << 'EOF' > /tmp/decoder.c
#include <stdio.h>
#include <stdint.h>
#include <math.h>

int main() {
    uint32_t timestamp;
    float sensor_val;
    char user_id[17];

    while (fread(&timestamp, 1, 4, stdin) == 4) {
        if (fread(&sensor_val, 1, 4, stdin) != 4) break;
        user_id[16] = '\0';
        if (fread(user_id, 1, 16, stdin) != 16) break;

        char text[1024];
        int i = 0;
        while (1) {
            int c = fgetc(stdin);
            if (c == EOF) {
                text[i] = '\0';
                break;
            }
            text[i++] = c;
            if (c == '\0') break;
            if (i >= 1023) {
                text[1023] = '\0';
                break;
            }
        }

        printf("{\"timestamp\": %u, \"sensor_val\": ", timestamp);
        if (isnan(sensor_val)) {
            printf("null");
        } else {
            printf("%f", sensor_val);
        }
        printf(", \"user_id\": \"%s\", \"text_note\": \"%s\"}\n", user_id, text);
    }
    return 0;
}
EOF

gcc -o /app/sensor_decoder /tmp/decoder.c -lm
strip /app/sensor_decoder || true
chmod +x /app/sensor_decoder
rm /tmp/decoder.c

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
