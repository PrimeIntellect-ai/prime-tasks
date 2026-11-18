#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils gdb strace
    pip3 install pytest

    mkdir -p /home/user

    # 1. Create the C source code for the binary
    cat << 'EOF' > /home/user/math_processor.c
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

void process(uint32_t id, FILE *f) {
    uint32_t magic = 0xDEADBEEF;
    uint64_t result = id * 2;
    if (id == 31337) { // 31337 is 0x7A69
        // Intentionally misaligned write to simulate corruption (3 bytes instead of 4)
        fwrite("\xEF\xBE\xAD", 1, 3, f);
        fwrite(&id, sizeof(id), 1, f);
        fwrite(&result, sizeof(result), 1, f);
    } else {
        fwrite(&magic, sizeof(magic), 1, f);
        fwrite(&id, sizeof(id), 1, f);
        fwrite(&result, sizeof(result), 1, f);
    }
}

int main(int argc, char **argv) {
    FILE *f = fopen("/home/user/processor.log", "wb");
    if (!f) return 1;
    process(100, f);
    process(200, f);
    process(31337, f); // Trigger corruption
    process(400, f);   // This will be misaligned and fail parsing
    fclose(f);
    return 0;
}
EOF

    # 2. Compile the binary without optimization so the constant is easily visible in objdump
    gcc -O0 -o /home/user/math_processor /home/user/math_processor.c
    rm /home/user/math_processor.c

    # 3. Run the binary to generate processor.log
    /home/user/math_processor

    # 4. Create the buggy python script
    cat << 'EOF' > /home/user/process_logs.py
import struct
import sys

def main():
    total = 0
    with open("/home/user/processor.log", "rb") as f:
        while True:
            magic_data = f.read(4)
            if not magic_data:
                break

            magic = struct.unpack("<I", magic_data)[0]
            if magic != 0xDEADBEEF:
                # Script doesn't break here, assumes it can recover, leading to failure
                pass

            id_data = f.read(4)
            res_data = f.read(8)

            # This will raise struct.error if EOF is reached and length isn't exact
            input_id = struct.unpack("<I", id_data)[0]
            result = struct.unpack("<Q", res_data)[0]
            total += result

    with open("/home/user/aggregate.txt", "w") as out:
        out.write(str(total))

if __name__ == "__main__":
    main()
EOF

    chmod +x /home/user/math_processor
    chmod +x /home/user/process_logs.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
