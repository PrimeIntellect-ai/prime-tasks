#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc zlib1g-dev make bash
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/api_workspace
    cd /home/user/api_workspace

    echo -n "INTEGRATION_TEST_PAYLOAD_V1" > payload.dat

    cat << 'EOF' > api_tester.c
#include <stdio.h>
#include <stdlib.h>
#include <zlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <filename>\n", argv[0]);
        return 1;
    }

    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    fseek(f, 0, SEEK_END);
    long fsize = ftell(f);
    fseek(f, 0, SEEK_SET);

    unsigned char *buffer = malloc(fsize);
    fread(buffer, 1, fsize, f);
    fclose(f);

    // BUG: Freeing buffer before calculating checksum
    free(buffer);

    uLong crc = crc32(0L, Z_NULL, 0);
    crc = crc32(crc, buffer, fsize);

    printf("%08lx\n", crc);

    return 0;
}
EOF

    cat << 'EOF' > build.sh
#!/bin/bash
gcc -O2 -Wall api_tester.c -o api_tester
EOF
    chmod +x build.sh

    chown -R user:user /home/user/api_workspace
    chmod -R 777 /home/user
