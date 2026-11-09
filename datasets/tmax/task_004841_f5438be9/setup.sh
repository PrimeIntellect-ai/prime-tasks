#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc socat tesseract-ocr imagemagick strace
    pip3 install pytest

    mkdir -p /app/legacy_proc/bin
    mkdir -p /app/legacy_proc/lib/v1
    mkdir -p /app/legacy_proc/lib/v2
    mkdir -p /app/legacy_proc/docs

    # Create v1 library (crashes)
    cat << 'EOF' > /tmp/libv1.c
void process_data() {
    int *p = 0;
    *p = 1;
}
EOF
    gcc -shared -fPIC -o /app/legacy_proc/lib/v1/libmatrix_math.so /tmp/libv1.c

    # Create v2 library (works)
    cat << 'EOF' > /tmp/libv2.c
void process_data() {
    // success
}
EOF
    gcc -shared -fPIC -o /app/legacy_proc/lib/v2/libmatrix_math.so /tmp/libv2.c

    # Create data_engine binary
    cat << 'EOF' > /tmp/data_engine.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern void process_data();

int main() {
    char *magic = getenv("MATRIX_ABI_MAGIC");
    if (!magic || strcmp(magic, "0x7F4A") != 0) {
        int *p = 0;
        *p = 1; // crash if magic is missing or wrong
    }

    process_data();

    char buffer[256];
    if (fgets(buffer, sizeof(buffer), stdin)) {
        printf("Processed: %s", buffer);
        fflush(stdout);
    }
    return 0;
}
EOF
    gcc -o /app/legacy_proc/bin/data_engine /tmp/data_engine.c -L/app/legacy_proc/lib/v2 -lmatrix_math -Wl,-rpath=/app/legacy_proc/lib/v2
    # Remove rpath so it requires LD_LIBRARY_PATH
    # Wait, we can just compile without rpath
    gcc -o /app/legacy_proc/bin/data_engine /tmp/data_engine.c -L/app/legacy_proc/lib/v2 -lmatrix_math

    # Create handwritten memo image
    convert -size 800x100 xc:white -font DejaVu-Sans -pointsize 20 -fill black -draw "text 10,50 'Ensure you set MATRIX_ABI_MAGIC=0x7F4A before starting the engine'" /app/legacy_proc/docs/handwritten_memo.png

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
