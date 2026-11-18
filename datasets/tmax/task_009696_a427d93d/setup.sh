#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/build_tools /home/user/artifacts

    cat << 'EOF' > /home/user/build_tools/extractor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    fseek(f, 0, SEEK_END);
    long fsize = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *string = malloc(fsize + 1);
    fread(string, fsize, 1, f);
    fclose(f);
    string[fsize] = 0;

    // BUG: Buffer too small, missing null terminator
    char hex_out[16]; 
    char *start = strstr(string, "HEX[");
    if (start) {
        start += 4;
        char *end = strchr(start, ']');
        if (end) {
            strncpy(hex_out, start, end - start);
            printf("ENCODED:%s\n", hex_out);
        }
    }
    free(string);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/build_tools/Makefile
extractor: extractor.c
	gcc -O2 -Wall extractor.c -o extractor
EOF

    echo -n "SOME_JUNK_DATA_IGNORE_THIS_HEX[3130202b2035202a2032]MORE_JUNK_DATA" > /home/user/artifacts/module_A.bin
    echo -n "BINARY_HEADER_0x00_HEX[28313030202f203229202b2037]FOOTER_DATA" > /home/user/artifacts/module_B.bin
    echo -n "PADDING_PADDING_HEX[34202a2034202a2034202d2034]" > /home/user/artifacts/core_v1.bin
    echo -n "HEX[313530202d203530202a2032]TRAIL" > /home/user/artifacts/lib_legacy.bin

    chown -R user:user /home/user/build_tools /home/user/artifacts
    chmod -R 777 /home/user
