#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc socat jq binutils
    pip3 install pytest

    mkdir -p /app/builder

    cat << 'EOF' > /app/builder/build.sh
#!/bin/bash
source /app/builder/lib_a.sh
echo "Building service root..."
mkdir -p /home/user/service_root/bin
# Copy system tools to simulate conditional build
cp $(which socat) /home/user/service_root/bin/
cp $(which jq) /home/user/service_root/bin/
echo "Done."
EOF

    cat << 'EOF' > /app/builder/lib_a.sh
#!/bin/bash
# lib_a.sh
source /app/builder/lib_b.sh
function setup_env() {
    export SERVICE_PORT=9000
}
EOF

    cat << 'EOF' > /app/builder/lib_b.sh
#!/bin/bash
# lib_b.sh
# Circular dependency here:
source /app/builder/lib_a.sh
function check_deps() {
    echo "Checking deps..."
}
EOF

    chmod +x /app/builder/build.sh

    cat << 'EOF' > /tmp/legacy_processor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Base64 encoding table
static const char b64_table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    char *hex = argv[1];
    size_t len = strlen(hex);
    if (len % 2 != 0) return 1;

    size_t blen = len / 2;
    unsigned char *bytes = malloc(blen);
    for (size_t i = 0; i < blen; i++) {
        unsigned int b;
        if (sscanf(hex + 2*i, "%2x", &b) != 1) return 1;
        bytes[i] = b ^ 0x5A;
    }

    // Simple B64 encode
    for (size_t i = 0; i < blen; i += 3) {
        unsigned int val = 0;
        int bytes_to_encode = blen - i;
        if (bytes_to_encode > 3) bytes_to_encode = 3;

        for (int j = 0; j < bytes_to_encode; j++) {
            val |= (bytes[i + j] << (16 - j * 8));
        }

        printf("%c", b64_table[(val >> 18) & 0x3F]);
        printf("%c", b64_table[(val >> 12) & 0x3F]);
        if (bytes_to_encode > 1) printf("%c", b64_table[(val >> 6) & 0x3F]);
        else printf("=");
        if (bytes_to_encode > 2) printf("%c", b64_table[val & 0x3F]);
        else printf("=");
    }
    printf("\n");
    return 0;
}
EOF

    gcc -O2 /tmp/legacy_processor.c -o /app/legacy_processor
    strip /app/legacy_processor
    rm /tmp/legacy_processor.c
    chmod +x /app/legacy_processor

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
