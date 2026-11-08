#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/app/bin
    mkdir -p /home/user/app/data

    # Create the C source for the parser
    cat << 'EOF' > /home/user/app/bin/parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char** argv) {
    if (argc < 2) {
        printf("Usage: %s <file>\n", argv[0]);
        return 1;
    }
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    unsigned int magic;
    if (fread(&magic, 4, 1, f) != 1) return 1;
    if (magic != 0xDEADC0DE) {
        printf("Bad magic\n");
        return 1;
    }

    unsigned int len;
    if (fread(&len, 4, 1, f) != 1) return 1;

    char *buf = malloc(len + 1);
    if (fread(buf, 1, len, f) != len) return 1;
    buf[len] = '\0';

    printf("{\"status\": \"success\", \"payload\": \"%s\"}\n", buf);

    free(buf);
    fclose(f);
    return 0;
}
EOF

    # Compile the parser and remove source to enforce binary analysis
    gcc /home/user/app/bin/parser.c -o /home/user/app/bin/parser
    rm /home/user/app/bin/parser.c

    # Create the expected output
    cat << 'EOF' > /home/user/app/expected.json
{"status": "success", "payload": "error99"}
EOF

    # Create the malformed raw.dat file using Python
    python3 -c '
import struct
magic = 0xDEADC0DE
payload = "error99".encode("utf-16le")
length = len(payload)
with open("/home/user/app/data/raw.dat", "wb") as f:
    f.write(struct.pack("<I", magic))
    f.write(struct.pack("<I", length))
    f.write(payload)
'

    # Create the Makefile
    cat << 'EOF' > /home/user/app/Makefile
test:
	./bin/parser data/raw.dat > actual.json
	diff actual.json expected.json
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
