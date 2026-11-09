#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/log_tool

    cat << 'EOF' > /home/user/log_tool/log_processor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

// Decodes a hex string to a byte array
void decode_hex(const char *hex_str, unsigned char *out_buffer, int len) {
    for (int i = 0; i < len; i++) {
        // BUG: %x writes an int (4 bytes) to out_buffer, which is char. 
        // This causes stack corruption.
        sscanf(hex_str + i * 2, "%02x", (unsigned int*)&out_buffer[i]);
    }
}

int main(int argc, char *argv[]) {
    char line[256];
    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\n")] = 0;
        if (strlen(line) == 0) continue;

        int byte_len = strlen(line) / 2;
        if (byte_len != 8) continue;

        unsigned char buffer[8];
        decode_hex(line, buffer, byte_len);

        int N;
        float val;
        memcpy(&N, buffer, 4);
        memcpy(&val, buffer + 4, 4);

        // BUG: Integer division 5/9 evaluates to 0
        float adjusted = pow(val, 2.0) * (5 / 9);

        printf("N: %d, Adj: %.2f\n", N, adjusted);
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/log_tool/Makefile
log_processor: log_processor.c
	gcc -g -O0 -o log_processor log_processor.c
EOF

    python3 -c "
import struct
# 10, 3.0 -> '0a000000' + '00004040' = '0a00000000004040'
print(struct.pack('<If', 10, 3.0).hex())
# 20, 6.0 -> '14000000' + '0000c040' = '140000000000c040'
print(struct.pack('<If', 20, 6.0).hex())
# 5, 1.5 -> '05000000' + '0000c03f' = '050000000000c03f'
print(struct.pack('<If', 5, 1.5).hex())
" > /home/user/log_tool/raw_logs.txt

    chmod -R 777 /home/user
