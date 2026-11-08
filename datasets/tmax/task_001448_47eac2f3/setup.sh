#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/auth_gen.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

unsigned int generate_token(unsigned int timestamp, const char* tz_str) {
    char tz_buf[10];
    // BUG 1: Buffer overflow
    strcpy(tz_buf, tz_str);

    int sign = 1;
    int hours = 0;
    int minutes = 0;

    if (tz_buf[3] == '-') sign = -1;
    sscanf(tz_buf + 4, "%d:%d", &hours, &minutes);

    // BUG 2: Formula error (hours * 360 instead of hours * 3600)
    int offset_seconds = sign * ((hours * 360) + (minutes * 60));

    unsigned int adjusted_time = timestamp + offset_seconds;
    return (adjusted_time ^ 0xCAFEBABE);
}

int main(int argc, char** argv) {
    if (argc != 2) {
        printf("Usage: %s <log_file>\n", argv[0]);
        return 1;
    }
    FILE* f = fopen(argv[1], "r");
    if (!f) return 1;

    unsigned int ts;
    char tz[256];
    while (fscanf(f, "%u %255s", &ts, tz) == 2) {
        unsigned int token = generate_token(ts, tz);
        printf("%u %s -> %08X\n", ts, tz, token);
    }
    fclose(f);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/verify_tokens.py
import subprocess
import os

def test():
    with open("/home/user/test_harness.txt", "w") as f:
        f.write("1600000000 UTC+05:30\n")
        f.write("1600000000 UTC-04:00\n")

    # Expected:
    # 1600000000 + (5*3600 + 30*60) = 1600019800 -> ^ 0xCAFEBABE = A3195BAE
    # 1600000000 - (4*3600) = 1599985600 -> ^ 0xCAFEBABE = A318DD3E

    try:
        out = subprocess.check_output(["/home/user/auth_gen", "/home/user/test_harness.txt"]).decode()
    except subprocess.CalledProcessError:
        print("Binary failed to run.")
        return False

    lines = out.strip().split("\n")
    if len(lines) != 2:
        return False

    if "A3195BAE" in lines[0] and "A318DD3E" in lines[1]:
        print("SUCCESS: Tokens match expected valid tokens.")
        return True
    else:
        print("FAILURE: Formula logic is incorrect.")
        return False

if __name__ == "__main__":
    if not os.path.exists("/home/user/auth_gen"):
        print("Compile the code first.")
    else:
        test()
EOF

    python3 -c '
import random
with open("/home/user/traffic.log", "w") as f:
    for i in range(500):
        f.write(f"1625000000 UTC+0{random.randint(1,9)}:00\n")
    f.write("1625000000 UTC+02:00_MALFORMED_LONG_STRING_CAUSING_CRASH\n")
    for i in range(500):
        f.write(f"1625000000 UTC-0{random.randint(1,9)}:00\n")
'

    cat << 'EOF' > /home/user/target_traffic.txt
1700000000 UTC+09:00
1700000000 UTC-08:00
1700000000 UTC+05:45
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
