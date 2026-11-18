#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc
    pip3 install pytest

    mkdir -p /app

    # Create oracle C source
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

int main(int argc, char** argv) {
    if (argc != 3) return 1;
    FILE* f = fopen(argv[1], "rb");
    if (!f) return 1;

    uint32_t magic;
    if (fread(&magic, 1, 4, f) != 4 || magic != 0x43524143) { fclose(f); return 1; }

    while (1) {
        uint16_t name_len;
        if (fread(&name_len, 1, 2, f) != 2) break;

        char* name_utf16 = malloc(name_len);
        if (fread(name_utf16, 1, name_len, f) != name_len) break;

        char* name_utf8 = malloc(name_len + 1);
        int j = 0;
        for (int i = 0; i < name_len; i += 2) {
            name_utf8[j++] = name_utf16[i];
        }
        name_utf8[j] = 0;

        uint32_t data_len;
        if (fread(&data_len, 1, 4, f) != 4) break;

        char* data = malloc(data_len);
        if (data_len > 0 && fread(data, 1, data_len, f) != data_len) break;

        if (strstr(name_utf8, "../") || strstr(name_utf8, "..\\") || name_utf8[0] == '/') {
            printf("WARNING: Skipped malicious path %s\n", name_utf8);
        } else {
            char path[1024];
            snprintf(path, sizeof(path), "%s/%s", argv[2], name_utf8);
            FILE* out = fopen(path, "wb");
            if (out) {
                fwrite(data, 1, data_len, out);
                fclose(out);
            }
        }
        free(name_utf16);
        free(name_utf8);
        free(data);
    }
    fclose(f);
    return 0;
}
EOF

    # Compile oracle
    gcc -O2 -o /app/oracle_unpacker /app/oracle.c
    rm /app/oracle.c

    # Generate video
    cat << 'EOF' > /app/text.txt
CARC Format:
Magic: 0x43 0x41 0x52 0x43
File Record:
- 2 bytes (LE): Filename length
- UTF-16LE Filename
- 4 bytes (LE): File content length
- Raw Data
Skip malicious paths outside target!
EOF
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=1 -vf "drawtext=textfile=/app/text.txt:fontcolor=white:fontsize=24:x=10:y=10" -y /app/config_session.mp4
    rm /app/text.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
