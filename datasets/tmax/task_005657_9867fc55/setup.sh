#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb xxd bsdmainutils
    pip3 install pytest

    mkdir -p /home/user/project
    cd /home/user/project

    cat << 'EOF' > processor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void process_record(FILE *f, int record_index) {
    unsigned char type;
    unsigned char length;
    char buffer[32]; // Vulnerable buffer: max 31 chars + null terminator

    if (fread(&type, 1, 1, f) != 1) return;
    if (fread(&length, 1, 1, f) != 1) return;

    // VULNERABILITY: reads 'length' bytes directly into a 32-byte buffer
    if (fread(buffer, 1, length, f) != length) return;
    buffer[length] = '\0';

    printf("Record %d - Type: %d, Data: %s\n", record_index, type, buffer);
}

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    int index = 0;
    while(fgetc(f) != EOF) {
        fseek(f, -1, SEEK_CUR);
        process_record(f, index);
        index++;
    }
    fclose(f);
    return 0;
}
EOF

    cat << 'EOF' > build.sh
#!/bin/bash
cd /home/user/project
gcc -g -O0 processor.c -o processor
./processor data.bin > output.log 2>&1
if [ $? -eq 0 ]; then
    echo "Build Success" > build_status.txt
    exit 0
else
    echo "Build Failed" > build_status.txt
    exit 1
fi
EOF
    chmod +x build.sh

    python3 -c '
import struct

def write_record(f, t, data):
    f.write(struct.pack("B", t))
    f.write(struct.pack("B", len(data)))
    f.write(data)

with open("data.bin", "wb") as f:
    write_record(f, 1, b"Valid data 1")      # Index 0
    write_record(f, 2, b"Valid data 2")      # Index 1
    write_record(f, 3, b"Another valid one") # Index 2
    write_record(f, 4, b"Short")             # Index 3
    write_record(f, 99, b"A" * 60)           # Index 4 (Triggers buffer overflow in 32-byte buffer)
    write_record(f, 5, b"Post crash data")   # Index 5
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
