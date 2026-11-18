#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils gzip
    pip3 install pytest

    mkdir -p /app/corpus/evil /app/corpus/clean /home/user/sample_corpus/evil /home/user/sample_corpus/clean

    # Compile the validator_oracle
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    unsigned char buffer[1024];
    size_t bytes = fread(buffer, 1, 1024, stdin);
    for (size_t i = 0; i < bytes - 1; i++) {
        // Very basic UTF-16LE text check for 'R0GUE'
        if (buffer[i] == 'R' && buffer[i+1] == 0) {
            if (i+8 < bytes && buffer[i+2]=='0' && buffer[i+4]=='G' && buffer[i+6]=='U' && buffer[i+8]=='E') {
                return 1;
            }
        }
    }
    return 0;
}
EOF
    gcc -o /app/validator_oracle /tmp/oracle.c
    strip /app/validator_oracle
    chmod +x /app/validator_oracle

    # Generate dummy base ELF
    cat << 'EOF' > /tmp/dummy.c
int main() { return 0; }
EOF
    gcc -o /tmp/base.elf /tmp/dummy.c

    # Generate payloads
    python3 -c 'open("/tmp/clean.bin", "wb").write("CLEAN".encode("utf-16le"))'
    python3 -c 'open("/tmp/evil.bin", "wb").write("R0GUE".encode("utf-16le"))'

    # Generate App corpus
    objcopy --add-section .note.artifact=/tmp/clean.bin /tmp/base.elf /app/corpus/clean/1.elf
    gzip /app/corpus/clean/1.elf
    objcopy --add-section .note.artifact=/tmp/evil.bin /tmp/base.elf /app/corpus/evil/1.elf
    gzip /app/corpus/evil/1.elf

    # Generate Sample corpus
    objcopy --add-section .note.artifact=/tmp/clean.bin /tmp/base.elf /home/user/sample_corpus/clean/sample1.elf
    gzip /home/user/sample_corpus/clean/sample1.elf
    objcopy --add-section .note.artifact=/tmp/evil.bin /tmp/base.elf /home/user/sample_corpus/evil/sample1.elf
    gzip /home/user/sample_corpus/evil/sample1.elf

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
