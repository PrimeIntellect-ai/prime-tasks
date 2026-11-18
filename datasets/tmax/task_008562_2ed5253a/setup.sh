#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc gdb
pip3 install pytest

useradd -m -s /bin/bash user || true
mkdir -p /home/user/incident
cd /home/user/incident

# 1. Write the source code
cat << 'EOF' > telemetry_parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

typedef struct {
    char device_id[16];
    int payload_length;
} PacketHeader;

void process_telemetry(PacketHeader *hdr, FILE *f) {
    // Artificial math operation to force linking against libm
    double val = pow((double)hdr->payload_length, 2.0);

    char *buffer = malloc(128);

    // The bug: reading based on an untrusted, arbitrarily large payload_length
    fread(buffer, 1, hdr->payload_length, f);

    // Iterating out of bounds causes a segmentation fault
    for(int i = 0; i < hdr->payload_length; i++) {
        buffer[i] = buffer[i] + 1; 
    }

    printf("Processed %s, score: %f\n", hdr->device_id, val);
    free(buffer);
}

int main(int argc, char **argv) {
    FILE *f = fopen("telemetry.tmp", "rb");
    if (!f) {
        fprintf(stderr, "Missing telemetry.tmp\n");
        return 1;
    }

    PacketHeader hdr;
    fread(&hdr, sizeof(PacketHeader), 1, f);
    process_telemetry(&hdr, f);

    fclose(f);
    return 0;
}
EOF

# 2. Compile
gcc -g -O0 -o telemetry_parser telemetry_parser.c -lm

# 3. Generate the malicious payload file
python3 -c '
import struct
with open("telemetry.tmp", "wb") as f:
    device_id = b"SENSOR-X99".ljust(16, b"\x00")
    f.write(device_id)
    f.write(struct.pack("<i", 9999999))
    f.write(b"A" * 1000)
'

# 4. Generate the core dump using gdb to avoid host core_pattern issues
cat << 'EOF' > run.gdb
run
generate-core-file core
quit
EOF
gdb -batch -x run.gdb ./telemetry_parser

# 5. Cleanup to hide evidence
rm telemetry_parser telemetry.tmp run.gdb

# 6. Create the broken build script
cat << 'EOF' > build.sh
#!/bin/bash
gcc -g -O0 -o telemetry_parser telemetry_parser.c
EOF
chmod +x build.sh

chmod -R 777 /home/user
